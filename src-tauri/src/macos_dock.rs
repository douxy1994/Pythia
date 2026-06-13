use crate::window::show_translate_from_dock;
use cocoa::base::id;
use log::{info, warn};
use objc::runtime::{
    class_addMethod, class_getInstanceMethod, sel_registerName, Class, Imp, Object, Sel, BOOL, YES,
};
use std::ffi::CString;

pub fn install_reopen_handler() {
    unsafe {
        let Some(delegate_class) = Class::get("TaoAppDelegate") else {
            warn!("TaoAppDelegate not found, macOS Dock reopen handler was not installed");
            return;
        };
        let selector_name =
            CString::new("applicationShouldHandleReopen:hasVisibleWindows:").unwrap();
        let selector = sel_registerName(selector_name.as_ptr());
        let class_ptr = delegate_class as *const Class as *mut Class;

        if !class_getInstanceMethod(class_ptr, selector).is_null() {
            info!("macOS Dock reopen handler already installed");
            return;
        }

        let types = CString::new("B@:@B").unwrap();
        let handler: Imp = std::mem::transmute(
            application_should_handle_reopen
                as unsafe extern "C" fn(&Object, Sel, id, BOOL) -> BOOL,
        );
        if class_addMethod(class_ptr, selector, handler, types.as_ptr()) == YES {
            info!("Installed macOS Dock reopen handler");
        } else {
            warn!("Failed to install macOS Dock reopen handler");
        }
    }
}

unsafe extern "C" fn application_should_handle_reopen(_: &Object, _: Sel, _: id, _: BOOL) -> BOOL {
    let _ = std::panic::catch_unwind(show_translate_from_dock);
    YES
}
