import SwiftUI


// MARK: - 3D Hoverable Card Component
struct HoverableGlossyCard<Content: View>: View {
    @State private var isHovered = false
    let content: Content
    let excludeInteractiveElements: Bool
    
    init(excludeInteractiveElements: Bool = false, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.excludeInteractiveElements = excludeInteractiveElements
    }
     
    var body: some    View {
        content
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.10, green: 0.12, blue: 0.20).opacity(0.85))
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.10, green: 0.12, blue: 0.20).opacity(0.4),
                                        Color(red: 0.06, green: 0.08, blue: 0.14).opacity(0.25)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(isHovered ? 0.35 : 0.18), lineWidth: isHovered ? 1.5 : 1)
                    )
                    .shadow(color: Color.black.opacity(isHovered ? 0.45 : 0.28), radius: isHovered ? 24 : 18, x: 0, y: isHovered ? 12 : 8)
            )
            .brightness(isHovered && !excludeInteractiveElements ? 0.02 : 0.0)
            .onHover { hovering in
                isHovered = hovering
            }
            .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

// MARK: - Enhanced Button with Hover Effects
struct HoverableButton<Content: View>: View {
    @State private var isHovered = false
    let action: () -> Void
    let isDisabled: Bool
    let content: Content
    
    init(action: @escaping () -> Void, isDisabled: Bool = false, @ViewBuilder content: () -> Content) {
        self.action = action
        self.isDisabled = isDisabled
        self.content = content()
    }
    
    var body: some View {
        Button(action: action) {
            content
                .scaleEffect(isHovered && !isDisabled ? 1.05 : 1.0)
                .brightness(isHovered && !isDisabled ? 0.1 : 0.0)
                .shadow(
                    color: .white.opacity(isHovered && !isDisabled ? 0.3 : 0.1), 
                    radius: isHovered && !isDisabled ? 8 : 2
                )
        }
        .disabled(isDisabled)
        .onHover { hovering in
            if !isDisabled {
                isHovered = hovering
            }
        }
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
    }
}

// MARK: - Enhanced Button Styles with Hover Effects
struct EnhancedGlassButtonStyle: ButtonStyle {
    @State private var isHovered = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.semibold)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(red: 0.12, green: 0.14, blue: 0.24).opacity(0.9))
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.12, green: 0.14, blue: 0.24).opacity(isHovered ? 0.45 : 0.3),
                                        Color(red: 0.07, green: 0.09, blue: 0.16).opacity(isHovered ? 0.25 : 0.15)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(isHovered ? 0.35 : 0.22), lineWidth: isHovered ? 1.5 : 1)
                    )
                    .shadow(color: Color.black.opacity(isHovered ? 0.5 : 0.3), radius: isHovered ? 14 : 10, x: 0, y: isHovered ? 7 : 5)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : (isHovered ? 1.05 : 1.0))
            .brightness(isHovered ? 0.05 : 0.0)
            .onHover { hovering in isHovered = hovering }
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: configuration.isPressed)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
    }
}

// MARK: - Button Hover Extension
extension View {
    func buttonHoverEffect() -> some View {
        self.modifier(ButtonHoverModifier())
    }
}

struct ButtonHoverModifier: ViewModifier {
    @State private var isHovered = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .brightness(isHovered ? 0.1 : 0.0)
            .shadow(color: .white.opacity(isHovered ? 0.3 : 0.0), radius: isHovered ? 6 : 0)
            .onHover { hovering in 
                isHovered = hovering
            }
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
    }
}

// Removed CursorFollowingGlow - was causing performance issues
// struct CursorFollowingGlow: View {
//     @EnvironmentObject var mouseTracker: MousePositionTracker
//     let size: CGFloat
//     let intensity: Double
//
//     init(size: CGFloat = 300, intensity: Double = 0.2) {
//         self.size = size
//         self.intensity = intensity
//     }
//
//     var body: some View {
//         GeometryReader { geometry in
//             let relativeX = mouseTracker.relativePosition.x
//             let relativeY = mouseTracker.relativePosition.y
//
//             RadialGradient(
//                 colors: [
//                     Color.white.opacity(intensity * 0.6),
//                     Color.white.opacity(intensity * 0.3),
//                     Color.white.opacity(intensity * 0.1),
//                     Color.clear
//                 ],
//                 center: UnitPoint(x: relativeX, y: relativeY),
//                 startRadius: size * 0.1,
//                 endRadius: size * 0.5
//             )
//             .blendMode(.overlay)
//             .allowsHitTesting(false)
//             .animation(.easeInOut(duration: 0.25), value: mouseTracker.mousePosition)
//         }
//     }
// }



