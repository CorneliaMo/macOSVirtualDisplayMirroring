import Darwin
import Foundation
import VirtualDisplayCore

@main
struct VirtualDisplayStreamCommand {
    @MainActor
    static func main() async {
        do {
            switch try CLIParser.parse(Array(CommandLine.arguments.dropFirst())) {
            case .help: print(CLIParser.usage)
            case .run(let configuration): try await run(configuration)
            }
        } catch {
            fputs("Error: \(error.localizedDescription)\n\n\(CLIParser.usage)\n", stderr)
            exit(2)
        }
    }

    @MainActor
    private static func run(_ configuration: StreamConfiguration) async throws {
        let coordinator = StreamCoordinator()
        let health = try await coordinator.start(configuration)
        print("Virtual display \(health.displayID) is streaming \(health.width)x\(health.height) @ \(health.fps) fps.")
        let addresses = localIPv4Addresses()
        for address in addresses {
            let url = "http://\(address):\(configuration.port)/"
            print("Viewer: \(url)")
        }
        if addresses.isEmpty { print("Viewer: http://<Mac-IP>:\(configuration.port)/") }
        print("Health: http://127.0.0.1:\(configuration.port)/healthz")
        print("Press Ctrl-C to stop.")

        signal(SIGINT, SIG_IGN); signal(SIGTERM, SIG_IGN)
        let intSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let gate = SignalGate(continuation)
            let finish = { @Sendable in gate.resume() }
            intSource.setEventHandler(handler: finish); termSource.setEventHandler(handler: finish)
            intSource.resume(); termSource.resume()
        }
        intSource.cancel(); termSource.cancel(); await coordinator.stop()
    }

    private static func localIPv4Addresses() -> [String] {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [] }
        defer { freeifaddrs(pointer) }
        var result: [String] = []; var current: UnsafeMutablePointer<ifaddrs>? = first
        while let item = current?.pointee {
            defer { current = item.ifa_next }
            guard let addressPointer = item.ifa_addr,
                  addressPointer.pointee.sa_family == UInt8(AF_INET),
                  (item.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }
            var address = addressPointer.pointee
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(&address, socklen_t(item.ifa_addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                result.append(String(cString: host))
            }
        }
        return Array(Set(result)).sorted()
    }
}

private final class SignalGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    init(_ continuation: CheckedContinuation<Void, Never>) { self.continuation = continuation }
    func resume() {
        lock.lock(); defer { lock.unlock() }
        continuation?.resume(); continuation = nil
    }
}
