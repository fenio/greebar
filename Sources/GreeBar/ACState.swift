import Foundation

enum ACMode: Int, CaseIterable, Identifiable {
    case auto = 0, cool, dry, fan, heat
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .auto: "Auto"
        case .cool: "Cool"
        case .dry: "Dry"
        case .fan: "Fan"
        case .heat: "Heat"
        }
    }

    var symbol: String {
        switch self {
        case .auto: "arrow.triangle.2.circlepath"
        case .cool: "snowflake"
        case .dry: "drop"
        case .fan: "fan"
        case .heat: "sun.max"
        }
    }
}

enum FanSpeed: Int, CaseIterable, Identifiable {
    case auto = 0, low, mediumLow, medium, mediumHigh, high
    var id: Int { rawValue }
    var title: String { self == .auto ? "Auto" : "\(rawValue)" }
}

/// Typed view over the raw Gree parameter dictionary (column name -> value).
struct ACState {
    static let columns = ["Pow", "Mod", "SetTem", "WdSpd", "Tur", "Quiet", "SwUpDn", "SwingLfRig",
                          "Lig", "SwhSlp", "Health", "TemUn", "TemRec", "TemSen"]
    static let temperatureRange = 16...30

    var raw: [String: Int] = [:]

    var power: Bool { raw["Pow"] == 1 }
    var mode: ACMode { ACMode(rawValue: raw["Mod"] ?? 0) ?? .auto }
    var targetTemperature: Int { raw["SetTem"] ?? 24 }
    var fanSpeed: FanSpeed { FanSpeed(rawValue: raw["WdSpd"] ?? 0) ?? .auto }

    /// Indoor sensor reading; most units report it with a +40 offset. Some report 0 when unsupported.
    var roomTemperature: Int? {
        guard let value = raw["TemSen"], value != 0 else { return nil }
        return value >= 40 ? value - 40 : value
    }

    func flag(_ key: String) -> Bool { (raw[key] ?? 0) != 0 }
}
