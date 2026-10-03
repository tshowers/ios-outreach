import SwiftUI
import UIKit

// Outreach in the Find family (design_handoff_outreach): Find's tokens and
// pill controls, and one colour per area of the product everywhere it shows
// up - Needs You pink, Drafts violet, Inbox blue, Catalyst cyan, Activity and
// warnings yellow, TODD / Maya notes green. The main action is always blue.

/// Find's colour tokens, light and dark (the theme follows the system).
enum Ink {
    static let bg = dynamic(0xffffff, 0x0c0e13)
    static let surface = dynamic(0xf2f3f6, 0x171a22)
    static let surface2 = dynamic(0xe4e7ed, 0x242936)
    static let text = dynamic(0x0f1115, 0xf2f4f8)
    static let muted = dynamic(0x5a6170, 0x9aa2b2)
    static let blue = dynamic(0x2f6bff, 0x3d7bff)
    static let blueInk = dynamic(0x1f55e0, 0x86aeff)
    static let danger = dynamic(0xd92d4a, 0xff6b81)

    // Solid accents, for dots and bars.
    static let cyan = Color(hex: 0x1fc8ec)
    static let violet = Color(hex: 0xa259ff)
    static let pink = Color(hex: 0xff4fa8)
    static let yellow = Color(hex: 0xffd92e)

    static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

/// A tinted pair: a soft background and the ink that reads on it.
struct Tint {
    let background: Color
    let foreground: Color
    /// The solid accent, for dots, bars and the selected chip.
    let solid: Color

    static let blue = Tint(background: Ink.dynamic(0xe3ecff, 0x15254a), foreground: Ink.dynamic(0x1d4fd6, 0xa3c1ff), solid: Ink.blue)
    static let cyan = Tint(background: Ink.dynamic(0xdaf6fc, 0x0c2d35), foreground: Ink.dynamic(0x08657d, 0x74e4f8), solid: Ink.cyan)
    static let pink = Tint(background: Ink.dynamic(0xffe3f1, 0x3a1029), foreground: Ink.dynamic(0xa8105a, 0xff92c9), solid: Ink.pink)
    static let violet = Tint(background: Ink.dynamic(0xefe5ff, 0x2a1847), foreground: Ink.dynamic(0x6427c9, 0xcdaaff), solid: Ink.violet)
    static let yellow = Tint(background: Ink.dynamic(0xfff4c2, 0x2f2906), foreground: Ink.dynamic(0x6e5700, 0xffe56a), solid: Ink.yellow)
    static let green = Tint(background: Ink.dynamic(0xe0f6e6, 0x0e2c19), foreground: Ink.dynamic(0x17703a, 0x80e2a4), solid: Ink.dynamic(0x17703a, 0x80e2a4))
    static let neutral = Tint(background: Ink.surface2, foreground: Ink.muted, solid: Ink.muted)
}

/// Each area keeps one colour wherever it appears.
enum Area {
    case needsYou, drafts, inbox, catalyst, activity, todd

    var tint: Tint {
        switch self {
        case .needsYou: return .pink
        case .drafts: return .violet
        case .inbox: return .blue
        case .catalyst: return .cyan
        case .activity: return .yellow
        case .todd: return .green
        }
    }
}

// MARK: - Pieces

/// The small 11/700 pill for a message type or status ("Out of office").
struct TagPill: View {
    let text: String
    var tint: Tint = .neutral
    var symbol: String?

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(text)
        }
        .font(.system(size: 11, weight: .bold))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(tint.foreground)
        .background(tint.background, in: Capsule())
    }
}

/// TODD's (or Maya's) note: green, a sparkle, an uppercase label and the
/// text, with an optional decision chip and follow-up buttons below.
struct TODDNote<Accessory: View>: View {
    let label: String
    let text: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(label.uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.7)
            } icon: {
                Image(systemName: "sparkle")
            }
            Text(text)
                .font(.system(size: 14))
                .fixedSize(horizontal: false, vertical: true)
            accessory
        }
        .foregroundStyle(Tint.green.foreground)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tint.green.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

extension TODDNote where Accessory == EmptyView {
    init(label: String, text: String) {
        self.init(label: label, text: text) { EmptyView() }
    }
}

/// Find's segmented control: a surface track with the active segment raised.
struct PillSegments<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { option in
                let isSelected = option.value == selection
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = option.value }
                } label: {
                    Text(option.title)
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .foregroundStyle(Ink.text)
                        .background {
                            if isSelected {
                                Capsule().fill(Ink.bg).shadow(color: .black.opacity(0.1), radius: 3, y: 1)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Ink.surface, in: Capsule())
    }
}

/// Filter chips: the selected one is solid ink, the rest sit on the surface.
struct FilterChips<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.value) { option in
                    let isSelected = option.value == selection
                    Button(option.title) { selection = option.value }
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .foregroundStyle(isSelected ? Ink.bg : Ink.text)
                        .background(isSelected ? Ink.text : Ink.surface, in: Capsule())
                        .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Pill buttons. Primary is blue; secondary sits on the surface; dark is the
/// near-black pill used for "Start" and "Reconnect".
struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, dark, danger }
    var kind: Kind = .primary
    var height: CGFloat = 52

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: height >= 48 ? 17 : 14, weight: .bold))
            .padding(.horizontal, height >= 48 ? 22 : 14)
            .frame(minHeight: height)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return .white
        case .secondary: return Ink.text
        case .dark: return Ink.bg
        case .danger: return Ink.danger
        }
    }

    private var background: Color {
        switch kind {
        case .primary: return Ink.blue
        case .secondary, .danger: return Ink.surface
        case .dark: return Ink.text
        }
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pillPrimary: PillButtonStyle { PillButtonStyle(kind: .primary) }
    static var pillSecondary: PillButtonStyle { PillButtonStyle(kind: .secondary) }
    static var pillDark: PillButtonStyle { PillButtonStyle(kind: .dark, height: 40) }
    static func pill(_ kind: PillButtonStyle.Kind, height: CGFloat = 52) -> PillButtonStyle { PillButtonStyle(kind: kind, height: height) }
}

/// The sticky bottom action bar: page background, an upward shadow, the
/// primary pill and a secondary row.
struct StickyActionBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 10) { content }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .background {
                Rectangle()
                    .fill(Ink.bg)
                    .shadow(color: .black.opacity(0.08), radius: 12, y: -4)
                    .ignoresSafeArea()
            }
    }
}

/// A round initials badge in an area's tint.
struct InitialsBadge: View {
    let name: String
    var tint: Tint = .blue
    var size: CGFloat = 40

    var body: some View {
        Text(Self.initials(name))
            .font(.system(size: size * 0.32, weight: .bold))
            .foregroundStyle(tint.foreground)
            .frame(width: size, height: size)
            .background(tint.background, in: Circle())
            .accessibilityHidden(true)
    }

    static func initials(_ name: String) -> String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}

/// A large tinted card, radius 24 - Needs You's hero, Catalyst's chooser.
struct TintCard<Content: View>: View {
    var tint: Tint
    var radius: CGFloat = 24
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.background, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// A plain surface card, radius 18-20.
struct SurfaceCard<Content: View>: View {
    var radius: CGFloat = 20
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// 12/700 uppercase eyebrow.
struct Eyebrow: View {
    let text: String
    var color: Color = Ink.muted

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .bold))
            .tracking(0.7)
            .foregroundStyle(color)
    }
}

// MARK: - Colour helpers

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: 1
        )
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }
}
