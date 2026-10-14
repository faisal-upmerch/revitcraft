//! Application state, caches, documents and the top-level frame layout.

use crate::canvas::{self, Cam2, Interact};
use crate::commands::{Cmd, Shortcuts};
use crate::dialogs::Dialogs;
use crate::render3d::{Camera, Renderer, Scene};
use crate::snap::{Override, SnapGeom, SnapSettings};
use crate::tools::{Sketch, Tool, ToolKind, ToolOptions};
use crate::{actions, browser, options_bar, properties, ribbon, schedule_ui, sheet_ui, statusbar, style, view3d, viewbar};
use eframe::egui;
use egui_dock::{DockArea, DockState, TabViewer};
use rc_core::analysis::{self, Footprint};
use rc_core::geom::{DVec2, DVec3};
use rc_core::model::*;
use rc_core::plan::Drawing;
use rc_core::section::ViewFrame;
use rc_core::units::UnitSystem;
use rc_core::{defaults, io};
use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use std::rc::Rc;

/// User settings kept between sessions (File > Options, Snaps, shortcuts, UI layout).
#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
#[serde(default)]
pub struct Settings {
    pub dark: bool,
    pub black_canvas: bool,
    pub user: String,
    pub snaps: SnapSettings,
    pub shortcuts: Shortcuts,
    pub tooltips: bool,
    pub recent: Vec<String>,
    pub show_properties: bool,
    pub show_browser: bool,
    pub show_status: bool,
    pub show_options_bar: bool,
    pub show_viewcube: bool,
    pub show_navbar: bool,
    pub drag_on_selection: bool,
    pub select_pinned: bool,
    pub select_underlay: bool,
    pub select_links: bool,
    pub select_by_face: bool,
    pub palette_width: f32,
}

impl Default for Settings {
    fn default() -> Self {
        Settings {
            dark: false,
            black_canvas: false,
            user: std::env::var("USERNAME").or_else(|_| std::env::var("USER")).unwrap_or_default(),
            snaps: SnapSettings::default(),
            shortcuts: Shortcuts::default(),
            tooltips: true,
            recent: Vec::new(),
            show_properties: true,
            show_browser: true,
            show_status: true,
            show_options_bar: true,
            show_viewcube: true,
            show_navbar: true,
            drag_on_selection: true,
            select_pinned: true,
            select_underlay: true,
            select_links: true,
            select_by_face: false,
            palette_width: 290.0,
        }
    }
}

pub struct Toast {
    pub text: String,
    pub error: bool,
    pub until: f64,
}

/// Temporary Hide/Isolate state of one view (not saved, cyan border while active).
#[derive(Clone, Debug, Default)]
pub struct TempHide {
    pub hidden_elements: HashSet<Id>,
    pub hidden_categories: HashSet<Category>,
    pub isolate_elements: Option<HashSet<Id>>,
    pub isolate_categories: Option<HashSet<Category>>,
}

impl TempHide {
    pub fn hides(&self, id: Id, c: Category) -> bool {
        if self.hidden_elements.contains(&id) || self.hidden_categories.contains(&c) {
            return true;
        }
        if let Some(iso) = &self.isolate_elements {
            if !iso.contains(&id) {
                return true;
            }
        }
        if let Some(iso) = &self.isolate_categories {
            if !iso.contains(&c) {
                return true;
            }
        }
        false
    }
    pub fn is_active(&self) -> bool {
        !self.hidden_elements.is_empty() || !self.hidden_categories.is_empty() || self.isolate_elements.is_some() || self.isolate_categories.is_some()
    }
}

#[derive(Clone, Debug)]
pub struct Clipboard {
    pub elements: Vec<Element>,
    pub base: DVec2,
    pub level: Option<Id>,
}

#[derive(Default)]
pub struct Cache {
    pub revision: u64,
    pub footprints: Rc<HashMap<Id, Footprint>>,
    pub drawings: HashMap<Id, Rc<Drawing>>,
    pub revealed: HashMap<Id, Rc<Drawing>>,
    pub frames: HashMap<Id, Option<ViewFrame>>,
    pub snap: HashMap<Id, Rc<SnapGeom>>,
    pub tables: HashMap<Id, Rc<rc_core::schedule::Table>>,
    pub bounds: Option<Option<(DVec3, DVec3)>>,
    /// Element id → index in `Project::elements`.
    pub index: Rc<HashMap<Id, usize>>,
    /// Read-only copy of the project for palettes (made at most once per change).
    pub snapshot: Option<Rc<Project>>,
    /// Plan pick outlines per view.
    pub picks: HashMap<Id, Rc<Vec<canvas::PickShape>>>,
    /// Sheet layouts and viewport boxes per sheet.
    pub sheets: HashMap<Id, Rc<(Vec<rc_core::sheet::SheetPrim>, Vec<rc_core::sheet::ViewportBox>)>>,
}

