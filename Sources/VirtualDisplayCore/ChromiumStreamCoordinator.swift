import CoreGraphics
import Foundation

@MainActor
public final class ChromiumStreamCoordinator {
    private let display = VirtualDisplaySession()
    private var process: Process?

    public init() {}

    public func start(_ configuration: StreamConfiguration) async throws -> HealthSnapshot {
        let displayID = try await display.start(configuration: configuration)
        let width = Int(CGDisplayPixelsWide(displayID)); let height = Int(CGDisplayPixelsHigh(displayID))
        guard width > 0, height > 0 else { display.stop(); throw StreamError.captureCreationFailed }
        do {
            let directory = URL(fileURLWithPath: configuration.chromiumDirectory, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).standardizedFileURL
            let manifest = directory.appendingPathComponent("package.json")
            guard FileManager.default.fileExists(atPath: manifest.path) else { throw StreamError.chromiumHelper("package.json not found at \(manifest.path)") }
            let executable = directory.appendingPathComponent("node_modules/electron/dist/Electron.app/Contents/MacOS/Electron")
            guard FileManager.default.isExecutableFile(atPath: executable.path) else {
                throw StreamError.chromiumHelper("Electron is not installed at \(executable.path); run npm install and npm run build in \(directory.path)")
            }
            let viewerBundle = directory.appendingPathComponent("dist/viewer.js")
            guard FileManager.default.fileExists(atPath: viewerBundle.path) else {
                throw StreamError.chromiumHelper("Chromium bundles are missing; run npm run build in \(directory.path)")
            }
            let child = Process()
            child.executableURL = executable
            child.arguments = [directory.path, "--display-id", String(displayID), "--port", String(configuration.port),
                               "--width", String(width), "--height", String(height), "--fps", String(configuration.fps)]
            child.standardOutput = FileHandle.standardOutput; child.standardError = FileHandle.standardError
            try child.run(); process = child
            try await Task.sleep(for: .milliseconds(750))
            guard child.isRunning else { let status = child.terminationStatus; process = nil; throw StreamError.chromiumHelper("helper exited during startup with status \(status)") }
            return .init(displayID: displayID, width: width, height: height, fps: configuration.fps, viewerConnected: false)
        } catch { stop(); throw error }
    }

    public func stop() {
        if let process, process.isRunning { process.terminate() }
        process = nil; display.stop()
    }
}
