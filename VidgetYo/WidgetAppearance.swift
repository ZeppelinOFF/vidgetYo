import AppKit
import SwiftUI

struct WidgetAppearanceConfig {
    var panelOpacity: Double
    var background: Color
    var text: Color

    static let defaults = WidgetAppearanceConfig(
        panelOpacity: 0.72,
        background: Color(red: 0.32, green: 0.32, blue: 0.36),
        text: .white
    )

    var typography: WidgetTypography {
        WidgetTypography(textColor: text, panelOpacity: panelOpacity)
    }
}

struct WidgetTypography {
    let primary: Color
    let secondary: Color
    let tertiary: Color
    let weight: Font.Weight
    let shadowColor: Color?
    let shadowRadius: CGFloat

    init(textColor: Color, panelOpacity: Double) {
        let opacity = min(1, max(0.12, panelOpacity))
        let lift = 1 - opacity

        weight = opacity >= 0.78 ? .regular : (opacity >= 0.48 ? .medium : .semibold)

        primary = textColor
        secondary = textColor.opacity(0.52 + lift * 0.28)
        tertiary = textColor.opacity(0.38 + lift * 0.32)

        if opacity < 0.72 {
            let luminance = textColor.luminance
            shadowColor = (luminance > 0.55 ? Color.black : Color.white)
                .opacity(0.22 + lift * 0.45)
            shadowRadius = 0.6 + lift * 1.2
        } else {
            shadowColor = nil
            shadowRadius = 0
        }
    }
}

extension Color {
    fileprivate var luminance: Double {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return 0.5 }
        return 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
    }
}

enum ColorStorage {
    static func loadRGB(prefix: String, in defaults: UserDefaults, fallback: (Double, Double, Double)) -> (Double, Double, Double) {
        guard defaults.object(forKey: "\(prefix).r") != nil else { return fallback }
        let r = defaults.double(forKey: "\(prefix).r")
        let g = defaults.double(forKey: "\(prefix).g")
        let b = defaults.double(forKey: "\(prefix).b")
        return (r, g, b)
    }

    static func saveRGB(_ rgb: (Double, Double, Double), prefix: String, in defaults: UserDefaults) {
        defaults.set(rgb.0, forKey: "\(prefix).r")
        defaults.set(rgb.1, forKey: "\(prefix).g")
        defaults.set(rgb.2, forKey: "\(prefix).b")
    }

    static func color(from rgb: (Double, Double, Double)) -> Color {
        Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }

    static func rgb(from color: Color) -> (Double, Double, Double)? {
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return (c.redComponent, c.greenComponent, c.blueComponent)
    }
}

private struct WidgetReadableTextModifier: ViewModifier {
    let typography: WidgetTypography

    func body(content: Content) -> some View {
        if let shadow = typography.shadowColor {
            content.shadow(color: shadow, radius: typography.shadowRadius, x: 0, y: 0.5)
        } else {
            content
        }
    }
}

extension View {
    func widgetReadableText(_ typography: WidgetTypography) -> some View {
        modifier(WidgetReadableTextModifier(typography: typography))
    }
}