pub struct App {
    pub doc: Document,
    pub renderer: Option<Renderer>,
    pub dock: Option<DockState<Id>>,
    pub active: Option<Id>,
    pub selection: Vec<Id>,
    pub prev_selection: Vec<Id>,
    pub tool: Tool,
    pub sketch: Option<Sketch>,
    pub opts: ToolOptions,
    pub cams: HashMap<Id, Cam2>,
    pub nav_history: HashMap<Id, canvas::NavHistory>,
    pub cams3d: HashMap<Id, Camera>,
    pub cache: Cache,
    pub scenes: HashMap<Id, Scene>,
    pub toast: Option<Toast>,
    pub dialogs: Dialogs,
    pub key_buffer: (String, f64),
    /// Digits typed while drawing (listening dimension).
    pub typed: String,
    pub snap_override: Option<Override>,
    pub interact: Interact,
    pub clipboard: Option<Clipboard>,
    pub temp_hide: HashMap<Id, TempHide>,
    pub reveal_hidden: HashSet<Id>,
    pub thin_lines: bool,
    pub settings: Settings,
    pub active_option: Option<Id>,
    pub group_edit: Option<(Id, Project)>,
    pub ribbon_tab: ribbon::Tab,
    pub file_menu: bool,
    pub last_cmd: Option<Cmd>,
    pub recent_cmds: Vec<Cmd>,
    pub warnings: Vec<String>,
    pub now: f64,
    pub quit_requested: bool,
    pub screenshot: Option<(PathBuf, u32)>,
    pub input_script: Option<crate::script::InputScript>,
    pub family_editor: Option<crate::family_editor::FamilyEditor>,
    pub settings_dirty: bool,
}

impl App {
    pub fn new(cc: &eframe::CreationContext<'_>) -> App {
        let settings: Settings = cc.storage.and_then(|s| eframe::get_value(s, "settings")).unwrap_or_default();
        style::apply(&cc.egui_ctx, settings.dark);
        let renderer = cc.wgpu_render_state.as_ref().map(Renderer::new);
        let project = defaults::new_project(UnitSystem::Metric);
        let mut app = App {
            opts: ToolOptions::for_project(&project),
            doc: Document::new(project),
            renderer,
            dock: Some(DockState::new(vec![])),
            active: None,
            selection: Vec::new(),
            prev_selection: Vec::new(),
            tool: Tool::select(),
            sketch: None,
            cams: HashMap::new(),
            nav_history: HashMap::new(),
            cams3d: HashMap::new(),
            cache: Cache::default(),
            scenes: HashMap::new(),
            toast: None,
            dialogs: Dialogs::default(),
            key_buffer: (String::new(), 0.0),
            typed: String::new(),
            snap_override: None,
            interact: Interact::default(),
            clipboard: None,
            temp_hide: HashMap::new(),
            reveal_hidden: HashSet::new(),
            thin_lines: false,
            settings,
            active_option: None,
            group_edit: None,
            ribbon_tab: ribbon::Tab::Architecture,
            file_menu: false,
            last_cmd: None,
            recent_cmds: Vec::new(),
            warnings: Vec::new(),
            now: 0.0,
            quit_requested: false,
            screenshot: std::env::var("RC_SCREENSHOT").ok().map(|p| (PathBuf::from(p), 0)),
            input_script: crate::script::InputScript::from_env(),
            family_editor: None,
            settings_dirty: false,
        };
        app.open_first_plan();
        app.dialogs.home = std::env::args().skip(1).all(|a| a.is_empty()) && app.screenshot.is_none();
        app.handle_args();
        app
    }

    /// Command line: [project.rcx | model.ifc] [--sample] [--imperial] [--view NAME] [--select CATEGORY]
    /// [--tool XX] [--dialog NAME] [--tile]
    fn handle_args(&mut self) {
        let args: Vec<String> = std::env::args().skip(1).collect();
        let mut k = 0;
        while k < args.len() {
            let next = |k: &mut usize| -> Option<String> {
                *k += 1;
                args.get(*k).cloned()
            };
            match args[k].as_str() {
                "--sample" => self.open_sample(),
                "--imperial" => self.replace_document(defaults::new_project(UnitSystem::Imperial), None),
                "--view" => {
                    if let Some(name) = next(&mut k) {
                        let found = self
                            .doc
                            .data
                            .views
                            .iter()
                            .find(|v| v.name == name || matches!(&v.kind, ViewKind::Sheet(s) if s.number == name))
                            .map(|v| v.id);
                        if let Some(id) = found {
                            self.open_view(id);
                        }
                    }
                }
                "--select" => {
                    if let Some(cat) = next(&mut k) {
                        self.selection = self.doc.data.elements.iter().filter(|e| e.category().label().eq_ignore_ascii_case(&cat)).map(|e| e.id).take(1).collect();
                    }
                }
                "--select-all" => {
                    if let Some(cat) = next(&mut k) {
                        self.selection = self.doc.data.elements.iter().filter(|e| e.category().label().eq_ignore_ascii_case(&cat)).map(|e| e.id).collect();
                    }
                }
                "--tool" => {
                    if let Some(code) = next(&mut k) {
                        if let Some(c) = self.settings.shortcuts.lookup(&code) {
                            actions::exec(self, c);
                        }
                    }
                }
                "--cmd" => {
                    if let Some(name) = next(&mut k) {
                        if let Some(c) = Cmd::ALL.iter().find(|c| c.key_name().eq_ignore_ascii_case(&name)) {
                            actions::exec(self, *c);
                        }
                    }
                }
                "--dialog" => {
                    if let Some(name) = next(&mut k) {
                        crate::dialogs::open_by_name(self, &name);
                    }
                }
                "--dark" => {
                    self.settings.dark = true;
                }
                "--tile" => actions::exec(self, Cmd::TileViews),
                path => self.open_path(std::path::Path::new(path)),
            }
            k += 1;
        }
    }

    pub fn open_sample(&mut self) {
        self.replace_document(rc_core::sample::sample_house(), None);
        self.info("Opened the sample project.");
    }

