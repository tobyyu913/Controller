# Controller

## Rules

- **Auto-commit & push**: Whenever a major update is completed (new feature, new interface, significant refactor), automatically commit and push to `origin/main` without asking. Use a descriptive commit message summarizing the changes.
- **Install before pushing**: Before committing and pushing, build and install the macOS app to `/Applications/Controller.app`, and install APKs on connected Android devices.

A dual-platform app that turns an Android (or iOS) phone into a PS5-style game controller, connected to a macOS receiver via USB. Includes a 3D demo game on macOS.

## Project Structure

```
Controller/                     # iOS/macOS SwiftUI app (Xcode project)
  ControllerApp.swift           # Entry point, platform routing
  ContentView.swift             # iOS controller UI (PS5 layout)
  NetworkService.swift          # ControllerServer (macOS/iPad) + ControllerClient (iPhone)
  ControllerMessage.swift       # Shared Codable message model
  GameView.swift                # macOS SceneKit 3D game
  ReceiverView.swift            # macOS debug view + tab switcher (MacContentView)
  iPadReceiverView.swift        # iPad receiver (server + game + debug)
Controller-Android/             # Android app (Kotlin + Jetpack Compose)
  app/src/main/java/com/toby/controller/
    MainActivity.kt             # Activity, Compose UI, edit mode
    ControllerSender.kt         # TCP client connecting to Mac/iPad server
    ControllerMessage.kt        # JSON message with length-prefixed framing
    LayoutStore.kt              # SharedPreferences for custom layout + server host
.github/workflows/build-apk.yml  # CI for Android APK
```

## Architecture

- **Protocol**: TCP on fixed port 9876. Messages are 4-byte big-endian length prefix + JSON payload.
- **Server-Client Model**: macOS/iPad runs a TCP server on port 9876. Phones (iOS/Android) connect as clients. One server can accept multiple phone clients simultaneously.
- **WiFi**: Server advertises via Bonjour (`_ps5ctrl._tcp`). Phones auto-discover or manually enter the server IP.
- **USB (Android)**: macOS polls for ADB devices, runs `adb reverse tcp:9876 tcp:9876`. Android connects to `localhost:9876` which tunnels to the Mac's server.

### Data Model (ControllerMessage)
```json
{
  "pressedButtons": ["Circle", "R2"],
  "leftStickX": 0.5,
  "leftStickY": -0.3,
  "rightStickX": 0.0,
  "rightStickY": 0.0
}
```

Button names: `DPadUp`, `DPadDown`, `DPadLeft`, `DPadRight`, `Triangle`, `Circle`, `Cross`, `Square`, `L1`, `L2`, `R1`, `R2`, `L3`, `R3`, `Create`, `Options`, `PS`, `Touchpad`.

## Build Commands

### iOS/macOS (requires Xcode)
```bash
# iOS
xcodebuild -scheme Controller -project Controller.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# macOS
xcodebuild -scheme Controller -project Controller.xcodeproj \
  -destination 'platform=macOS' build
```

### Android (requires JDK 17)
```bash
cd Controller-Android
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
./gradlew assembleDebug
```

APK output: `Controller-Android/app/build/outputs/apk/debug/app-debug.apk`

### Install on phone
```bash
adb install -r Controller-Android/app/build/outputs/apk/debug/app-debug.apk
```

## ADB Setup

ADB is installed at `/opt/homebrew/share/android-commandlinetools/platform-tools/adb`. The macOS receiver searches these paths automatically:
- `/opt/homebrew/share/android-commandlinetools/platform-tools/adb`
- `/opt/homebrew/bin/adb`
- `/usr/local/bin/adb`
- `~/Library/Android/sdk/platform-tools/adb`
- `/Applications/Android Studio.app/Contents/plugins/android/resources/platform-tools/adb`

## Key Dependencies

- **iOS/macOS**: SwiftUI, SceneKit, Network.framework (NWConnection). No third-party deps.
- **Android**: Jetpack Compose (BOM 2024.12.01), Material3, Activity Compose 1.9.3. Gradle 8.11.1, AGP 8.7.3, Kotlin 2.1.0.

## Platform Behavior

| Platform | Role | Key Feature |
|----------|------|-------------|
| iOS (iPhone) | Controller client | PS5 layout, fixed landscape, auto-discovers server via Bonjour |
| iOS (iPad) | Receiver server | Runs server on port 9876, shows parkour game + debug |
| Android | Controller client | PS5 layout + edit mode, connects via WiFi (NSD/manual IP) or USB (ADB reverse) |
| macOS | Receiver server | Runs server on port 9876, three tabs: Universal + Parkour + Debug, supports multiple clients |

### Universal Mode (any game)
Emulates keyboard + mouse via CGEvent. Requires Accessibility permission.
- **Left stick** → W/A/S/D
- **Right stick** → Mouse movement
- **D-Pad** → Arrow keys
- **Cross** → Space, **Circle** → E, **Triangle** → Q, **Square** → F
- **L2** → Shift (sprint), **R2** → Ctrl (crouch)
- **L1** → 1, **R1** → 2
- **Options** → Escape, **Create** → Tab

### macOS Game Controls (Parkour)
- **Left stick**: Move (WASD-style, relative to facing)
- **Right stick**: Look (pitch/yaw)
- **Circle**: Jump (press again in air for double jump)
- **L2**: Sprint (faster movement, longer jumps, FOV widens)
- **R2**: Squat (lowers camera, slows movement)
- Fall off a platform = respawn at last checkpoint
- Complete all checkpoints to finish the course

## Platform-Specific Code

Uses `#if os(iOS)` / `#if os(macOS)` throughout. UIKit APIs (haptics, orientation lock, status bar) are gated behind `#if os(iOS)`. The macOS receiver and game are gated behind `#if os(macOS)`.

## Android Edit Mode

The Android app has a gear icon (top right) that toggles edit mode. In edit mode, all controls become draggable. Positions are saved to SharedPreferences via `LayoutStore` and persist across restarts. A reset button restores defaults.
