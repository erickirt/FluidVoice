import AppKit
import Combine
import CoreGraphics
import SwiftUI

// MARK: - Active App Tracker

class ActiveAppTracker: ObservableObject {
    @Published var activeAppName: String = "Unknown App"
    @Published var activeWindowTitle: String = ""
    private var timer: Timer?

    init() {
        updateActiveApp()
        startTracking()
    }

    private func startTracking() {
        // Reduced frequency for app tracking - 2 FPS is sufficient for app name updates
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            self.updateActiveApp()
        }
    }

    private func updateActiveApp() {
        if let frontmostApp = NSWorkspace.shared.frontmostApplication {
            activeAppName = frontmostApp.localizedName ?? "Unknown App"
            activeWindowTitle = fetchFrontmostWindowTitle(for: frontmostApp.processIdentifier) ?? ""
        }
    }

    private func fetchFrontmostWindowTitle(for ownerPid: pid_t) -> String? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for info in windowInfo {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid == ownerPid else { continue }
            if let name = info[kCGWindowName as String] as? String, name.isEmpty == false {
                return name
            }
        }
        return nil
    }

    deinit {
        timer?.invalidate()
    }
}

// MARK: - Spokenly-Style Talking Animation Configuration

struct TalkingAnimationConfig: AudioVisualizationConfig {
    let noiseThreshold: CGFloat // Now dynamic - set from user preference
    let maxAnimationScale: CGFloat = 2.5
    let animationSpring: Animation = .spring(response: 0.3, dampingFraction: 0.7, blendDuration: 0.1)

    init(noiseThreshold: CGFloat = 0.4) {
        self.noiseThreshold = max(0.01, min(0.8, noiseThreshold)) // Clamp to valid range
    }

    // Bar-specific properties
    let barCount: Int = 12
    let barSpacing: CGFloat = 3
    let barWidth: CGFloat = 5
    let minBarHeight: CGFloat = 4
    let maxBarHeight: CGFloat = 32
    let animationSpeed: Double = 0.12 // Optimized animation speed
    let containerWidth: CGFloat = 140
    let containerHeight: CGFloat = 40

    // Performance optimization settings - much faster and more responsive
    let maxFPS: Double = 60.0 // Higher FPS for smoothness
    let idleAnimationReduction: Int = 4 // Less aggressive reduction
    let activeFPS: Double = 60.0 // High FPS during active speech
    let idleFPS: Double = 30.0 // Higher idle FPS
    let silenceFPS: Double = 10.0 // Higher silence FPS
}

// MARK: - Spokenly-Style Audio Visualization View

struct TalkingAudioVisualizationView: View {
    @StateObject private var data: AudioVisualizationData
    @State private var dynamicNoiseThreshold: CGFloat = .init(SettingsStore.shared.visualizerNoiseThreshold)

    // Dynamic config that updates with settings
    private var config: TalkingAnimationConfig {
        TalkingAnimationConfig(noiseThreshold: dynamicNoiseThreshold)
    }

    init(audioLevelPublisher: AnyPublisher<CGFloat, Never>) {
        _data = StateObject(wrappedValue: AudioVisualizationData(audioLevelPublisher: audioLevelPublisher))
    }

    var body: some View {
        SpokenlyWaveform(
            config: config,
            audioLevel: data.audioLevel,
            isActive: data.audioLevel > config.noiseThreshold
        )
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            // Update threshold when UserDefaults changes
            let newThreshold = CGFloat(SettingsStore.shared.visualizerNoiseThreshold)
            if newThreshold != self.dynamicNoiseThreshold {
                self.dynamicNoiseThreshold = newThreshold
            }
        }
    }
}

// MARK: - Spokenly-Style Clean Waveform

struct SpokenlyWaveform: View {
    let config: TalkingAnimationConfig
    let audioLevel: CGFloat
    let isActive: Bool

    @State private var barHeights: [CGFloat] = []
    @State private var barOpacities: [Double] = []
    @State private var animationPhases: [Double] = []
    @State private var animationTrigger: Int = 0
    @State private var lastUpdateTime: TimeInterval = 0
    @State private var isViewVisible: Bool = true

    private let animationTimer = Timer.publish(every: 0.033, on: .main, in: .common)
        .autoconnect() // 30 FPS base timer - safer for CoreML concurrency

    var body: some View {
        HStack(spacing: config.barSpacing) {
            ForEach(0..<self.config.barCount, id: \.self) { index in
                SpokenlyBar(
                    height: index < self.barHeights.count ? self.barHeights[index] : self.config.minBarHeight,
                    opacity: index < self.barOpacities.count ? self.barOpacities[index] : 0.4,
                    index: index,
                    config: self.config,
                    isActive: self.isActive
                )
            }
        }
        .frame(width: config.containerWidth, height: config.containerHeight)
        .onAppear {
            self.initializeBars()
            self.isViewVisible = true
        }
        .onDisappear {
            self.isViewVisible = false
        }
        .onReceive(animationTimer) { _ in
            if self.isViewVisible {
                self.updateBars()
            }
        }
    }