    fn screenshot_step(&mut self, ctx: &egui::Context) {
        let Some((path, frames)) = self.screenshot.as_mut() else { return };
        *frames += 1;
        ctx.request_repaint();
        if *frames == crate::script::shot_frame() {
            ctx.send_viewport_cmd(egui::ViewportCommand::Screenshot(Default::default()));
        }
        let path = path.clone();
        let image = ctx.input(|i| {
            i.events.iter().find_map(|e| match e {
                egui::Event::Screenshot { image, .. } => Some(image.clone()),
                _ => None,
            })
        });
        if let Some(img) = image {
            let rgba: Vec<u8> = img.pixels.iter().flat_map(|c| c.to_array()).collect();
            let _ = std::fs::write(&path, rc_core::png::encode(img.size[0] as u32, img.size[1] as u32, 4, &rgba));
            self.quit_requested = true;
            self.doc.dirty = false;
            ctx.send_viewport_cmd(egui::ViewportCommand::Close);
        }
    }

    pub fn open_first_plan(&mut self) {
        let first = self.doc.data.views.iter().find(|v| matches!(v.kind, ViewKind::FloorPlan { .. }) && !v.is_template).map(|v| v.id);
        if let Some(id) = first {
            self.open_view(id);
        }
    }

    // ------------------------------------------------------------ messages

    pub fn info(&mut self, text: impl Into<String>) {
        self.toast = Some(Toast { text: text.into(), error: false, until: self.now + 4.0 });
    }

    pub fn error(&mut self, text: impl Into<String>) {
        let text = text.into();
        self.warnings.push(text.clone());
        self.toast = Some(Toast { text, error: true, until: self.now + 6.0 });
    }

    /// Runs a model change as one undoable transaction, reporting errors. New elements join the
    /// active design option, the active view's phase and the group being edited.
    pub fn run<T>(&mut self, name: &str, f: impl FnOnce(&mut Project) -> Result<T, String>) -> Option<T> {
        let option = self.active_option;
        let phase = self.active_view().and_then(|v| v.phase);
        let group = self.group_edit.as_ref().map(|g| g.0);
        let result = self.doc.transact(name, |p| {
            let first_new = p.next_id;
            let v = f(p)?;
            for e in p.elements.iter_mut().filter(|e| e.id >= first_new && e.view.is_none()) {
                if option.is_some() && e.design_option.is_none() {
                    e.design_option = option;
                }
                if phase.is_some() && e.phase_created.is_none() {
                    e.phase_created = phase;
                }
                if let Some(g) = group {
                    if e.group.is_none() && e.id != g {
                        e.group = Some(g);
                    }
                }
            }
            Ok(v)
        });
        match result {
            Ok(v) => Some(v),
            Err(e) => {
                self.error(e);
                None
            }
        }
    }

    // ------------------------------------------------------------ caches

    pub fn refresh_cache(&mut self) {
        if self.cache.revision == self.doc.revision {
            return;
        }
        self.cache.revision = self.doc.revision;
        self.cache.footprints = Rc::new(analysis::wall_footprints(&self.doc.data));
        self.cache.drawings.clear();
        self.cache.revealed.clear();
        self.cache.frames.clear();
        self.cache.snap.clear();
        self.cache.tables.clear();
        self.cache.bounds = None;
        self.cache.snapshot = None;
        self.cache.picks.clear();
        self.cache.sheets.clear();
        self.cache.index = Rc::new(self.doc.data.elements.iter().enumerate().map(|(i, e)| (e.id, i)).collect());
        let p = &self.doc.data;
        self.selection.retain(|id| p.element(*id).is_some());
        if let Some(dock) = self.dock.as_mut() {
            dock.retain_tabs(|id| p.view(*id).is_some());
        }
        if self.active.is_some_and(|a| p.view(a).is_none()) {
            self.active = self.dock.as_ref().and_then(|d| d.iter_all_tabs().map(|(_, t)| *t).last());
        }
        self.opts.validate(p);
        if self.active_option.is_some_and(|o| !p.option_sets.iter().any(|s| s.options.iter().any(|x| x.id == o))) {
            self.active_option = None;
        }
    }

    /// Fast element lookup through the cached index.
    pub fn el(&self, id: Id) -> Option<&Element> {
        self.cache.index.get(&id).and_then(|i| self.doc.data.elements.get(*i)).filter(|e| e.id == id).or_else(|| self.doc.data.element(id))
    }

    /// A cheap shared copy of the project for UI code that must read while it edits.
    pub fn snapshot(&mut self) -> Rc<Project> {
        self.refresh_cache();
        if let Some(s) = &self.cache.snapshot {
            return s.clone();
        }
        let s = Rc::new(self.doc.data.clone());
        self.cache.snapshot = Some(s.clone());
        s
    }

    /// Sheet layout (primitives and viewport boxes), cached per change.
    pub fn sheet_layout(&mut self, sheet: Id) -> Rc<(Vec<rc_core::sheet::SheetPrim>, Vec<rc_core::sheet::ViewportBox>)> {
        if let Some(s) = self.cache.sheets.get(&sheet) {
            return s.clone();
        }
        let fp = self.footprints();
        let p = &self.doc.data;
        let r = match p.view(sheet) {
            Some(v) => {
                let prims = rc_core::sheet::layout(p, v, &fp);
                let boxes = match &v.kind {
                    ViewKind::Sheet(sh) => rc_core::sheet::viewport_boxes(p, sh, &fp),
                    _ => vec![],
                };
                Rc::new((prims, boxes))
            }
            None => Rc::new((vec![], vec![])),
        };
        self.cache.sheets.insert(sheet, r.clone());
        r
    }

    pub fn footprints(&self) -> Rc<HashMap<Id, Footprint>> {
        self.cache.footprints.clone()
    }

    /// The 2D drawing of a plan, section, elevation, drafting view or legend.
    pub fn drawing(&mut self, view: Id) -> Rc<Drawing> {
        if let Some(d) = self.cache.drawings.get(&view) {
            return d.clone();
        }
        let fp = self.footprints();
        let d = match self.doc.data.view(view) {
            Some(v) => Rc::new(rc_core::sheet::view_drawing(&self.doc.data, v, &fp).unwrap_or_default()),
            None => Rc::new(Drawing::default()),
        };
        self.cache.drawings.insert(view, d.clone());
        d
    }

