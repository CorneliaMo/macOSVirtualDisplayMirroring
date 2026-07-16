# macOS 虚拟显示器与网络镜像实现研究

> 研究基线：DeskPad `c3349f0`（2026-02-28），VirtualDisplayKit `32227f2`（2026-04-16），Deskreen `b5dc3d4` / 3.2.16（2026-07-08）。本文基于对应源码快照，私有 API 随 macOS 更新可能改变，必须按目标系统实测。

## 1. 结论先行

项目可以实现，建议使用“原生 macOS 主程序 + 浏览器观看端”的结构：

1. Swift/AppKit 主程序通过 CoreGraphics 私有类 `CGVirtualDisplay*` 创建虚拟显示器；
2. 使用公开的 ScreenCaptureKit 精确采集该虚拟显示器；
3. 将帧交给 VideoToolbox/WebRTC 编码与传输；
4. 内置 HTTPS/WSS 信令与静态网页服务，其他设备扫码后直接用浏览器观看；
5. Bonjour 用于可选发现，二维码携带一次性配对凭据；
6. 私有显示 API 封装为极薄的适配层，启动时做运行时探测，并维护按 macOS 版本划分的兼容性测试。

真正不可替代的私有部分只有“创建软件虚拟显示器”。采集、编码、传输、服务发现和 UI 都应使用公开 API。不要把 DeskPad 的 `CGDisplayStream` 预览链路或 Deskreen 的 Electron 捕获与明文信令整体照搬。

## 2. DeskPad 的实现方式

### 2.1 创建虚拟显示器

DeskPad 在 `CGVirtualDisplayPrivate.h` 中自行声明了 CoreGraphics 内未公开到 SDK 的 Objective-C 类。运行时实现来自系统 CoreGraphics，而不是项目自带代码：

- `CGVirtualDisplayDescriptor`：描述显示设备身份和上限；
- `CGVirtualDisplay`：创建并持有实际虚拟显示设备；
- `CGVirtualDisplaySettings`：一次性应用模式集合及 HiDPI 标记；
- `CGVirtualDisplayMode`：一个宽、高、刷新率组合。

调用顺序严格为：

1. 创建 descriptor；
2. 设置 dispatch queue、名称、最大像素尺寸、物理尺寸、vendor/product/serial；
3. 用 descriptor 初始化 `CGVirtualDisplay`；
4. 读取其 `displayID`，将它与 `NSScreen` / CoreGraphics API 关联；
5. 创建 settings，设置 `hiDPI` 和 modes；
6. 调用 `applySettings:` 并检查返回值；
7. 在需要显示器存活的整个期间强引用 `CGVirtualDisplay`。

DeskPad 的具体参数是最大 5120×2160、物理尺寸 1600×1000 mm、vendor `0x3456`、product `0x1234`、serial `1`、HiDPI 开启，并提供多组 32:9、21:9、16:9、16:10 的 60 Hz 模式。

### 2.2 私有 API 的 ABI 约定

当前源码声明出的契约如下：

```objc
CGVirtualDisplayMode.initWithWidth:height:refreshRate:
CGVirtualDisplaySettings.modes
CGVirtualDisplaySettings.hiDPI
CGVirtualDisplayDescriptor.queue / setDispatchQueue:
CGVirtualDisplayDescriptor.name
CGVirtualDisplayDescriptor.maxPixelsWide / maxPixelsHigh
CGVirtualDisplayDescriptor.sizeInMillimeters
CGVirtualDisplayDescriptor.vendorID / productID / serialNum
CGVirtualDisplayDescriptor.terminationHandler
CGVirtualDisplay.initWithDescriptor:
CGVirtualDisplay.displayID
CGVirtualDisplay.applySettings:
```

类型约定尤其重要：像素和模式宽高为 `NSUInteger`，刷新率为 `CGFloat`，ID 字段为 32 位 unsigned int，显示器 ID 为 `CGDirectDisplayID`，物理尺寸为 `CGSize`，queue 为 `dispatch_queue_t`。Swift 通过 bridging header 直接调用 Objective-C selector。

实现层必须增加 DeskPad 尚未做的防护：

