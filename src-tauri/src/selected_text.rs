#[cfg(not(target_os = "macos"))]
pub fn get_text() -> String {
    selection::get_text()
}

#[cfg(target_os = "macos")]
mod macos {
    use accessibility_ng::{AXAttribute, AXUIElement};
    use accessibility_sys_ng::{kAXFocusedUIElementAttribute, kAXSelectedTextAttribute};
    use arboard::{Clipboard, ImageData};
    use core_foundation::string::CFString;
    use core_graphics::event::{CGEvent, CGEventFlags, CGEventTapLocation};
    use core_graphics::event_source::{CGEventSource, CGEventSourceStateID};
    use log::{error, info};
    use objc::runtime::{sel_registerName, Class, Object};
    use objc::Message;
    use std::borrow::Cow;
    use std::error::Error;
    use std::process::Command;
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::thread::sleep;
    use std::time::Duration;

    const KEY_CODE_C: u16 = 8;
    const ACCESSIBILITY_SETTINGS_URL: &str =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility";

    static OPENED_ACCESSIBILITY_SETTINGS: AtomicBool = AtomicBool::new(false);

    enum ClipboardState {
        Text(String),
        Image(ImageData<'static>),
        Empty,
    }

    impl ClipboardState {
        fn read(clipboard: &mut Clipboard) -> Self {
            if let Ok(text) = clipboard.get_text() {
                return Self::Text(text);
            }
            if let Ok(image) = clipboard.get_image() {
                return Self::Image(ImageData {
                    width: image.width,
                    height: image.height,
                    bytes: Cow::Owned(image.bytes.into_owned()),
                });
            }
            Self::Empty
        }

        fn restore(self, clipboard: &mut Clipboard) {
            match self {
                Self::Text(text) => {
                    let _ = clipboard.set_text(text);
                }
                Self::Image(image) => {
                    let _ = clipboard.set_image(image);
                }
                Self::Empty => {
                    let _ = clipboard.clear();
                }
            }
        }
    }

    pub fn get_text() -> String {
        if !macos_accessibility_client::accessibility::application_is_trusted() {
            report_missing_accessibility_permission();
            return String::new();
        }

        match get_selected_text_by_ax() {
            Ok(text) => {
                if !text.trim().is_empty() {
                    return text.trim().to_owned();
                }
                info!("get_selected_text_by_ax is empty");
            }
            Err(err) => {
                error!("get_selected_text_by_ax error:{}", err);
            }
        }

        info!("fallback to get_text_by_clipboard");
        match get_text_by_clipboard() {
            Ok(text) => {
                if !text.trim().is_empty() {
                    return text.trim().to_owned();
                }
                info!("get_text_by_clipboard is empty");
            }
            Err(err) => {
                error!("get_text_by_clipboard error:{}", err);
            }
        }

        String::new()
    }

    fn report_missing_accessibility_permission() {
        let trusted =
            macos_accessibility_client::accessibility::application_is_trusted_with_prompt();
        error!(
            "Pot needs macOS Accessibility permission to read selected text; trusted:{}",
            trusted
        );
        if !trusted && !OPENED_ACCESSIBILITY_SETTINGS.swap(true, Ordering::Relaxed) {
            let _ = Command::new("open").arg(ACCESSIBILITY_SETTINGS_URL).spawn();
        }
    }

    fn get_selected_text_by_ax() -> Result<String, Box<dyn Error>> {
        let system_element = AXUIElement::system_wide();
        let Some(selected_element) = system_element
            .attribute(&AXAttribute::new(&CFString::from_static_string(
                kAXFocusedUIElementAttribute,
            )))
            .map(|element| element.downcast_into::<AXUIElement>())
            .ok()
            .flatten()
        else {
            return Err(Box::new(std::io::Error::new(
                std::io::ErrorKind::NotFound,
                "No selected element",
            )));
        };
        let Some(selected_text) = selected_element
            .attribute(&AXAttribute::new(&CFString::from_static_string(
                kAXSelectedTextAttribute,
            )))
            .map(|text| text.downcast_into::<CFString>())
            .ok()
            .flatten()
        else {
            return Err(Box::new(std::io::Error::new(
                std::io::ErrorKind::NotFound,
                "No selected text",
            )));
        };
        Ok(selected_text.to_string())
    }

    fn get_text_by_clipboard() -> Result<String, Box<dyn Error>> {
        let mut clipboard = Clipboard::new()?;
        let saved_clipboard = ClipboardState::read(&mut clipboard);
        let change_count_before = pasteboard_change_count();

        send_copy_shortcut()?;
        sleep(Duration::from_millis(150));

        let change_count_after = pasteboard_change_count();
        if change_count_after == change_count_before {
            saved_clipboard.restore(&mut clipboard);
            return Ok(String::new());
        }

        let selected_text = clipboard.get_text().unwrap_or_default();
        saved_clipboard.restore(&mut clipboard);
        Ok(selected_text)
    }

    fn send_copy_shortcut() -> Result<(), Box<dyn Error>> {
        let source = CGEventSource::new(CGEventSourceStateID::HIDSystemState)
            .map_err(|_| "failed to create CGEventSource")?;
        let key_down = CGEvent::new_keyboard_event(source.clone(), KEY_CODE_C, true)
            .map_err(|_| "failed to create copy key-down event")?;
        let key_up = CGEvent::new_keyboard_event(source, KEY_CODE_C, false)
            .map_err(|_| "failed to create copy key-up event")?;

        key_down.set_flags(CGEventFlags::CGEventFlagCommand);
        key_up.set_flags(CGEventFlags::CGEventFlagCommand);
        key_down.post(CGEventTapLocation::HID);
        key_up.post(CGEventTapLocation::HID);
        Ok(())
    }

    fn pasteboard_change_count() -> isize {
        unsafe {
            let ns_pasteboard = Class::get("NSPasteboard").unwrap();
            let general_pasteboard = std::ffi::CString::new("generalPasteboard").unwrap();
            let change_count = std::ffi::CString::new("changeCount").unwrap();
            let pasteboard: *mut Object = ns_pasteboard
                .send_message(sel_registerName(general_pasteboard.as_ptr()), ())
                .unwrap();
            (*pasteboard)
                .send_message(sel_registerName(change_count.as_ptr()), ())
                .unwrap()
        }
    }
}

#[cfg(target_os = "macos")]
pub use macos::get_text;
