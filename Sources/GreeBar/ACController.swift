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
            let bound = try await Task.detached { try GreeClient.bind(candidate) }.value
            device = bound
            UserDefaults.standard.set(try JSONEncoder().encode(bound), forKey: Self.deviceDefaultsKey)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            return
        }
        await refresh()
    }

    func forgetDevice() {
        device = nil
        state = ACState()
        discovered = []
        UserDefaults.standard.removeObject(forKey: Self.deviceDefaultsKey)
    }

    // MARK: Status & control

    func refresh() async {
        guard let device, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let values = try await Task.detached {
                try GreeClient.status(device, columns: ACState.columns)
            }.value
            state.raw = values
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Applies the change locally right away, then sends it to the unit.
    func send(_ params: [String: Int]) async {
        guard let device else { return }
        state.raw.merge(params) { $1 }
        do {
            try await Task.detached { try GreeClient.set(device, params) }.value
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
