import AppKit
import Darwin
import Foundation
import UniformTypeIdentifiers

final class LocalSendManager: NSObject, URLSessionDelegate {
    static let shared = LocalSendManager()

    private let port = 53_317
    private let multicastAddress = "224.0.0.167"
    private let localSendBundleIdentifier = "org.localsend.localsendApp"
    private let fingerprintKey = "localSendFingerprint"
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 1.0
        configuration.timeoutIntervalForResource = 300.0
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    private var fingerprint: String {
        if let value = UserDefaults.standard.string(forKey: fingerprintKey) {
            return value
        }

        let value = UUID().uuidString
        UserDefaults.standard.set(value, forKey: fingerprintKey)
        return value
    }

    static func send(urls: [URL]) {
        shared.send(urls: urls)
    }

    func send(urls: [URL]) {
        let fileURLs = urls.filter { $0.isFileURL }
        guard !fileURLs.isEmpty else { return }

        Task {
            let devices = await discoverDevices()
            await MainActor.run {
                chooseDevice(from: devices, urls: fileURLs)
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    private func chooseDevice(from devices: [LocalSendDevice], urls: [URL]) {
        guard !devices.isEmpty else {
            showNoDeviceFallback(for: urls)
            return
        }

        if devices.count == 1, let device = devices.first {
            startUpload(urls: urls, to: device)
            return
        }

        let menu = NSMenu(title: "LocalSend")
        for device in devices {
            let item = NSMenuItem(
                title: "\(device.alias) (\(device.host))",
                action: #selector(sendFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = LocalSendSelection(device: device, urls: urls)
            menu.addItem(item)
        }

        popUp(menu: menu)
    }

    private func showNoDeviceFallback(for urls: [URL]) {
        _ = handOffToLocalSendSendScreen(urls: urls)
    }

    private func handOffToLocalSendSendScreen(urls: [URL]) -> Bool {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: localSendBundleIdentifier) else {
            return false
        }

        let runningApplications = NSRunningApplication.runningApplications(
            withBundleIdentifier: localSendBundleIdentifier
        )
        guard !runningApplications.isEmpty else {
            launchLocalSend(at: appURL, urls: urls)
            return true
        }

        for application in runningApplications {
            application.terminate()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            let stillRunning = NSRunningApplication.runningApplications(
                withBundleIdentifier: self?.localSendBundleIdentifier ?? ""
            )
            for application in stillRunning where !application.isTerminated {
                application.forceTerminate()
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                self?.launchLocalSend(at: appURL, urls: urls)
            }
        }
        return true
    }

    private func launchLocalSend(at appURL: URL, urls: [URL]) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.arguments = urls.map(\.path)
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }

    @objc private func sendFromMenu(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? LocalSendSelection else { return }
        startUpload(urls: selection.urls, to: selection.device)
    }

    private func popUp(menu: NSMenu, at location: NSPoint = NSEvent.mouseLocation) {
        if let window = NSApp.keyWindow ?? NSApp.mainWindow, let view = window.contentView {
            let pointInWindow = window.convertPoint(fromScreen: location)
            let pointInView = view.convert(pointInWindow, from: nil)
            menu.popUp(positioning: nil, at: pointInView, in: view)
        } else {
            menu.popUp(positioning: nil, at: .zero, in: nil)
        }
    }

    private func startUpload(urls: [URL], to device: LocalSendDevice) {
        Task {
            do {
                try await upload(urls: urls, to: device)
            } catch {
                await MainActor.run {
                    showAlert(
                        title: "LocalSend Transfer Failed",
                        message: error.localizedDescription
                    )
                }
            }
        }
    }

    private func discoverDevices() async -> [LocalSendDevice] {
        let localNetwork = localNetworkSnapshot()
        let multicastDevices = filterRemoteDevices(
            await multicastDiscoverDevices(localIPs: localNetwork.localIPs),
            localIPs: localNetwork.localIPs
        )
        if !multicastDevices.isEmpty {
            return sortDevices(multicastDevices)
        }

        return sortDevices(await scanLocalNetwork(
            hosts: localNetwork.hosts,
            localIPs: localNetwork.localIPs
        ))
    }

    private func filterRemoteDevices(
        _ devices: [LocalSendDevice],
        localIPs: Set<String>
    ) -> [LocalSendDevice] {
        var devicesByFingerprint: [String: LocalSendDevice] = [:]
        for device in devices {
            guard !localIPs.contains(device.host),
                  device.fingerprint != fingerprint
            else { continue }
            devicesByFingerprint[device.fingerprint] = device
        }
        return Array(devicesByFingerprint.values)
    }

    private func sortDevices(_ devices: [LocalSendDevice]) -> [LocalSendDevice] {
        devices
            .sorted { $0.alias.localizedCaseInsensitiveCompare($1.alias) == .orderedAscending }
    }

    private func multicastDiscoverDevices(localIPs: Set<String>) async -> [LocalSendDevice] {
        await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return [] }
            return self.multicastDiscoverDevicesSync(localIPs: localIPs)
        }.value
    }