    /// The drawing with hidden elements and categories shown (Reveal Hidden Elements).
    pub fn revealed_drawing(&mut self, view: Id) -> Rc<Drawing> {
        if let Some(d) = self.cache.revealed.get(&view) {
            return d.clone();
        }
        let fp = self.footprints();
        let d = match self.doc.data.view(view) {
            Some(v) => {
                let mut v = v.clone();
                v.hidden.clear();
                v.hidden_elements.clear();
                Rc::new(rc_core::sheet::view_drawing(&self.doc.data, &v, &fp).unwrap_or_default())
            }
            None => Rc::new(Drawing::default()),
        };
        self.cache.revealed.insert(view, d.clone());
        d
    }

    pub fn frame_of(&mut self, view: Id) -> Option<ViewFrame> {
        if let Some(f) = self.cache.frames.get(&view) {
            return *f;
        }
        let fp = self.footprints();
        let f = self.doc.data.view(view).and_then(|v| rc_core::section::view_frame(&self.doc.data, v, &fp));
        self.cache.frames.insert(view, f);
        f
    }

    pub fn model_bounds(&mut self) -> Option<(DVec3, DVec3)> {
        if let Some(b) = self.cache.bounds {
            return b;
        }
        let fp = self.footprints();
        let b = rc_core::sheet::model_bounds(&self.doc.data, &fp);
        self.cache.bounds = Some(b);
        b
    }

    pub fn table(&mut self, view: Id) -> Option<Rc<rc_core::schedule::Table>> {
        if let Some(t) = self.cache.tables.get(&view) {
            return Some(t.clone());
        }
        let v = self.doc.data.view(view)?;
        let ViewKind::Schedule(def) = &v.kind else { return None };
        let t = Rc::new(rc_core::schedule::build(&self.doc.data, def));
        self.cache.tables.insert(view, t.clone());
        Some(t)
    }

    // ------------------------------------------------------------ views

    pub fn open_view(&mut self, id: Id) {
        let Some(dock) = self.dock.as_mut() else { return };
        match dock.find_tab(&id) {
            Some(path) => {
                let _ = dock.set_active_tab(path);
                dock.set_focused_node_and_surface(path.node_path());
            }
            None => dock.push_to_focused_leaf(id),
        }
        self.activate(id);
    }

    /// Makes `id` the active view (tools that need another view type are cancelled).
    pub fn activate(&mut self, id: Id) {
        if self.active == Some(id) {
            return;
        }
        self.active = Some(id);
        if !self.tool.is_select() && self.sketch.is_none() {
            let ok = self.active_view().is_some_and(|v| !self.tool.kind.needs_plan() || v.plan_level().is_some());
            if !ok {
                self.tool = Tool::select();
            }
        } else {
            self.tool.reset();
        }
        self.interact = Interact::default();
    }

    pub fn close_view(&mut self, id: Id) {
        if let Some(dock) = self.dock.as_mut() {
            if let Some(path) = dock.find_tab(&id) {
                dock.remove_tab(path);
            }
        }
        if self.active == Some(id) {
            self.active = self.dock.as_ref().and_then(|d| d.iter_all_tabs().map(|(_, t)| *t).last());
        }
        if let Some(r) = self.renderer.as_mut() {
            r.forget(id);
        }
        self.scenes.remove(&id);
    }

    pub fn open_tabs(&self) -> Vec<Id> {
        self.dock.as_ref().map(|d| d.iter_all_tabs().map(|(_, t)| *t).collect()).unwrap_or_default()
    }

    pub fn active_view(&self) -> Option<&View> {
        self.active.and_then(|id| self.doc.data.view(id))
    }

    pub fn active_level(&self) -> Option<Id> {
        self.active_view().and_then(|v| v.plan_level())
    }

    pub fn view_title(&self, id: Id) -> String {
        match self.doc.data.view(id) {
            Some(v) => match &v.kind {
                ViewKind::Sheet(s) => format!("Sheet: {} - {}", s.number, v.name),
                ViewKind::ThreeD { .. } => format!("3D View: {}", v.name),
                _ => format!("{}: {}", v.type_label(), v.name),
            },
            None => "View".into(),
        }
    }

    /// Starts a tool, switching to a suitable view when needed.
    pub fn set_tool(&mut self, kind: ToolKind) {
        if kind.needs_plan() && self.active_level().is_none() && self.sketch.is_none() {
            let plan = self
                .doc
                .data
                .views
                .iter()
                .find(|v| matches!(v.kind, ViewKind::FloorPlan { .. }) && !v.is_template)
                .map(|v| v.id);
            match plan {
                Some(id) => self.open_view(id),
                None => {
                    self.error("Open a plan view to use this tool.");
                    return;
                }
            }
        }
        if kind.needs_selection() && self.selection.is_empty() {
            self.error(format!("{}: select elements first, then start the tool.", kind.name()));
            return;
        }
        if self.active_view().is_some_and(|v| !v.is_graphical() || matches!(v.kind, ViewKind::ThreeD { .. })) && kind != ToolKind::Select {
            self.error(format!("{} cannot be used in this view. Open a plan, section or elevation.", kind.name()));
            return;
        }
        self.typed.clear();
        self.snap_override = None;
        let mut t = Tool::new(kind);
        t.ids = self.selection.clone();
        self.tool = t;
        self.interact.drag = None;
    }

