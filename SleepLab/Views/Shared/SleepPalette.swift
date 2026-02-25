import SwiftUI
import UIKit

enum SleepPalette {
    static let primary = Color.dynamic(light: "#0A84FF", dark: "#0A84FF")
    static let accent = Color.dynamic(light: "#30D158", dark: "#30D158")
    static let panelBackground = Color.dynamic(light: "#FFFFFF", dark: "#1C1C1E", lightOpacity: 0.97, darkOpacity: 0.9)
    static let panelSecondary = Color.dynamic(light: "#EAF1FB", dark: "#2A2D33", lightOpacity: 0.98, darkOpacity: 0.95)
    static let mutedText = Color.dynamic(light: "#3F4D62", dark: "#9AA4B2")
    static let cardStroke = Color.dynamic(light: "#B8C6DA", dark: "#333A48")
    static let chartGrid = Color.dynamic(light: "#C9D5E6", dark: "#2E3645")
    static let chartPlotBackground = Color.dynamic(light: "#F8FAFF", dark: "#11141B")
    static let stageLabelText = Color.dynamic(light: "#4F5C70", dark: "#A7AFBC")
    static let titleText = Color.dynamic(light: "#0F172A", dark: "#F3F4F6")
    static let iconCircle = Color.dynamic(light: "#FFFFFF", dark: "#2D3038", lightOpacity: 0.82, darkOpacity: 0.86)
    static let metricChipBackground = Color.dynamic(light: "#FFFFFF", dark: "#2A2D33", lightOpacity: 0.82, darkOpacity: 0.95)

    static let backgroundGradient = LinearGradient(
        colors: [
            Color.dynamic(light: "#E9F1FF", dark: "#0B0D13"),
            Color.dynamic(light: "#F7FBFF", dark: "#12151D"),
            Color.dynamic(light: "#EDF7F0", dark: "#0E1416")
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let chartStageColors: [SleepStage: Color] = [
        .awake: Color.dynamic(light: "#FF6B5A", dark: "#FF7A6A"),
        .rem: Color.dynamic(light: "#43C8F2", dark: "#46CCFF"),
        .core: Color.dynamic(light: "#1492FF", dark: "#1E9BFF"),
        .deep: Color.dynamic(light: "#443CC2", dark: "#5A4AE6"),
        .inBed: Color.dynamic(light: "#1492FF", dark: "#1E9BFF")
    ]

    static let comparisonSeries: [Color] = [
        Color.dynamic(light: "#3B82F6", dark: "#60A5FA"),
        Color.dynamic(light: "#0EA5A4", dark: "#2DD4BF"),
        Color.dynamic(light: "#D97706", dark: "#F59E0B"),
        Color.dynamic(light: "#DC2626", dark: "#F87171"),
        Color.dynamic(light: "#7C3AED", dark: "#A78BFA")
    ]

    static func stageColor(for stage: SleepStage) -> Color {
        chartStageColors[stage] ?? primary
    }
}

extension Color {
    static func dynamic(light: String, dark: String, lightOpacity: Double = 1, darkOpacity: Double = 1) -> Color {
        Color(
            UIColor { traits in
                let isDark = traits.userInterfaceStyle == .dark
                return UIColor(
                    hex: isDark ? dark : light,
                    alpha: isDark ? darkOpacity : lightOpacity
                )
            }
        )
    }

    init(hex: String, opacity: Double = 1) {
        let sanitized = hex.replacingOccurrences(of: "#", with: "")
        let scanner = Scanner(string: sanitized)
        var value: UInt64 = 0
        scanner.scanHexInt64(&value)

        let red = Double((value & 0xFF0000) >> 16) / 255.0
        let green = Double((value & 0x00FF00) >> 8) / 255.0
        let blue = Double(value & 0x0000FF) / 255.0

        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}

private extension UIColor {
    convenience init(hex: String, alpha: Double = 1) {
        let sanitized = hex.replacingOccurrences(of: "#", with: "")
        let scanner = Scanner(string: sanitized)
        var value: UInt64 = 0
        scanner.scanHexInt64(&value)

        let red = CGFloat((value & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((value & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(value & 0x0000FF) / 255.0

        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
