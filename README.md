# Sky Pie for iOS

The iOS companion of [Sky Pie](https://github.com/contract-hero/skypie-core): pair
it once with your Mac and every `skypie://` link a tool produces opens on the
phone, pulled straight from the Mac over an end-to-end encrypted link.

Everything the app does lives in the `core` submodule (skypie-core). This
repository owns only what makes it an iOS app: `src-tauri/tauri.conf.json`,
`src-tauri/Info.ios.plist`, the XcodeGen spec at `src-tauri/gen/apple/project.yml`
(the only home of `DEVELOPMENT_TEAM` and `LD_RUNPATH_SEARCH_PATHS`), and the
`#[tauri::mobile_entry_point]` that hands the generated context to
`skypie_app::app::run`.

## Build

```bash
git clone --recurse-submodules git@github.com:contract-hero/skypie-ios.git
cd skypie-ios
pnpm install
pnpm tauri ios init          # regenerates the Xcode project from project.yml
./scripts/build-ios-sim.sh   # debug build for the arm64 simulator
```

Physical device: `./scripts/install-ios-device.sh`.

## Updating core

```bash
git submodule update --init --recursive --remote --merge
git add core && git commit -m "core: <what changed>"
```
