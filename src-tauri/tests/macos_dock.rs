#[cfg(target_os = "macos")]
#[test]
fn macos_build_exposes_regular_dock_app() {
    let main_rs = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/src/main.rs"))
        .expect("read main.rs");

    assert!(
        main_rs.contains("tauri::ActivationPolicy::Regular"),
        "macOS builds must use Regular activation policy so Pot can be pinned to the Dock"
    );
    assert!(
        !main_rs.contains("tauri::ActivationPolicy::Accessory"),
        "Accessory activation policy hides Pot from the Dock"
    );
}

#[cfg(target_os = "macos")]
#[test]
fn macos_dock_reopen_routes_to_translate_window() {
    let main_rs = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/src/main.rs"))
        .expect("read main.rs");
    let dock_rs =
        std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/src/macos_dock.rs"))
            .expect("read macos_dock.rs");

    assert!(
        main_rs.contains("macos_dock::install_reopen_handler()"),
        "app setup must install the macOS Dock reopen handler"
    );
    assert!(
        dock_rs.contains("applicationShouldHandleReopen:hasVisibleWindows:"),
        "Dock clicks are delivered through applicationShouldHandleReopen:hasVisibleWindows:"
    );
    assert!(
        dock_rs.contains("show_translate_from_dock"),
        "Dock reopen handling must bring the translate window to the front"
    );
}