- 用 `NSClassFromString`、`instancesRespond(to:)` 检查类和 selector；
- 校验构造结果、`displayID != 0` 和 `applySettings == true`；
- 设置 termination handler 并将异常终止转成状态事件；
- descriptor 的 `maxPixels*` 不小于任何 mode 的像素尺寸；
- vendor/product/serial 在同一应用创建多个显示器时保持唯一且稳定，以利 macOS 恢复显示排列；
- 所有生命周期操作串行化；销毁即释放最后一个 display 强引用；
- 不假设属性、selector 或 HiDPI 语义跨系统版本永远稳定。

### 2.3 沙盒私有约定

DeskPad 开启 App Sandbox，并加入：

```xml
<key>com.apple.security.temporary-exception.mach-lookup.global-name</key>
<array><string>com.apple.VirtualDisplay</string></array>
```

这说明虚拟显示器实现需要与名为 `com.apple.VirtualDisplay` 的全局 Mach 服务通信。它是临时例外 entitlement，而非稳定公开能力。实际分发前必须分别验证：

- Developer ID 签名 + notarization 是否接受并能运行；
- Mac App Store 审核是否接受该临时例外和未公开 API（不应把通过审核当作可依赖前提）；
- 新 macOS 版本上服务名、沙盒行为和类 ABI 是否变化。

若走沙盒，网络服务还要显式增加 `com.apple.security.network.server`；WebRTC/更新等出站连接需要 `com.apple.security.network.client`。当前 DeskPad entitlement 不包含网络能力。

### 2.4 显示配置、预览和输入

DeskPad 监听 `NSApplication.didChangeScreenParametersNotification`，再用 `NSScreenNumber` 将 `NSScreen` 匹配到虚拟 `displayID`，读取逻辑分辨率与 `backingScaleFactor`。

它用 `CGDisplayStream(dispatchQueueDisplay:...)` 捕获虚拟显示器，将 `IOSurface` 直接放入 `CALayer.contents`，像素格式常量 `1111970369` 即 `kCVPixelFormatType_32BGRA`，并开启 cursor。配置变化时停止旧 stream、按逻辑尺寸×scale factor 重建。点击预览时把窗口坐标映射到显示坐标，再调用 `CGDisplayMoveCursorToPoint`。

我们应保留坐标映射和显示变化监听思路，但采集改用 ScreenCaptureKit。后者输出 `CMSampleBuffer`，更适合接 VideoToolbox/WebRTC，并提供更现代的内容选择、帧元数据和音频能力。

### 2.5 VirtualDisplayKit 补充验证

VirtualDisplayKit 是 DeskPad 的 MIT 派生项目，把同一组私有声明包装成 macOS 13+、Swift 5.9+ 的 Swift Package。它确认了私有 ABI 与 DeskPad 完全一致，并提供了值得借鉴的工程分层：

- 独立 C target `CVirtualDisplayPrivate` + module map 暴露私有 Objective-C 声明；
- `VirtualDisplayConfiguration` 汇总名称、最大尺寸、物理尺寸、设备 ID、HiDPI、刷新率、模式和捕获 backend；
- `VirtualDisplay` 由 `@MainActor` 隔离，持有显示器、发布 displayID/resolution/scale/isReady 状态；
- 创建后每 100 ms 查询一次 `NSScreen`，最多 50 次，用于处理显示器注册到 AppKit 的异步延迟；
- ScreenCaptureKit 找不到虚拟 display 时回退 `CGDisplayStream`；
- 将 `IOSurface`/`CVPixelBuffer` 接入 AVAssetWriter 和 VideoToolbox；
- VideoToolbox 流配置使用 realtime、平均码率、期望帧率、关键帧间隔、禁止 B-frame，并输出 Annex-B NAL units。

它也揭示了不能把第三方封装直接视为生产答案的原因：