    private func multicastDiscoverDevicesSync(localIPs: Set<String>) -> [LocalSendDevice] {
        let socketFileDescriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketFileDescriptor >= 0 else { return [] }
        defer { close(socketFileDescriptor) }

        var reuse: Int32 = 1
        setsockopt(socketFileDescriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
#if !os(Linux)
        setsockopt(socketFileDescriptor, SOL_SOCKET, SO_REUSEPORT, &reuse, socklen_t(MemoryLayout<Int32>.size))
#endif

        var receiveAddress = sockaddr_in()
        receiveAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        receiveAddress.sin_family = sa_family_t(AF_INET)
        receiveAddress.sin_port = UInt16(port).bigEndian
        receiveAddress.sin_addr.s_addr = INADDR_ANY

        let didBind = withUnsafePointer(to: &receiveAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(socketFileDescriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        } == 0

        guard didBind else { return [] }

        var membership = ip_mreq()
        membership.imr_multiaddr.s_addr = inet_addr(multicastAddress)
        membership.imr_interface.s_addr = INADDR_ANY
        setsockopt(socketFileDescriptor, IPPROTO_IP, IP_ADD_MEMBERSHIP, &membership, socklen_t(MemoryLayout<ip_mreq>.size))

        var timeout = timeval(tv_sec: 1, tv_usec: 500_000)
        setsockopt(socketFileDescriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        sendMulticastAnnouncement(socketFileDescriptor: socketFileDescriptor)

        var devicesByFingerprint: [String: LocalSendDevice] = [:]
        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline {
            var buffer = [UInt8](repeating: 0, count: 4096)
            var senderAddress = sockaddr_in()
            var senderLength = socklen_t(MemoryLayout<sockaddr_in>.size)

            let bytesRead = withUnsafeMutablePointer(to: &senderAddress) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    recvfrom(
                        socketFileDescriptor,
                        &buffer,
                        buffer.count,
                        0,
                        sockaddrPointer,
                        &senderLength
                    )
                }
            }

            guard bytesRead > 0 else { break }

            let data = Data(buffer.prefix(bytesRead))
            guard let info = try? JSONDecoder().decode(LocalSendInfo.self, from: data),
                  info.fingerprint != fingerprint,
                  let host = hostString(from: senderAddress),
                  !localIPs.contains(host)
            else { continue }

            let device = LocalSendDevice(
                info: info,
                host: host,
                port: info.port ?? port,
                scheme: info.protocol ?? "https"
            )
            devicesByFingerprint[device.fingerprint] = device
        }

        return Array(devicesByFingerprint.values)
    }

    private func sendMulticastAnnouncement(socketFileDescriptor: Int32) {
        guard let data = try? JSONEncoder().encode(localInfo(protocolName: "https", announce: true))
        else { return }

        var destination = sockaddr_in()
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = UInt16(port).bigEndian
        destination.sin_addr.s_addr = inet_addr(multicastAddress)

        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            withUnsafePointer(to: &destination) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    _ = sendto(
                        socketFileDescriptor,
                        baseAddress,
                        data.count,
                        0,
                        $0,
                        socklen_t(MemoryLayout<sockaddr_in>.size)
                    )
                }
            }
        }
    }

    private func hostString(from address: sockaddr_in) -> String? {
        var address = address
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &address.sin_addr, &buffer, socklen_t(buffer.count)) != nil
        else { return nil }
        return String(cString: buffer)
    }

    private func scanLocalNetwork(hosts: [String], localIPs: Set<String>) async -> [LocalSendDevice] {
        let remoteHosts = hosts.filter { !localIPs.contains($0) }
        guard !remoteHosts.isEmpty else { return [] }

        return await withTaskGroup(of: LocalSendDevice?.self) { group in
            for host in remoteHosts {
                group.addTask { [weak self] in
                    guard let self else { return nil }
                    if let httpsDevice = await self.register(host: host, scheme: "https") {
                        return httpsDevice
                    }
                    return await self.register(host: host, scheme: "http")
                }
            }

            var devicesByFingerprint: [String: LocalSendDevice] = [:]
            for await device in group {
                guard let device,
                      device.fingerprint != fingerprint,
                      !localIPs.contains(device.host)
                else { continue }
                devicesByFingerprint[device.fingerprint] = device
            }
            return Array(devicesByFingerprint.values)
                .sorted { $0.alias.localizedCaseInsensitiveCompare($1.alias) == .orderedAscending }
        }
    }

    private func register(host: String, scheme: String) async -> LocalSendDevice? {
        guard let url = URL(string: "\(scheme)://\(host):\(port)/api/localsend/v2/register")
        else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 0.8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(localInfo(protocolName: scheme))

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let info = try? JSONDecoder().decode(LocalSendInfo.self, from: data)
            else { return nil }

            return LocalSendDevice(info: info, host: host, port: port, scheme: scheme)
        } catch {
            return nil
        }
    }

    private func upload(urls: [URL], to device: LocalSendDevice) async throws {
        let files = try Dictionary(
            uniqueKeysWithValues: urls.enumerated().map { index, url in
                let id = UUID().uuidString
                return (id, try LocalSendFile(id: id, url: url, fallbackIndex: index))
            }
        )

        guard let prepareURL = URL(
            string: "\(device.scheme)://\(device.host):\(device.port)/api/localsend/v2/prepare-upload"
        ) else { throw LocalSendError.invalidURL }

        var prepareRequest = URLRequest(url: prepareURL)
        prepareRequest.httpMethod = "POST"
        prepareRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        prepareRequest.timeoutInterval = 90
        prepareRequest.httpBody = try JSONEncoder().encode(
            LocalSendPrepareUploadRequest(info: localInfo(protocolName: device.scheme), files: files)
        )

        let (data, response) = try await session.data(for: prepareRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LocalSendError.invalidResponse
        }
        guard httpResponse.statusCode != 204 else { return }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw LocalSendError.requestRejected(statusCode: httpResponse.statusCode)
        }

        let prepared = try JSONDecoder().decode(LocalSendPrepareUploadResponse.self, from: data)

        for (fileId, token) in prepared.files {
            guard let file = files[fileId],
                  let uploadURL = uploadURL(for: device, sessionId: prepared.sessionId, fileId: fileId, token: token)
            else { continue }

            var uploadRequest = URLRequest(url: uploadURL)
            uploadRequest.httpMethod = "POST"
            uploadRequest.setValue(file.fileType, forHTTPHeaderField: "Content-Type")
            uploadRequest.timeoutInterval = 300

            let (_, uploadResponse) = try await session.upload(for: uploadRequest, fromFile: file.url)
            guard let httpUploadResponse = uploadResponse as? HTTPURLResponse,
                  (200..<300).contains(httpUploadResponse.statusCode)
            else {
                throw LocalSendError.uploadFailed(fileName: file.fileName)
            }
        }
    }

    private func uploadURL(
        for device: LocalSendDevice,
        sessionId: String,
        fileId: String,
        token: String
    ) -> URL? {
        var components = URLComponents()
        components.scheme = device.scheme
        components.host = device.host
        components.port = device.port
        components.path = "/api/localsend/v2/upload"
        components.queryItems = [
            URLQueryItem(name: "sessionId", value: sessionId),
            URLQueryItem(name: "fileId", value: fileId),
            URLQueryItem(name: "token", value: token),
        ]
        return components.url
    }

    private func localInfo(protocolName: String, announce: Bool? = nil) -> LocalSendInfo {
        LocalSendInfo(
            alias: Host.current().localizedName ?? "NotchMore",
            version: "2.0",
            deviceModel: "Mac",
            deviceType: "desktop",
            fingerprint: fingerprint,
            port: port,
            protocol: protocolName,
            download: false,
            announce: announce
        )
    }

    private func localNetworkSnapshot() -> (hosts: [String], localIPs: Set<String>) {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let firstInterface = interfaces else {
            return ([], [])
        }
        defer { freeifaddrs(interfaces) }

        var hosts = Set<String>()
        var localIPs = Set<String>()
        var pointer: UnsafeMutablePointer<ifaddrs>? = firstInterface
        while pointer != nil {
            defer { pointer = pointer?.pointee.ifa_next }
            guard let interface = pointer?.pointee,
                  interface.ifa_addr.pointee.sa_family == UInt8(AF_INET),
                  let netmaskPointer = interface.ifa_netmask
            else { continue }

            let flags = Int32(interface.ifa_flags)
            guard (flags & IFF_LOOPBACK) == 0,
                  (flags & IFF_UP) != 0
            else { continue }

            let address = interface.ifa_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                $0.pointee.sin_addr.s_addr
            }
            let netmask = netmaskPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                $0.pointee.sin_addr.s_addr
            }
            localIPs.insert(ipString(fromNetworkOrderAddress: address))

            let network = UInt32(bigEndian: address) & UInt32(bigEndian: netmask)
            let broadcast = network | ~UInt32(bigEndian: netmask)
            guard broadcast > network, broadcast - network <= 4096 else { continue }

            for host in (network + 1)..<broadcast {
                hosts.insert(ipString(fromHostOrderAddress: host))
            }
        }

        return (Array(hosts), localIPs)
    }

    private func ipString(fromNetworkOrderAddress address: in_addr_t) -> String {
        ipString(fromHostOrderAddress: UInt32(bigEndian: address))
    }

    private func ipString(fromHostOrderAddress address: UInt32) -> String {
        [
            (address >> 24) & 0xff,
            (address >> 16) & 0xff,
            (address >> 8) & 0xff,
            address & 0xff,
        ]
        .map(String.init)
        .joined(separator: ".")
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

private final class LocalSendSelection {
    let device: LocalSendDevice
    let urls: [URL]

    init(device: LocalSendDevice, urls: [URL]) {
        self.device = device
        self.urls = urls
    }
}

private struct LocalSendDevice {
    let info: LocalSendInfo
    let host: String
    let port: Int
    let scheme: String

    var alias: String { info.alias }
    var fingerprint: String { info.fingerprint }
}

private struct LocalSendInfo: Codable {
    let alias: String
    let version: String
    let deviceModel: String?
    let deviceType: String?
    let fingerprint: String
    let port: Int?
    let `protocol`: String?
    let download: Bool?
    let announce: Bool?
}

private struct LocalSendFile: Encodable {
    let id: String
    let fileName: String
    let size: Int64
    let fileType: String
    let sha256: String?
    let preview: String?
    let metadata: LocalSendFileMetadata?

    var url: URL

    enum CodingKeys: String, CodingKey {
        case id
        case fileName
        case size
        case fileType
        case sha256
        case preview
        case metadata
    }

    init(id: String, url: URL, fallbackIndex: Int) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        self.id = id
        self.url = url
        self.fileName = url.lastPathComponent.isEmpty ? "File \(fallbackIndex + 1)" : url.lastPathComponent
        self.size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        self.fileType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"
        self.sha256 = nil
        self.preview = nil
        self.metadata = LocalSendFileMetadata(modified: attributes[.modificationDate] as? Date)
    }
}

private struct LocalSendFileMetadata: Codable {
    let modified: String?
    let accessed: String?

    init(modified: Date?) {
        self.modified = modified.map { ISO8601DateFormatter().string(from: $0) }
        self.accessed = nil
    }
}

private struct LocalSendPrepareUploadRequest: Encodable {
    let info: LocalSendInfo
    let files: [String: LocalSendFile]
}

private struct LocalSendPrepareUploadResponse: Codable {
    let sessionId: String
    let files: [String: String]
}

private enum LocalSendError: LocalizedError {
    case invalidURL
    case invalidResponse
    case requestRejected(statusCode: Int)
    case uploadFailed(fileName: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "NotchMore could not create a valid LocalSend request."
        case .invalidResponse:
            return "The LocalSend receiver returned an invalid response."
        case .requestRejected(let statusCode):
            return "The LocalSend receiver rejected the request. Status code: \(statusCode)."
        case .uploadFailed(let fileName):
            return "Could not upload \(fileName)."
        }
    }
}
