//
// Copyright 2024 Signal Messenger, LLC.
// SPDX-License-Identifier: AGPL-3.0-only
//

// These testing endpoints aren't generated in device builds, to save on code size.
#if !os(iOS) || targetEnvironment(simulator)

import Foundation
@testable import LibSignalClient
import SignalFfi
import Testing

#if canImport(Glibc)
import Glibc
#endif

let userAgent: String = "test"

final class NetTests {
    @Test
    func cdsiLookupResultConversion() async throws {
        let ACI_UUID = "9d0652a3-dcc3-4d11-975f-74d61598733f"
        let PNI_UUID = "796abedb-ca4e-4f18-8803-1fde5b921f9f"

        let aci = Aci(fromUUID: UUID(uuidString: ACI_UUID)!)
        let pni = Pni(fromUUID: UUID(uuidString: PNI_UUID)!)

        let asyncContext = TokioAsyncContext()

        let output: SignalFfiCdsiLookupResponse = try await asyncContext.invokeAsyncFunction { promise, asyncContext in
            signal_testing_cdsi_lookup_response_convert(promise, asyncContext.const())
        }
        #expect(output.debug_permits_used == 123)

        let entryList = LookupResponseEntryList(owned: output.entries)
        let expected = [
            SignalFfiCdsiLookupResponseEntry(
                e164: 18_005_551_011,
                aci,
                pni
            ),
            SignalFfiCdsiLookupResponseEntry(
                e164: 18_005_551_012,
                nil,
                pni
            ),
        ]

        #expect(expected == Array(entryList))
    }

    @Test
    func cdsiLookupErrorConversion() async throws {
        let failWithError = {
            try checkError(signal_testing_cdsi_lookup_error_convert($0))
            Issue.record("should have failed")
        }
        do {
            try failWithError("Protocol")
        } catch SignalError.networkProtocolError(let message) {
            #expect(
                message
                    == "Protocol error: protocol error after establishing a connection: failed to decode frame as protobuf"
            )
        }
        do {
            try failWithError("CdsiProtocol")
        } catch SignalError.networkProtocolError(let message) {
            #expect(message == "Protocol error: CDS protocol: no token found in response")
        }
        do {
            try failWithError("AttestationDataError")
        } catch SignalError.invalidAttestationData(let message) {
            #expect(message == "SGX operation failed: attestation data invalid: fake reason")
        }
        do {
            try failWithError("RetryAfter42Seconds")
        } catch SignalError.rateLimitedError(retryAfter: 42, let message) {
            #expect(message == "Rate limited; try again after 42s")
        }
        do {
            try failWithError("InvalidToken")
        } catch SignalError.cdsiInvalidToken(let message) {
            #expect(message == "CDSI request token was invalid")
        }
        do {
            try failWithError("InvalidArgument")
        } catch SignalError.invalidArgument(let message) {
            #expect(message == "invalid argument: request was invalid: fake reason")
        }
        do {
            try failWithError("TcpConnectFailed")
        } catch SignalError.ioError(let message) {
            #expect(message == "IO error: Failed to establish TCP connection to any of the IPs")
        }
        do {
            try failWithError("WebSocketIdleTooLong")
        } catch SignalError.webSocketError(let message) {
            #expect(message == "WebSocket error: channel was idle for too long")
        }
        do {
            try failWithError("AllConnectionAttemptsFailed")
        } catch SignalError.connectionFailed(let message) {
            #expect(message == "No connection attempts succeeded before timeout")
        }
        do {
            try failWithError("ServerCrashed")
        } catch SignalError.networkProtocolError(let message) {
            #expect(message == "Protocol error: server error: crashed")
        }
    }

    // Compile-only, no @Test
    func testCdsiLookupCompilation() async throws {
        let auth = Auth(username: "username", password: "password")
        let request = try CdsiLookupRequest(
            e164s: [],
            prevE164s: [],
            acisAndAccessKeys: [],
            token: nil
        )
        let net = Net(env: .staging, userAgent: userAgent, buildVariant: .production)

        let lookup = try await net.cdsiLookup(auth: auth, request: request)
        let response = try await lookup.complete()
        for entry in response.entries {
            _ = entry.aci
            _ = entry.pni
            _ = entry.e164
        }
    }

    @Test
    func networkChangeEvent() throws {
        // There's no feedback from this, we're just making sure it doesn't normally crash or throw.
        let net = Net(env: .staging, userAgent: userAgent, buildVariant: .production)
        try net.networkDidChange()
    }
}

// MARK: - SWARM additions (see docs/SWARM-CHANGES.md)
//
// Nothing below contacts any server: the chat connection attempts go to a proxy on 127.0.0.1 that
// records which host they asked for and refuses every tunnel.

final class SwarmNetTests {
    @Test
    func swarmEnvironmentsAreNumberedAsTheRustBridgeExpects() {
        #expect(Net.Environment.staging.rawValue == 0)
        #expect(Net.Environment.production.rawValue == 1)
        #expect(Net.Environment.swarm.rawValue == 2)
        #expect(Net.Environment.swarmStaging.rawValue == 3)
    }

