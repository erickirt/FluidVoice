//
//  NotchContentViews.swift
//  Fluid
//
//  Created by Assistant
//

import SwiftUI
import Combine

// MARK: - Observable state for notch content (Singleton)

@MainActor
class NotchContentState: ObservableObject {
    static let shared = NotchContentState()
    
    @Published var transcriptionText: String = ""
    @Published var mode: OverlayMode = .dictation
    @Published var isProcessing: Bool = false  // AI processing state
    
    // Cached transcription lines to avoid recomputing on every render
    @Published private(set) var cachedLine1: String = ""
    @Published private(set) var cachedLine2: String = ""
    
    private init() {}
    
    /// Set AI processing state
    func setProcessing(_ processing: Bool) {
        isProcessing = processing
    }
    
    /// Update transcription and recompute cached lines
    func updateTranscription(_ text: String) {
        guard text != transcriptionText else { return }
        transcriptionText = text
        recomputeTranscriptionLines()
    }
    
    /// Recompute cached transcription lines (called only when text changes)
    private func recomputeTranscriptionLines() {
        let text = transcriptionText
        
        guard !text.isEmpty else {
            cachedLine1 = ""
            cachedLine2 = ""
            return
        }
        
        // Show last ~100 characters
        let maxChars = 100
        let displayText = text.count > maxChars ? String(text.suffix(maxChars)) : text
        
        // Split into words
        let words = displayText.split(separator: " ").map(String.init)
        
        if words.count <= 6 {
            // Short: only line 2
            cachedLine1 = ""
            cachedLine2 = displayText
        } else {
            // Long: split roughly in half
            let midPoint = words.count / 2
            cachedLine1 = words[..<midPoint].joined(separator: " ")
            cachedLine2 = words[midPoint...].joined(separator: " ")
        }
    }
}

// MARK: - Shared Mode Color Helper

extension OverlayMode {
    /// Mode-specific color for notch UI elements
    var notchColor: Color {
        switch self {
        case .dictation:
            return Color.white.opacity(0.85)
        case .rewrite:
            return Color(red: 0.45, green: 0.55, blue: 1.0) // Lighter blue
        case .write:
            return Color(red: 0.4, green: 0.6, blue: 1.0)   // Blue
        case .command:
            return Color(red: 1.0, green: 0.35, blue: 0.35) // Red
        }
    }
}

// MARK: - Shimmer Text (Cursor-style thinking animation)

struct ShimmerText: View {
    let text: String
    let color: Color
    
    @State private var shimmerPhase: CGFloat = 0
    
    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        color.opacity(0.4),
                        color.opacity(0.4),
                        color.opacity(1.0),
                        color.opacity(0.4),
                        color.opacity(0.4)
                    ],
                    startPoint: UnitPoint(x: shimmerPhase - 0.3, y: 0.5),
                    endPoint: UnitPoint(x: shimmerPhase + 0.3, y: 0.5)
                )
            )
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    shimmerPhase = 1.3
                }
            }
    }
}

// MARK: - Expanded View (Main Content) - Minimal Design

struct NotchExpandedView: View {
    let audioPublisher: AnyPublisher<CGFloat, Never>
    @ObservedObject private var contentState = NotchContentState.shared
    
    private var modeColor: Color {
        contentState.mode.notchColor
    }
    
    private var modeLabel: String {
        switch contentState.mode {
        case .dictation: return "Dictate"
        case .rewrite: return "Write"
        case .write: return "Write"
        case .command: return "Command"
        }
    }
    
    private var processingLabel: String {
        switch contentState.mode {
        case .dictation: return "Refining..."
        case .rewrite: return "Thinking..."
        case .write: return "Thinking..."
        case .command: return "Working..."
        }
    }
    
    private var hasTranscription: Bool {
        !contentState.transcriptionText.isEmpty
    }
    
    var body: some View {
        VStack(spacing: 4) {
            // Visualization + Mode label row
            HStack(spacing: 6) {
                NotchWaveformView(
                    audioPublisher: audioPublisher,
                    color: modeColor
                )
                .frame(width: 80, height: 22)
                
                // Mode label - shimmer effect when processing
                if contentState.isProcessing {
                    ShimmerText(text: processingLabel, color: modeColor)
                } else {
                    Text(modeLabel)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(modeColor)
                        .opacity(0.9)
                }
            }
            
            // Transcription preview (single line, minimal)
            if hasTranscription && !contentState.isProcessing {
                Text(contentState.cachedLine2)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 180)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.black)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: hasTranscription)
        .animation(.easeInOut(duration: 0.2), value: contentState.mode)
        .animation(.easeInOut(duration: 0.25), value: contentState.isProcessing)
    }
}

// MARK: - Minimal Notch Waveform (Color-matched)

struct NotchWaveformView: View {
    let audioPublisher: AnyPublisher<CGFloat, Never>
    let color: Color
    
    @StateObject private var data: AudioVisualizationData
    @ObservedObject private var contentState = NotchContentState.shared
    @State private var barHeights: [CGFloat] = Array(repeating: 3, count: 7)
    @State private var glowPhase: CGFloat = 0  // 0 to 1, controls glow intensity
    @State private var glowTimer: Timer? = nil
    @State private var noiseThreshold: CGFloat = CGFloat(SettingsStore.shared.visualizerNoiseThreshold)
    
