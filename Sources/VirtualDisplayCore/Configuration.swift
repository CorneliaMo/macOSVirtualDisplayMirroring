import Foundation

public struct StreamConfiguration: Sendable, Equatable {
    public var name = "Network Virtual Display"
    public var width = 1920
    public var height = 1080
    public var refreshRate = 60.0
    public var hiDPI = false
    public var fps = 30
    public var bitrate = 4_000_000
    public var port: UInt16 = 8080
    public var showCursor = true

    public init() {}
}

public struct HealthSnapshot: Sendable {
    public var displayID: UInt32
    public var width: Int
    public var height: Int
    public var fps: Int
    public var viewerConnected: Bool

    public init(displayID: UInt32, width: Int, height: Int, fps: Int, viewerConnected: Bool) {
        self.displayID = displayID; self.width = width; self.height = height
        self.fps = fps; self.viewerConnected = viewerConnected
    }
}

public enum CLIParseResult: Equatable { case run(StreamConfiguration); case help }

public enum CLIError: Error, LocalizedError, Equatable {
    case unknownOption(String), missingValue(String), invalidValue(String, String)
    public var errorDescription: String? {
        switch self {
        case .unknownOption(let value): "Unknown option: \(value). Use --help for usage."
        case .missingValue(let option): "Missing value for \(option)."
        case .invalidValue(let option, let value): "Invalid value for \(option): \(value)."
        }
    }
}

public enum CLIParser {
    public static let usage = """
    Usage: virtual-display-stream [options]
      --name <text>          Display name (default: Network Virtual Display)
      --width <pixels>       Even display width (default: 1920)
      --height <pixels>      Even display height (default: 1080)
      --refresh-rate <hz>    Refresh rate (default: 60)
      --hidpi                Enable HiDPI mode
      --fps <frames>         Encoder frame rate (default: 30)
      --bitrate <bits/sec>   Encoder bitrate (default: 4000000)
      --port <1-65535>       HTTP port (default: 8080)
      --hide-cursor          Do not capture the cursor
      --help                 Show this help
    """

    public static func parse(_ arguments: [String]) throws -> CLIParseResult {
        var value = StreamConfiguration(); var index = 0
        func next(_ option: String) throws -> String {
            guard index + 1 < arguments.count else { throw CLIError.missingValue(option) }
            return arguments[index + 1]
        }
        while index < arguments.count {
            let option = arguments[index]
            switch option {
            case "--help", "-h": return .help
            case "--hidpi": value.hiDPI = true
            case "--hide-cursor": value.showCursor = false
            case "--name": value.name = try next(option); index += 1
            case "--width": value.width = try positiveInt(next(option), option); index += 1
            case "--height": value.height = try positiveInt(next(option), option); index += 1
            case "--fps": value.fps = try positiveInt(next(option), option); index += 1
            case "--bitrate": value.bitrate = try positiveInt(next(option), option); index += 1
            case "--refresh-rate":
                let raw = try next(option); guard let parsed = Double(raw), parsed.isFinite, parsed > 0 else { throw CLIError.invalidValue(option, raw) }
                value.refreshRate = parsed; index += 1
            case "--port":
                let raw = try next(option); guard let parsed = UInt16(raw), parsed > 0 else { throw CLIError.invalidValue(option, raw) }
                value.port = parsed; index += 1
            default: throw CLIError.unknownOption(option)
            }
            index += 1
        }
        guard value.width <= Int(UInt32.max) else { throw CLIError.invalidValue("--width", String(value.width)) }
        guard value.height <= Int(UInt32.max) else { throw CLIError.invalidValue("--height", String(value.height)) }
        guard value.width.isMultiple(of: 2) else { throw CLIError.invalidValue("--width", String(value.width)) }
        guard value.height.isMultiple(of: 2) else { throw CLIError.invalidValue("--height", String(value.height)) }
        guard !value.name.isEmpty else { throw CLIError.invalidValue("--name", value.name) }
        return .run(value)
    }

    private static func positiveInt(_ raw: String, _ option: String) throws -> Int {
        guard let value = Int(raw), value > 0 else { throw CLIError.invalidValue(option, raw) }
        return value
    }
}
