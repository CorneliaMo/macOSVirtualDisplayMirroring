# virtual-display-stream

An experimental macOS 15 command-line MVP that creates one virtual display and streams it to a browser over WebRTC. The default backend delegates capture and WebRTC to Chromium while Swift owns the virtual-display lifecycle. Signaling and the viewer page use unencrypted HTTP/WebSocket, so it is intended only for a trusted LAN.

## Requirements

- Apple Silicon Mac running macOS 15
- Xcode 16 command-line tools
- Node.js and npm for the default Chromium backend
- Screen Recording permission for Electron when using the default backend, or for the executable when using `--backend native`
- A current Safari, Chrome, Firefox, or Edge browser on the viewing device

## Build and run

```bash
cd ChromiumStreamer && npm install && npm run build && cd ..
swift build -c release
.build/release/virtual-display-stream --backend chromium --width 1920 --height 1080 --fps 60 --port 8080
```

The command prints viewer URLs for active non-loopback IPv4 interfaces. Open `http://<Mac-IP>:8080/` on another device in the trusted LAN. The page connects automatically and exposes live sender/receiver diagnostics—including codec, resolution, throughput, recent playout delay, RTT, loss, QP, Chromium's quality-limitation reason, and the latest Auto decision—plus fullscreen, reconnect, and diagnostics-copy controls.

The helper uses Chromium `desktopCapturer`/`getUserMedia` and `simple-peer`, with manual 100%/50% modes and an experimental Auto mode. Auto combines motion, receiver buffering/loss, sender RTT, encoding time, and Chromium limitation signals; it currently adjusts sender bitrate/FPS while retaining native capture resolution. Use `--chromium-directory <path>` when launching outside the repository root. The earlier ScreenCaptureKit/libwebrtc path remains available through `--backend native`.

If Electron reports an incomplete installation, rerun `npm install` in `ChromiumStreamer`. The launcher uses Electron's supported CLI entry point instead of assuming a version-specific `.app` layout.

Use `virtual-display-stream --help` for display, WebRTC SDP bandwidth, port, HiDPI, and cursor options. Defaults follow Deskreen's LAN-oriented profile: 60 FPS, an effectively unrestricted 500 Mbps SDP video bandwidth, VP8 preference, and no STUN/TURN servers. Only one browser viewer is supported. `/healthz` provides basic JSON status.

## Permissions and limitations

On first launch, approve Screen Recording in **System Settings → Privacy & Security → Screen Recording**, then restart the command. The server has no TLS, authentication, discovery, audio, remote input, relay, or STUN/TURN service. WebRTC encrypts media by protocol, but the page and signaling channel are unauthenticated and unencrypted. Direct host ICE candidates also mean peers must be mutually reachable on the LAN.

`CGVirtualDisplay` is private, undocumented, and may change without notice. This package deliberately has no sandbox/signing/App Store configuration. Real display creation, TCC permission, hardware encoding, and playback must be tested on the target Mac; macOS frameworks are unavailable on Linux.

## License and references

Project code is MIT licensed. The private API declarations and lifecycle patterns are derived from the MIT-licensed DeskPad and VirtualDisplayKit projects; see [NOTICE](NOTICE). Deskreen was used only as architectural research and no AGPL source is included.
