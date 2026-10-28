import Darwin
import Foundation

/// Minimal blocking UDP socket (BSD sockets), needed for broadcast discovery.
final class UDPSocket {
    private let fd: Int32

    init() throws {
        fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw GreeError.socket(errno) }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))
    }

    deinit { close(fd) }

    func send(_ data: Data, to host: String, port: UInt16) throws {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else { throw GreeError.badAddress(host) }
        let sent = data.withUnsafeBytes { buf in
            withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, buf.baseAddress, buf.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent == data.count else { throw GreeError.socket(errno) }
    }

    /// Returns nil on timeout.
    func receive(timeout: TimeInterval) throws -> (data: Data, host: String)? {
        var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let ready = poll(&pfd, 1, Int32(max(0, timeout * 1000)))
        if ready == 0 { return nil }
        guard ready > 0 else { throw GreeError.socket(errno) }

        var buffer = [UInt8](repeating: 0, count: 65536)
        var addr = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let count = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                recvfrom(fd, &buffer, buffer.count, 0, $0, &length)
            }
        }
        guard count >= 0 else { throw GreeError.socket(errno) }

        var ip = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &addr.sin_addr, &ip, socklen_t(INET_ADDRSTRLEN))
        return (Data(buffer[0..<count]), String(cString: ip))
    }

    /// Address and netmask (host byte order) of each active non-loopback IPv4 interface.
    static func localSubnets() -> [(address: UInt32, mask: UInt32)] {
        var result: [(address: UInt32, mask: UInt32)] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return result }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  let addr = ptr.pointee.ifa_addr, addr.pointee.sa_family == sa_family_t(AF_INET),
                  let mask = ptr.pointee.ifa_netmask
            else { continue }
            result.append((ipv4(addr), ipv4(mask)))
        }
        return result
    }

    private static func ipv4(_ sa: UnsafeMutablePointer<sockaddr>) -> UInt32 {
        sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
    }

    static func string(_ ip: UInt32) -> String {
        "\(ip >> 24).\(ip >> 16 & 0xff).\(ip >> 8 & 0xff).\(ip & 0xff)"
    }
}
