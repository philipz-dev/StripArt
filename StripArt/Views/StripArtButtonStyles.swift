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

/// Full-width, rounded, glossy gradient button.
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
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.28), .clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                    )
            )
            .shadow(
                color: shadowColor.opacity(configuration.isPressed ? 0.2 : 0.4),
                radius: configuration.isPressed ? 6 : 12,
                x: 0,
                y: configuration.isPressed ? 3 : 6
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
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
                                    colors: [.white.opacity(0.38), .clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    )
                    .overlay(
                        Circle().strokeBorder(.white.opacity(strokeOpacity), lineWidth: 1)
                    )
            )
            .shadow(
                color: shadowColor.opacity(configuration.isPressed ? 0.25 : 0.45),
                radius: configuration.isPressed ? 7 : 13,
                x: 0,
                y: configuration.isPressed ? 3 : 7
            )
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
