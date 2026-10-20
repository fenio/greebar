# GreeBar

A macOS menu bar app for controlling Gree air conditioners over your local network.
It speaks the same UDP protocol as the Gree+ app (port 7000), so no cloud account is needed.

- Power, target temperature, mode (Auto/Cool/Dry/Fan/Heat) and fan speed
- Turbo, Quiet, Sleep, Swing, Light and Health toggles
- Shows the mode and target temperature in the menu bar, and the room temperature in the popover
- Supports both older (AES-ECB) and newer (AES-GCM) firmware

## Install

```bash
brew install --cask fenio/tap/greebar
```

Requires macOS 14 (Sonoma) or later, on Apple Silicon or Intel.

## Setup

1. The air conditioner must already be on your Wi-Fi network. Set it up once with the Gree+ app.
2. Launch GreeBar and click the air conditioner icon in the menu bar.
3. Allow **Local Network** access when macOS asks. If you missed the prompt, enable GreeBar in
   System Settings › Privacy & Security › Local Network.
4. Click **Scan network**, then **Pair**. If the scan finds nothing, enter the unit's IP address
   and click **Find**.

Tip: give the air conditioner a fixed IP address (a DHCP reservation on your router), since
GreeBar remembers the address it paired with.

To start GreeBar at login, use the gear icon › **Launch at Login**.

## Build from source

Requires Xcode (the SwiftUI macros aren't included in the Command Line Tools).

```bash
./build-app.sh
open build/GreeBar.app
```

## Layout

- `GreeCrypto.swift`: AES-ECB and AES-GCM pack encryption
- `UDPSocket.swift`: BSD-socket UDP with broadcast support
- `GreeClient.swift`: scan, bind, status and cmd messages
- `ACState.swift`: typed view over Gree parameters (`Pow`, `Mod`, `SetTem`, `WdSpd`, ...)
- `ACController.swift`: app state, polling (60 s), debounced temperature changes
- `MenuView.swift`: SwiftUI popover UI

Releases are published with `./release.sh <version>`, which also updates the cask in
[fenio/homebrew-tap](https://github.com/fenio/homebrew-tap).

## License

MIT
