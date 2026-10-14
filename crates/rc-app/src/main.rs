//! RevitCraft: a BIM authoring app (architecture and structure modelling, documentation,
//! parametric families, schedules, sheets, IFC/DXF/PDF exchange) built with egui and wgpu so it
//! runs on Windows, macOS and Linux.

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod actions;
mod app;
mod browser;
mod canvas;
mod canvas_tools;
mod commands;
mod dialogs;
mod family_editor;
mod grips;
mod icons;
mod options_bar;
mod properties;
mod render3d;
mod ribbon;
mod schedule_ui;
mod sheet_ui;
mod snap;
mod statusbar;
mod style;
mod tempdims;
mod tools;
mod view3d;
mod viewbar;

use eframe::egui;

fn main() -> eframe::Result {
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default().with_title("RevitCraft").with_inner_size([1600.0, 980.0]).with_min_inner_size([1024.0, 640.0]),
        renderer: eframe::Renderer::Wgpu,
        persist_window: true,
        ..Default::default()
    };
    eframe::run_native("RevitCraft", options, Box::new(|cc| Ok(Box::new(app::App::new(cc)))))
}
