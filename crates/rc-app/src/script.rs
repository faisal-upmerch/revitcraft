//! Scripted input for automated screenshots: `RC_INPUT` holds `;`-separated steps
//! `FRAME ACTION ARGS`, e.g. `20 move 800 400; 22 click 800 400; 30 type 40; 32 key Enter`.
//! Actions: move X Y, click X Y, text STRING (text input), drag X0 Y0 X1 Y1, rclick X Y, dblclick X Y, key NAME, type TEXT, scroll X Y DY.
//! `RC_SHOT_FRAME` sets the frame of the screenshot (default 14).

use eframe::egui::{self, Event, Key, Modifiers, PointerButton, pos2, vec2};

#[derive(Default)]
pub struct InputScript {
    events: Vec<(u32, Event)>,
    frame: u32,
}

impl InputScript {
    pub fn from_env() -> Option<InputScript> {
        let text = std::env::var("RC_INPUT").ok()?;
        let mut events = Vec::new();
        for step in text.split(';') {
            let parts: Vec<&str> = step.split_whitespace().collect();
            if parts.len() < 2 {
                continue;
            }
            let Ok(f) = parts[0].parse::<u32>() else { continue };
            let num = |i: usize| parts.get(i).and_then(|s| s.parse::<f32>().ok()).unwrap_or(0.0);
            let click = |events: &mut Vec<(u32, Event)>, f: u32, button: PointerButton, x: f32, y: f32| {
                let pos = pos2(x, y);
                events.push((f, Event::PointerMoved(pos)));
                events.push((f, Event::PointerButton { pos, button, pressed: true, modifiers: Modifiers::NONE }));
                events.push((f + 1, Event::PointerButton { pos, button, pressed: false, modifiers: Modifiers::NONE }));
            };
            match parts[1] {
                "move" => events.push((f, Event::PointerMoved(pos2(num(2), num(3))))),
                "click" => click(&mut events, f, PointerButton::Primary, num(2), num(3)),
                "rclick" => click(&mut events, f, PointerButton::Secondary, num(2), num(3)),
                "dblclick" => {
                    click(&mut events, f, PointerButton::Primary, num(2), num(3));
                    click(&mut events, f + 2, PointerButton::Primary, num(2), num(3));
                }
                "drag" => {
                    // drag X0 Y0 X1 Y1: press, move over 8 frames, release.
                    let (a, b) = (pos2(num(2), num(3)), pos2(num(4), num(5)));
                    events.push((f, Event::PointerMoved(a)));
                    events.push((f, Event::PointerButton { pos: a, button: PointerButton::Primary, pressed: true, modifiers: Modifiers::NONE }));
                    for k in 1..=8u32 {
                        let t = k as f32 / 8.0;
                        events.push((f + k, Event::PointerMoved(a + (b - a) * t)));
                    }
                    events.push((f + 9, Event::PointerButton { pos: b, button: PointerButton::Primary, pressed: false, modifiers: Modifiers::NONE }));
                }
                "scroll" => {
                    events.push((f, Event::PointerMoved(pos2(num(2), num(3)))));
                    events.push((f, Event::MouseWheel { unit: egui::MouseWheelUnit::Line, delta: vec2(0.0, num(4)), modifiers: Modifiers::NONE, phase: egui::TouchPhase::Move }));
                }
                "key" => {
                    if let Some(k) = parts.get(2).and_then(|n| Key::from_name(n)) {
                        events.push((f, key_event(k, true)));
                        events.push((f + 1, key_event(k, false)));
                    }
                }
                "text" => events.push((f, Event::Text(parts[2..].join(" ")))),
                "type" => {
                    let t = parts[2..].join(" ");
                    for (i, c) in t.chars().enumerate() {
                        if let Some(k) = Key::from_name(&c.to_string()) {
                            events.push((f + i as u32 * 2, key_event(k, true)));
                            events.push((f + i as u32 * 2 + 1, key_event(k, false)));
                        }
                    }
                }
                _ => {}
            }
        }
        Some(InputScript { events, frame: 0 })
    }

    /// Adds this frame's scripted events to the raw input.
    pub fn feed(&mut self, raw: &mut egui::RawInput) {
        self.frame += 1;
        let f = self.frame;
        raw.events.extend(self.events.iter().filter(|(k, _)| *k == f).map(|(_, e)| e.clone()));
    }
}

fn key_event(key: Key, pressed: bool) -> Event {
    Event::Key { key, physical_key: None, pressed, repeat: false, modifiers: Modifiers::NONE }
}

pub fn shot_frame() -> u32 {
    std::env::var("RC_SHOT_FRAME").ok().and_then(|s| s.parse().ok()).unwrap_or(14)
}
