# Controller

Turn your phone into a PS5-style game controller for your Mac — connected over USB.

A cross-platform system with native apps for **Android** (Kotlin/Compose), **iOS** (SwiftUI), and **macOS** (SwiftUI/SceneKit). The phone acts as the controller, the Mac acts as the receiver, and everything runs over a wired USB connection via ADB port forwarding. No WiFi, no Bluetooth, no lag.

## How It Works

```
Phone (Android/iOS)          USB Cable            Mac (macOS)
┌──────────────────┐                        ┌──────────────────────┐
│  PS5 Controller  │──── TCP on port ────►  │  Receiver            │
│  Touch UI        │      9876 via ADB      │  ├─ Universal Mode   │
│                  │                        │  ├─ Parkour Game     │
│  Sends button +  │                        │  └─ Debug View       │
│  stick input as  │                        │                      │
│  JSON frames     │                        │  Maps input to keys, │
│                  │                        │  mouse, or 3D game   │
└──────────────────┘                        └──────────────────────┘
```

The phone runs a TCP server on port 9876. The Mac detects the phone via ADB, sets up port forwarding, and connects. Controller input is streamed as length-prefixed JSON frames in real time.

## Features

### Phone Controller (iOS & Android)
- Full PS5 DualSense layout — D-Pad, face buttons, analog sticks, triggers, bumpers, and system buttons
- Analog sticks with spring-back animation and click (L3/R3) support
- Haptic feedback on stick press (iOS)
- Connection status indicator
- **Edit Mode** (Android only) — tap the gear icon to drag any button/stick to a custom position; layout persists across restarts

### Mac Receiver — Three Modes

**Universal Mode** — use your phone as a controller for *any* game or app:
- Emulates keyboard + mouse input via macOS Accessibility APIs
- Default mapping: left stick → WASD, right stick → mouse look, face buttons → Space/E/Q/F, triggers → Shift/Ctrl
- 3 built-in presets (FPS, Racing, Platformer) + fully custom rebinding
- Adjustable mouse sensitivity

**Parkour Game** — a built-in 3D platformer to test the controller:
- SceneKit-based 3D course with 8 checkpoints and 28+ platforms
- Move with left stick, look with right stick, jump with Circle
- Sprint (L2) for speed + longer jumps, squat (R2) to slow down
- Double-jump, coyote time, fall respawn
- Procedurally generated soundtrack and sound effects

**Debug View** — live visualization of all controller input:
- Real-time stick position display with crosshairs
- Color-coded button state indicators
- Connection status

## Requirements

- **macOS** with Xcode installed
- **Android phone** with USB debugging enabled, or **iOS device/simulator**
- **ADB** installed (the app searches common install paths automatically)

## Building

### macOS Receiver
```bash
xcodebuild -scheme Controller -project Controller.xcodeproj \
  -destination 'platform=macOS' build
```

### iOS Controller
```bash
xcodebuild -scheme Controller -project Controller.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

### Android Controller
```bash
cd Controller-Android
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
./gradlew assembleDebug
```

APK output: `Controller-Android/app/build/outputs/apk/debug/app-debug.apk`

### Install on Android Phone
```bash
adb install -r Controller-Android/app/build/outputs/apk/debug/app-debug.apk
```

## Usage

1. **Connect** your Android phone to your Mac via USB
2. **Enable USB debugging** on the phone (Settings → Developer Options → USB Debugging)
3. **Launch the Controller app** on the phone — it starts a TCP server and shows "Waiting..."
4. **Launch the Controller app** on the Mac — it auto-detects the phone, forwards the port, and connects
5. **Choose a mode** on the Mac: Universal (keyboard/mouse emulation), Parkour (built-in game), or Debug
6. For Universal Mode, grant **Accessibility permission** when prompted (System Settings → Privacy & Security → Accessibility)

## Protocol

TCP on port 9876. Each message is a 4-byte big-endian length prefix followed by a JSON payload:

```
[4 bytes: length] [JSON payload]
```

```json
{
  "pressedButtons": ["Circle", "L2"],
  "leftStickX": 0.5,
  "leftStickY": -0.3,
  "rightStickX": 0.0,
  "rightStickY": 0.0
}
```

Button names: `DPadUp`, `DPadDown`, `DPadLeft`, `DPadRight`, `Triangle`, `Circle`, `Cross`, `Square`, `L1`, `L2`, `R1`, `R2`, `L3`, `R3`, `Create`, `Options`, `PS`, `Touchpad`, `Mute`

## Project Structure

```
Controller/                         # iOS/macOS SwiftUI app
  ControllerApp.swift               # Entry point, platform routing
  ContentView.swift                 # iOS controller UI (PS5 layout)
  NetworkService.swift              # iOS TCP sender + macOS USB receiver
  ControllerMessage.swift           # Shared Codable message model
  InputMapper.swift                 # macOS keyboard/mouse emulation
  ReceiverView.swift                # macOS UI with tab switcher
  GameView.swift                    # macOS 3D parkour game (SceneKit)
  SoundManager.swift                # Procedural audio engine

Controller-Android/                 # Android app (Kotlin + Compose)
  app/src/main/java/com/toby/controller/
    MainActivity.kt                 # Activity + Compose UI + edit mode
    ControllerSender.kt             # TCP server on port 9876
    ControllerMessage.kt            # JSON message model
    LayoutStore.kt                  # SharedPreferences for layout persistence
```

## Tech Stack

| Component | Technology |
|-----------|-----------|
| iOS/macOS UI | SwiftUI |
| 3D Game | SceneKit |
| Networking | Network.framework (Apple), raw sockets (Android) |
| Audio | AVAudioEngine (procedural synthesis) |
| Android UI | Jetpack Compose + Material3 |
| Build | Xcode / Gradle 8.11.1 |
| Language | Swift (Apple) / Kotlin 2.1.0 (Android) |

No third-party dependencies on the Apple side. Android uses only standard Jetpack libraries.
