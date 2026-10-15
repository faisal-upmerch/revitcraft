//! `--selftest`: runs every command in every kind of view with clicks and Esc, logging each
//! step to stderr so a crash names the command. Each step is rolled back, so the model is the
//! same for every command. `RC_SELFTEST_CONTEXT` limits the run to one view kind and
//! `RC_SELFTEST_FROM` starts at a step (to continue after a crash).

use crate::actions;
use crate::app::App;
use crate::commands::Cmd;
use eframe::egui::{self, Event, Key, Modifiers, PointerButton, pos2};
use rc_core::model::*;

/// Commands that leave the project or open native windows; not swept.
const SKIP: [Cmd; 13] = [
    Cmd::Open,
    Cmd::Save,
    Cmd::SaveAs,
    Cmd::OpenSample,
    Cmd::ImportIfc,
    Cmd::ExportIfc,
    Cmd::ExportDxf,
    Cmd::ExportPdf,
    Cmd::ExportImage,
    Cmd::ExportCsv,
    Cmd::Exit,
    Cmd::LinkCad,
    Cmd::ImportCad,
];

/// Frames per step.
const STEP: u32 = 20;

pub struct SelfTest {
    steps: Vec<(String, Id, Cmd)>,
    index: usize,
    t: u32,
    depth: usize,
    snapshot: Option<Project>,
    settings: Option<crate::app::Settings>,
    errors: usize,
}

impl SelfTest {
    pub fn new(app: &mut App) -> SelfTest {
        crate::files::disable();
        let p = &mut app.doc.data;
        // Make sure every kind of view exists.
        if !p.views.iter().any(|v| matches!(v.kind, ViewKind::Section { .. })) {
            let _ = rc_core::edit::new_section(p, rc_core::geom::DVec2::new(-2000.0, 3000.0), rc_core::geom::DVec2::new(14000.0, 3000.0), 20000.0);
        }
        if !p.views.iter().any(|v| matches!(v.kind, ViewKind::Drafting)) {
            rc_core::edit::new_drafting_view(p, "Drafting 1", 10.0);
        }
        let pick = |label: &str, f: &dyn Fn(&ViewKind) -> bool| p.views.iter().find(|v| !v.is_template && f(&v.kind)).map(|v| (label.to_string(), v.id));
        let contexts: Vec<(String, Id)> = [
            pick("floor plan", &|k| matches!(k, ViewKind::FloorPlan { .. })),
            pick("ceiling plan", &|k| matches!(k, ViewKind::CeilingPlan { .. })),
            pick("elevation", &|k| matches!(k, ViewKind::Elevation { .. })),
            pick("section", &|k| matches!(k, ViewKind::Section { .. })),
            pick("3d", &|k| matches!(k, ViewKind::ThreeD { .. })),
            pick("sheet", &|k| matches!(k, ViewKind::Sheet(_))),
            pick("schedule", &|k| matches!(k, ViewKind::Schedule(_))),
            pick("drafting", &|k| matches!(k, ViewKind::Drafting)),
        ]
        .into_iter()
        .flatten()
        .collect();
        let only: Option<usize> = std::env::var("RC_SELFTEST_CONTEXT").ok().and_then(|s| s.parse().ok());
        let mut steps = Vec::new();
        for (k, (label, view)) in contexts.iter().enumerate() {
            if only.is_some_and(|o| o != k) {
                continue;
            }
            for c in Cmd::ALL.iter().filter(|c| !SKIP.contains(c)) {
                steps.push((label.clone(), *view, *c));
            }
        }
        let from: usize = std::env::var("RC_SELFTEST_FROM").ok().and_then(|s| s.parse().ok()).unwrap_or(0);
        eprintln!("[selftest] {} steps over {} views", steps.len(), contexts.len());
        SelfTest { steps, index: from, t: 0, depth: 0, snapshot: None, settings: None, errors: 0 }
    }

    fn point(&self, raw: &egui::RawInput, k: u32) -> egui::Pos2 {
        let r = raw.screen_rect.unwrap_or(egui::Rect::from_min_size(pos2(0.0, 0.0), egui::vec2(1600.0, 900.0)));
        let (fx, fy) = [(0.56, 0.55), (0.64, 0.47), (0.5, 0.64)][k as usize % 3];
        pos2(r.left() + r.width() * fx, r.top() + r.height() * fy)
    }

    /// Pointer and key input for this frame.
    pub fn input(&self, raw: &mut egui::RawInput) {
        if self.index >= self.steps.len() {
            return;
        }
        let press = |pos: egui::Pos2, pressed: bool| Event::PointerButton { pos, button: PointerButton::Primary, pressed, modifiers: Modifiers::NONE };
        let key = |pressed: bool| Event::Key { key: Key::Escape, physical_key: None, pressed, repeat: false, modifiers: Modifiers::NONE };
        match self.t {
            5 | 8 | 11 => raw.events.push(Event::PointerMoved(self.point(raw, (self.t - 5) / 3))),
            6 | 9 | 12 => {
                let q = self.point(raw, (self.t - 6) / 3);
                raw.events.push(press(q, true));
            }
            7 | 10 | 13 => {
                let q = self.point(raw, (self.t - 7) / 3);
                raw.events.push(press(q, false));
            }
            14 | 16 => raw.events.push(key(true)),
            15 | 17 => raw.events.push(key(false)),
            _ => {}
        }
    }

    /// Advances the run; returns false when it has finished.
    pub fn step(&mut self, app: &mut App, ctx: &egui::Context) -> bool {
        ctx.request_repaint();
        let Some((label, view, cmd)) = self.steps.get(self.index).cloned() else {
            eprintln!("[selftest] done: {} steps, {} command errors reported", self.steps.len(), self.errors);
            return false;
        };
        match self.t {
            0 => {
                self.snapshot = Some(app.doc.data.clone());
                self.settings = Some(app.settings.clone());
                self.depth = app.doc.undo_depth();
                app.open_view(view);
                // A wall (or any model element) is selected for commands that need a selection.
                let sel: Vec<Id> = app.doc.data.elements.iter().filter(|e| matches!(e.kind, ElementKind::Wall(_))).map(|e| e.id).take(1).collect();
                app.select(sel);
            }
            1 => {
                eprintln!("[selftest] {}/{} {label}: {cmd:?}", self.index + 1, self.steps.len());
                let before = app.toast_text();
                actions::exec(app, cmd);
                if let Some(t) = app.toast.as_ref().filter(|t| t.error && Some(t.text.clone()) != before) {
                    self.errors += 1;
                    eprintln!("[selftest]   refused: {}", t.text);
                }
            }
            4 => {
                app.dialogs = Default::default();
            }
            t if t >= STEP - 1 => {
                if let Some(t) = app.toast.as_ref().filter(|t| t.error) {
                    eprintln!("[selftest]   after clicks: {}", t.text);
                }
                app.toast = None;
                app.cancel();
                app.cancel();
                app.dialogs = Default::default();
                app.family_editor = None;
                app.group_edit = None;
                app.sketch = None;
                app.sheet_activation = None;
                app.doc.rollback_to(self.depth);
                if let Some(s) = self.snapshot.take() {
                    if app.doc.undo_depth() < self.depth || app.doc.data.elements.len() != s.elements.len() || app.doc.data.views.len() != s.views.len() {
                        app.doc.data = s;
                        app.doc.touch();
                    }
                }
                if let Some(s) = self.settings.take() {
                    app.settings = s;
                }
                app.selection.clear();
                self.index += 1;
                self.t = 0;
                return true;
            }
            _ => {}
        }
        self.t += 1;
        true
    }
}
