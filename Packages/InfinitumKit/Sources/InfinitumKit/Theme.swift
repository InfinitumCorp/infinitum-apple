import SwiftUI

/// Infinitum house style: white paper, ink, hairlines, square corners, Helvetica Neue.
public enum Theme {
    public static let paper = Color.white
    public static let ink = Color(red: 0x11 / 255, green: 0x18 / 255, blue: 0x20 / 255)
    public static let muted = Color(red: 0x52 / 255, green: 0x60 / 255, blue: 0x6b / 255)
    public static let hairline = Color(red: 0xd6 / 255, green: 0xdc / 255, blue: 0xe1 / 255)
    public static let accent = Color(red: 0x24 / 255, green: 0x54 / 255, blue: 0xdd / 255)

    public static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Helvetica Neue", size: size).weight(weight)
    }
}

/// Full-width square button: filled ink (primary) or ink outline.
struct InkButtonStyle: ButtonStyle {
    var primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(16, weight: .medium))
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(primary ? Theme.paper : Theme.ink)
            .background(primary ? Theme.ink : Theme.paper)
            .overlay(Rectangle().stroke(Theme.ink, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Rectangle())
    }
}
