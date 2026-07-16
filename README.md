# virtual-display-stream

An experimental macOS 15 command-line MVP that creates one virtual display and streams it to a browser over WebRTC. Signaling and the viewer page use unencrypted HTTP/WebSocket, so it is intended only for a trusted LAN. The virtual display uses private CoreGraphics APIs and is not suitable for the Mac App Store.

## Requirements

- Apple Silicon Mac running macOS 15
- Xcode 16 command-line tools
- Screen Recording permission for the terminal or executable
- A current Safari, Chrome, Firefox, or Edge browser on the viewing device

## Build and run

```bash
swift build -c release
.build/release/virtual-display-stream --width 1920 --height 1080 --fps 30 --bitrate 12000000 --port 8080
```

The command prints viewer URLs for active non-loopback IPv4 interfaces. Open `http://<Mac-IP>:8080/` on another device in the trusted LAN. The page connects automatically and exposes live WebRTC receiver statistics—including codec, decode time, playout-buffer delay, and dropped frames—fullscreen (button or `F`), and manual reconnect controls.

Capture and WebRTC delivery favor latency over frame completeness: ScreenCaptureKit uses its minimum supported three-frame surface pool, while the sender retains only the latest frame when delivery falls behind. Resolution remains fixed; under load, WebRTC should drop frames instead of accumulating stale video.

Use `virtual-display-stream --help` for display, WebRTC bitrate, port, HiDPI, and cursor options. Only one browser viewer is supported. `/healthz` provides basic JSON status.

## Permissions and limitations

On first launch, approve Screen Recording in **System Settings → Privacy & Security → Screen Recording**, then restart the command. The server has no TLS, authentication, discovery, audio, remote input, relay, or STUN/TURN service. WebRTC encrypts media by protocol, but the page and signaling channel are unauthenticated and unencrypted. Direct host ICE candidates also mean peers must be mutually reachable on the LAN.

`CGVirtualDisplay` is private, undocumented, and may change without notice. This package deliberately has no sandbox/signing/App Store configuration. Real display creation, TCC permission, hardware encoding, and playback must be tested on the target Mac; macOS frameworks are unavailable on Linux.

## License and references

Project code is MIT licensed. The private API declarations and lifecycle patterns are derived from the MIT-licensed DeskPad and VirtualDisplayKit projects; see [NOTICE](NOTICE). Deskreen was used only as architectural research and no AGPL source is included.