    pub fn cancel(&mut self) {
        self.typed.clear();
        self.snap_override = None;
        self.interact.drag = None;
        self.interact.temp_dim_edit = None;
        if self.tool.in_progress() {
            self.tool.reset();
            return;
        }
        if !self.tool.is_select() {
            self.tool = Tool::select();
            return;
        }
        if let Some(s) = self.sketch.as_mut() {
            if !s.selected.is_empty() {
                s.selected.clear();
                return;
            }
            // Esc in sketch mode just returns to the draw tool.
            return;
        }
        if !self.selection.is_empty() {
            self.prev_selection = std::mem::take(&mut self.selection);
        }
    }

    pub fn select(&mut self, ids: Vec<Id>) {
        if !self.selection.is_empty() && ids != self.selection {
            self.prev_selection = self.selection.clone();
        }
        self.selection = ids;
    }

    // ------------------------------------------------------------ documents

    pub fn title(&self) -> String {
        let name = self.doc.path.as_ref().and_then(|p| p.file_stem()).map(|s| s.to_string_lossy().to_string()).unwrap_or_else(|| "Project1".into());
        let view = self.active.map(|v| format!(" - {}", self.view_title(v))).unwrap_or_default();
        format!("RevitCraft - {}{}{}", name, if self.doc.dirty { "*" } else { "" }, view)
    }

    pub fn replace_document(&mut self, project: Project, path: Option<PathBuf>) {
        let mut doc = Document::new(project);
        doc.path = path;
        self.doc = doc;
        self.opts = ToolOptions::for_project(&self.doc.data);
        self.dock = Some(DockState::new(vec![]));
        self.active = None;
        self.selection.clear();
        self.prev_selection.clear();
        self.tool = Tool::select();
        self.sketch = None;
        self.cams.clear();
        self.nav_history.clear();
        self.cams3d.clear();
        self.scenes.clear();
        self.cache = Cache::default();
        self.dialogs = Dialogs::default();
        self.temp_hide.clear();
        self.reveal_hidden.clear();
        self.active_option = None;
        self.group_edit = None;
        self.interact = Interact::default();
        self.family_editor = None;
        self.open_first_plan();
    }

    pub fn new_project(&mut self, system: UnitSystem) {
        self.replace_document(defaults::new_project(system), None);
        self.info(format!("New project from the {} template.", if system == UnitSystem::Metric { "metric" } else { "imperial" }));
    }

    pub fn add_recent(&mut self, path: &std::path::Path) {
        let s = path.display().to_string();
        self.settings.recent.retain(|r| r != &s);
        self.settings.recent.insert(0, s);
        self.settings.recent.truncate(8);
        self.settings_dirty = true;
    }

    pub fn open_dialog(&mut self) {
        if let Some(path) = rfd::FileDialog::new().add_filter("Projects and IFC", &[io::EXTENSION, "ifc"]).add_filter("RevitCraft Project", &[io::EXTENSION]).add_filter("IFC", &["ifc"]).pick_file() {
            self.open_path(&path);
        }
    }

    pub fn open_path(&mut self, path: &std::path::Path) {
        let ext = path.extension().map(|e| e.to_string_lossy().to_lowercase()).unwrap_or_default();
        match ext.as_str() {
            "ifc" => self.import_ifc_path(path),
            "rcfa" => crate::actions::load_family_path(self, path),
            "dxf" => crate::actions::link_cad_path(self, path),
            _ => match io::load(path) {
                Ok(p) => {
                    self.replace_document(p, Some(path.to_path_buf()));
                    self.add_recent(path);
                    self.info(format!("Opened {}", path.display()));
                }
                Err(e) => self.error(e),
            },
        }
    }

    pub fn save(&mut self) -> bool {
        match self.doc.path.clone() {
            Some(path) => self.save_to(&path),
            None => self.save_as(),
        }
    }

    pub fn save_as(&mut self) -> bool {
        let Some(mut path) = rfd::FileDialog::new().add_filter("RevitCraft Project", &[io::EXTENSION]).set_file_name("Project1.rcx").save_file() else {
            return false;
        };
        if path.extension().is_none() {
            path.set_extension(io::EXTENSION);
        }
        self.save_to(&path)
    }

    fn save_to(&mut self, path: &std::path::Path) -> bool {
        self.store_cameras();
        match io::save(&self.doc.data, path) {
            Ok(()) => {
                self.doc.path = Some(path.to_path_buf());
                self.doc.dirty = false;
                self.add_recent(path);
                self.info(format!("Saved {}", path.display()));
                true
            }
            Err(e) => {
                self.error(e);
                false
            }
        }
    }

    /// Writes the 3D view cameras into the model (not an undo step).
    pub fn store_cameras(&mut self) {
        for (id, cam) in &self.cams3d {
            if let Some(v) = self.doc.data.view_mut(*id) {
                if let ViewKind::ThreeD { perspective, .. } = v.kind {
                    v.kind = ViewKind::ThreeD { eye: cam.eye, target: cam.target, perspective };
                }
            }
        }
    }

    pub fn import_ifc_path(&mut self, path: &std::path::Path) {
        let text = match std::fs::read(path) {
            Ok(b) => String::from_utf8_lossy(&b).to_string(),
            Err(e) => {
                self.error(format!("Could not read {}: {e}", path.display()));
                return;
            }
        };
        match rc_core::ifc::import(&text) {
            Ok(r) => {
                self.replace_document(r.project, None);
                self.doc.dirty = true;
                if r.warnings.is_empty() {
                    self.info(format!("Imported {}", path.display()));
                } else {
                    self.warnings.extend(r.warnings.iter().cloned());
                    self.dialogs.import_warnings = Some(r.warnings);
                    self.info(format!("Imported {} with warnings", path.display()));
                }
                if let Some(v) = self.doc.data.views.iter().find(|v| matches!(v.kind, ViewKind::ThreeD { .. })).map(|v| v.id) {
                    self.open_view(v);
                }
            }
            Err(e) => self.error(format!("IFC import failed: {e}")),
        }
    }

