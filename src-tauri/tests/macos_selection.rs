#[cfg(target_os = "macos")]
#[test]
fn macos_selection_fallback_does_not_shell_out_to_osascript() {
    let selected_text_rs =
        std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/src/selected_text.rs"))
            .expect("read selected_text.rs");

    assert!(
        selected_text_rs.contains("CGEvent::new_keyboard_event"),
        "macOS selected-text fallback should send Cmd+C from the Pot process"
    );
    assert!(
        !selected_text_rs.contains("osascript"),
        "macOS selected-text fallback must not require separate osascript accessibility permission"
    );
}

#[cfg(target_os = "macos")]
#[test]
fn selection_translate_uses_selected_text_helper() {
    let window_rs = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/src/window.rs"))
        .expect("read window.rs");

    assert!(
        window_rs.contains("crate::selected_text::get_text"),
        "selection_translate should use the app-owned selected text helper"
    );
    assert!(
        !window_rs.contains("use selection::get_text"),
        "selection_translate should not call selection::get_text directly"
    );
}

#[cfg(target_os = "macos")]
#[test]
fn macos_selection_reports_missing_accessibility_permission() {
    let selected_text_rs =
        std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/src/selected_text.rs"))
            .expect("read selected_text.rs");

    assert!(
        selected_text_rs.contains("application_is_trusted"),
        "macOS selected-text helper must check whether Pot has Accessibility permission"
    );
    assert!(
        selected_text_rs.contains(
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ),
        "macOS selected-text helper must direct the user to the Accessibility settings pane"
    );
    assert!(
        selected_text_rs.contains("Pot needs macOS Accessibility permission"),
        "macOS selected-text helper must log a clear missing-permission message"
    );
}