- 没有 `NSClassFromString` / selector 响应检查，仍是静态链接私有类声明；
- 未设置 `terminationHandler`；
- `CGVirtualDisplay` 构造结果、`displayID` 和 `applySettings` 的失败没有转成可靠错误，`applySettings` 只打印；
- 配置缺少 mode 范围、空列表、负/零尺寸、ID 冲突等验证；
- `.automatic` 实际固定选择 legacy `CGDisplayStream`，注释称虚拟显示器使用 ScreenCaptureKit 存在已知问题；因此“默认使用 ScreenCaptureKit”必须经过我们的目标 macOS 实测，不能只凭 API 新旧决定；
- ScreenCaptureKit 出错会静默回退，调用方无法区分权限错误、display 不可见和 stream 错误；
- `IOSurface → CVPixelBuffer` 路径逐行 CPU memcpy，不是零拷贝，高分辨率下会增加延迟和功耗；ScreenCaptureKit 已给出的 CVPixelBuffer 应直接传递；
- 测试目前主要覆盖配置值和初始状态，没有真实显示创建、捕获、编码、休眠唤醒和清理的集成测试；
- demo entitlement 是空的，不能据此证明沙盒 + `com.apple.VirtualDisplay` 临时例外可工作；
- 文档所称“RTMP-ready”只是生成 Annex-B H.264/HEVC；实际 RTMP mux/握手、WebRTC RTP packetization、拥塞控制和网络服务均未实现。

因此可把它作为本项目 `VirtualDisplayKit` 模块的设计输入，甚至在遵守 MIT NOTICE 的前提下选择性复用，但应先修正上述错误边界、兼容探测和性能路径。尤其不要把已经由 VideoToolbox 编出的 Annex-B H.264 直接塞入浏览器 WebRTC；原生 WebRTC SDK 通常应接收 raw pixel buffer 并自行完成 RTP/RTCP、编解码协商和拥塞控制，除非我们实现并维护完整的 external encoder adapter。

## 3. Deskreen 的实现方式

### 3.1 端到端数据流

Deskreen 是 Electron 应用，主要链路为：

1. 主进程在 `0.0.0.0:3131`（冲突时 3132 或随机端口）运行 Koa HTTP 服务器；
2. 同一服务分发浏览器 viewer 静态资源，并挂载 Socket.IO 信令；
3. 主界面生成 `http://局域网IP:端口/roomID` 和二维码；
4. 浏览器进入 room，通过 Socket.IO 交换设备信息和 WebRTC SDP/ICE signal；
5. 宿主端显示连接设备并要求用户允许；
6. Electron `desktopCapturer.getSources` 枚举 screen/window；
7. Chromium 私有约束 `chromeMediaSource` + `chromeMediaSourceId` 调用 `getUserMedia` 获得 MediaStream；
8. `simple-peer` 建立 WebRTC，宿主为 initiator，浏览器为 responder；
9. 浏览器把收到的 MediaStream 交给视频播放器，可调质量与全屏。

服务端只转发 `MESSAGE`，媒体通常走 WebRTC 点对点；房间状态驻留内存，房间 ID 在服务端用 SHA-256 作为存储 key。当前实现只允许一个非 owner viewer。

### 3.2 捕获和质量控制

Deskreen 每 5 秒刷新 Electron 桌面源。屏幕源根据 Electron display ID 取得显示尺寸，然后以 0.5～1.0 倍原始宽高、15～60 fps 请求捕获。切换源时优先 `replaceTrack`，失败才重建 peer。

浏览器端通过 WebRTC data channel 请求 1.0 或 0.5 质量；宿主据此换捕获轨道。浏览器还基于视频帧表现做自动质量选择。这个“接收端反馈 → 发送端动态调整”的闭环值得保留，但生产实现应优先用：

- `RTCRtpSender.setParameters` 调整码率、帧率和 degradation preference；
- WebRTC stats（丢包、RTT、available outgoing bitrate、frames dropped）；
- 必要时再改变 ScreenCaptureKit 输出尺寸或重建编码器；
- 尺寸、码率、帧率三者用策略状态机控制，避免频繁抖动。

### 3.3 Deskreen 不能原样继承的地方

安全审计发现：

