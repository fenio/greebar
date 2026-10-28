import Foundation

enum GreeError: LocalizedError {
    case socket(Int32)
    case badAddress(String)
    case timeout
    case crypto
    case badResponse(String)
    case bindFailed

    var errorDescription: String? {
        switch self {
        case .socket(let code) where code == EPERM:
            "Network blocked. Allow GreeBar in System Settings › Privacy & Security › Local Network."
        case .socket(let code) where code == EHOSTUNREACH || code == EHOSTDOWN:
            "Can't reach the air conditioner. Is it powered and on Wi-Fi? If this persists, check Local Network access."
        case .socket(let code): "Network error: \(String(cString: strerror(code)))"
        case .badAddress(let host): "Invalid IP address: \(host)"
        case .timeout: "The air conditioner did not respond"
        case .crypto: "Could not decrypt the device's response"
        case .badResponse(let detail): "Unexpected response: \(detail)"
        case .bindFailed: "Could not pair with the air conditioner"
        }
    }
}

struct GreeDevice: Codable, Hashable, Identifiable, Sendable {
    var id: String { mac }
    let mac: String
    var name: String
    var ip: String
    var version: String?
    var key: String?
    var usesGCM = false
}

/// Talks the Gree local UDP protocol (port 7000). All calls block; run them off the main thread.
enum GreeClient {
    static let port: UInt16 = 7000

    // MARK: Discovery & pairing

    /// Broadcasts a scan, or sends it straight to `host` if given.
    static func discover(host: String? = nil, timeout: TimeInterval = 3) throws -> [GreeDevice] {
        let socket = try UDPSocket()
        let scan = Data(#"{"t":"scan"}"#.utf8)
        var targets = host.map { [$0] } ?? ["255.255.255.255"]
        if host == nil {
            for (address, mask) in UDPSocket.localSubnets() {
                let network = address & mask, size = ~mask
                targets.append(UDPSocket.string(network | size))
                // Units often ignore broadcasts, so also ask every host on small subnets directly.
                if size >= 2 && size <= 1024 {
                    targets += (1..<size).map { UDPSocket.string(network | $0) }
                }
            }
        }
        var sendError: Error?
        var sentAny = false
        for target in targets {
            do {
                try socket.send(scan, to: target, port: port)
                sentAny = true
            } catch {
                sendError = error
            }
        }
        if !sentAny, let sendError { throw sendError }

        var found: [String: GreeDevice] = [:]
        let deadline = Date().addingTimeInterval(timeout)
        while case let remaining = deadline.timeIntervalSinceNow, remaining > 0 {
            guard let (data, ip) = try socket.receive(timeout: remaining) else { break }
            guard let (outer, inner) = try? decode(data, key: nil), inner["t"] as? String == "dev",
                  let mac = (inner["mac"] ?? inner["cid"] ?? outer["cid"]) as? String
            else { continue }
            let name = (inner["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? mac
            found[mac] = GreeDevice(mac: mac, name: name, ip: ip, version: inner["ver"] as? String)
        }
        return found.values.sorted { $0.name < $1.name }
    }

    /// Obtains the per-device key. Tries the legacy ECB cipher first, then GCM.
    static func bind(_ device: GreeDevice) throws -> GreeDevice {
        for gcm in [false, true] {
            let pack: [String: Any] = gcm
                ? ["cid": device.mac, "mac": device.mac, "t": "bind", "uid": 0]
                : ["mac": device.mac, "t": "bind", "uid": 0]
            let key = gcm ? GreeCrypto.genericGCMKey : GreeCrypto.genericECBKey
            guard let response = try? request(device.ip, pack: pack, mac: device.mac, key: key, gcm: gcm, i: 1, decodeKey: nil),
                  response["t"] as? String == "bindok", let deviceKey = response["key"] as? String
            else { continue }
            var bound = device
            bound.key = deviceKey
            bound.usesGCM = gcm
            return bound
        }
        throw GreeError.bindFailed
    }

    // MARK: Status & commands

    static func status(_ device: GreeDevice, columns: [String]) throws -> [String: Int] {
        let response = try request(device, pack: ["cols": columns, "mac": device.mac, "t": "status"])
        guard let cols = response["cols"] as? [String], let values = response["dat"] as? [Any] else {
            throw GreeError.badResponse("missing status data")
        }
        var result: [String: Int] = [:]
        for (col, value) in zip(cols, values) {
            if let number = value as? NSNumber { result[col] = number.intValue }
        }
        return result
    }

    static func set(_ device: GreeDevice, _ params: [String: Int]) throws {
        let keys = Array(params.keys)
        let response = try request(device, pack: ["opt": keys, "p": keys.map { params[$0]! }, "t": "cmd"])
        if let code = response["r"] as? Int, code != 200 {
            throw GreeError.badResponse("device returned code \(code)")
        }
    }

    // MARK: Transport

    private static func request(_ device: GreeDevice, pack: [String: Any]) throws -> [String: Any] {
        guard let key = device.key else { throw GreeError.bindFailed }
        return try request(device.ip, pack: pack, mac: device.mac, key: key, gcm: device.usesGCM, i: 0, decodeKey: key)
    }

    private static func request(_ ip: String, pack: [String: Any], mac: String, key: String,
                                gcm: Bool, i: Int, decodeKey: String?, attempts: Int = 2) throws -> [String: Any] {
        let plain = try JSONSerialization.data(withJSONObject: pack)
        var message: [String: Any] = ["cid": "app", "i": i, "t": "pack", "uid": 0, "tcid": mac]
        if gcm {
            let (encrypted, tag) = try GreeCrypto.gcmEncrypt(plain, key: key)
            message["pack"] = encrypted
            message["tag"] = tag
        } else {
            message["pack"] = try GreeCrypto.ecbEncrypt(plain, key: key)
        }
        let payload = try JSONSerialization.data(withJSONObject: message)

        let socket = try UDPSocket()
        for _ in 0..<attempts {
            try socket.send(payload, to: ip, port: port)
            if let (data, _) = try socket.receive(timeout: 2) {
                return try decode(data, key: decodeKey).inner
            }
        }
        throw GreeError.timeout
    }

    /// Decodes an outer message and decrypts its pack. With `key == nil` the generic key is used.
    private static func decode(_ data: Data, key: String?) throws -> (outer: [String: Any], inner: [String: Any]) {
        guard let outer = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pack = outer["pack"] as? String
        else { throw GreeError.badResponse("not a pack message") }

        let plain: Data
        if let tag = outer["tag"] as? String {
            plain = try GreeCrypto.gcmDecrypt(pack: pack, tag: tag, key: key ?? GreeCrypto.genericGCMKey)
        } else {
            plain = try GreeCrypto.ecbDecrypt(pack, key: key ?? GreeCrypto.genericECBKey)
        }
        guard let inner = try JSONSerialization.jsonObject(with: plain) as? [String: Any] else {
            throw GreeError.badResponse("invalid pack contents")
        }
        return (outer, inner)
    }
}
