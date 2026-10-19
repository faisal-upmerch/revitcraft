//! arcus-dwg: Arcus's bundled DWG engine.
//!
//! A small command-line program that Arcus runs as a separate local process (never linked into the app). It reads and
//! writes DWG with the acadrust crate (MPL-2.0, https://github.com/hakanaktt/acadrust) and talks to Arcus only through
//! files, arguments, exit codes and one line of JSON on stdout. It makes no network connections.
//!
//! ```text
//! arcus-dwg to-dxf   <in.dwg> <out.dxf>                    DWG → DXF (the drawing's own version)
//! arcus-dwg from-dxf <in.dxf> <out.dwg> --version AC1032   DXF → DWG, then reads the DWG back to check it
//! arcus-dwg info     <in.dwg>                              version, entity count, layers (JSON)
//! arcus-dwg version                                        helper and acadrust versions (JSON)
//! common options: --max-memory-mb N (default 4096), --timeout S (default 300)
//! ```
//!
//! Errors go to stderr as one plain sentence and an exit code (see `Exit`). Panics inside acadrust are caught and
//! reported; memory use and run time are capped so a hostile or damaged file cannot take the Mac down with it.

use std::alloc::{GlobalAlloc, Layout, System};
use std::fmt::Write as _;
use std::panic::{self, AssertUnwindSafe};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Mutex;
use std::time::Duration;

use acadrust::{CadDocument, DwgReadOptions, DwgReader, DwgWriter, DxfReader, DxfReaderConfiguration, DxfVersion, DxfWriter};

/// Exit codes (Arcus maps them to plain-language messages; keep in sync with BundledDWGEngine.swift).
#[derive(Clone, Copy)]
#[repr(i32)]
enum Exit {
    Ok = 0,
    /// The input is not a drawing this engine can read (damaged, unsupported version or content).
    Unreadable = 2,
    /// The memory cap was reached.
    Memory = 3,
    /// The time cap was reached.
    Timeout = 4,
    /// The output could not be written.
    WriteFailed = 5,
    /// The engine failed internally (a caught panic).
    Internal = 6,
    /// The written DWG could not be read back.
    VerifyFailed = 7,
    Usage = 64,
    /// The input file could not be opened.
    NoInput = 66,
}

const HELPER_VERSION: &str = env!("CARGO_PKG_VERSION");
const ACADRUST_VERSION: &str = "0.6.5";

// MARK: Memory cap

/// Counts live heap bytes and stops the process cleanly when the cap is crossed (macOS does not enforce RLIMIT_AS).
struct CappedAllocator;

static USED: AtomicUsize = AtomicUsize::new(0);
static LIMIT: AtomicUsize = AtomicUsize::new(usize::MAX);

static DYING: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

fn die_raw(message: &str, code: Exit) -> ! {
    // No allocation here: this runs from inside the allocator and the watchdog. Only the first caller reports.
    unsafe {
        if !DYING.swap(true, Ordering::SeqCst) {
            libc::write(2, message.as_ptr() as *const libc::c_void, message.len());
        }
        libc::_exit(code as i32);
    }
}

#[inline]
fn charge(size: usize) {
    let now = USED.fetch_add(size, Ordering::Relaxed) + size;
    if now > LIMIT.load(Ordering::Relaxed) {
        die_raw("The drawing needs more memory than Arcus allows the DWG engine to use.\n", Exit::Memory);
    }
}

unsafe impl GlobalAlloc for CappedAllocator {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        charge(layout.size());
        System.alloc(layout)
    }
    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        charge(layout.size());
        System.alloc_zeroed(layout)
    }
    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        System.dealloc(ptr, layout);
        USED.fetch_sub(layout.size(), Ordering::Relaxed);
    }
    unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
        if new_size > layout.size() {
            charge(new_size - layout.size());
        } else {
            USED.fetch_sub(layout.size() - new_size, Ordering::Relaxed);
        }
        System.realloc(ptr, layout, new_size)
    }
}

