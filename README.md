# Controller

Turn your phone into a PS5-style game controller for your Mac — over USB, WiFi, or Bluetooth. Supports **multiple controllers** simultaneously, and can deliver camera input as **genuine mouse hardware** for games that ignore synthetic input.

A cross-platform system with native apps for **Android** (Kotlin/Compose), **iOS** (SwiftUI), and **macOS** (SwiftUI). The Mac runs a server, phones connect as clients, and controller input streams in real time with a low-latency pipeline tuned end to end (no-delay TCP, 250 Hz sending, real-time threads, 500 Hz virtual HID reports).

## Download

- **[Controller.dmg](../../releases/latest)** — the macOS app, with the Virtual Mouse Helper bundled inside.
- For **Real mouse mode** (camera input as genuine mouse hardware — needed for games that ignore synthetic input, e.g. Wuthering Waves), also install the
  **[Karabiner virtual HID driver](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/releases)** (.pkg), approve it under
  System Settings → General → Login Items & Extensions → Driver Extensions, then run `sudo ./install.sh` from the *Virtual Mouse Helper* folder in the DMG.

## How It Works

```
Phone (Android/iOS)                      Mac (macOS) — Server
┌──────────────────┐                    ┌────────────────────────────┐
│  PS5 Controller  │──── TCP 9876 ────► │  Universal Mode            │
│  Touch UI        │  USB (ADB reverse) │  ├─ keyboard + mouse       │
└──────────────────┘    or WiFi         │  │  emulation (CGEvents)   │
                                        │  └─ Real mouse mode        │
         │                              │     (virtual HID hardware) │
         └─── Bluetooth HID gamepad ──► │  Debug View                │
              (any host, no app needed) └────────────────────────────┘
```

Four ways to connect:

| Mode | Path | Best for |
|------|------|----------|
| **USB** | ADB reverse tunnel, phone → `localhost:9876` | Lowest latency; Wi‑Fi auto-closes while linked |
| **WiFi** | Bonjour auto-discovery or manual IP | Wireless play on the same network |
| **Gamepad (BT)** | Phone registers as a real Bluetooth HID gamepad | Any Mac/PC/Android TV — no receiver app needed |
| **iPad BT** | BLE link to the iPad receiver app | Using an iPad as the receiver |

## Features