    private func initializeBars() {
        barHeights = Array(repeating: config.minBarHeight, count: config.barCount)
        barOpacities = Array(repeating: 0.4, count: config.barCount)
        animationPhases = (0..<config.barCount).map { _ in Double.random(in: 0...2 * Double.pi) }
    }

    private func updateBars() {
        let currentTime = Date().timeIntervalSince1970

        // Adaptive frame limiting - reduce rate during active processing to prevent CoreML conflicts
        let targetFPS: Double = isActive ? 30.0 : 20.0 // Lower FPS to reduce state update conflicts
        let frameTime = 1.0 / targetFPS
        if currentTime - lastUpdateTime < frameTime { return }
        lastUpdateTime = currentTime

        // Safety check
        guard barHeights.count == config.barCount,
              barOpacities.count == config.barCount else { return }

        // Direct real-time animation based on current audio level
        if audioLevel <= config.noiseThreshold { // USE THE USER-CONTROLLABLE THRESHOLD!
            // Complete stillness
            for i in 0..<min(config.barCount, barHeights.count) {
                barHeights[i] = config.minBarHeight
                barOpacities[i] = 0.3
            }
        } else {
            // Real-time responsive animation
            let audioInfluence = Double(audioLevel) * 2.0

            for i in 0..<min(config.barCount, barHeights.count) {
                // Fast frequency for immediate response
                let frequency = 3.0 + Double(i) * 0.4
                let phase = animationPhases[i]
                let waveValue = sin(currentTime * frequency + phase)
                let normalizedWave = (waveValue + 1) / 2

                // Direct audio-responsive calculation
                let heightMultiplier = normalizedWave * audioInfluence + 0.2
                let heightRange = config.maxBarHeight - config.minBarHeight
                let newHeight = config.minBarHeight + heightRange * CGFloat(min(heightMultiplier, 1.0))

                barHeights[i] = newHeight
                barOpacities[i] = 0.6 + (audioInfluence * 0.4)
            }
        }
    }
}

// MARK: - Premium Talking Animation Configuration

struct EnhancedTalkingAnimationConfig: AudioVisualizationConfig {
    let noiseThreshold: CGFloat // Now dynamic - set from user preference
    let maxAnimationScale: CGFloat = 2.8
    let animationSpring: Animation = .interpolatingSpring(stiffness: 400, damping: 20)

    init(noiseThreshold: CGFloat = 0.4) {
        self.noiseThreshold = max(0.01, min(0.8, noiseThreshold)) // Clamp to valid range
    }

    let particleCount: Int = 9
    let particleSpacing: CGFloat = 4
    let minParticleSize: CGFloat = 4
    let maxParticleSize: CGFloat = 16
    let baseOpacity: Double = 0.2
    let maxOpacity: Double = 0.8
}

struct EnhancedTalkingAudioVisualizationView: View {
    @StateObject private var data: AudioVisualizationData
    @State private var dynamicNoiseThreshold: CGFloat = .init(SettingsStore.shared.visualizerNoiseThreshold)

    // Dynamic config that updates with settings
    private var config: EnhancedTalkingAnimationConfig {
        EnhancedTalkingAnimationConfig(noiseThreshold: dynamicNoiseThreshold)
    }

    init(audioLevelPublisher: AnyPublisher<CGFloat, Never>) {
        _data = StateObject(wrappedValue: AudioVisualizationData(audioLevelPublisher: audioLevelPublisher))
    }

    var body: some View {
        HStack(spacing: config.particleSpacing) {
            ForEach(0..<self.config.particleCount, id: \.self) { index in
                PremiumTalkingParticle(
                    audioLevel: self.data.audioLevel,
                    config: self.config,
                    index: index
                )
            }
        }
        .frame(width: CGFloat(config.particleCount) * (config.maxParticleSize + config.particleSpacing) -
            config.particleSpacing)
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            // Update threshold when UserDefaults changes
            let newThreshold = CGFloat(SettingsStore.shared.visualizerNoiseThreshold)
            if newThreshold != self.dynamicNoiseThreshold {
                self.dynamicNoiseThreshold = newThreshold
            }
        }
    }
}

struct PremiumTalkingParticle: View {
    let audioLevel: CGFloat
    let config: EnhancedTalkingAnimationConfig
    let index: Int

