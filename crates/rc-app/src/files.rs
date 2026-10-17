//! Native file dialogs. During the self-test they behave as if cancelled, so an unattended
//! run never blocks on a dialog; `RC_PICK_FILE` and `RC_SAVE_FILE` answer file pickers in scripted runs.

use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};

static DISABLED: AtomicBool = AtomicBool::new(false);

pub fn disable() {
    DISABLED.store(true, Ordering::Relaxed);
}

pub struct FileDialog(rfd::FileDialog);

impl FileDialog {
    pub fn new() -> Self {
        FileDialog(rfd::FileDialog::new())
    }
    pub fn add_filter(self, name: &str, ext: &[&str]) -> Self {
        FileDialog(self.0.add_filter(name, ext))
    }
    pub fn set_file_name(self, name: impl Into<String>) -> Self {
        FileDialog(self.0.set_file_name(name))
    }
    pub fn set_title(self, title: impl Into<String>) -> Self {
        FileDialog(self.0.set_title(title))
    }
    pub fn pick_file(self) -> Option<PathBuf> {
        // Scripted screenshots pick this file instead of showing the dialog.
        if let Ok(f) = std::env::var("RC_PICK_FILE") {
            return Some(PathBuf::from(f));
        }
        if DISABLED.load(Ordering::Relaxed) { None } else { self.0.pick_file() }
    }
    pub fn pick_folder(self) -> Option<PathBuf> {
        if DISABLED.load(Ordering::Relaxed) { None } else { self.0.pick_folder() }
    }
    pub fn save_file(self) -> Option<PathBuf> {
        // Scripted runs save here instead of showing the dialog.
        if let Ok(f) = std::env::var("RC_SAVE_FILE") {
            return Some(PathBuf::from(f));
        }
        if DISABLED.load(Ordering::Relaxed) { None } else { self.0.save_file() }
    }
}