### Phone Controller (Android & iOS)
- Full PS5 DualSense layout, positioned and proportioned to match the real controller
- **Themes** — DualSense (Midnight Black shell, blue light bar down the touchpad's slanted sides, PS5 face buttons, glyphs printed above the Create/Options pills), plus Minimal, Neon and Stealth
- **Light bar states** — hairline blue when connected, dim pulse while connecting; a white player-indicator strip under the touchpad flashes while connecting and stays lit once linked
- **Wallpapers** — five built-in gradients or your own photo, independent of the theme
- **Stick click (L3/R3)** — Off, Button (curved arc on the stick's inner side) or Ring (full ring plus push-past-the-edge click)
- **Edit Mode** — drag any button/stick to a custom position; persists across restarts
- **Bluetooth Gamepad mode** (Android) — the phone becomes a genuine BT HID gamepad: standard hat-switch D-Pad, 14 buttons, dual analog sticks; pairs with any host from its Bluetooth settings
- Unbuffered touch dispatch + 250 Hz send pump — stick input isn't quantized to the display refresh
- Low-latency WiFi lock and no-delay TCP so packets leave immediately
- Haptic feedback, auto-discovery, auto-reconnect to the last Bluetooth host

### Mac Receiver

**Universal Mode** — use your phone as a controller for *any* game or app:
- Emulates keyboard + mouse via macOS Accessibility APIs, or — with **Real mouse mode** — through a **virtual HID pointing device**, indistinguishable from physical mouse hardware (for games like Wuthering Waves that ignore or badly pace synthetic input)
- Camera pipeline built like a gaming mouse: real-time (audio-class) input thread, constant 500 Hz reports, adjustable smoothing for touch-sampling jitter
- Presets: **FPS**, **Racing**, **Platformer**, **WuWa** (mirrors the game's PS5 layout onto its PC keybinds, including mouse-button attacks) + fully custom rebinding, with mouse L/R/M bindable
- Connection panel: live Wi‑Fi address, USB link status with one-click reconnect, and automatic **Wi‑Fi shutoff while a USB cable is linked** so input never arrives over two paths
- Live Accessibility-permission banner — no more silent failure when macOS revokes it

**Debug View** — real-time stick positions, button states, and connected clients.

### iPad Receiver
- Runs the same server as macOS — phones connect to the iPad too
- Includes a SceneKit parkour game and debug view

## Known issues

- **The right stick still feels slightly glitchy in some games.** The input path
  has been rebuilt end to end — real-time scheduling, 500 Hz virtual HID
  reports, no allocations in the hot loop, unbuffered touch sampling, ordered
  low-latency networking — and the packet stream measures clean (p50 ~8ms).
  A real mouse is perfectly smooth in the same game, so what remains appears to
  be how the game itself paces non-hardware pointer input rather than anything
  measurable in this pipeline. **Camera Smoothing** in the Universal tab trades
  responsiveness for steadiness; USB is the smoothest transport.

## Requirements

- **macOS** (Xcode to build, or use the DMG)
- **Android phone** with USB debugging enabled, or **iOS device**
- **ADB** for USB mode (common install paths are searched automatically)
- For WiFi: Mac and phone on the same network
- For Real mouse mode: the [Karabiner virtual HID driver](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/releases) + bundled helper

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
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

### Virtual Mouse Helper (Real mouse mode)
```bash
cd tools/vhid-bridge
VHID_SRC=/path/to/Karabiner-DriverKit-VirtualHIDDevice ./build.sh
sudo ./install.sh          # installs as a root LaunchDaemon
```

## Usage

### USB (recommended — lowest latency)
1. Connect the phone via USB (USB debugging enabled)
2. Launch Controller on the Mac — the USB status in the Universal tab shows the phone as *linked* and Wi‑Fi closes automatically
3. On the phone, pick **USB** in the gear menu

### WiFi
1. Launch Controller on the Mac — the Universal tab shows the listen address
2. On the phone, pick **WiFi** — it auto-discovers the Mac (or enter the IP manually)

### Bluetooth Gamepad (no Mac app needed)
1. On the phone, pick **Gamepad** in the gear menu
2. Tap **Make phone discoverable**, then pair from the computer's Bluetooth settings — or tap an already-paired device in the list
3. The phone shows up as a standard gamepad on any host (note: not iPhone/iPad — Apple only accepts Xbox/PS/MFi controllers)

### Playing games that ignore synthetic input (e.g. Wuthering Waves)
1. Install the Karabiner driver + helper (see Download)
2. Universal tab → **Enable Keyboard/Mouse Mapping** → **Real mouse mode** (badge shows green `HID OK`)
3. Pick the **WuWa** preset and play — camera and clicks arrive as real mouse hardware
4. Tune **Mouse Sensitivity** and **Camera Smoothing** to taste

Grant **Accessibility permission** when prompted (the Universal tab shows a red banner with a Grant button if it's missing).

## Architecture

**Server-client model**: the Mac (or iPad) runs a TCP server on port 9876; phones connect as clients.

- **WiFi**: Bonjour advertising (`_ps5ctrl._tcp`), auto-discovery, no-delay TCP everywhere
- **USB (Android)**: the Mac polls ADB and maintains `adb reverse tcp:9876 tcp:9876`; the phone connects to localhost. While a cable client is live, Bonjour stops and Wi‑Fi clients are refused
- **Input hot path (Mac)**: network thread → mapper → real-time tick thread → CGEvents *or* the virtual HID bridge — the UI is fully out of the input path and updates at a throttled rate
- **Virtual mouse**: `tools/vhid-bridge` runs as root, bridging a unix socket (4-byte binary records) to the Karabiner DriverKit virtual pointing device at 500 Hz
- **Multi-client**: multiple phones connect simultaneously, each tracked independently

## Protocol

TCP on port 9876. Each message is a 4-byte big-endian length prefix followed by a JSON payload:

```json
{
  "pressedButtons": ["Circle", "L2"],
  "leftStickX": 0.5,
  "leftStickY": -0.3,
  "rightStickX": 0.0,
  "rightStickY": 0.0
}
```

Button names: `DPadUp`, `DPadDown`, `DPadLeft`, `DPadRight`, `Triangle`, `Circle`, `Cross`, `Square`, `L1`, `L2`, `R1`, `R2`, `L3`, `R3`, `Create`, `Options`, `PS`, `Touchpad`

Helper socket (`/tmp/controller-vhid.sock`): fixed 4-byte records `[0xA5][buttons][int8 dx][int8 dy]`.

## Project Structure

```
Controller/                         # iOS/macOS SwiftUI app
  ControllerApp.swift               # Entry point, platform routing
  ContentView.swift                 # iOS controller UI (PS5 layout)
  NetworkService.swift              # ControllerServer (macOS/iPad) + ControllerClient (iPhone)
  ControllerMessage.swift           # Shared Codable message model
  InputMapper.swift                 # macOS input engine: CGEvents, presets, RT tick thread
  VirtualMouse.swift                # Client for the virtual HID bridge
  ReceiverView.swift                # macOS UI (Universal + Debug)
  GameView.swift / DualGameView.swift  # SceneKit parkour (iPad)
  iPadReceiverView.swift            # iPad receiver
  SoundManager.swift                # Procedural audio engine (iPad game)

Controller-Android/                 # Android app (Kotlin + Compose)
  app/src/main/java/com/toby/controller/
    MainActivity.kt                 # Activity + Compose UI + edit mode
    ControllerSender.kt             # TCP client, 250 Hz send pump, WiFi lock
    BluetoothHidController.kt       # BT HID gamepad mode (works with any host)
    BleControllerPeripheral.kt      # BLE link to the iPad receiver
    ControllerMessage.kt            # JSON message model
    LayoutStore.kt                  # SharedPreferences for layout + connection settings

tools/vhid-bridge/                  # Root helper for Real mouse mode
  main.cpp                          # Unix socket → Karabiner virtual HID pointing device
  build.sh / install.sh             # Build + LaunchDaemon installer
```

## Tech Stack

| Component | Technology |
|-----------|-----------|
| iOS/macOS UI | SwiftUI |
| Networking | Network.framework (Apple), raw sockets (Android), no-delay TCP |
| Discovery | Bonjour / NSD (mDNS) |
| Bluetooth | BluetoothHidDevice (Android), CoreBluetooth (iPad link) |
| Virtual mouse | Karabiner DriverKit virtual HID + C++ bridge |
| Input timing | mach time-constraint (real-time) threads |
| Android UI | Jetpack Compose + Material3 |
| 3D Game (iPad) | SceneKit + AVAudioEngine |
| Build | Xcode / Gradle 8.11.1 |
| Language | Swift / Kotlin 2.1.0 / C++ (bridge) |

No third-party runtime dependencies on the Apple side beyond the optional Karabiner driver. Android uses only standard Jetpack libraries.