    @State private var animationPhase: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var rotationAngle: Double = 0
    @State private var randomOffset: Double = .random(in: 0...2 * Double.pi)
    @State private var animationTrigger: Int = 0
    @State private var lastParticleUpdateTime: TimeInterval = 0
    @State private var isParticleVisible: Bool = true

    private let particleTimer = Timer.publish(every: 0.033, on: .main, in: .common).autoconnect() // 30 FPS

    private var isActive: Bool {
        audioLevel > config.noiseThreshold
    }

    private var particleSize: CGFloat {
        if !isActive { return config.minParticleSize }

        let waveValue = sin(animationPhase + Double(index) * 0.8 + randomOffset)
        let normalizedWave = (waveValue + 1) / 2
        let audioMultiplier = pow(audioLevel, 0.6) * 1.5
        let sizeRange = config.maxParticleSize - config.minParticleSize

        return config.minParticleSize + (sizeRange * CGFloat(normalizedWave) * min(audioMultiplier, 1.0))
    }

    private var particleOpacity: Double {
        if !isActive { return config.baseOpacity }
        let opacityRange = config.maxOpacity - config.baseOpacity
        return config.baseOpacity + (opacityRange * Double(audioLevel))
    }

    var body: some View {
        ZStack {
            // Outer glow ring
            Circle()
                .fill(RadialGradient(
                    gradient: Gradient(colors: [
                        Color.clear,
                        Color.purple.opacity(0.2),
                        Color.indigo.opacity(0.08),
                        Color.clear,
                    ]),
                    center: .center,
                    startRadius: self.particleSize * 0.3,
                    endRadius: self.particleSize * 1.8
                ))
                .frame(width: self.particleSize * 2.5, height: self.particleSize * 2.5)
                .opacity(self.isActive ? 0.6 : 0.1)
                .blur(radius: 2)

            // Main particle
            Circle()
                .fill(AngularGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color.gray.opacity(0.6), location: 0.0),
                        .init(color: Color.purple.opacity(0.7), location: 0.25),
                        .init(color: Color.indigo.opacity(0.8), location: 0.5),
                        .init(color: Color.black.opacity(0.9), location: 0.75),
                        .init(color: Color.gray.opacity(0.6), location: 1.0),
                    ]),
                    center: .center,
                    startAngle: .degrees(self.rotationAngle),
                    endAngle: .degrees(self.rotationAngle + 360)
                ))
                .frame(width: self.particleSize, height: self.particleSize)
                .opacity(self.particleOpacity)
                .scaleEffect(self.pulseScale)
                .overlay(Circle()
                    .fill(RadialGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.3),
                            Color.white.opacity(0.1),
                            Color.clear,
                        ]),
                        center: UnitPoint(x: 0.3, y: 0.3),
                        startRadius: 0,
                        endRadius: self.particleSize * 0.6
                    ))
                    .frame(width: self.particleSize, height: self.particleSize))
                .shadow(color: Color.purple.opacity(0.4), radius: 4, x: 0, y: 2)
                .shadow(color: Color.indigo.opacity(0.3), radius: 8, x: 0, y: 0)
        }
        .animation(.easeInOut(duration: 0.12), value: particleSize)
        .animation(.easeInOut(duration: 0.15), value: particleOpacity)
        .onReceive(particleTimer) { _ in
            if self.isParticleVisible {
                self.updateParticleAnimation()
            }
        }
        .onAppear {
            self.isParticleVisible = true
        }
        .onDisappear {
            self.isParticleVisible = false
        }
    }

    private func updateParticleAnimation() {
        let currentTime = Date().timeIntervalSince1970

        // Simple frame limiting for consistent 30 FPS
        if currentTime - lastParticleUpdateTime < 0.033 { return }
        lastParticleUpdateTime = currentTime

        animationTrigger += 1

        // Real-time responsive animation
        if audioLevel <= config.noiseThreshold { // USE THE USER-CONTROLLABLE THRESHOLD!
            // Complete stillness during silence
            pulseScale = 1.0
            if animationTrigger % 10 == 0 {
                rotationAngle += 0.2
            }
        } else {
            // Fast, responsive animation
            animationPhase += 0.3 // Much faster phase changes
            rotationAngle += 1.5 // Faster rotation
            pulseScale = 1.0 + (audioLevel * 0.15) // More pronounced pulsing
        }
    }
}

// MARK: - Individual Spokenly Bar

struct SpokenlyBar: View {
    let height: CGFloat
    let opacity: Double
    let index: Int
    let config: TalkingAnimationConfig
    let isActive: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: config.barWidth / 2)
            .fill(Color.white)
            .frame(width: config.barWidth, height: height)
            .opacity(opacity)
            .shadow(color: Color.black.opacity(0.2), radius: 1, x: 0, y: 1)
    }
}
