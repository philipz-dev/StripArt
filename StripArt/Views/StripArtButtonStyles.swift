import SwiftUI

/// Shared 3D, rounded button visual language used across the whole app.
enum BrandStyle {
    static let blue = LinearGradient(
        colors: [
            Color(red: 0.36, green: 0.68, blue: 1.0),
            Color(red: 0.05, green: 0.27, blue: 0.78)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let green = LinearGradient(
        colors: [
            Color(red: 0.30, green: 0.78, blue: 0.50),
            Color(red: 0.10, green: 0.55, blue: 0.32)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let red = LinearGradient(
        colors: [
            Color(red: 0.95, green: 0.42, blue: 0.42),
            Color(red: 0.82, green: 0.18, blue: 0.24)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let neutral = LinearGradient(
        colors: [
            Color(white: 1.0),
            Color(white: 0.90)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Translucent glass fill for icon buttons placed over imagery.
    static let glass = LinearGradient(
        colors: [
            Color.white.opacity(0.28),
            Color.white.opacity(0.10)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let blueShadow = Color(red: 0.1, green: 0.3, blue: 0.7)
    static let greenShadow = Color(red: 0.1, green: 0.45, blue: 0.25)
    static let redShadow = Color(red: 0.7, green: 0.1, blue: 0.15)
}

/// A square black frame with a grey bevel line that gives a 3D look: vertical
/// borders carry the grey line on their right side, horizontal borders on their
/// lower side (light from the top-left). Never interactive.
struct Picture3DBorder: View {
    var black: CGFloat = 3
    var grey: CGFloat = 2

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let t = black
            let g = grey
            let greyShading = GraphicsContext.Shading.color(Color(white: 0.55))
            let blackShading = GraphicsContext.Shading.color(.black)

            // Grey bevel lines first (right side of verticals, lower side of horizontals).
            context.fill(Path(CGRect(x: t, y: 0, width: g, height: h)), with: greyShading)
            context.fill(Path(CGRect(x: w - g, y: 0, width: g, height: h)), with: greyShading)
            context.fill(Path(CGRect(x: 0, y: t, width: w, height: g)), with: greyShading)
            context.fill(Path(CGRect(x: 0, y: h - g, width: w, height: g)), with: greyShading)

            // Black frame, shifted in by the grey width on the right and bottom.
            context.fill(Path(CGRect(x: 0, y: 0, width: t, height: h - g)), with: blackShading)
            context.fill(Path(CGRect(x: w - g - t, y: 0, width: t, height: h - g)), with: blackShading)
            context.fill(Path(CGRect(x: 0, y: 0, width: w - g, height: t)), with: blackShading)
            context.fill(Path(CGRect(x: 0, y: h - g - t, width: w - g, height: t)), with: blackShading)
        }
        .allowsHitTesting(false)
    }
}

/// The StripArt wordmark with the glowing spark on the "i". Shared so every
/// screen shows an identical logo.
struct StripArtLogo: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            logoText("Str")
            ZStack(alignment: .top) {
                logoText("i")
                Circle()
                    .fill(Color.white)
                    .frame(width: 7, height: 7)
                    .overlay(
                        Circle()
                            .fill(Color(red: 0.6, green: 0.85, blue: 1.0))
                            .blur(radius: 3)
                    )
                    .shadow(color: Color(red: 0.4, green: 0.75, blue: 1.0), radius: 6)
                    .offset(y: -3)
            }
            logoText("pArt")
        }
        .font(.system(size: 44, weight: .heavy, design: .rounded))
    }

    private func logoText(_ string: String) -> some View {
        Text(string).foregroundStyle(BrandStyle.blue)
    }
}

/// The standard cancel (✗) / confirm (✓) pair, centered and horizontally
/// aligned the same way on every screen.
struct DecisionButtons: View {
    var confirmEnabled: Bool = true
    let cancel: () -> Void
    let confirm: () -> Void

    var body: some View {
        HStack(spacing: 28) {
            Button(action: cancel) {
                Image(systemName: "xmark")
            }
            .buttonStyle(
                CircleIconButtonStyle(
                    gradient: BrandStyle.red,
                    shadowColor: BrandStyle.redShadow,
                    diameter: 72,
                    iconSize: 27
                )
            )

            Button(action: confirm) {
                Image(systemName: "checkmark")
            }
            .buttonStyle(
                CircleIconButtonStyle(
                    gradient: BrandStyle.green,
                    shadowColor: BrandStyle.greenShadow,
                    diameter: 72,
                    iconSize: 27
                )
            )
            .opacity(confirmEnabled ? 1 : 0.45)
            .disabled(!confirmEnabled)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Soft, elegant ambient background: a light blue/indigo tint at the top that
/// fades into the system background toward the bottom. Used on every screen.
struct AppBackground: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)

            LinearGradient(
                colors: [
                    Color(red: 0.40, green: 0.47, blue: 0.95).opacity(0.12),
                    Color(red: 0.40, green: 0.47, blue: 0.95).opacity(0.0)
                ],
                startPoint: .top,
                endPoint: .center
            )

            RadialGradient(
                colors: [Color(red: 0.42, green: 0.7, blue: 1.0).opacity(0.10), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 380
            )
        }
        .ignoresSafeArea()
    }
}

/// Full-width, rounded, flat modern button with a soft shadow.
struct GradientButtonStyle: ButtonStyle {
    var gradient: LinearGradient = BrandStyle.blue
    var shadowColor: Color = BrandStyle.blueShadow
    var foreground: Color = .white
    var cornerRadius: CGFloat = 16

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(gradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
            )
            .shadow(
                color: shadowColor.opacity(configuration.isPressed ? 0.10 : 0.18),
                radius: configuration.isPressed ? 2 : 5,
                x: 0,
                y: configuration.isPressed ? 1 : 2
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Circular, glossy 3D icon button (cancel / confirm / direction arrows).
struct CircleIconButtonStyle: ButtonStyle {
    var gradient: LinearGradient = BrandStyle.blue
    var shadowColor: Color = BrandStyle.blueShadow
    var foreground: Color = .white
    var diameter: CGFloat = 60
    var iconSize: CGFloat = 24
    var strokeOpacity: Double = 0.3

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: iconSize, weight: .bold))
            .foregroundStyle(foreground)
            .frame(width: diameter, height: diameter)
            .background(
                Circle()
                    .fill(gradient)
                    .overlay(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.18), .clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    )
                    .overlay(
                        Circle().strokeBorder(.white.opacity(strokeOpacity * 0.6), lineWidth: 1)
                    )
            )
            .shadow(
                color: shadowColor.opacity(configuration.isPressed ? 0.12 : 0.22),
                radius: configuration.isPressed ? 4 : 8,
                x: 0,
                y: configuration.isPressed ? 2 : 4
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Shared card + title styling

/// Premium frosted card used to group related controls across screens.
struct CardStyle: ViewModifier {
    var padding: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color(.separator).opacity(0.35), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
    }
}

extension View {
    func cardStyle(padding: CGFloat = 20) -> some View {
        modifier(CardStyle(padding: padding))
    }
}

/// A bold, rounded, brand-gradient screen title with an optional tracked,
/// uppercase subtitle — the shared header look for every screen.
struct ScreenTitle: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(.title, design: .rounded).weight(.bold))
                .foregroundStyle(BrandStyle.blue)
                .multilineTextAlignment(.center)

            if let subtitle {
                Text(subtitle.uppercased())
                    .font(.footnote.weight(.semibold))
                    .tracking(2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
