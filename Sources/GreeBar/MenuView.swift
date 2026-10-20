import SwiftUI

struct MenuView: View {
    @EnvironmentObject private var ac: ACController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let device = ac.device {
                ControlView(device: device)
            } else {
                SetupView()
            }

            if let error = ac.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()
            FooterView()
        }
        .padding(14)
        .frame(width: 300)
        .task { await ac.refresh() }
    }
}

// MARK: - Controls

private struct ControlView: View {
    @EnvironmentObject private var ac: ACController
    let device: GreeDevice

    var body: some View {
        let state = ac.state

        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name).font(.headline)
                if let room = state.roomTemperature {
                    Text("Room \(room)°C").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if ac.isBusy {
                ProgressView().controlSize(.small)
            } else {
                Button { Task { await ac.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Refresh")
            }
            Toggle("", isOn: Binding(get: { state.power }, set: { ac.setPower($0) }))
                .toggleStyle(.switch)
                .labelsHidden()
        }

        VStack(spacing: 14) {
            HStack(spacing: 24) {
                Button { ac.setTemperature(state.targetTemperature - 1) } label: {
                    Image(systemName: "minus.circle").font(.title2)
                }
                .disabled(state.targetTemperature <= ACState.temperatureRange.lowerBound)

                Text("\(state.targetTemperature)°")
                    .font(.system(size: 40, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .frame(minWidth: 70)

                Button { ac.setTemperature(state.targetTemperature + 1) } label: {
                    Image(systemName: "plus.circle").font(.title2)
                }
                .disabled(state.targetTemperature >= ACState.temperatureRange.upperBound)
            }
            .buttonStyle(.borderless)
            .frame(maxWidth: .infinity)

            LabeledPicker(title: "Mode") {
                Picker("Mode", selection: Binding(get: { state.mode }, set: { ac.setMode($0) })) {
                    ForEach(ACMode.allCases) { mode in
                        Image(systemName: mode.symbol).help(mode.title).tag(mode)
                    }
                }
            } detail: { state.mode.title }

            LabeledPicker(title: "Fan") {
                Picker("Fan", selection: Binding(get: { state.fanSpeed }, set: { ac.setFanSpeed($0) })) {
                    ForEach(FanSpeed.allCases) { Text($0.title).tag($0) }
                }
            } detail: { nil }

            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    FeatureToggle(title: "Turbo", symbol: "bolt", key: "Tur")
                    FeatureToggle(title: "Quiet", symbol: "moon.zzz", key: "Quiet")
                    FeatureToggle(title: "Sleep", symbol: "bed.double", key: "SwhSlp")
                }
                GridRow {
                    FeatureToggle(title: "Swing", symbol: "arrow.up.and.down", key: "SwUpDn")
                    FeatureToggle(title: "Light", symbol: "lightbulb", key: "Lig")
                    FeatureToggle(title: "Health", symbol: "leaf", key: "Health")
                }
            }
        }
        .opacity(state.power ? 1 : 0.5)
    }
}

private struct LabeledPicker<P: View>: View {
    let title: String
    @ViewBuilder let picker: () -> P
    let detail: () -> String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let detail = detail() {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            picker()
                .pickerStyle(.segmented)
                .labelsHidden()
        }
    }
}

private struct FeatureToggle: View {
    @EnvironmentObject private var ac: ACController
    let title: String
    let symbol: String
    let key: String

    var body: some View {
        Toggle(isOn: Binding(get: { ac.state.flag(key) }, set: { _ in ac.toggle(key) })) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .frame(maxWidth: .infinity)
        }
        .toggleStyle(.button)
    }
}

// MARK: - Setup

private struct SetupView: View {
    @EnvironmentObject private var ac: ACController
    @State private var manualIP = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connect your air conditioner").font(.headline)
            Text("The unit must already be on your Wi-Fi network (set up once with the Gree+ app).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Scan network") { Task { await ac.scan() } }
                    .disabled(ac.isScanning)
                if ac.isScanning || ac.isBusy { ProgressView().controlSize(.small) }
            }

            ForEach(ac.discovered) { device in
                Button { Task { await ac.pair(device) } } label: {
                    HStack {
                        Image(systemName: "air.conditioner.horizontal")
                        VStack(alignment: .leading) {
                            Text(device.name)
                            Text("\(device.ip) · \(device.mac)").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("Pair").foregroundStyle(.tint)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(ac.isBusy)
            }

            HStack {
                TextField("Or enter IP address", text: $manualIP)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await ac.scan(host: manualIP) } }
                Button("Find") { Task { await ac.scan(host: manualIP) } }
                    .disabled(manualIP.isEmpty || ac.isScanning)
            }
        }
    }
}

// MARK: - Footer

private struct FooterView: View {
    @EnvironmentObject private var ac: ACController

    var body: some View {
        HStack {
            Menu {
                Toggle("Launch at Login", isOn: Binding(get: { ac.launchAtLogin }, set: { ac.launchAtLogin = $0 }))
                if ac.device != nil {
                    Divider()
                    Button("Forget Air Conditioner") { ac.forgetDevice() }
                }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .keyboardShortcut("q")
        }
    }
}