    /// Asks before discarding unsaved changes. Returns true when it is safe to continue.
    pub fn confirm_discard(&mut self, action: crate::dialogs::Pending) -> bool {
        if !self.doc.dirty {
            return true;
        }
        self.dialogs.pending = Some(action);
        false
    }

    pub fn undo(&mut self) {
        if self.sketch.is_some() {
            if let Some(s) = self.sketch.as_mut() {
                s.segs.pop();
                s.slopes.pop();
            }
            return;
        }
        if let Some(name) = self.doc.undo_name().map(String::from) {
            self.doc.undo();
            self.info(format!("Undo: {name}"));
        }
    }

    pub fn redo(&mut self) {
        if let Some(name) = self.doc.redo_name().map(String::from) {
            self.doc.redo();
            self.info(format!("Redo: {name}"));
        }
    }

    // ------------------------------------------------------------ keyboard

    fn handle_keys(&mut self, ctx: &egui::Context) {
        if ctx.egui_wants_keyboard_input() || self.family_editor.is_some() {
            return;
        }
        let (events, modifiers) = ctx.input(|i| (i.events.clone(), i.modifiers));
        for ev in events {
            match ev {
                egui::Event::Key { key, pressed: true, .. } => self.key(key, modifiers),
                egui::Event::Copy => actions::exec(self, Cmd::CopyClip),
                egui::Event::Cut => actions::exec(self, Cmd::Cut),
                egui::Event::Paste(_) => actions::exec(self, Cmd::Paste),
                _ => {}
            }
        }
    }

    fn key(&mut self, key: egui::Key, m: egui::Modifiers) {
        use egui::Key as K;
        if m.command {
            match key {
                K::Z if m.shift => self.redo(),
                K::Z => self.undo(),
                K::Y => self.redo(),
                K::S if m.shift => {
                    self.save_as();
                }
                K::S => {
                    self.save();
                }
                K::O => {
                    if self.confirm_discard(crate::dialogs::Pending::Open) {
                        self.open_dialog();
                    }
                }
                K::N => {
                    if self.confirm_discard(crate::dialogs::Pending::New) {
                        self.dialogs.new_project = true;
                    }
                }
                K::A => actions::select_all_in_view(self),
                K::Tab => self.cycle_views(),
                K::V => actions::exec(self, Cmd::Paste),
                K::C => actions::exec(self, Cmd::CopyClip),
                K::X => actions::exec(self, Cmd::Cut),
                _ => {}
            }
            return;
        }
        let drawing_active = self.tool.in_progress() || (self.sketch.is_some() && !self.tool.pts.is_empty());
        let digit = match key {
            K::Num0 => Some('0'),
            K::Num1 => Some('1'),
            K::Num2 => Some('2'),
            K::Num3 => Some('3'),
            K::Num4 => Some('4'),
            K::Num5 => Some('5'),
            K::Num6 => Some('6'),
            K::Num7 => Some('7'),
            K::Num8 => Some('8'),
            K::Num9 => Some('9'),
            K::Period => Some('.'),
            K::Minus => Some('-'),
            K::Quote => Some('\''),
            _ => None,
        };
        if drawing_active {
            if let Some(d) = digit {
                self.typed.push(d);
                return;
            }
            if key == K::Backspace && !self.typed.is_empty() {
                self.typed.pop();
                return;
            }
            if key == K::Space && !self.typed.is_empty() {
                self.typed.push(' ');
                return;
            }
        }
        match key {
            K::Escape => self.cancel(),
            K::Delete => actions::exec(self, Cmd::Delete),
            K::Backspace if self.tool.is_select() => actions::exec(self, Cmd::Delete),
            K::Enter => canvas::enter(self),
            K::Tab => self.interact.tab_pressed = true,
            K::Space => canvas::space(self),
            K::ArrowLeft | K::ArrowRight | K::ArrowUp | K::ArrowDown => {
                let d = match key {
                    K::ArrowLeft => DVec2::new(-1.0, 0.0),
                    K::ArrowRight => DVec2::new(1.0, 0.0),
                    K::ArrowUp => DVec2::new(0.0, 1.0),
                    _ => DVec2::new(0.0, -1.0),
                };
                canvas::nudge(self, d, m.shift);
            }
            K::F1 => self.dialogs.about = true,
            K::F8 => {}
            _ => {
                let c = match digit {
                    Some(d) => Some(d),
                    None => key_letter(key),
                };
                if let Some(c) = c {
                    self.shortcut(c);
                }
            }
        }
    }

    /// Two-letter keyboard shortcuts (WA, DR, ...).
    pub fn shortcut(&mut self, c: char) {
        if self.now - self.key_buffer.1 > 1.5 {
            self.key_buffer.0.clear();
        }
        self.key_buffer.0.push(c.to_ascii_uppercase());
        self.key_buffer.1 = self.now;
        let seq = self.key_buffer.0.clone();
        if let Some(cmd) = self.settings.shortcuts.lookup(&seq) {
            if !self.settings.shortcuts.is_prefix(&seq) || seq.len() >= 2 {
                self.key_buffer.0.clear();
                actions::exec(self, cmd);
                return;
            }
        }
        if !self.settings.shortcuts.is_prefix(&seq) {
            // Start over with the last key as the first of a new sequence.
            self.key_buffer.0 = seq[seq.len() - 1..].to_string();
            if !self.settings.shortcuts.is_prefix(&self.key_buffer.0) {
                self.key_buffer.0.clear();
            }
        }
    }

