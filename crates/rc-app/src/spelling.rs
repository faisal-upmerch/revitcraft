//! Check Spelling: the system spell checker (English, United States), less the words added
//! in this session.

use std::cell::RefCell;
use std::collections::HashSet;

thread_local! {
    static ADDED: RefCell<HashSet<String>> = RefCell::new(HashSet::new());
}

/// Add: the word is accepted from now on.
pub fn add_word(word: &str) {
    ADDED.with(|a| a.borrow_mut().insert(word.to_lowercase()));
}

/// Misspelt words of `text` as byte ranges.
pub fn check(text: &str) -> Vec<(usize, usize)> {
    imp::check(text).into_iter().filter(|(s, e)| !ADDED.with(|a| a.borrow().contains(&text[*s..*e].to_lowercase()))).collect()
}

/// Suggested spellings, best first.
pub fn suggest(word: &str) -> Vec<String> {
    imp::suggest(word)
}

#[cfg(windows)]
mod imp {
    use windows::Win32::Globalization::{ISpellChecker, ISpellCheckerFactory, ISpellingError, SpellCheckerFactory};
    use windows::Win32::System::Com::{CLSCTX_INPROC_SERVER, COINIT_APARTMENTTHREADED, CoCreateInstance, CoInitializeEx, CoTaskMemFree};
    use windows::core::{HSTRING, PWSTR};

    thread_local! {
        // Never released: releasing COM objects as the thread exits can hang.
        static CHECKER: std::mem::ManuallyDrop<Option<ISpellChecker>> = std::mem::ManuallyDrop::new(make());
    }

    fn make() -> Option<ISpellChecker> {
        unsafe {
            let _ = CoInitializeEx(None, COINIT_APARTMENTTHREADED);
            let f: ISpellCheckerFactory = CoCreateInstance(&SpellCheckerFactory, None, CLSCTX_INPROC_SERVER).ok()?;
            f.CreateSpellChecker(&HSTRING::from("en-US")).ok()
        }
    }

    pub fn check(text: &str) -> Vec<(usize, usize)> {
        CHECKER.with(|c| {
            let Some(c) = &**c else { return vec![] };
            // UTF-16 index → byte index.
            let mut map: Vec<usize> = Vec::new();
            for (b, ch) in text.char_indices() {
                for _ in 0..ch.len_utf16() {
                    map.push(b);
                }
            }
            map.push(text.len());
            let mut out = Vec::new();
            unsafe {
                let Ok(errs) = c.Check(&HSTRING::from(text)) else { return out };
                loop {
                    let mut e: Option<ISpellingError> = None;
                    if errs.Next(&mut e).0 != 0 {
                        break;
                    }
                    let Some(e) = e else { break };
                    let (Ok(s), Ok(l)) = (e.StartIndex(), e.Length()) else { continue };
                    let (s, l) = (s as usize, l as usize);
                    if l > 0 && s + l < map.len() {
                        out.push((map[s], map[s + l]));
                    }
                }
            }
            out
        })
    }

    pub fn suggest(word: &str) -> Vec<String> {
        CHECKER.with(|c| {
            let Some(c) = &**c else { return vec![] };
            let mut out = Vec::new();
            unsafe {
                let Ok(list) = c.Suggest(&HSTRING::from(word)) else { return out };
                while out.len() < 30 {
                    let mut buf = [PWSTR::null()];
                    let mut n = 0u32;
                    if list.Next(&mut buf, Some(&mut n)).0 != 0 || n == 0 {
                        break;
                    }
                    out.push(buf[0].to_string().unwrap_or_default());
                    CoTaskMemFree(Some(buf[0].0 as _));
                }
            }
            out
        })
    }
}

#[cfg(not(windows))]
mod imp {
    pub fn check(_: &str) -> Vec<(usize, usize)> {
        vec![]
    }
    pub fn suggest(_: &str) -> Vec<String> {
        vec![]
    }
}
