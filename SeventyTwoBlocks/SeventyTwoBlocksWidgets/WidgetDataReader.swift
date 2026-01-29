import SwiftUI

// MARK: - Widget Data Reader (reads from App Group UserDefaults)

enum WidgetDataReader {
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    static func read() -> WidgetData {
        guard let defaults = UserDefaults(suiteName: WidgetConstants.appGroupID),
              let data = defaults.data(forKey: WidgetConstants.widgetDataKey),
              let widgetData = try? decoder.decode(WidgetData.self, from: data) else {
            return .empty
        }
        return widgetData
    }
}

// MARK: - HSL Color Conversion (replicates Category.swiftUIColor for widget context)

extension Color {
    /// Create a Color from an HSL string like "187 85% 53%"
    static func fromHSL(_ hslString: String?) -> Color {
        guard let hslString = hslString else { return .gray }

        let components = hslString.split(separator: " ")
        guard components.count >= 3,
              let h = Double(components[0]),
              let sValue = Double(String(components[1]).replacingOccurrences(of: "%", with: "")),
              let lValue = Double(String(components[2]).replacingOccurrences(of: "%", with: "")) else {
            return .gray
        }

        let s = sValue / 100
        let l = lValue / 100

        // HSL to HSB conversion
        let b = l + s * min(l, 1 - l)
        let sHsb = b == 0 ? 0 : 2 * (1 - l / b)

        return Color(hue: h / 360, saturation: sHsb, brightness: b)
    }
}

// MARK: - Widget Helper Views

struct BlockNumberView: View {
    let displayNumber: Int
    let fontSize: CGFloat

    var body: some View {
        Text("BLOCK \(displayNumber)")
            .font(.system(size: fontSize, weight: .bold, design: .monospaced))
    }
}

struct TimeRangeView: View {
    let blockIndex: Int
    let fontSize: CGFloat

    var body: some View {
        let start = BlockTimeUtils.blockToTime(blockIndex)
        let end = BlockTimeUtils.blockEndTime(blockIndex)
        Text("\(start)-\(end)")
            .font(.system(size: fontSize, design: .monospaced))
            .foregroundStyle(.secondary)
    }
}
