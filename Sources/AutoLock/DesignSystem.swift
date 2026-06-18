import SwiftUI
import AppKit

// Shared UI design tokens and reusable view primitives. Extracted from the
// former 896-line MenuView.swift so the menu, device picker, and password sheet
// can each live in their own file while sharing one design vocabulary. These
// are `internal` (not `private`) precisely so the sibling views can use them.

// MARK: - Design tokens

enum Palette {
    /// NSColor lets us hand off appearance resolution to AppKit so SwiftUI
    /// re-renders automatically when the system flips between light and dark.
    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let darkMatch = appearance.bestMatch(from: [
                .darkAqua, .vibrantDark,
                .accessibilityHighContrastDarkAqua,
                .accessibilityHighContrastVibrantDark,
            ])
            return darkMatch != nil ? dark : light
        })
    }

    static let bg = dynamic(
        light: NSColor(red: 0.962, green: 0.970, blue: 0.945, alpha: 1),
        dark: NSColor(red: 0.055, green: 0.075, blue: 0.063, alpha: 1)
    )
    static let surface = dynamic(
        light: NSColor.white,
        dark: NSColor(red: 0.082, green: 0.106, blue: 0.090, alpha: 1)
    )
    static let surfaceHi = dynamic(
        light: NSColor(red: 0.985, green: 0.990, blue: 0.975, alpha: 1),
        dark: NSColor(red: 0.110, green: 0.137, blue: 0.118, alpha: 1)
    )
    static let stroke = dynamic(
        light: NSColor.black.withAlphaComponent(0.10),
        dark: NSColor.white.withAlphaComponent(0.08)
    )
    static let strokeHi = dynamic(
        light: NSColor.black.withAlphaComponent(0.18),
        dark: NSColor.white.withAlphaComponent(0.14)
    )
    /// Brand accent. Light variant is darker so it stays readable on white;
    /// dark variant keeps the high-energy neon.
    static let lime = dynamic(
        light: NSColor(red: 0.32, green: 0.60, blue: 0.10, alpha: 1),
        dark: NSColor(red: 0.65, green: 1.0, blue: 0.24, alpha: 1)
    )
    static let amber = dynamic(
        light: NSColor(red: 0.78, green: 0.50, blue: 0.04, alpha: 1),
        dark: NSColor(red: 1.0, green: 0.78, blue: 0.30, alpha: 1)
    )
    static let crimson = dynamic(
        light: NSColor(red: 0.80, green: 0.20, blue: 0.20, alpha: 1),
        dark: NSColor(red: 1.0, green: 0.36, blue: 0.36, alpha: 1)
    )
    static let dim = dynamic(
        light: NSColor.black.withAlphaComponent(0.40),
        dark: NSColor.white.withAlphaComponent(0.42)
    )
    static let muted = dynamic(
        light: NSColor.black.withAlphaComponent(0.62),
        dark: NSColor.white.withAlphaComponent(0.62)
    )
    static let label = dynamic(
        light: NSColor.black.withAlphaComponent(0.92),
        dark: NSColor.white.withAlphaComponent(0.92)
    )
    /// Foreground for elements painted on top of `lime` (e.g. LOCK NOW).
    /// Light lime is dark-green so we paint white; dark lime is neon so we paint black.
    static let onLime = dynamic(light: NSColor.white, dark: NSColor.black)
}

enum AppFont {
    static func pretendard(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Pretendard", size: max(size, 13)).weight(weight)
    }
}

// MARK: - Reusable surfaces

struct Surface<Content: View>: View {
    var elevated: Bool = false
    @ViewBuilder var content: Content
    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(elevated ? Palette.surfaceHi : Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(elevated ? Palette.strokeHi : Palette.stroke, lineWidth: 0.5)
            )
    }
}

struct Caption: View {
    let text: String
    var body: some View {
        Text(text)
            .font(AppFont.pretendard(13, weight: .semibold))
            .foregroundStyle(Palette.dim)
    }
}

// MARK: - ParameterDial

struct ParameterDial: View {
    let label: String
    let valueText: String
    let binding: Binding<Double>
    let range: ClosedRange<Double>
    let step: Double
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(AppFont.pretendard(13))
                    .foregroundStyle(Palette.label)
                Spacer()
                Text(valueText)
                    .font(AppFont.pretendard(13, weight: .semibold))
                    .foregroundStyle(accent)
                    .monospacedDigit()
            }
            Slider(value: binding, in: range, step: step)
                .controlSize(.small)
                .tint(accent)
        }
    }
}

// MARK: - DotPulse

struct DotPulse: View {
    let active: Bool
    @State private var pulse: Bool = false

    var body: some View {
        ZStack {
            if active {
                Circle()
                    .stroke(Palette.lime.opacity(0.6), lineWidth: 1)
                    .frame(width: 14, height: 14)
                    .scaleEffect(pulse ? 1.4 : 0.8)
                    .opacity(pulse ? 0 : 1)
                    .animation(
                        .easeOut(duration: 1.6).repeatForever(autoreverses: false),
                        value: pulse
                    )
            }
            Circle()
                .fill(active ? Palette.lime : Palette.dim.opacity(0.4))
                .frame(width: 8, height: 8)
        }
        .frame(width: 14, height: 14)
        .onAppear { pulse = true }
    }
}

// MARK: - Button styles

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.pretendard(13, weight: .bold))
            .foregroundStyle(Palette.lime)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Palette.lime.opacity(0.5), lineWidth: 0.5)
            )
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
