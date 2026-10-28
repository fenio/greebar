import Foundation
import ServiceManagement

@MainActor
final class ACController: ObservableObject {
    @Published private(set) var device: GreeDevice?
    @Published private(set) var state = ACState()
    @Published private(set) var discovered: [GreeDevice] = []
    @Published private(set) var isBusy = false
    @Published private(set) var isScanning = false
    @Published var lastError: String?

    private static let deviceDefaultsKey = "device"
    private var temperatureTask: Task<Void, Never>?
    private var pollTimer: Timer?

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.deviceDefaultsKey) {
            device = try? JSONDecoder().decode(GreeDevice.self, from: data)
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
        Task { await refresh() }
    }

    // MARK: Setup

    func scan(host: String? = nil) async {
        isScanning = true
        defer { isScanning = false }
        let target = host?.trimmingCharacters(in: .whitespaces)
        do {
            discovered = try await Task.detached {
                try GreeClient.discover(host: target?.isEmpty == false ? target : nil)
            }.value
            lastError = discovered.isEmpty ? "No air conditioners found" : nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func pair(_ candidate: GreeDevice) async {
        isBusy = true
        defer { isBusy = false }
        do {
            store(try await Task.detached { try GreeClient.bind(candidate) }.value)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            return
        }
        await refresh()
    }

    private func store(_ device: GreeDevice) {
        self.device = device
        UserDefaults.standard.set(try? JSONEncoder().encode(device), forKey: Self.deviceDefaultsKey)
    }

    /// The router may have given the unit a new IP; find it again by MAC. Returns true if it moved.
    private func relocate() async -> Bool {
        guard var moved = device else { return false }
        let mac = moved.mac
        guard let found = try? await Task.detached(operation: { try GreeClient.discover() }).value
            .first(where: { $0.mac == mac }), found.ip != moved.ip
        else { return false }
        moved.ip = found.ip
        store(moved)
        return true
    }

    /// Runs `operation` off the main thread; if the unit moved to a new IP, retries once at the new one.
    private func perform<T: Sendable>(_ operation: @escaping @Sendable (GreeDevice) throws -> T) async throws -> T {
        guard let device else { throw GreeError.bindFailed }
        do {
            return try await Task.detached { try operation(device) }.value
        } catch {
            guard await relocate(), let moved = self.device else { throw error }
            return try await Task.detached { try operation(moved) }.value
        }
    }

    func forgetDevice() {
        device = nil
        state = ACState()
        discovered = []
        UserDefaults.standard.removeObject(forKey: Self.deviceDefaultsKey)
    }

    // MARK: Status & control

    func refresh() async {
        guard device != nil, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            state.raw = try await perform { try GreeClient.status($0, columns: ACState.columns) }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Applies the change locally right away, then sends it to the unit.
    func send(_ params: [String: Int]) async {
        guard device != nil else { return }
        state.raw.merge(params) { $1 }
        do {
            try await perform { try GreeClient.set($0, params) }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            await refresh()
        }
    }

    func set(_ key: String, _ value: Int) {
        Task { await send([key: value]) }
    }

    func setPower(_ on: Bool) { set("Pow", on ? 1 : 0) }
    func setMode(_ mode: ACMode) { set("Mod", mode.rawValue) }
    func setFanSpeed(_ speed: FanSpeed) { set("WdSpd", speed.rawValue) }
    func toggle(_ key: String) { set(key, state.flag(key) ? 0 : 1) }

    /// Debounced so that clicking +/- several times sends a single command.
    func setTemperature(_ value: Int) {
        let clamped = min(max(value, ACState.temperatureRange.lowerBound), ACState.temperatureRange.upperBound)
        state.raw["SetTem"] = clamped
        temperatureTask?.cancel()
        temperatureTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await send(["SetTem": clamped, "TemUn": 0, "TemRec": 0])
        }
    }

    // MARK: Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                lastError = "Launch at login: \(error.localizedDescription)"
            }
            objectWillChange.send()
        }
    }

    // MARK: Menu bar label

    var menuBarSymbol: String {
        guard device != nil, state.power else { return "air.conditioner.horizontal" }
        return state.mode.symbol
    }

    var menuBarText: String? {
        guard device != nil, state.power, state.mode != .fan else { return nil }
        return "\(state.targetTemperature)°"
    }
}
