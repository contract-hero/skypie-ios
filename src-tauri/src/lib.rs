// iOS entry point. There is no `main` on mobile: the Xcode project links this
// crate as a static library and calls the `start_app` symbol
// `#[tauri::mobile_entry_point]` emits. The builder itself lives in
// `skypie_app::app::run` (skypie-core); this shell owns tauri.conf.json.

#[tauri::mobile_entry_point]
fn start() {
    skypie_app::app::run(tauri::generate_context!());
}