#[global_allocator]
static GLOBAL: CappedAllocator = CappedAllocator;

// MARK: Errors

struct Failure {
    code: Exit,
    message: String,
}

impl Failure {
    fn new(code: Exit, message: impl Into<String>) -> Self {
        Failure { code, message: message.into() }
    }
}

type Outcome = Result<String, Failure>;

static PANIC_MESSAGE: Mutex<Option<String>> = Mutex::new(None);

// MARK: Options

struct Options {
    command: String,
    paths: Vec<PathBuf>,
    version: Option<String>,
    max_memory_mb: usize,
    timeout_s: u64,
}

fn usage() -> Failure {
    Failure::new(
        Exit::Usage,
        "usage: arcus-dwg to-dxf <in.dwg> <out.dxf> | from-dxf <in.dxf> <out.dwg> --version AC1032 | info <in.dwg> | version \
         [--max-memory-mb N] [--timeout S]",
    )
}

fn parse(args: &[String]) -> Result<Options, Failure> {
    let mut it = args.iter().skip(1);
    let command = it.next().cloned().ok_or_else(usage)?;
    let mut o = Options { command, paths: vec![], version: None, max_memory_mb: 4096, timeout_s: 300 };
    while let Some(a) = it.next() {
        match a.as_str() {
            "--version" => o.version = Some(it.next().cloned().ok_or_else(usage)?),
            "--max-memory-mb" => o.max_memory_mb = it.next().and_then(|v| v.parse().ok()).ok_or_else(usage)?,
            "--timeout" => o.timeout_s = it.next().and_then(|v| v.parse().ok()).ok_or_else(usage)?,
            s if s.starts_with("--") => return Err(usage()),
            s => o.paths.push(PathBuf::from(s)),
        }
    }
    let need = match o.command.as_str() {
        "to-dxf" | "from-dxf" => 2,
        "info" => 1,
        "version" => 0,
        _ => return Err(usage()),
    };
    if o.paths.len() != need {
        return Err(usage());
    }
    Ok(o)
}

// MARK: JSON

