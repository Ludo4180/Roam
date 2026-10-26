import SwiftUI

// Roam v0.5 design system. LocusTheme retains its name to avoid touching
// the existing, untested location engine and setup screens.
enum RoamPalette {
    static let midnight = Color(red: 10 / 255, green: 31 / 255, blue: 61 / 255)
    static let background = Color(red: 5 / 255, green: 14 / 255, blue: 32 / 255)
    static let surface = Color(red: 10 / 255, green: 26 / 255, blue: 53 / 255)
    static let electricBlue = Color(red: 59 / 255, green: 130 / 255, blue: 255 / 255)
    static let turquoise = Color(red: 20 / 255, green: 224 / 255, blue: 210 / 255)
    static let muted = Color(red: 158 / 255, green: 178 / 255, blue: 207 / 255)
    static let border = Color.white.opacity(0.13)
    static let primaryGradient = LinearGradient(
        colors: [electricBlue, turquoise], startPoint: .leading, endPoint: .trailing
    )
}

enum LocusTheme {
    static let accent = RoamPalette.turquoise
    static let accentSecondary = RoamPalette.electricBlue
    static let danger = Color(red: 0.96, green: 0.31, blue: 0.40)
    static let panelStroke = RoamPalette.border
    static let statusGood = Color(red: 0.33, green: 0.85, blue: 0.58)
    static let statusWarn = Color(red: 0.98, green: 0.76, blue: 0.34)
    static let statusBad = danger
}

/// New dark glass-like surface for Roam's main navigation controls.
struct RoamSurfaceModifier: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(shape.fill(RoamPalette.surface.opacity(0.96)))
            .overlay(shape.stroke(RoamPalette.border, lineWidth: 1))
            .shadow(color: .black.opacity(0.28), radius: 20, y: 8)
            .contentShape(shape)
    }
}

/// Retained for the existing Locus-derived setup, pairing, and detail views.
enum LocusGlassStyle {
    case regular
    case clear
    case interactive
}

struct LocusGlassModifier<S: Shape>: ViewModifier {
    var style: LocusGlassStyle
    var shape: S
    var tint: Color?

    // Cross-SDK material fallback. Does not require the iOS 26 Liquid Glass SDK.
    // The main Roam controls use roamSurface() and are unaffected.
    func body(content: Content) -> some View {
        content
            .background {
                shape.fill(.ultraThinMaterial)
                if let tint { shape.fill(tint.opacity(0.30)) }
            }
            .overlay(shape.stroke(LocusTheme.panelStroke, lineWidth: 1))
            .contentShape(shape)
    }
}

extension View {
    func roamSurface(cornerRadius: CGFloat = 20) -> some View {
        modifier(RoamSurfaceModifier(cornerRadius: cornerRadius))
    }

    func locusGlass<S: Shape>(
        _ style: LocusGlassStyle = .regular,
        tint: Color? = nil,
        in shape: S
    ) -> some View {
        modifier(LocusGlassModifier(style: style, shape: shape, tint: tint))
    }

    func locusGlass(_ style: LocusGlassStyle = .regular, tint: Color? = nil) -> some View {
        locusGlass(style, tint: tint, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
