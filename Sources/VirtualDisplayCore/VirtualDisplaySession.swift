import AppKit
import CoreGraphics
import CVirtualDisplayPrivate

@MainActor
public final class VirtualDisplaySession {
    private var display: CGVirtualDisplay?
    public private(set) var wasTerminated = false

    public init() {}

    public func start(configuration: StreamConfiguration) async throws -> CGDirectDisplayID {
        guard display == nil else { return display!.displayID }
        try verifyPrivateAPI()
        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.setDispatchQueue(.main)
        descriptor.name = configuration.name
        descriptor.maxPixelsWide = UInt32(configuration.width)
        descriptor.maxPixelsHigh = UInt32(configuration.height)
        descriptor.sizeInMillimeters = CGSize(width: 600, height: 340)
        descriptor.vendorID = 0x3456; descriptor.productID = 0x1234; descriptor.serialNum = 1
        descriptor.terminationHandler = { [weak self] _, _ in
            Task { @MainActor in self?.wasTerminated = true; self?.display = nil }
        }
        let created = CGVirtualDisplay(descriptor: descriptor)
        guard created.displayID != 0 else { throw StreamError.displayCreationFailed }
        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = configuration.hiDPI ? 1 : 0
        settings.modes = [CGVirtualDisplayMode(width: UInt(configuration.width), height: UInt(configuration.height), refreshRate: configuration.refreshRate)]
        guard created.apply(settings) else { throw StreamError.displaySettingsFailed }
        display = created
        let id = created.displayID
        let deadline = ContinuousClock.now + .seconds(5)
        while NSScreen.screens.allSatisfy({
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value != id
        }) {
            if ContinuousClock.now >= deadline { stop(); throw StreamError.displayRegistrationTimedOut }
            try await Task.sleep(for: .milliseconds(100))
        }
        return id
    }

    public func stop() { display = nil }

    private func verifyPrivateAPI() throws {
        let names = ["CGVirtualDisplayDescriptor", "CGVirtualDisplay", "CGVirtualDisplaySettings", "CGVirtualDisplayMode"]
        for name in names where NSClassFromString(name) == nil { throw StreamError.privateAPIUnavailable(name) }
        guard CGVirtualDisplay.instancesRespond(to: NSSelectorFromString("initWithDescriptor:")),
              CGVirtualDisplay.instancesRespond(to: NSSelectorFromString("applySettings:")),
              CGVirtualDisplayDescriptor.instancesRespond(to: NSSelectorFromString("setDispatchQueue:")),
              CGVirtualDisplayMode.instancesRespond(to: NSSelectorFromString("initWithWidth:height:refreshRate:")) else {
            throw StreamError.privateAPIUnavailable("required selector")
        }
    }
}