- HTTP 和 Socket.IO 均为明文；静态响应虽设置 HSTS，但 HTTP 上的 HSTS 对首次访问没有保护；
- `sendEncryptedMessage` / `receiveEncryptedMessage` 名称具有误导性，当前 `message.ts` 仅添加 sender/username 并原样返回 JSON，没有加密、签名或认证；
- Socket.IO 服务端会把客户端提交的任意 `MESSAGE` 转发给房间；
- `roomId` 实质是 bearer secret，没有额外一次性配对 token；
- SDP/ICE 信令可以被同网段中间人查看或篡改；
- `iceServers: []`，因此只面向能直连的局域网环境，跨 NAT 不可靠；
- 依靠 localhost socket 判定 owner，属于实现技巧，不宜作为完整身份认证；
- 存在源码 TODO，明确承认设备 IP spoofing 检查尚未完成；
- `sandbox: false` 的 Electron renderer 与较宽 IPC 面增加攻击面。

WebRTC 自身的媒体传输使用 DTLS-SRTP，但这不替代安全信令和可信配对。我们的实现必须提供 HTTPS/WSS、不可预测且短时有效的一次性 token、严格消息 schema、速率限制、origin 检查、明确的宿主确认，并在配对后锁定会话。

### 3.4 许可证

DeskPad 是 MIT，可在保留许可证通知的条件下复用。Deskreen 是 AGPL-3.0；若本项目不准备整体满足 AGPL 的源码提供义务，应把 Deskreen 仅作为行为与架构研究材料，重新独立实现，不复制其源码、UI 或具体表达。正式商业化前应让法律顾问确认边界。

## 4. 推荐架构

### 4.1 模块边界

```text
App/UI
 ├─ VirtualDisplayKit（唯一私有 API 边界）
 ├─ CaptureKit（ScreenCaptureKit）
 ├─ StreamingCore（WebRTC + VideoToolbox）
 ├─ PairingServer（HTTPS/WSS + token + viewer 静态页）
 ├─ Discovery（Bonjour / QR）
 └─ SessionCoordinator（状态机、权限、生命周期、恢复）

Browser Viewer
 ├─ Pairing UI
 ├─ WebSocket signaling
 ├─ RTCPeerConnection
 ├─ video/fullscreen/quality controls
 └─ connection health and reconnect UI
```

建议 Swift 原生应用承载虚拟显示与采集。WebRTC 可选 Google WebRTC 原生库；若 MVP 希望降低集成成本，也可先使用本地 WebRTC 服务组件，但不要为界面整体引入 Electron。H.264 作为 Apple 设备与浏览器的首选兼容编码，VP8 作为兼容回退；编码协商必须以浏览器 SDP 能力为准。

### 4.2 核心状态机

`idle → creatingDisplay → displayReady → awaitingPermission → capturable → advertising → pairing → awaitingApproval → negotiating → streaming → reconnecting/stopping → idle`

任一阶段都要能进入 `failed(reason)`，并有确定性的清理顺序：停止接受新连接 → 关闭 peer → 停止 capture → 撤销 Bonjour/HTTPS listener → 释放 virtual display。显示器被系统终止、分辨率变化、睡眠/唤醒、网络切换和屏幕录制权限变化都应作为显式事件处理。

### 4.3 参数模型

创建请求至少包含：

- 显示名称；
- 一组 mode：pixel width、pixel height、refresh rate；
- 默认 mode；
- HiDPI 开关；
- 最大 pixel envelope；
- 物理尺寸 mm；
- 稳定的 vendor/product/serial；
- 是否捕获 cursor；
- 网络流的最大分辨率、fps、bitrate；
- viewer 数量上限。

必须区分三套尺寸：虚拟显示模式的像素尺寸、macOS/NSScreen 的逻辑点尺寸、网络编码尺寸。HiDPI 下不可混用。

## 5. 权限、签名和分发

预计需要：

- Screen Recording 用户授权；
- Local Network 使用说明 `NSLocalNetworkUsageDescription`；
- 若用 Bonjour，声明具体 `NSBonjourServices` 类型；
- 沙盒入站网络 entitlement `com.apple.security.network.server`；
- 需要出站时加 `com.apple.security.network.client`；
- 虚拟显示 Mach lookup 临时例外 `com.apple.VirtualDisplay`；
- Hardened Runtime、Developer ID 签名和 notarization。