    @Test
    func swarmEnvironmentsIgnoreCensorshipCircumvention() {
        for env in [Net.Environment.swarm, Net.Environment.swarmStaging] {
            let net = Net(env: env, userAgent: userAgent, buildVariant: .production)
            // SWARM operates no reflectors: enabling circumvention is a logged no-op, not a crash, and it must
            // not route anything through somebody else's front.
            net.setCensorshipCircumventionEnabled(true)
            #expect(Self.isUsingProxy(net) == 0)
            net.setCensorshipCircumventionEnabled(false)
            #expect(Self.isUsingProxy(net) == 0)
        }
    }

    @Test
    func swarmEnvironmentDialsOnlyTheSwarmChatHost() async throws {
        try await Self.checkDialsOnly(env: .swarm, host: "chat.swarm.green")
    }

    @Test
    func swarmStagingEnvironmentDialsOnlyTheSwarmStagingChatHost() async throws {
        try await Self.checkDialsOnly(env: .swarmStaging, host: "staging.chat.swarm.green")
    }

    private static func isUsingProxy(_ net: Net) -> Int32 {
        net.connectionManager.withNativeHandle { handle in
            failOnError {
                try invokeFnReturningInteger {
                    signal_testing_connection_manager_is_using_proxy($0, handle.const())
                }
            }
        }
    }

    private static func checkDialsOnly(env: Net.Environment, host: String) async throws {
        let proxy = try RefusingConnectProxy()
        defer { proxy.stop() }

        let net = Net(env: env, userAgent: userAgent, buildVariant: .production)
        try net.setProxy(scheme: "http", host: "127.0.0.1", port: proxy.port)
        #expect(Self.isUsingProxy(net) == 1)

        // The proxy refuses the tunnel, so the attempt fails without leaving this machine.
        do {
            _ = try await net.connectUnauthenticatedChat()
            Issue.record("connecting through a refusing proxy should have failed")
        } catch {
            // Expected.
        }

        let requestLines = proxy.requestLines
        #expect(!requestLines.isEmpty, "the chat connection never reached the proxy")
        for requestLine in requestLines {
            #expect(requestLine == "CONNECT \(host):443 HTTP/1.1")
            #expect(!requestLine.contains("signal"))
        }
    }
}

/// Stands in for an HTTP CONNECT proxy on 127.0.0.1: records the request line of every tunnel it is asked for,
/// and refuses it.
private final class RefusingConnectProxy: @unchecked Sendable {
    enum SetupError: Error {
        case socketCall(String, Int32)
    }

    let port: UInt16
    private let listener: Int32
    private let lock = NSLock()
    private var lines: [String] = []

    var requestLines: [String] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.lines
    }

    init() throws {
        #if canImport(Glibc)
        let listener = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #else
        let listener = socket(AF_INET, SOCK_STREAM, 0)
        #endif
        guard listener >= 0 else {
            throw SetupError.socketCall("socket", errno)
        }

        var address = sockaddr_in()
        #if canImport(Darwin)
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: UInt32(0x7F00_0001).bigEndian)  // 127.0.0.1
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)

        let bound = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, length) }
        }
        guard bound == 0, listen(listener, 16) == 0 else {
            let error = errno
            close(listener)
            throw SetupError.socketCall("bind/listen", error)
        }
        let named = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(listener, $0, &length) }
        }
        guard named == 0 else {
            let error = errno
            close(listener)
            throw SetupError.socketCall("getsockname", error)
        }

        self.listener = listener
        self.port = UInt16(bigEndian: address.sin_port)
        let acceptor = Thread { [self] in self.acceptLoop() }
        acceptor.start()
    }

    /// Stops accepting. On Linux this also wakes the accepting thread; elsewhere it may stay parked in `accept`
    /// until the test process exits, which is harmless.
    func stop() {
        shutdown(self.listener, Int32(SHUT_RDWR))
        close(self.listener)
    }

    private func acceptLoop() {
        while true {
            let client = accept(self.listener, nil, nil)
            if client < 0 {
                return
            }
            self.refuse(client)
            close(client)
        }
    }

    private func refuse(_ client: Int32) {
        var received: [UInt8] = []
        let capacity = 1024
        var buffer = [UInt8](repeating: 0, count: capacity)
        while !String(decoding: received, as: UTF8.self).contains("\r\n\r\n") {
            let count = read(client, &buffer, capacity)
            if count <= 0 {
                break
            }
            received.append(contentsOf: buffer[0..<count])
        }
        let head = String(decoding: received, as: UTF8.self)
        if let requestLine = head.components(separatedBy: "\r\n").first, !requestLine.isEmpty {
            self.lock.lock()
            self.lines.append(requestLine)
            self.lock.unlock()
        }
        let refusal = Array("HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n".utf8)
        _ = refusal.withUnsafeBytes { write(client, $0.baseAddress, $0.count) }
    }
}

#endif
