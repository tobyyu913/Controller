# Controller

Turn your phone into a PS5-style game controller for your Mac — over USB or WiFi. Supports **multiple controllers** simultaneously.

A cross-platform system with native apps for **Android** (Kotlin/Compose), **iOS** (SwiftUI), and **macOS** (SwiftUI/SceneKit). The Mac runs a server, phones connect as clients, and controller input streams in real time. Includes a split-screen co-op platformer for two players.

## How It Works

```
Phone 1 (Android/iOS)                    Mac (macOS) — Server
┌──────────────────┐                    ┌──────────────────────┐
│  PS5 Controller  │──── TCP 9876 ────► │  Receiver            │
│  Touch UI        │  USB (ADB reverse) │  ├─ Universal Mode   │
└──────────────────┘    or WiFi         │  ├─ Parkour Game     │
                                        │  ├─ Co-op (2P Split) │
Phone 2 (Android/iOS)                   │  └─ Debug View       │
┌──────────────────┐                    │                      │
│  PS5 Controller  │──── TCP 9876 ────► │  Maps input to keys, │
│  Touch UI        │                    │  mouse, or 3D game   │
└──────────────────┘                    └──────────────────────┘
```

The Mac runs a TCP server on port 9876 and advertises via Bonjour. Phones discover the server automatically (WiFi) or connect through ADB reverse port forwarding (USB). Multiple phones can connect simultaneously — each becomes a separate controller.

## Features

### Phone Controller (iOS & Android)
- Full PS5 DualSense layout — D-Pad, face buttons, analog sticks, triggers, bumpers, and system buttons
- Analog sticks with spring-back animation and click (L3/R3) support
- Haptic feedback on stick press (iOS)
- Auto-discovery of Mac server via Bonjour/mDNS
- Manual server IP entry for WiFi, automatic localhost for USB
- **Edit Mode** (Android only) — tap the gear icon to drag any button/stick to a custom position; layout persists across restarts

### Mac Receiver — Four Modes

**Universal Mode** — use your phone as a controller for *any* game or app:
- Emulates keyboard + mouse input via macOS Accessibility APIs
- Default mapping: left stick -> WASD, right stick -> mouse look, face buttons -> Space/E/Q/F, triggers -> Shift/Ctrl
- 3 built-in presets (FPS, Racing, Platformer) + fully custom rebinding
- Adjustable mouse sensitivity

**Parkour Game** — a built-in 3D platformer to test the controller:
- SceneKit-based 3D course with 8 checkpoints and 28+ platforms
- Move with left stick, look with right stick, jump with Circle
- Sprint (L2) for speed + longer jumps, squat (R2) to slow down
- Double-jump, coyote time, fall respawn
- Procedurally generated soundtrack and sound effects

**Co-op Mode** — split-screen dual-player platformer:
- Two phones, two players, one screen split in half
- Player 1 (orange) on left, Player 2 (cyan) on right
- Each player has their own camera with right-stick orbit control
- Movement is relative to camera facing direction
- Shared checkpoints and course progression

**Debug View** — live visualization of all controller input:
- Real-time stick position display with crosshairs
- Color-coded button state indicators
- Connected clients list showing all active controllers

### iPad Receiver
- Runs the same server as macOS — phones connect to iPad too
- Parkour game + debug view tabs
- Auto-advertises via Bonjour on the local network

## Requirements

- **macOS** with Xcode installed
- **Android phone** with USB debugging enabled, or **iOS device/simulator**
- **ADB** installed (the app searches common install paths automatically) — needed for USB only
- For WiFi: Mac and phone on the same network

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

### Single Controller (USB)
1. **Connect** your Android phone to your Mac via USB
2. **Enable USB debugging** on the phone (Settings > Developer Options > USB Debugging)
3. **Launch the Controller app** on the Mac — it auto-detects the phone and sets up ADB reverse forwarding
4. **Launch the Controller app** on the phone — set to Cable mode in settings, it connects to localhost:9876
5. **Choose a mode** on the Mac: Universal, Parkour, Co-op, or Debug

### Single Controller (WiFi)
1. **Launch the Controller app** on the Mac — server starts and advertises via Bonjour
2. **Launch the Controller app** on the phone — set to WiFi mode, it auto-discovers the Mac
3. Alternatively, enter the Mac's IP address manually in the phone's settings

### Two Controllers (Co-op)
1. Connect two phones (USB or WiFi)
2. Open the **Co-op** tab on the Mac
3. First phone connected = **P1** (orange, left screen), second = **P2** (cyan, right screen)
4. Left stick to move, Circle to jump, L2 to sprint, right stick to rotate camera

For Universal Mode, grant **Accessibility permission** when prompted (System Settings > Privacy & Security > Accessibility).

## Architecture

**Server-client model**: The Mac (or iPad) runs a TCP server on port 9876. Phones connect as clients.

- **WiFi**: Server advertises via Bonjour (`_ps5ctrl._tcp`). Phones auto-discover or manually enter the server IP.
- **USB (Android)**: Mac polls for ADB devices and runs `adb reverse tcp:9876 tcp:9876`. The phone connects to `localhost:9876` which tunnels back to the Mac's server.
- **Multi-client**: The server accepts multiple simultaneous connections. Each connected phone is tracked independently with its own controller state.

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
  NetworkService.swift              # ControllerServer (macOS/iPad) + ControllerClient (iPhone)
  ControllerMessage.swift           # Shared Codable message model
  InputMapper.swift                 # macOS keyboard/mouse emulation
  ReceiverView.swift                # macOS UI with tab switcher
  GameView.swift                    # macOS 3D parkour game (SceneKit)
  DualGameView.swift                # Split-screen co-op platformer (2 players)
  iPadReceiverView.swift            # iPad receiver (server + game + debug)
  SoundManager.swift                # Procedural audio engine

Controller-Android/                 # Android app (Kotlin + Compose)
  app/src/main/java/com/toby/controller/
    MainActivity.kt                 # Activity + Compose UI + edit mode
    ControllerSender.kt             # TCP client connecting to Mac/iPad server
    ControllerMessage.kt            # JSON message model
    LayoutStore.kt                  # SharedPreferences for layout + server host
```

## Tech Stack

| Component | Technology |
|-----------|-----------|
| iOS/macOS UI | SwiftUI |
| 3D Game | SceneKit |
| Networking | Network.framework (Apple), raw sockets (Android) |
| Discovery | Bonjour / NSD (mDNS) |
| Audio | AVAudioEngine (procedural synthesis) |
| Android UI | Jetpack Compose + Material3 |
| Build | Xcode / Gradle 8.11.1 |
| Language | Swift (Apple) / Kotlin 2.1.0 (Android) |

No third-party dependencies on the Apple side. Android uses only standard Jetpack libraries.
