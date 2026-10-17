//! Insert > Link PDF / Import PDF: a page rendered to an image by the system's PDF engine
//! (Windows.Data.Pdf), on a worker thread of its own.

use rc_core::model::{Id, ImageAsset};
use std::path::Path;

/// Pages in a PDF file.
pub fn page_count(path: &Path) -> Result<u32, String> {
    imp::render(path, None, 0.0).map(|(_, n)| n)
}

/// One page (0-based) as an image asset at `dpi`.
pub fn render_page(path: &Path, page: u32, dpi: f64, id: Id) -> Result<ImageAsset, String> {
    let (png, _) = imp::render(path, Some(page), dpi)?;
    let img = image::load_from_memory(&png).map_err(|e| format!("The PDF page could not be read: {e}"))?;
    let img = if img.width().max(img.height()) > 4096 { img.thumbnail(4096, 4096) } else { img };
    let rgba = img.to_rgba8();
    let (w, h) = rgba.dimensions();
    let mut rgb = Vec::with_capacity((w * h * 3) as usize);
    for px in rgba.pixels() {
        let a = px[3] as u32;
        for k in 0..3 {
            rgb.push(((px[k] as u32 * a + 255 * (255 - a)) / 255) as u8);
        }
    }
    let name = path.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_else(|| "PDF".into());
    Ok(ImageAsset::from_rgb(id, &format!("{name} (page {})", page + 1), w, h, &rgb))
}

#[cfg(windows)]
mod imp {
    use std::path::Path;
    use windows::Data::Pdf::{PdfDocument, PdfPageRenderOptions};
    use windows::Storage::StorageFile;
    use windows::Storage::Streams::{DataReader, InMemoryRandomAccessStream};
    use windows::Win32::System::Com::{COINIT_MULTITHREADED, CoInitializeEx};
    use windows::core::HSTRING;

    fn msg(e: windows::core::Error) -> String {
        format!("The PDF could not be read: {}", e.message())
    }

    /// The rendered page as PNG bytes (None page: count only) and the page count.
    pub fn render(path: &Path, page: Option<u32>, dpi: f64) -> Result<(Vec<u8>, u32), String> {
        let path = std::fs::canonicalize(path).map_err(|e| e.to_string())?.to_string_lossy().trim_start_matches(r"\\?\").to_string();
        // WinRT async calls are waited on in a multithreaded apartment of their own.
        std::thread::spawn(move || -> Result<(Vec<u8>, u32), String> {
            unsafe {
                let _ = CoInitializeEx(None, COINIT_MULTITHREADED);
            }
            let file = StorageFile::GetFileFromPathAsync(&HSTRING::from(path.as_str())).map_err(msg)?.join().map_err(msg)?;
            let doc = PdfDocument::LoadFromFileAsync(&file).map_err(msg)?.join().map_err(msg)?;
            let count = doc.PageCount().map_err(msg)?;
            let Some(page) = page else { return Ok((Vec::new(), count)) };
            if count == 0 {
                return Err("The PDF has no pages.".into());
            }
            let pg = doc.GetPage(page.min(count - 1)).map_err(msg)?;
            let size = pg.Size().map_err(msg)?;
            let opts = PdfPageRenderOptions::new().map_err(msg)?;
            opts.SetDestinationWidth(((size.Width as f64) * dpi / 96.0).max(16.0) as u32).map_err(msg)?;
            let stream = InMemoryRandomAccessStream::new().map_err(msg)?;
            pg.RenderWithOptionsToStreamAsync(&stream, &opts).map_err(msg)?.join().map_err(msg)?;
            let n = stream.Size().map_err(msg)? as u32;
            let input = stream.GetInputStreamAt(0).map_err(msg)?;
            let reader = DataReader::CreateDataReader(&input).map_err(msg)?;
            reader.LoadAsync(n).map_err(msg)?.join().map_err(msg)?;
            let mut buf = vec![0u8; n as usize];
            reader.ReadBytes(&mut buf).map_err(msg)?;
            Ok((buf, count))
        })
        .join()
        .map_err(|_| "The PDF could not be read.".to_string())?
    }
}

#[cfg(not(windows))]
mod imp {
    pub fn render(_: &std::path::Path, _: Option<u32>, _: f64) -> Result<(Vec<u8>, u32), String> {
        Err("PDF files can be imported on Windows only.".into())
    }
}