    private let barCount = 7
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 4
    private let minHeight: CGFloat = 3
    private let maxHeight: CGFloat = 20
    
    // Computed glow values based on phase (sine wave for smooth pulsing)
    private var currentGlowIntensity: CGFloat {
        contentState.isProcessing ? 0.4 + 0.4 * sin(glowPhase * .pi * 2) : 0.4
    }
    
    private var currentGlowRadius: CGFloat {
        contentState.isProcessing ? 2 + 4 * sin(glowPhase * .pi * 2) : 2
    }
    
    private var currentOuterGlowRadius: CGFloat {
        contentState.isProcessing ? 6 * sin(glowPhase * .pi * 2) : 0
    }
    
    init(audioPublisher: AnyPublisher<CGFloat, Never>, color: Color, isProcessing: Bool = false) {
        self.audioPublisher = audioPublisher
        self.color = color
        self._data = StateObject(wrappedValue: AudioVisualizationData(audioLevelPublisher: audioPublisher))
    }
    
    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: barWidth / 2)
                    .fill(color)
                    .frame(width: barWidth, height: barHeights[index])
                    .shadow(color: color.opacity(currentGlowIntensity), radius: currentGlowRadius, x: 0, y: 0)
                    .shadow(color: color.opacity(currentGlowIntensity * 0.5), radius: currentOuterGlowRadius, x: 0, y: 0)
            }
        }
        .onChange(of: data.audioLevel) { level in
            if !contentState.isProcessing {
                updateBars(level: level)
            }
        }
        .onChange(of: contentState.isProcessing) { processing in
            if processing {
                setStaticProcessingBars()
                startGlowAnimation()
            } else {
                stopGlowAnimation()
            }
        }
        .onAppear {
            if contentState.isProcessing {
                setStaticProcessingBars()
                startGlowAnimation()
            } else {
                updateBars(level: 0)
            }
        }
        .onDisappear {
            stopGlowAnimation()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            // Update threshold when user changes sensitivity setting
            let newThreshold = CGFloat(SettingsStore.shared.visualizerNoiseThreshold)
            if newThreshold != noiseThreshold {
                noiseThreshold = newThreshold
            }
        }
    }
    
    private func startGlowAnimation() {
        stopGlowAnimation() // Clean up any existing timer
        glowPhase = 0
        
        // Timer-based animation for explicit control
        glowTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            withAnimation(.linear(duration: 1.0 / 30.0)) {
                glowPhase += 1.0 / 30.0 / 1.5  // Complete cycle in 1.5 seconds
                if glowPhase >= 1.0 {
                    glowPhase = 0
                }
            }
        }
    }
    
    private func stopGlowAnimation() {
        glowTimer?.invalidate()
        glowTimer = nil
        glowPhase = 0
    }
    
    private func setStaticProcessingBars() {
        // Set bars to a nice static shape (taller in center)
        withAnimation(.easeInOut(duration: 0.3)) {
            for i in 0..<barCount {
                let centerDistance = abs(CGFloat(i) - CGFloat(barCount - 1) / 2)
                let centerFactor = 1.0 - (centerDistance / CGFloat(barCount / 2)) * 0.4
                barHeights[i] = minHeight + (maxHeight - minHeight) * 0.5 * centerFactor
            }
        }
    }
    
    private func updateBars(level: CGFloat) {
        let normalizedLevel = min(max(level, 0), 1)
        let isActive = normalizedLevel > noiseThreshold  // Use user's sensitivity setting
        
        withAnimation(.spring(response: 0.15, dampingFraction: 0.6)) {
            for i in 0..<barCount {
                let centerDistance = abs(CGFloat(i) - CGFloat(barCount - 1) / 2)
                let centerFactor = 1.0 - (centerDistance / CGFloat(barCount / 2)) * 0.4
                
                if isActive {
                    // Scale audio level relative to threshold for smoother response
                    let adjustedLevel = (normalizedLevel - noiseThreshold) / (1.0 - noiseThreshold)
                    let randomVariation = CGFloat.random(in: 0.7...1.0)
                    barHeights[i] = minHeight + (maxHeight - minHeight) * adjustedLevel * centerFactor * randomVariation
                } else {
                    // Complete stillness when below threshold
                    barHeights[i] = minHeight
                }
            }
        }
    }
}

// MARK: - Compact Views (Small States)

struct NotchCompactLeadingView: View {
    @ObservedObject private var contentState = NotchContentState.shared
    @State private var isPulsing = false
    
    var body: some View {
        Image(systemName: "waveform")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(contentState.mode.notchColor)
            .scaleEffect(isPulsing ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
            .onDisappear { isPulsing = false }
    }
}

struct NotchCompactTrailingView: View {
    @ObservedObject private var contentState = NotchContentState.shared
    @State private var isPulsing = false
    
    var body: some View {
        Circle()
            .fill(contentState.mode.notchColor)
            .frame(width: 5, height: 5)
            .opacity(isPulsing ? 0.5 : 1.0)
            .scaleEffect(isPulsing ? 0.85 : 1.0)
            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
            .onDisappear { isPulsing = false }
    }
}