fn json_string(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => {
                let _ = write!(out, "\\u{:04x}", c as u32);
            }
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

fn summary(doc: &CadDocument, recovered: bool, diagnostics: usize, with_layers: bool) -> String {
    let mut s = String::new();
    let _ = write!(
        s,
        "{{\"ok\":true,\"engine\":\"acadrust\",\"engineVersion\":{},\"helperVersion\":{},\"version\":{},\"entities\":{},\"modelSpaceEntities\":{},\"layerCount\":{},\"blockCount\":{},\"recovered\":{},\"diagnostics\":{}",
        json_string(ACADRUST_VERSION),
        json_string(HELPER_VERSION),
        json_string(doc.version.as_str()),
        doc.entity_count(),
        doc.model_space_entities().count(),
        doc.layers.len(),
        doc.block_records.len(),
        recovered,
        diagnostics
    );
    if with_layers {
        let names: Vec<String> = doc.layers.names().map(json_string).collect();
        let _ = write!(s, ",\"layers\":[{}]", names.join(","));
    }
    s.push('}');
    s
}

// MARK: Reading

fn sniff(path: &Path) -> Option<String> {
    use std::io::Read;
    let mut f = std::fs::File::open(path).ok()?;
    let mut b = [0u8; 6];
    f.read_exact(&mut b).ok()?;
    let s = std::str::from_utf8(&b).ok()?.to_string();
    s.starts_with("AC").then_some(s)
}

/// Reads a DWG strictly, then in acadrust's failsafe (recovery) mode. A recovery that yields no entities at all is
/// treated as a failure, so Arcus can try its next engine instead of importing an empty drawing.
fn read_dwg(path: &Path) -> Result<(CadDocument, bool, usize), Failure> {
    if std::fs::metadata(path).is_err() {
        return Err(Failure::new(Exit::NoInput, format!("The file {} could not be opened.", path.display())));
    }
    let strict = DwgReader::from_file(path).and_then(|mut r| r.read_with_stats());
    let strict_error = match strict {
        Ok(o) => return Ok((o.document, false, o.stats.diagnostics.len())),
        Err(e) => e.to_string(),
    };
    let lenient = DwgReader::from_file_with_options(path, DwgReadOptions::failsafe()).and_then(|mut r| r.read_with_stats());
    match lenient {
        Ok(o) if o.document.entity_count() > 0 => Ok((o.document, true, o.stats.diagnostics.len())),
        Ok(_) => Err(Failure::new(Exit::Unreadable, format!("acadrust could not read this DWG ({}).", describe(path, &strict_error)))),
        Err(_) => Err(Failure::new(Exit::Unreadable, format!("acadrust could not read this DWG ({}).", describe(path, &strict_error)))),
    }
}

fn describe(path: &Path, error: &str) -> String {
    let v = sniff(path).unwrap_or_else(|| "no DWG version header".into());
    let mut e: String = error.chars().take(300).collect();
    if e.is_empty() {
        e = "unknown error".into();
    }
    format!("{v}: {e}")
}

fn read_dxf(path: &Path) -> Result<CadDocument, Failure> {
    if std::fs::metadata(path).is_err() {
        return Err(Failure::new(Exit::NoInput, format!("The file {} could not be opened.", path.display())));
    }
    match DxfReader::from_file(path).and_then(|r| r.read()) {
        Ok(d) => Ok(d),
        Err(strict) => {
            let config = DxfReaderConfiguration { failsafe: true, ..Default::default() };
            DxfReader::from_file(path)
                .and_then(|r| r.with_configuration(config).read())
                .map_err(|_| Failure::new(Exit::Unreadable, format!("The DXF could not be read: {}", strict.to_string().chars().take(300).collect::<String>())))
        }
    }
}

// MARK: Writing

/// Writes through `<out>.partial`, checks the partial file, then renames, so a stopped or failed run never leaves a
/// half-written or unreadable drawing behind.
fn write_atomically(
    out: &Path,
    write: impl FnOnce(&Path) -> acadrust::Result<()>,
    check: impl FnOnce(&Path) -> Result<(), Failure>,
) -> Result<(), Failure> {
    let mut partial = out.as_os_str().to_owned();
    partial.push(".partial");
    let partial = PathBuf::from(partial);
    let _ = std::fs::remove_file(&partial);
    let result = write(&partial)
        .map_err(|e| Failure::new(Exit::WriteFailed, format!("The drawing could not be written: {e}")))
        .and_then(|_| check(&partial))
        .and_then(|_| {
            std::fs::rename(&partial, out)
                .map_err(|e| Failure::new(Exit::WriteFailed, format!("The drawing could not be saved to {}: {e}", out.display())))
        });
    if result.is_err() {
        let _ = std::fs::remove_file(&partial);
    }
    result
}

// MARK: Commands

fn to_dxf(input: &Path, output: &Path) -> Outcome {
    let (doc, recovered, diagnostics) = read_dwg(input)?;
    write_atomically(output, |p| DxfWriter::new(&doc).write_to_file(p), |_| Ok(()))?;
    Ok(summary(&doc, recovered, diagnostics, false))
}

/// DWG versions this helper writes (Arcus offers the ones its round-trip corpus test confirmed).
fn target_version(s: &str) -> Result<DxfVersion, Failure> {
    match DxfVersion::parse(&s.to_ascii_uppercase()) {
        Some(v @ (DxfVersion::AC1015 | DxfVersion::AC1018 | DxfVersion::AC1021 | DxfVersion::AC1024 | DxfVersion::AC1027 | DxfVersion::AC1032)) => Ok(v),
        _ => Err(Failure::new(Exit::Usage, format!("Unsupported DWG version {s}; use AC1015, AC1018, AC1021, AC1024, AC1027 or AC1032."))),
    }
}

fn from_dxf(input: &Path, output: &Path, version: &str) -> Outcome {
    let target = target_version(version)?;
    let mut doc = read_dxf(input)?;
    let source_entities = doc.entity_count();
    let source_model = doc.model_space_entities().count();
    doc.version = target;
    write_atomically(
        output,
        |p| DwgWriter::write_to_file(p, &doc),
        // Read the new file back before it replaces anything: a DWG the engine cannot read again is not saved.
        |p| {
            let back = DwgReader::from_file(p)
                .and_then(|mut r| r.read())
                .map_err(|e| Failure::new(Exit::VerifyFailed, format!("The DWG was written but could not be read back ({e}), so it was not saved.")))?;
            let n = back.model_space_entities().count();
            if back.version != target || n < source_model {
                return Err(Failure::new(
                    Exit::VerifyFailed,
                    format!("The DWG read back with {n} of {source_model} model-space entities (version {}), so it was not saved.", back.version.as_str()),
                ));
            }
            Ok(())
        },
    )?;
    let mut s = summary(&doc, false, 0, false);
    s.pop();
    let _ = write!(s, ",\"sourceEntities\":{source_entities}}}");
    Ok(s)
}

fn info(input: &Path) -> Outcome {
    let (doc, recovered, diagnostics) = read_dwg(input)?;
    Ok(summary(&doc, recovered, diagnostics, true))
}

fn run(o: &Options) -> Outcome {
    match o.command.as_str() {
        "to-dxf" => to_dxf(&o.paths[0], &o.paths[1]),
        "from-dxf" => from_dxf(&o.paths[0], &o.paths[1], o.version.as_deref().unwrap_or("AC1032")),
        "info" => info(&o.paths[0]),
        _ => Ok(format!(
            "{{\"ok\":true,\"engine\":\"acadrust\",\"engineVersion\":{},\"helperVersion\":{},\"writes\":[\"AC1015\",\"AC1018\",\"AC1021\",\"AC1024\",\"AC1027\",\"AC1032\"]}}",
            json_string(ACADRUST_VERSION),
            json_string(HELPER_VERSION)
        )),
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let o = match parse(&args) {
        Ok(o) => o,
        Err(f) => {
            eprintln!("{}", f.message);
            std::process::exit(f.code as i32);
        }
    };
    LIMIT.store(o.max_memory_mb.max(1).saturating_mul(1 << 20), Ordering::Relaxed);
    let timeout = Duration::from_secs(o.timeout_s.max(1));
    std::thread::spawn(move || {
        std::thread::sleep(timeout);
        die_raw("The DWG engine did not finish within its time limit and was stopped.\n", Exit::Timeout);
    });
    panic::set_hook(Box::new(|info| {
        let msg = if let Some(s) = info.payload().downcast_ref::<&str>() {
            s.to_string()
        } else if let Some(s) = info.payload().downcast_ref::<String>() {
            s.clone()
        } else {
            "unknown panic".to_string()
        };
        let place = info.location().map(|l| format!(" at {}:{}", l.file(), l.line())).unwrap_or_default();
        if let Ok(mut m) = PANIC_MESSAGE.lock() {
            *m = Some(format!("{msg}{place}"));
        }
    }));
    // Deep block nesting can recurse far: run the work on a thread with a large stack.
    let worker = std::thread::Builder::new()
        .stack_size(256 << 20)
        .spawn(move || panic::catch_unwind(AssertUnwindSafe(|| run(&o))))
        .expect("worker thread");
    let result = match worker.join() {
        Ok(Ok(r)) => r,
        _ => {
            let detail = PANIC_MESSAGE.lock().ok().and_then(|m| m.clone()).unwrap_or_else(|| "unknown error".into());
            Err(Failure::new(Exit::Internal, format!("The DWG engine stopped on an internal error ({detail}).")))
        }
    };
    match result {
        Ok(json) => {
            println!("{json}");
            std::process::exit(Exit::Ok as i32);
        }
        Err(f) => {
            eprintln!("{}", f.message);
            std::process::exit(f.code as i32);
        }
    }
}
