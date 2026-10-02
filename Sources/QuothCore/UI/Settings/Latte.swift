import AppKit
import SwiftUI

/// Quoth's "latte" look for its windows: the website's warm palette. Cream
/// cards on a warm off-white, espresso text, amber headings and switches;
/// in Dark Mode, the same in espresso. Native controls throughout, so
/// everything behaves like a Mac app; only the colors are Quoth's.
enum Latte {
    static let background = Color(light: 0xF4F1EC, dark: 0x1C140E)
    static let card = Color(light: 0xFFFDF9, dark: 0x2A1F16)
    static let stroke = Color(light: 0xE2D9CC, dark: 0x46321F)
    static let text = Color(light: 0x24180F, dark: 0xF6EBDD)
    static let secondary = Color(light: 0x6E5F52, dark: 0xBCA892)
    static let header = Color(light: 0x9A4F0B, dark: 0xFFC56A)
    static let tint = Color(light: 0xB8610F, dark: 0xFFB457)

    /// The window background, for the title bar and toolbar around a pane.
    static let windowBackground = NSColor(light: 0xF4F1EC, dark: 0x1C140E)
}

extension NSColor {
    /// A color that follows the appearance, from two hex values.
    convenience init(light: UInt32, dark: UInt32) {
        self.init(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        }
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(light: light, dark: dark))
    }
}

/// A titled card of rows, as in System Settings: a small amber heading and
/// a cream card. Put `RowDivider()` between rows.
struct SettingsSection<Content: View>: View {
    let title: String?
    var footer: String?
    @ViewBuilder let content: () -> Content

    init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Latte.header)
                    .padding(.leading, 4)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Latte.card))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Latte.stroke, lineWidth: 1))
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(Latte.secondary)
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One row of a section: a label, an optional caption under it, and its
/// control on the right. VoiceOver reads the label with the control.
struct SettingRow<Control: View>: View {
    let label: String
    var caption: String?
    @ViewBuilder let control: () -> Control

    init(_ label: String, caption: String? = nil, @ViewBuilder control: @escaping () -> Control) {
        self.label = label
        self.caption = caption
        self.control = control
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).foregroundStyle(Latte.text)
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(Latte.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            control()
                .accessibilityLabel(Text(label))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// The hairline between rows in a section.
struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Latte.stroke)
            .frame(height: 1)
            .padding(.leading, 14)
    }
}

/// A native pop-up menu showing `title`, for choices with sections or
/// marks that a Picker can't show.
struct SettingMenu<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu(content: content) {
            Text(title)
        }
        .fixedSize()
    }
}