    pub fn cycle_views(&mut self) {
        let tabs = self.open_tabs();
        if tabs.len() < 2 {
            return;
        }
        let i = self.active.and_then(|a| tabs.iter().position(|t| *t == a)).unwrap_or(0);
        self.open_view(tabs[(i + 1) % tabs.len()]);
    }

    // ------------------------------------------------------------ frame

    pub fn frame(&mut self, ui: &mut egui::Ui) {
        let ctx = ui.ctx().clone();
        self.now = ctx.input(|i| i.time);
        if style::is_dark() != self.settings.dark {
            style::apply(&ctx, self.settings.dark);
        }
        self.refresh_cache();
        self.handle_keys(&ctx);
        self.refresh_cache();
        ctx.send_viewport_cmd(egui::ViewportCommand::Title(self.title()));

        if let Some(fe) = self.family_editor.take() {
            let keep = crate::family_editor::show(self, fe, ui);
            self.family_editor = keep;
            self.show_toast(&ctx);
            crate::dialogs::show(self, &ctx);
            self.screenshot_step(&ctx);
            return;
        }

        egui::Panel::top("ribbon").frame(style::ribbon_frame()).show(ui, |ui| ribbon::show(self, ui));
        if self.settings.show_options_bar {
            let contextual = !self.tool.is_select() || !self.selection.is_empty() || self.sketch.is_some();
            let fill = if contextual { style::ribbon_tint(self.sketch.is_some()) } else { style::ribbon() };
            egui::Panel::top("options_bar").frame(style::bar_frame().fill(fill)).exact_size(23.0).show(ui, |ui| options_bar::show(self, ui));
        }
        if self.settings.show_status {
            egui::Panel::bottom("status").frame(style::bar_frame()).exact_size(22.0).show(ui, |ui| statusbar::show(self, ui));
        }
        if self.settings.show_properties || self.settings.show_browser {
            let resp = egui::Panel::left("palettes")
                .resizable(true)
                .default_size(self.settings.palette_width)
                .size_range(200.0..=520.0)
                .frame(style::side_frame())
                .show(ui, |ui| {
                    let total = ui.available_height();
                    match (self.settings.show_properties, self.settings.show_browser) {
                        (true, true) => {
                            egui::Panel::top("properties_palette")
                                .resizable(true)
                                .default_size(total * 0.52)
                                .size_range(120.0..=total - 120.0)
                                .frame(egui::Frame::NONE)
                                .show(ui, |ui| properties::show(self, ui));
                            egui::CentralPanel::default().frame(egui::Frame::NONE).show(ui, |ui| browser::show(self, ui));
                        }
                        (true, false) => properties::show(self, ui),
                        _ => browser::show(self, ui),
                    }
                });
            self.settings.palette_width = resp.response.rect.width();
        }
        egui::CentralPanel::default().frame(style::canvas_frame()).show(ui, |ui| self.dock_area(ui));

        crate::dialogs::show(self, &ctx);
        self.show_toast(&ctx);
        self.screenshot_step(&ctx);

        if ctx.input(|i| i.viewport().close_requested()) && self.doc.dirty && !self.quit_requested {
            ctx.send_viewport_cmd(egui::ViewportCommand::CancelClose);
            self.dialogs.pending = Some(crate::dialogs::Pending::Quit);
        }
    }

    fn dock_area(&mut self, ui: &mut egui::Ui) {
        let Some(mut dock) = self.dock.take() else { return };
        if dock.iter_all_tabs().next().is_none() {
            self.dock = Some(dock);
            ui.centered_and_justified(|ui| {
                ui.label(egui::RichText::new("Open a view from the Project Browser").size(16.0).color(style::text_dim()));
            });
            return;
        }
        let mut dstyle = egui_dock::Style::from_egui(ui.style());
        dstyle.tab_bar.bg_fill = style::tab_idle();
        dstyle.tab_bar.height = 21.0;
        dstyle.tab_bar.hline_color = style::border();
        dstyle.tab.tab_body.stroke = egui::Stroke::new(1.0, style::border());
        dstyle.tab.active.outline_color = style::border();
        dstyle.tab.focused.outline_color = style::border();
        dstyle.tab.inactive.outline_color = style::tab_idle();
        dstyle.tab.hovered.bg_fill = egui::Color32::from_rgb(222, 222, 222);
        dstyle.tab.hovered.text_color = style::text();
        dstyle.tab.minimum_width = Some(90.0);
        dstyle.buttons.close_tab_color = style::text();
        dstyle.buttons.close_tab_active_color = style::text();
        dstyle.tab.tab_body.bg_fill = style::canvas(self.settings.black_canvas);
        dstyle.tab.active.bg_fill = style::field();
        dstyle.tab.focused.bg_fill = style::field();
        dstyle.tab.inactive.bg_fill = style::tab_idle();
        dstyle.tab.focused.text_color = style::text();
        dstyle.tab.active.text_color = style::text();
        dstyle.tab.inactive.text_color = style::text();
        dstyle.tab.active.corner_radius = egui::CornerRadius::ZERO;
        dstyle.tab.focused.corner_radius = egui::CornerRadius::ZERO;
        dstyle.tab.inactive.corner_radius = egui::CornerRadius::ZERO;
        dstyle.tab.hovered.corner_radius = egui::CornerRadius::ZERO;
        dstyle.separator.color_idle = style::border();
        dstyle.main_surface_border_stroke = egui::Stroke::new(1.0, style::border());
        {
            let mut viewer = Viewer { app: self, closed: Vec::new(), focused: None };
            DockArea::new(&mut dock)
                .style(dstyle)
                .show_leaf_collapse_buttons(false)
                .show_leaf_close_all_buttons(false)
                .show_inside(ui, &mut viewer);
            let closed = std::mem::take(&mut viewer.closed);
            let focused = viewer.focused;
            for id in closed {
                if let Some(r) = self.renderer.as_mut() {
                    r.forget(id);
                }
                self.scenes.remove(&id);
            }
            if let Some(f) = focused {
                self.activate(f);
            }
        }
        if let Some((_, tab)) = dock.find_active_focused() {
            let t = *tab;
            if self.active != Some(t) {
                self.activate(t);
            }
        }
        if self.active.is_some_and(|a| dock.find_tab(&a).is_none()) {
            self.active = dock.iter_all_tabs().map(|(_, t)| *t).last();
        }
        self.dock = Some(dock);
    }

