import Testing
@testable import VirtualDisplayCore

@Test func defaults() throws {
    guard case .run(let value) = try CLIParser.parse([]) else { Issue.record("expected run"); return }
    #expect(value == StreamConfiguration())
}

@Test func parsesAllOptions() throws {
    let arguments = ["--name", "Test", "--width", "1280", "--height", "720", "--refresh-rate", "75",
                     "--hidpi", "--fps", "25", "--bitrate", "1000000", "--port", "9000", "--hide-cursor"]
    guard case .run(let value) = try CLIParser.parse(arguments) else { Issue.record("expected run"); return }
    #expect(value.name == "Test"); #expect(value.width == 1280); #expect(value.height == 720)
    #expect(value.refreshRate == 75); #expect(value.hiDPI); #expect(value.fps == 25)
    #expect(value.bitrate == 1_000_000); #expect(value.port == 9000); #expect(!value.showCursor)
}

@Test(arguments: [["--width", "1279"], ["--height", "0"], ["--port", "65536"], ["--fps"]])
func rejectsInvalid(_ arguments: [String]) { #expect(throws: Error.self) { try CLIParser.parse(arguments) } }

@Test func help() throws { #expect(try CLIParser.parse(["--help"]) == .help) }