Screen Recording 权限与私有虚拟显示能力是两回事：显示器可能成功创建，但没有捕获权限时只能让 macOS 把它当显示器使用，不能网络镜像。权限 UI 必须准确区分这两种状态。

使用私有 API 意味着 Mac App Store 不应作为唯一分发路线。优先规划 Developer ID + notarized DMG/Homebrew cask，同时维护一套无私有功能的降级模式（只镜像现有显示器），这样私有 API 在新系统失效时应用仍有基本价值。

## 6. 分阶段实施计划

### P0：技术探针

- 建最小 Swift 命令/GUI 工程，仅创建一个 1920×1080@60 HiDPI 虚拟显示器；
- 验证 Intel/Apple Silicon、当前支持的每个 macOS 主版本；
- 验证释放、崩溃、强退、睡眠唤醒、用户登出后的清理；
- 记录类、selector、Mach service、签名和 entitlement 的兼容矩阵。

### P1：本机 MVP

- 参数化创建/销毁、模式切换和稳定身份；
- ScreenCaptureKit 捕获指定 displayID；
- 本机预览、cursor、帧率与分辨率统计；
- 权限引导与失败恢复。

### P2：可信局域网 MVP

- 内置 viewer、二维码和一次性 token；
- HTTPS/WSS 信令、单 viewer、人工允许；
- WebRTC H.264/VP8、基础自适应码率；
- 网络切换、重连和 source 消失处理。

### P3：产品化

- Bonjour、多个预设、登录恢复；
- 多 viewer 或明确限制；
- TURN（如果要跨网）及证书/身份策略；
- 自动化兼容测试、崩溃恢复、功耗与延迟优化；
- notarization、更新签名、隐私说明和许可证清单。

## 7. 测试矩阵与验收指标

系统维度至少覆盖当前支持的最近三个 macOS 主版本、Intel 与 Apple Silicon、单/多物理屏、合盖/睡眠/快速用户切换。功能用例包括创建失败、重复 ID、多虚拟屏、模式切换、权限拒绝、网络断开、viewer 刷新、应用崩溃。

首版可设以下工程目标：

- LAN 端到端交互延迟 P95 < 150 ms；
- 1080p60 稳定传输，4K 根据网络/硬件降级；
- 断网后不残留 capture/peer，恢复后可重新配对；
- 应用退出后虚拟显示器在数秒内消失；
- 非法 token、重复 viewer、畸形信令和跨 origin 请求均拒绝；
- 私有 API 探测失败时不崩溃，清晰降级到现有显示器镜像。

## 8. 参考位置

本地源码重点入口：

- `references/DeskPad/DeskPad/CGVirtualDisplayPrivate.h`
- `references/DeskPad/DeskPad/Frontend/Screen/ScreenViewController.swift`
- `references/DeskPad/DeskPad/DeskPad.entitlements`
- `references/VirtualDisplayKit/Sources/VirtualDisplayKit/Core/VirtualDisplay.swift`
- `references/VirtualDisplayKit/Sources/VirtualDisplayKit/Core/DisplayStreamRenderer.swift`
- `references/VirtualDisplayKit/Sources/VirtualDisplayKit/Core/FrameOutputStream.swift`
- `references/VirtualDisplayKit/Sources/CVirtualDisplayPrivate/include/CGVirtualDisplayPrivate.h`
- `references/Deskreen/src/server/index.ts`
- `references/Deskreen/src/server/darkwireSocket.ts`
- `references/Deskreen/src/features/DesktopCapturerSourcesService/index.ts`
- `references/Deskreen/src/renderer/src/features/PeerConnection/`
- `references/Deskreen/src/client-viewer/src/features/PeerConnection/`
- `references/Deskreen/src/renderer/src/utils/message.ts`

公开平台文档应以 Apple 的 ScreenCaptureKit、App Sandbox network entitlements、Local Network privacy 和 Bonjour 文档为准。`CGVirtualDisplay*` 没有公开 Apple 文档，因此本文对它的描述是由 DeskPad 源码推导出的 ABI 观察，而不是 Apple 保证的 API 合约。
