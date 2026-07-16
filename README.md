# virtual-display-stream

An experimental macOS 15 command-line MVP that creates one virtual display and streams it as raw H.264 over unencrypted HTTP. It uses private CoreGraphics APIs and is not suitable for the Mac App Store or untrusted networks.

## Requirements

- Apple Silicon Mac running macOS 15
- Xcode 16 command-line tools
- Screen Recording permission for the terminal or executable
- `ffplay` or another player that accepts an Annex-B H.264 HTTP stream

## Build and run

```bash
swift build -c release
.build/release/virtual-display-stream --width 1920 --height 1080 --fps 30 --bitrate 4000000 --port 8080
```

The command prints URLs for active non-loopback IPv4 interfaces. On another machine in the trusted LAN:

```bash
ffplay -fflags nobuffer -flags low_delay -f h264 http://<Mac-IP>:8080/stream.h264
```

Use `virtual-display-stream --help` for display, encoder, port, HiDPI, and cursor options. Only one stream viewer is supported. `/healthz` provides basic JSON status.

## Permissions and limitations

On first launch, approve Screen Recording in **System Settings → Privacy & Security → Screen Recording**, then restart the command. The server has no TLS, authentication, discovery, audio, remote input, browser player, or congestion control. Raw HTTP/H.264 is intended only as an MVP transport on a trusted LAN.

`CGVirtualDisplay` is private, undocumented, and may change without notice. This package deliberately has no sandbox/signing/App Store configuration. Real display creation, TCC permission, hardware encoding, and playback must be tested on the target Mac; macOS frameworks are unavailable on Linux.

## License and references

Project code is MIT licensed. The private API declarations and lifecycle patterns are derived from the MIT-licensed DeskPad and VirtualDisplayKit projects; see [NOTICE](NOTICE). Deskreen was used only as architectural research and no AGPL source is included.