    fn show_toast(&mut self, ctx: &egui::Context) {
        let Some(t) = &self.toast else { return };
        if self.now > t.until {
            self.toast = None;
            return;
        }
        let (text, error) = (t.text.clone(), t.error);
        egui::Area::new(egui::Id::new("toast"))
            .anchor(egui::Align2::RIGHT_BOTTOM, egui::vec2(-16.0, -36.0))
            .order(egui::Order::Foreground)
            .show(ctx, |ui| {
                egui::Frame::popup(ui.style())
                    .fill(if error { egui::Color32::from_rgb(255, 240, 238) } else { style::field() })
                    .stroke(egui::Stroke::new(1.0, if error { style::ERROR } else { style::ACCENT }))
                    .show(ui, |ui| {
                        ui.set_max_width(420.0);
                        ui.horizontal(|ui| {
                            let (r, _) = ui.allocate_exact_size(egui::vec2(18.0, 18.0), egui::Sense::hover());
                            crate::icons::paint(ui.painter(), r, if error { crate::icons::Icon::Warnings } else { crate::icons::Icon::Info }, true);
                            ui.label(egui::RichText::new(text).color(if error { egui::Color32::from_rgb(140, 20, 20) } else { style::text() }));
                        });
                    });
            });
        ctx.request_repaint_after(std::time::Duration::from_millis(250));
    }
}

struct Viewer<'a> {
    app: &'a mut App,
    closed: Vec<Id>,
    focused: Option<Id>,
}

impl TabViewer for Viewer<'_> {
    type Tab = Id;

    fn id(&mut self, tab: &mut Id) -> egui::Id {
        egui::Id::new(("view-tab", *tab))
    }

    fn title(&mut self, tab: &mut Id) -> egui::WidgetText {
        // View tabs show just the view name, like the reference app.
        match self.app.doc.data.view(*tab) {
            Some(v) => match &v.kind {
                ViewKind::Sheet(s) => format!("{} - {}", s.number, v.name).into(),
                _ => v.name.clone().into(),
            },
            None => "View".into(),
        }
    }

    fn ui(&mut self, ui: &mut egui::Ui, tab: &mut Id) {
        let id = *tab;
        let app = &mut *self.app;
        let Some(kind) = app.doc.data.view(id).map(|v| v.kind.clone()) else { return };
        // Clicking anywhere in a tab makes it the active view.
        if ui.rect_contains_pointer(ui.max_rect()) && ui.input(|i| i.pointer.any_pressed()) && app.active != Some(id) {
            self.focused = Some(id);
            app.activate(id);
        }
        match kind {
            ViewKind::ThreeD { .. } => {
                viewbar::show(app, ui, id);
                view3d::show(app, ui, id);
            }
            ViewKind::Schedule(_) => schedule_ui::show(app, ui, id),
            ViewKind::Sheet(_) => sheet_ui::show(app, ui, id),
            _ => {
                viewbar::show(app, ui, id);
                canvas::show(app, ui, id);
            }
        }
    }

    fn on_close(&mut self, tab: &mut Id) -> egui_dock::widgets::tab_viewer::OnCloseResponse {
        self.closed.push(*tab);
        egui_dock::widgets::tab_viewer::OnCloseResponse::Close
    }

    fn on_tab_button(&mut self, tab: &mut Id, response: &egui::Response) {
        if response.clicked() || response.drag_started() {
            self.focused = Some(*tab);
        }
    }

    fn clear_background(&self, _tab: &Id) -> bool {
        true
    }

    fn scroll_bars(&self, _tab: &Id) -> [bool; 2] {
        [false, false]
    }

    fn allowed_in_windows(&self, _tab: &mut Id) -> bool {
        true
    }
}

fn key_letter(k: egui::Key) -> Option<char> {
    let name = k.name();
    (name.len() == 1 && name.chars().all(|c| c.is_ascii_alphabetic())).then(|| name.chars().next().unwrap().to_ascii_uppercase())
}

pub fn timestamp() -> String {
    let secs = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0);
    let days = (secs / 86400) as i64;
    let rem = secs % 86400;
    let z = days + 719468;
    let era = z.div_euclid(146097);
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = if m <= 2 { y + 1 } else { y };
    format!("{y:04}-{m:02}-{d:02}T{:02}:{:02}:{:02}", rem / 3600, rem % 3600 / 60, rem % 60)
}

impl eframe::App for App {
    fn ui(&mut self, ui: &mut egui::Ui, _frame: &mut eframe::Frame) {
        self.frame(ui);
    }

    fn save(&mut self, storage: &mut dyn eframe::Storage) {
        if self.screenshot.is_none() {
            eframe::set_value(storage, "settings", &self.settings);
        }
    }

    fn raw_input_hook(&mut self, _ctx: &egui::Context, raw_input: &mut egui::RawInput) {
        if let Some(s) = self.input_script.as_mut() {
            s.feed(raw_input);
        }
    }
}
