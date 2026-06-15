//
//  WelcomeView.swift
//  fluid
//
//  Welcome and setup guide view
//

import AppKit
import AVFoundation
import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var appServices: AppServices
    private var asr: ASRService { self.appServices.asr }
    @ObservedObject private var settings = SettingsStore.shared
    @Binding var selectedSidebarItem: SidebarItem?
    @Binding var playgroundUsed: Bool
    var isTranscriptionFocused: FocusState<Bool>.Binding
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme

    let accessibilityEnabled: Bool
    let stopAndProcessTranscription: () async -> Void
    let startRecording: () -> Void
    let openAccessibilitySettings: () -> Void
    let restartApp: () -> Void

    private var commandModeShortcutDisplay: String {
        self.settings.commandModeHotkeyShortcut.displayString
    }

    private var writeModeShortcutDisplay: String {
        self.settings.rewriteModeHotkeyShortcut.displayString
    }

    private let playgroundSectionID = "welcome-playground-section"

    private var commandModeColor: Color { self.theme.palette.warning }
    private var editModeColor: Color { self.theme.palette.accent }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    HStack(spacing: 10) {
                        Image(systemName: "book.fill")
                            .font(self.theme.typography.titleIcon)
                            .foregroundStyle(self.theme.palette.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text((self.asr.isAsrReady || self.asr.modelsExistOnDisk) ? "Getting Started" : "Welcome to FluidVoice")
                                .font(self.theme.typography.title)
                            Text("Talk anywhere. FluidVoice types for you.")
                                .font(self.theme.typography.bodySmall)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.bottom, 4)

                    // Quick Setup Checklist
                    ThemedCard(style: .prominent) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                Label("Quick Setup", systemImage: "checkmark.circle.fill")
                                    .font(self.theme.typography.sectionTitle)
                                    .foregroundStyle(self.theme.palette.accent)

                                Spacer()

                                Button {
                                    self.settings.resetOnboardingProgress()
                                    self.playgroundUsed = false
                                } label: {
                                    Label("Run Onboarding Again", systemImage: "arrow.counterclockwise")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                SetupStepView(
                                    step: 1,
                                    // Consider model step complete if ready OR downloaded (even if not loaded)
                                    title: (self.asr.isAsrReady || self.asr.modelsExistOnDisk) ? "Voice Model Ready" : "Download Voice Model",
                                    description: self.asr.isAsrReady
                                        ? "Speech recognition model is loaded and ready"
                                        : (self.asr.modelsExistOnDisk
                                            ? "Model downloaded, will load when needed"
                                            : "Download the AI model for offline voice transcription (~500MB)"),
                                    status: (self.asr.isAsrReady || self.asr.modelsExistOnDisk) ? .completed : .pending,
                                    action: {
                                        self.selectedSidebarItem = .voiceEngine
                                    },
                                    actionButtonTitle: "Go to Voice Engine",
                                    showActionButton: !(self.asr.isAsrReady || self.asr.modelsExistOnDisk)
                                )

                                SetupStepView(
                                    step: 2,
                                    title: self.asr.micStatus == .authorized ? "Microphone Permission Granted" : "Grant Microphone Permission",
                                    description: self.asr.micStatus == .authorized
                                        ? "FluidVoice has access to your microphone"
                                        : "Allow FluidVoice to access your microphone for voice input",
                                    status: self.asr.micStatus == .authorized ? .completed : .pending,
                                    action: {
                                        if self.asr.micStatus == .notDetermined {
                                            self.asr.requestMicAccess()
                                        } else if self.asr.micStatus == .denied {
                                            self.asr.openSystemSettingsForMic()
                                        }
                                    },
                                    actionButtonTitle: self.asr.micStatus == .notDetermined ? "Grant Access" : "Open Settings",
                                    showActionButton: self.asr.micStatus != .authorized
                                )

                                SetupStepView(
                                    step: 3,
                                    title: self.accessibilityEnabled ? "Accessibility Enabled" : "Enable Accessibility",
                                    description: self.accessibilityEnabled
                                        ? "Accessibility permission granted for typing into apps"
                                        : "Grant accessibility permission to type text into other apps",
                                    status: self.accessibilityEnabled ? .completed : .pending,
                                    action: {
                                        self.openAccessibilitySettings()
                                    },
                                    actionButtonTitle: "Open Settings",
                                    showActionButton: !self.accessibilityEnabled
                                )

                                SetupStepView(
                                    step: 4,
                                    title: self.settings.isAIConfigured ? "AI Enhancement Configured" : "Set Up AI Enhancement (Optional)",
                                    description: self.settings.isAIConfigured
                                        ? "AI-powered text enhancement is ready to use"
                                        : "Configure API keys for AI-powered text enhancement",
                                    status: self.settings.isAIConfigured ? .completed : .pending,
                                    action: {
                                        self.selectedSidebarItem = .aiEnhancements
                                    },
                                    actionButtonTitle: "Configure AI"
                                )

                                SetupStepView(
                                    step: 5,
                                    title: self.playgroundUsed ? "Setup Tested Successfully" : "Test Your Setup",
                                    description: self.playgroundUsed
                                        ? "You've successfully tested voice transcription"
                                        : "Try the playground below to test your complete setup",
                                    status: self.playgroundUsed ? .completed : .pending,
                                    action: {
                                        withAnimation(.easeInOut(duration: 0.25)) {
                                            proxy.scrollTo(self.playgroundSectionID, anchor: .top)
                                        }
                                        self.isTranscriptionFocused.wrappedValue = true
                                    },
                                    actionButtonTitle: "Go to Playground",
                                    showActionButton: !self.playgroundUsed
                                )
                                .id("playground-step-\(self.playgroundUsed)")
                            }
                        }
                        .padding(14)
                    }

                    // Test Playground
                    ThemedCard(hoverEffect: false) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Test Playground")
                                            .font(self.theme.typography.sectionTitle)
                                        Text("Click record, speak, and see your transcription")
                                            .font(self.theme.typography.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: "text.bubble")
                                        .font(self.theme.typography.titleIcon)
                                }

                                Spacer()

                                if self.asr.isRunning {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(.red)
                                            .frame(width: 6, height: 6)
                                        Text("Recording...")
                                            .font(self.theme.typography.captionStrong)
                                            .foregroundStyle(.red)
                                    }
                                } else if !self.asr.finalText.isEmpty {
                                    Text("\(self.asr.finalText.count) characters")
                                        .font(self.theme.typography.caption)
                                        .foregroundStyle(.secondary)
                                }

                                if !self.asr.finalText.isEmpty {
                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(self.asr.finalText, forType: .string)
                                    } label: {
                                        Label("Copy", systemImage: "doc.on.doc")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }

                            if self.settings.selectedSpeechModel == .parakeetTDT || self.settings.selectedSpeechModel == .parakeetTDTv2 {
                                HStack(spacing: 6) {
                                    Image(systemName: "text.magnifyingglass")
                                        .font(self.theme.typography.caption)
                                        .foregroundStyle(self.theme.palette.accent)
                                    Text(self.asr.wordBoostStatusText)
                                        .font(self.theme.typography.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(self.theme.palette.contentBackground.opacity(0.6))
                                )
                            }

                            VStack(alignment: .leading, spacing: 12) {
                                // Recording Control
                                VStack(spacing: 10) {
                                    Button {
                                        if self.asr.isRunning {
                                            Task {
                                                await self.stopAndProcessTranscription()
                                            }
                                        } else {
                                            self.startRecording()
                                            self.playgroundUsed = true
                                            SettingsStore.shared.playgroundUsed = true
                                        }
                                    } label: {
                                        HStack {
                                            Image(systemName: self.asr.isRunning ? "stop.fill" : "mic.fill")
                                            Text(self.asr.isRunning ? "Stop Recording" : "Start Recording")
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                    .fluidButton(.primary, size: .large, isRecording: self.asr.isRunning)
                                    .buttonHoverEffect()
                                    .scaleEffect(!self.reduceMotion && self.asr.isRunning ? 1.02 : 1.0)
                                    .animation(self.reduceMotion ? nil : .spring(response: 0.3), value: self.asr.isRunning)
                                    .disabled(!self.asr.isAsrReady && !self.asr.isRunning)

                                    if !self.asr.isRunning && !self.asr.finalText.isEmpty {
                                        Button("Clear Results") {
                                            self.asr.finalText = ""
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }
                                }

                                // Text Area
                                VStack(alignment: .leading, spacing: 8) {
                                    TextEditor(text: Binding(
                                        get: { self.asr.finalText },
                                        set: { self.asr.finalText = $0 }
                                    ))
                                    .font(self.theme.typography.body)
                                    .focused(self.isTranscriptionFocused)
                                    .frame(height: 140)
                                    .padding(10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(
                                                self.asr.isRunning ? self.theme.palette.accent.opacity(0.06) : self.theme.palette.cardBackground
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .strokeBorder(
                                                        self.asr.isRunning ? self.theme.palette.accent.opacity(0.4) : self.theme.palette.cardBorder.opacity(0.6),
                                                        lineWidth: self.asr.isRunning ? 2 : 1
                                                    )
                                            )
                                    )
                                    .scrollContentBackground(.hidden)
                                    .overlay(
                                        VStack(spacing: 8) {
                                            if self.asr.isRunning {
                                                Image(systemName: "waveform")
                                                    .font(self.theme.typography.titleIcon)
                                                    .foregroundStyle(self.theme.palette.accent)
                                                Text("Listening... Speak now!")
                                                    .font(self.theme.typography.bodySmallStrong)
                                                    .foregroundStyle(self.theme.palette.accent)
                                                Text("Transcription will appear when you stop recording")
                                                    .font(self.theme.typography.caption)
                                                    .foregroundStyle(self.theme.palette.accent.opacity(0.7))
                                            } else if self.asr.finalText.isEmpty {
                                                Image(systemName: "text.bubble")
                                                    .font(self.theme.typography.titleIcon)
                                                    .foregroundStyle(.secondary.opacity(0.5))
                                                Text("Ready to test!")
                                                    .font(self.theme.typography.bodySmallStrong)
                                                Text("Click 'Start Recording' or press your hotkey")
                                                    .font(self.theme.typography.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .allowsHitTesting(false)
                                    )

                                    if !self.asr.finalText.isEmpty {
                                        HStack(spacing: 8) {
                                            Button {
                                                NSPasteboard.general.clearContents()
                                                NSPasteboard.general.setString(self.asr.finalText, forType: .string)
                                            } label: {
                                                Label("Copy Text", systemImage: "doc.on.doc")
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .tint(self.theme.palette.accent)
                                            .controlSize(.small)

                                            Button("Clear & Test Again") {
                                                self.asr.finalText = ""
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)

                                            Spacer()
                                        }
                                    }
                                }
                            }
                        }
                        .padding(16)
                    }
                    .id(self.playgroundSectionID)

                    // Secondary guidance
                    ThemedCard(style: .subtle) {
                        VStack(alignment: .leading, spacing: 12) {
                            DisclosureGroup {
                                VStack(alignment: .leading, spacing: 10) {
                                    self.howToStep(number: 1, title: "Start Recording", description: "Press your hotkey (default: Right Option/Alt) or click the button")
                                    self.howToStep(number: 2, title: "Speak Clearly", description: "Speak naturally - works best in quiet environments")
                                    self.howToStep(number: 3, title: "Auto-Type Result", description: "Transcription is automatically typed into your focused app")
                                }
                                .padding(.top, 8)
                            } label: {
                                Label("How to Use", systemImage: "play.fill")
                                    .font(self.theme.typography.sectionTitle)
                                    .foregroundStyle(self.theme.palette.accent)
                            }

                            Divider().opacity(0.2)

                            DisclosureGroup {
                                self.commandModeGuide
                                    .padding(.top, 8)
                            } label: {
                                HStack(spacing: 8) {
                                    Label("Command Mode", systemImage: "terminal.fill")
                                        .font(self.theme.typography.sectionTitle)
                                        .foregroundStyle(self.commandModeColor)
                                    self.featureBadge("New", color: self.commandModeColor)
                                    self.featureBadge("Alpha", color: self.commandModeColor.opacity(0.75))
                                }
                            }

                            Divider().opacity(0.2)

                            DisclosureGroup {
                                self.editModeGuide
                                    .padding(.top, 8)
                            } label: {
                                HStack(spacing: 8) {
                                    Label("Edit Mode", systemImage: "pencil.and.outline")
                                        .font(self.theme.typography.sectionTitle)
                                        .foregroundStyle(self.editModeColor)
                                    self.featureBadge("New", color: self.editModeColor)
                                }
                            }
                        }
                        .padding(12)
                    }
                }
                .padding(16)
            }
        }
        .onAppear {
            // CRITICAL FIX: Refresh microphone and model status immediately on appear
            // This prevents the Quick Setup from showing stale status before ASRService.initialize() runs
            Task { @MainActor in
                // Check microphone status without triggering the full initialize() delay
                self.asr.micStatus = AVCaptureDevice.authorizationStatus(for: .audio)

                // Check if models exist on disk (async for accurate detection with AppleSpeechAnalyzerProvider)
                await self.asr.checkIfModelsExistAsync()
            }
        }
    }

    // MARK: - Helper Views

    private var commandModeGuide: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Control your Mac with voice commands. Execute terminal commands, open apps, and more.")
                    .font(self.theme.typography.bodySmall)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Open") {
                    self.selectedSidebarItem = .commandMode
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Getting Started")
                    .font(self.theme.typography.bodySmallStrong)
                    .foregroundStyle(self.commandModeColor)

                HStack(spacing: 4) {
                    Text("Press")
                    self.keyboardBadge(self.commandModeShortcutDisplay)
                    Text("to open, speak your command, then press again to send.")
                }
                .font(self.theme.typography.caption)
                .foregroundStyle(.primary.opacity(0.8))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Examples")
                    .font(self.theme.typography.bodySmallStrong)
                    .foregroundStyle(self.commandModeColor)
                self.commandModeExample(icon: "folder", text: "\"List files in my Downloads folder\"")
                self.commandModeExample(icon: "plus.rectangle.on.folder", text: "\"Create a folder called Projects on Desktop\"")
                self.commandModeExample(icon: "network", text: "\"What's my IP address?\"")
                self.commandModeExample(icon: "safari", text: "\"Open Safari\"")
            }

            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(self.theme.typography.captionSmall)
                    .foregroundStyle(self.commandModeColor)
                Text("AI can make mistakes. Avoid destructive commands.")
                    .font(self.theme.typography.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var editModeGuide: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AI-powered editing assistant. Write fresh content or edit selected text with voice.")
                    .font(self.theme.typography.bodySmall)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Open AI Settings") {
                    self.selectedSidebarItem = .aiEnhancements
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Create New Text")
                        .font(self.theme.typography.bodySmallStrong)
                        .foregroundStyle(self.editModeColor)

                    HStack(spacing: 4) {
                        Text("Press")
                        self.keyboardBadge(self.writeModeShortcutDisplay)
                        Text("and speak what you want to write.")
                    }
                    .font(self.theme.typography.caption)
                    .foregroundStyle(.primary.opacity(0.8))

                    self.writeModeExample(text: "\"Write an email asking for time off\"")
                    self.writeModeExample(text: "\"Draft a thank you note\"")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Edit Selected Text")
                        .font(self.theme.typography.bodySmallStrong)
                        .foregroundStyle(self.editModeColor)

                    HStack(spacing: 4) {
                        Text("Select text first, then press")
                        self.keyboardBadge(self.writeModeShortcutDisplay)
                        Text("and speak your instruction.")
                    }
                    .font(self.theme.typography.caption)
                    .foregroundStyle(.primary.opacity(0.8))

                    self.writeModeExample(text: "\"Make this more formal\"")
                    self.writeModeExample(text: "\"Fix grammar and spelling\"")
                    self.writeModeExample(text: "\"Summarize this\"")
                }
            }
        }
    }

    private func howToStep(number: Int, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(self.theme.palette.accent.opacity(0.15))
                    .frame(width: 28, height: 28)
                Text("\(number)")
                    .font(self.theme.typography.captionStrong)
                    .foregroundStyle(self.theme.palette.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(self.theme.typography.bodyStrong)
                Text(description)
                    .font(self.theme.typography.bodySmall)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func featureBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(self.theme.typography.badge)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private func keyboardBadge(_ text: String) -> some View {
        Text(text)
            .font(self.theme.typography.captionStrong)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(self.theme.palette.cardBackground.opacity(0.7), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private func commandModeExample(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(self.theme.typography.captionSmall)
                .foregroundStyle(self.commandModeColor.opacity(0.8))
                .frame(width: 14)
            Text(text)
                .font(self.theme.typography.caption)
                .foregroundStyle(.primary.opacity(0.8))
        }
    }

    private func writeModeExample(text: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(self.editModeColor.opacity(0.6))
                .frame(width: 4, height: 4)
            Text(text)
                .font(self.theme.typography.caption)
                .foregroundStyle(.primary.opacity(0.8))
        }
    }
}

struct OnboardingFlowView: View {
    @EnvironmentObject var appServices: AppServices
    private var asr: ASRService { self.appServices.asr }
    @ObservedObject private var settings = SettingsStore.shared

    @Binding var currentStep: Int
    let accessibilityEnabled: Bool
    let markAISkipped: () -> Void
    let markPlaygroundValidated: () -> Void
    let finishOnboarding: () -> Void
    let openAccessibilitySettings: () -> Void
    let restartApp: () -> Void
    let menuBarManager: MenuBarManager
    let theme: AppTheme

    @State private var preferredLanguageChoice: PreferredLanguageChoice = .englishOnly

    private enum PreferredLanguageChoice: String, CaseIterable, Identifiable {
        case englishOnly
        case multipleLanguages
        case other

        var id: String { self.rawValue }

        var title: String {
            switch self {
            case .englishOnly:
                return "English only"
            case .multipleLanguages:
                return "Multiple languages"
            case .other:
                return "More options"
            }
        }

        var subtitle: String {
            switch self {
            case .englishOnly:
                return "Uses Parakeet TDT v2 or Flash"
            case .multipleLanguages:
                return "Uses Parakeet TDT v3 or Cohere"
            case .other:
                return "Whisper and manual choices"
            }
        }
    }

    private enum Step: Int, CaseIterable {
        case landing = 0
        case voiceModel = 1
        case microphone = 2
        case accessibility = 3
        case aiEnhancement = 4
        case playground = 5

        var title: String {
            switch self {
            case .landing:
                return "Welcome"
            case .voiceModel:
                return "Download Voice Model"
            case .microphone:
                return "Grant Microphone Access"
            case .accessibility:
                return "Enable Accessibility"
            case .aiEnhancement:
                return "Set Up AI Enhancement"
            case .playground:
                return "Run Playground Test"
            }
        }

        var subtitle: String {
            switch self {
            case .landing:
                return "Talk anywhere. FluidVoice types for you."
            case .voiceModel:
                return CPUArchitecture.isAppleSilicon
                    ? "Choose the best voice model for how you speak. Download it once to continue."
                    : "Recommended for your Mac: Whisper. Download it once to continue."
            case .microphone:
                return "Allow FluidVoice to capture audio from your microphone."
            case .accessibility:
                return "Allow FluidVoice to type transcriptions into other apps."
            case .aiEnhancement:
                return "Optional: Configure AI post-processing or skip this step."
            case .playground:
                return "Record a quick sample to validate your setup before finishing."
            }
        }
    }

    private var step: Step {
        Step(rawValue: self.currentStep) ?? .voiceModel
    }

    private var progressValue: Double {
        Double(self.step.rawValue) / Double(Step.allCases.count - 1)
    }

    private var recommendedOnboardingModel: SettingsStore.SpeechModel {
        if CPUArchitecture.isAppleSilicon {
            switch self.preferredLanguageChoice {
            case .englishOnly:
                return .parakeetTDTv2
            case .multipleLanguages, .other:
                return .parakeetTDT
            }
        }
        return .whisperBase
    }

    private var recommendedOnboardingModelDisplayName: String {
        self.recommendedOnboardingModel.displayName
    }

    private var recommendedOnboardingModels: [SettingsStore.SpeechModel] {
        if CPUArchitecture.isAppleSilicon {
            switch self.preferredLanguageChoice {
            case .englishOnly:
                return [.parakeetTDTv2, .parakeetRealtime].filter { SettingsStore.SpeechModel.availableModels.contains($0) }
            case .multipleLanguages:
                return [.parakeetTDT, .cohereTranscribeSixBit].filter { SettingsStore.SpeechModel.availableModels.contains($0) }
            case .other:
                break
            }
        }
        return [self.recommendedOnboardingModel]
    }

    private var recommendedModelReasonText: String {
        if CPUArchitecture.isAppleSilicon {
            switch self.preferredLanguageChoice {
            case .englishOnly:
                return "Best if you mainly speak English. Parakeet TDT v2 is the stable default. Parakeet Flash is also available in beta for live word-by-word dictation."
            case .multipleLanguages:
                return "Best if you switch languages. Parakeet TDT v3 is the lighter default, and Cohere is the higher-accuracy option."
            case .other:
                return "Choose a different model below if neither of the default language paths fits."
            }
        }
        return "Best for Intel Macs: dependable Whisper quality with broad compatibility."
    }

    private var onboardingModelOptions: [SettingsStore.SpeechModel] {
        let candidates: [SettingsStore.SpeechModel] = CPUArchitecture.isAppleSilicon
            ? [.parakeetTDT, .cohereTranscribeSixBit, .parakeetRealtime, .parakeetTDTv2, .whisperBase, .whisperSmall]
            : [.whisperBase, .whisperTiny, .whisperSmall, .whisperMedium]

        var seenModelIDs = Set<String>()
        return candidates.filter { model in
            guard SettingsStore.SpeechModel.availableModels.contains(model) else { return false }
            return seenModelIDs.insert(model.id).inserted
        }
    }

    private var onboardingAlternativeModels: [SettingsStore.SpeechModel] {
        let filtered = self.onboardingModelOptions.filter { $0 != self.recommendedOnboardingModel }
        guard self.shouldShowLanguageChoice else {
            return filtered
        }
        switch self.preferredLanguageChoice {
        case .englishOnly:
            return []
        case .multipleLanguages:
            return []
        case .other:
            return filtered.filter { model in
                model != .parakeetTDT && model != .parakeetTDTv2 && model != .parakeetRealtime && model != .cohereTranscribeSixBit
            }
        }
    }

    private var shouldShowLanguageChoice: Bool {
        CPUArchitecture.isAppleSilicon
    }

    private var showsMappedRecommendedModel: Bool {
        !self.shouldShowLanguageChoice || self.preferredLanguageChoice != .other
    }

    private var shouldShowAlternativeModels: Bool {
        if self.shouldShowLanguageChoice {
            return self.preferredLanguageChoice == .other
        }
        return true
    }

    private var isRecommendedModelSelected: Bool {
        self.recommendedOnboardingModels.contains(self.settings.selectedSpeechModel)
    }

    private var isRecommendedModelDownloaded: Bool {
        self.isOnboardingModelDownloaded(self.recommendedOnboardingModel)
    }

    private var isPreparingRecommendedModel: Bool {
        self.isPreparingOnboardingModel(self.recommendedOnboardingModel)
    }

    private var isRecommendedModelReady: Bool {
        self.isOnboardingModelReady(self.recommendedOnboardingModel)
    }

    private var isVoiceModelReady: Bool {
        self.isOnboardingModelReady(self.settings.selectedSpeechModel)
    }

    private var isMicrophoneReady: Bool {
        self.asr.micStatus == .authorized
    }

    private var isAccessibilityReady: Bool {
        self.accessibilityEnabled
    }

    private var isAIReady: Bool {
        self.settings.onboardingAISkipped || DictationAIPostProcessingGate.isConfigured()
    }

    private var isPlaygroundReady: Bool {
        self.settings.onboardingPlaygroundValidated
    }

    private var onboardingShortcutDisplay: String {
        let display = self.settings.hotkeyShortcut.displayString.trimmingCharacters(in: .whitespacesAndNewlines)
        return display.isEmpty ? "your shortcut" : display
    }

    private var canContinue: Bool {
        switch self.step {
        case .landing:
            return true
        case .voiceModel:
            return self.isVoiceModelReady
        case .microphone:
            return self.isMicrophoneReady
        case .accessibility:
            return self.isAccessibilityReady
        case .aiEnhancement:
            return self.isAIReady
        case .playground:
            return self.isPlaygroundReady
        }
    }

    private var primaryButtonTitle: String {
        switch self.step {
        case .landing:
            return "Get Started"
        case .playground:
            return "Finish Setup"
        default:
            return "Continue"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if self.step == .landing {
                self.stepContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                self.header
                Divider()
                self.stepContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Divider()
                self.footer
            }
        }
        .background {
            ZStack {
                self.theme.palette.windowBackground
                    .opacity(0.98)
                    .ignoresSafeArea()

                Rectangle()
                    .fill(self.theme.materials.window)
                    .opacity(0.75)
                    .ignoresSafeArea()
            }
        }
        .onAppear {
            self.syncPreferredLanguageChoiceWithSelectedModel()
            Task { @MainActor in
                self.asr.micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                await self.asr.checkIfModelsExistAsync()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            self.asr.micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Welcome to FluidVoice")
                .font(self.theme.typography.title)
                .foregroundStyle(self.theme.palette.primaryText)

            Text(self.step.subtitle)
                .font(self.theme.typography.bodySmall)
                .foregroundStyle(self.theme.palette.secondaryText)

            HStack {
                Text("Step \(self.step.rawValue + 1) of \(Step.allCases.count)")
                    .font(self.theme.typography.captionStrong)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(self.step.title)
                    .font(self.theme.typography.captionStrong)
                    .foregroundStyle(self.theme.palette.accent)
            }

            ProgressView(value: self.progressValue)
                .tint(self.theme.palette.accent)
        }
        .padding(24)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch self.step {
        case .landing:
            self.landingStep
        case .voiceModel:
            self.voiceModelStep
        case .microphone:
            self.microphoneStep
        case .accessibility:
            self.accessibilityStep
        case .aiEnhancement:
            self.aiEnhancementStep
        case .playground:
            self.playgroundStep
        }
    }

    private var landingStep: some View {
        ScrollView {
            let landing = self.theme.metrics.onboardingSurface.landing
            let tileWidth = (landing.contentWidth - (landing.tileSpacing * 2)) / 3
            let tileColumns = Array(
                repeating: GridItem(.fixed(tileWidth), spacing: landing.tileSpacing, alignment: .top),
                count: 3
            )

            VStack(alignment: .leading, spacing: self.theme.metrics.onboardingSurface.landing.sectionSpacing) {
                FluidOnboardingLandingHero(
                    eyebrow: "FluidVoice",
                    title: "Say it once. Use it anywhere.",
                    statement: "FluidVoice turns your speech into clean, ready-to-use text across your Mac, with local dictation first and optional AI polish when you want it.",
                    systemImage: "waveform.and.mic"
                ) {
                    Button("Get Started") {
                        self.goNext()
                    }
                    .fluidOnboardingProminentButton(controlSize: .large)
                    .keyboardShortcut(.defaultAction)
                }

                LazyVGrid(
                    columns: tileColumns,
                    alignment: .leading,
                    spacing: self.theme.metrics.onboardingSurface.landing.tileSpacing
                ) {
                    FluidOnboardingValueTile(
                        systemImage: "keyboard",
                        title: "Types where you work",
                        description: "Dictate into Notes, browsers, chat, docs, and editors."
                    )
                    FluidOnboardingValueTile(
                        systemImage: "lock",
                        title: "Local-first setup",
                        description: "Prepare a voice model once and keep core dictation on your Mac."
                    )
                    FluidOnboardingValueTile(
                        systemImage: "wand.and.stars",
                        title: "Cleaner drafts",
                        description: "Turn rough speech into polished text when enhancement is enabled."
                    )
                }

                FluidOnboardingChecklistPanel(title: "Setup takes a few minutes") {
                    FluidOnboardingChecklistRow(systemImage: "cpu", text: "Choose and prepare a voice model")
                    FluidOnboardingChecklistRow(systemImage: "mic", text: "Allow microphone access")
                    FluidOnboardingChecklistRow(systemImage: "keyboard.badge.eye", text: "Allow FluidVoice to type into apps")
                    FluidOnboardingChecklistRow(systemImage: "text.bubble", text: "Run one quick test")
                }
            }
            .frame(width: landing.contentWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(24)
        }
        .defaultScrollAnchor(.center)
    }

    private var voiceModelStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ThemedCard(style: .standard) {
                    VStack(alignment: .leading, spacing: 14) {
                        if self.shouldShowLanguageChoice {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Preferred language")
                                    .font(self.theme.typography.bodyStrong)
                                    .foregroundStyle(self.theme.palette.primaryText)

                                Text("Pick the path that matches how you usually speak. You can change models later.")
                                    .font(self.theme.typography.caption)
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 10) {
                                    ForEach(PreferredLanguageChoice.allCases) { option in
                                        self.preferredLanguageOptionCard(for: option)
                                    }
                                }
                            }

                            Divider().padding(.vertical, 2)
                        }

                        HStack(spacing: 10) {
                            Image(systemName: self.isVoiceModelReady ? "checkmark.circle.fill" : "cpu")
                                .foregroundStyle(self.isVoiceModelReady ? self.theme.palette.success : self.theme.palette.accent)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(self.recommendedModelHeadline)
                                    .font(self.theme.typography.bodyStrong)
                                    .foregroundStyle(self.theme.palette.primaryText)

                                Text(self.recommendedModelReasonText)
                                    .font(self.theme.typography.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }

                        if self.shouldShowLanguageChoice && self.recommendedOnboardingModels.count > 1 {
                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), spacing: 10, alignment: .top),
                                    GridItem(.flexible(), spacing: 10, alignment: .top),
                                ],
                                spacing: 10
                            ) {
                                ForEach(self.recommendedOnboardingModels) { model in
                                    self.onboardingRecommendedModelCard(for: model)
                                }
                            }
                        } else if self.showsMappedRecommendedModel {
                            HStack(spacing: 10) {
                                Label(self.recommendedOnboardingModel.downloadSize, systemImage: "internaldrive")
                                    .font(self.theme.typography.caption)
                                    .foregroundStyle(.secondary)

                                Text(self.recommendedOnboardingModel.languageSupport)
                                    .font(self.theme.typography.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let supportedLanguageCodes = self.recommendedOnboardingModel.supportedLanguageCodes {
                                Text(supportedLanguageCodes)
                                    .font(self.theme.typography.captionSmall)
                                    .foregroundStyle(.secondary)
                            }

                            if let supportedLanguageNames = self.recommendedOnboardingModel.supportedLanguageNames {
                                Text("Supported languages: \(supportedLanguageNames)")
                                    .font(self.theme.typography.captionSmall)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if self.isPreparingRecommendedModel {
                            VStack(alignment: .leading, spacing: 6) {
                                if self.asr.isDownloadingModel, let progress = self.asr.downloadProgress {
                                    if progress >= 0.82 {
                                        HStack(spacing: 8) {
                                            ProgressView()
                                                .controlSize(.small)
                                            Text("Finalizing download and loading model…")
                                                .font(self.theme.typography.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    } else {
                                        ProgressView(value: progress)
                                            .tint(self.theme.palette.accent)
                                        Text("Downloading \(Int(progress * 100))%")
                                            .font(self.theme.typography.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                } else {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                            .controlSize(.small)
                                        Text("Loading model…")
                                            .font(self.theme.typography.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }

                        HStack(spacing: 10) {
                            if self.shouldShowLanguageChoice && self.recommendedOnboardingModels.count > 1 {
                                Text(
                                    self.preferredLanguageChoice == .englishOnly
                                        ? "Choose either FluidVoice-recommended English model."
                                        : "Choose either FluidVoice-recommended multilingual model."
                                )
                                .font(self.theme.typography.captionStrong)
                                .foregroundStyle(.secondary)
                            } else if self.isRecommendedModelReady {
                                Label(
                                    "Model downloaded and loaded",
                                    systemImage: "checkmark.seal.fill"
                                )
                                .font(self.theme.typography.captionStrong)
                                .foregroundStyle(self.theme.palette.success)
                            } else if self.isRecommendedModelDownloaded {
                                Label(
                                    self.isRecommendedModelSelected ? "Model downloaded. Click to finish loading." : "Model downloaded",
                                    systemImage: "arrow.triangle.2.circlepath"
                                )
                                .font(self.theme.typography.captionStrong)
                                .foregroundStyle(.secondary)
                            } else {
                                Label("Model not downloaded yet", systemImage: "arrow.down.circle")
                                    .font(self.theme.typography.captionStrong)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if self.shouldShowLanguageChoice && self.recommendedOnboardingModels.count > 1 {
                                EmptyView()
                            } else if self.preferredLanguageChoice == .other && self.shouldShowLanguageChoice {
                                Text("Choose a model from the options below.")
                                    .font(self.theme.typography.captionStrong)
                                    .foregroundStyle(.secondary)
                            } else {
                                Button(self.onboardingModelActionButtonTitle(for: self.recommendedOnboardingModel)) {
                                    self.prepareOnboardingModel(self.recommendedOnboardingModel)
                                }
                                .fluidOnboardingProminentButton()
                                .disabled(self.asr.isRunning || self.isPreparingRecommendedModel || self.isRecommendedModelReady)
                            }
                        }

                        if self.isVoiceModelReady && !self.isRecommendedModelSelected && self.preferredLanguageChoice != .other {
                            Text("A different model is already configured. You can continue, or switch to the recommended model.")
                                .font(self.theme.typography.caption)
                                .foregroundStyle(.secondary)
                        }

                        if self.shouldShowAlternativeModels && !self.onboardingAlternativeModels.isEmpty {
                            Divider().padding(.vertical, 2)

                            Text("More model options")
                                .font(self.theme.typography.bodySmallStrong)
                                .foregroundStyle(self.theme.palette.primaryText)

                            VStack(spacing: 8) {
                                ForEach(Array(self.onboardingAlternativeModels.prefix(3))) { model in
                                    self.onboardingModelOptionRow(for: model)
                                }
                            }
                        }

                        Text("You can switch models later in Voice Engine settings.")
                            .font(self.theme.typography.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                }
            }
            .padding(24)
        }
    }

    private var microphoneStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ThemedCard(style: .standard) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(self.isMicrophoneReady ? self.theme.palette.success : self.theme.palette.warning)
                                .frame(width: 10, height: 10)

                            Text(self.isMicrophoneReady ? "Microphone access granted" : "Microphone access required")
                                .font(self.theme.typography.bodyStrong)
                                .foregroundStyle(self.isMicrophoneReady ? .primary : self.theme.palette.warning)

                            Spacer()

                            if !self.isMicrophoneReady {
                                Button(self.microphoneActionButtonTitle) {
                                    self.handleMicrophoneAction()
                                }
                                .fluidOnboardingProminentButton()
                            }
                        }

                        if !self.isMicrophoneReady {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("How to enable microphone access")
                                    .font(self.theme.typography.captionStrong)
                                    .foregroundStyle(.secondary)

                                if self.asr.micStatus == .notDetermined {
                                    Text("1. Click \"Grant Access\"")
                                    Text("2. Choose \"Allow\" in the system dialog")
                                } else {
                                    Text("1. Click \"Open Settings\"")
                                    Text("2. Find FluidVoice in the microphone list")
                                    Text("3. Toggle FluidVoice on")
                                }
                            }
                            .font(self.theme.typography.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)
                }
            }
            .padding(24)
        }
    }

    private var accessibilityStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ThemedCard(style: .standard) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(self.isAccessibilityReady ? self.theme.palette.success : self.theme.palette.warning)
                                .frame(width: 10, height: 10)

                            Text(self.isAccessibilityReady ? "Accessibility enabled" : "Accessibility permission required")
                                .font(self.theme.typography.bodyStrong)
                                .foregroundStyle(self.isAccessibilityReady ? .primary : self.theme.palette.warning)

                            Spacer()

                            if !self.isAccessibilityReady {
                                Button("Enable Accessibility") {
                                    self.openAccessibilitySettings()
                                }
                                .fluidOnboardingProminentButton()
                            }
                        }

                        if !self.isAccessibilityReady {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("How to enable accessibility")
                                    .font(self.theme.typography.captionStrong)
                                    .foregroundStyle(.secondary)
                                Text("1. Click \"Enable Accessibility\"")
                                Text("2. Add or enable FluidVoice in Accessibility")
                                Text("3. FluidVoice should restart automatically")
                                Text("4. If it does not, use Restart FluidVoice below")
                            }
                            .font(self.theme.typography.caption)
                            .foregroundStyle(.secondary)

                            Button("Restart FluidVoice") {
                                self.restartApp()
                            }
                            .fluidOnboardingSecondaryButton(controlSize: .small)
                        }
                    }
                    .padding(16)
                }
            }
            .padding(24)
        }
    }

    private var aiEnhancementStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: self.isAIReady ? "checkmark.circle.fill" : "sparkles")
                    .foregroundStyle(self.isAIReady ? self.theme.palette.success : self.theme.palette.accent)
                Text(self.isAIReady
                    ? "AI enhancement is ready (or skipped)"
                    : "Configure AI enhancement or skip to continue")
                    .font(self.theme.typography.bodySmallStrong)
                    .foregroundStyle(self.isAIReady ? self.theme.palette.success : .secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            AIEnhancementSettingsScreen(menuBarManager: self.menuBarManager, theme: self.theme)
        }
    }

    private var playgroundStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ThemedCard(style: .standard) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Quick Playground Test")
                                .font(self.theme.typography.sectionTitle)
                            Spacer()
                            if self.asr.isRunning {
                                Text("Recording...")
                                    .font(self.theme.typography.captionStrong)
                                    .foregroundStyle(.red)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Press Start Recording or use \(self.onboardingShortcutDisplay), then stop and confirm your text appears below.")
                                .font(self.theme.typography.caption)
                                .foregroundStyle(.secondary)

                            Button(self.asr.isRunning ? "Stop Recording" : "Start Recording") {
                                self.togglePlaygroundRecording()
                            }
                            .fluidButton(.primary, size: .large, isRecording: self.asr.isRunning)
                            .disabled(self.asr.micStatus != .authorized)
                        }

                        TextEditor(text: Binding(
                            get: { self.asr.finalText },
                            set: { self.asr.finalText = $0 }
                        ))
                        .font(self.theme.typography.body)
                        .frame(height: 170)
                        .fluidOnboardingEditorSurface()
                        .scrollContentBackground(.hidden)

                        if self.isPlaygroundReady {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(self.theme.palette.success)
                                Text("Playground test passed. You can finish setup.")
                                    .font(self.theme.typography.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Record a short sample with the button or your hotkey and confirm transcription appears here.")
                                .font(self.theme.typography.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)
                }
            }
            .padding(24)
        }
        .onChange(of: self.asr.finalText) { _, newValue in
            if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.markPlaygroundValidated()
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if self.step.rawValue > 0 {
                Button("Back") {
                    self.goBack()
                }
                .fluidOnboardingSecondaryButton()
            }

            Spacer()

            if self.step == .aiEnhancement {
                Button("Skip this step") {
                    self.markAISkipped()
                    self.goNext()
                }
                .fluidOnboardingSecondaryButton()
            }

            Button(self.primaryButtonTitle) {
                self.handlePrimaryAction()
            }
            .fluidOnboardingProminentButton()
            .disabled(!self.canContinue)
        }
        .padding(20)
    }

    private var microphoneActionButtonTitle: String {
        switch self.asr.micStatus {
        case .notDetermined:
            return "Grant Access"
        case .denied, .restricted:
            return "Open Settings"
        default:
            return "Grant Access"
        }
    }

    private func isOnboardingModelSelected(_ model: SettingsStore.SpeechModel) -> Bool {
        self.settings.selectedSpeechModel == model
    }

    private func isOnboardingModelReady(_ model: SettingsStore.SpeechModel) -> Bool {
        self.isOnboardingModelSelected(model) && self.asr.isAsrReady
    }

    private func isOnboardingModelDownloaded(_ model: SettingsStore.SpeechModel) -> Bool {
        model.isInstalled || (self.isOnboardingModelSelected(model) && (self.asr.isAsrReady || self.asr.modelsExistOnDisk))
    }

    private func isPreparingOnboardingModel(_ model: SettingsStore.SpeechModel) -> Bool {
        self.isOnboardingModelSelected(model) && (self.asr.isDownloadingModel || (self.asr.isLoadingModel && !self.asr.isAsrReady))
    }

    private func onboardingModelActionButtonTitle(for model: SettingsStore.SpeechModel) -> String {
        let isDownloaded = self.isOnboardingModelDownloaded(model)
        let isReady = self.isOnboardingModelReady(model)

        if self.isPreparingOnboardingModel(model) {
            return self.asr.isLoadingModel ? "Loading..." : "Downloading..."
        }
        if isReady {
            return "Ready"
        }
        if isDownloaded {
            return "Use"
        }
        return "Use & Download"
    }

    private func prepareOnboardingModel(_ model: SettingsStore.SpeechModel, preserveManualChoice: Bool = false) {
        guard !self.asr.isRunning else { return }

        self.selectOnboardingModel(model, preserveManualChoice: preserveManualChoice)

        Task { @MainActor in
            do {
                try await self.asr.ensureAsrReady()
            } catch {
                DebugLogger.shared.error("Failed to prepare onboarding voice model \(model.displayName): \(error)", source: "OnboardingFlowView")
            }
            await self.asr.checkIfModelsExistAsync()
        }
    }

    private func onboardingModelOptionRow(for model: SettingsStore.SpeechModel) -> some View {
        let isSelected = self.isOnboardingModelSelected(model)
        let isDownloaded = self.isOnboardingModelDownloaded(model)
        let isPreparing = self.isPreparingOnboardingModel(model)
        let isReady = self.isOnboardingModelReady(model)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.displayName)
                        .font(self.theme.typography.bodyStrong)
                        .foregroundStyle(self.theme.palette.primaryText)

                    Text(model.cardDescription)
                        .font(self.theme.typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    HStack(spacing: 10) {
                        Label(model.downloadSize, systemImage: "internaldrive")
                            .font(self.theme.typography.captionSmall)
                            .foregroundStyle(.secondary)
                        Text(model.languageSupport)
                            .font(self.theme.typography.captionSmall)
                            .foregroundStyle(.secondary)
                    }

                    if let supportedLanguageCodes = model.supportedLanguageCodes {
                        Text(supportedLanguageCodes)
                            .font(self.theme.typography.captionSmall)
                            .foregroundStyle(.secondary)
                    }

                    if let supportedLanguageNames = model.supportedLanguageNames {
                        Text("Supported languages: \(supportedLanguageNames)")
                            .font(self.theme.typography.captionSmall)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 8)

            Button(self.onboardingModelActionButtonTitle(for: model)) {
                self.prepareOnboardingModel(model, preserveManualChoice: true)
            }
            .fluidOnboardingSecondaryButton(controlSize: .small)
            .disabled(self.asr.isRunning || isPreparing || isReady)

            if isPreparing {
                if self.asr.isDownloadingModel, let progress = self.asr.downloadProgress {
                    if progress >= 0.82 {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.mini)
                            Text("Finalizing...")
                                .font(self.theme.typography.captionSmall)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ProgressView(value: progress)
                            .tint(self.theme.palette.accent)
                        Text("Downloading \(Int(progress * 100))%")
                            .font(self.theme.typography.captionSmall)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Loading model...")
                        .font(self.theme.typography.captionSmall)
                        .foregroundStyle(.secondary)
                }
            } else if isReady {
                Label("Downloaded and loaded", systemImage: "checkmark.circle.fill")
                    .font(self.theme.typography.badge)
                    .foregroundStyle(self.theme.palette.success)
            } else if isDownloaded {
                Label("Downloaded", systemImage: "arrow.triangle.2.circlepath")
                    .font(self.theme.typography.badge)
                    .foregroundStyle(.secondary)
            }
        }
        .fluidOnboardingSelectableSurface(
            isSelected: isSelected,
            cornerRadius: self.theme.metrics.onboardingSurface.compactOptionCornerRadius,
            padding: self.theme.metrics.onboardingSurface.compactOptionPadding
        )
        .onTapGesture {
            self.selectOnboardingModel(model, preserveManualChoice: true)
        }
    }

    private func onboardingRecommendedModelCard(for model: SettingsStore.SpeechModel) -> some View {
        let isSelected = self.isOnboardingModelSelected(model)
        let isDownloaded = self.isOnboardingModelDownloaded(model)
        let isPreparing = self.isPreparingOnboardingModel(model)
        let isReady = self.isOnboardingModelReady(model)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Text(model.displayName)
                    .font(self.theme.typography.bodyStrong)
                    .foregroundStyle(self.theme.palette.primaryText)

                Spacer(minLength: 8)

                Text("FV Recommended")
                    .font(self.theme.typography.badge)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(self.theme.palette.accent.opacity(0.18)))
                    .foregroundStyle(self.theme.palette.accent)
            }

            Text(model.cardDescription)
                .font(self.theme.typography.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            HStack(spacing: 10) {
                Label(model.downloadSize, systemImage: "internaldrive")
                    .font(self.theme.typography.captionSmall)
                    .foregroundStyle(.secondary)
                Text(model.languageSupport)
                    .font(self.theme.typography.captionSmall)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if isPreparing {
                if self.asr.isDownloadingModel, let progress = self.asr.downloadProgress {
                    ProgressView(value: progress)
                        .tint(self.theme.palette.accent)
                    Text(progress >= 0.82 ? "Finalizing..." : "Downloading \(Int(progress * 100))%")
                        .font(self.theme.typography.captionSmall)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Loading model...")
                        .font(self.theme.typography.captionSmall)
                        .foregroundStyle(.secondary)
                }
            } else if isReady {
                Label("Downloaded and loaded", systemImage: "checkmark.circle.fill")
                    .font(self.theme.typography.badge)
                    .foregroundStyle(self.theme.palette.success)
            } else if isDownloaded {
                Label("Downloaded", systemImage: "arrow.triangle.2.circlepath")
                    .font(self.theme.typography.badge)
                    .foregroundStyle(.secondary)
            } else {
                Label("Not downloaded yet", systemImage: "arrow.down.circle")
                    .font(self.theme.typography.badge)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button(self.onboardingModelActionButtonTitle(for: model)) {
                    self.prepareOnboardingModel(model, preserveManualChoice: true)
                }
                .fluidOnboardingProminentButton(controlSize: .small)
                .disabled(self.asr.isRunning || isPreparing || isReady)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .fluidOnboardingSelectableSurface(isSelected: isSelected)
        .onTapGesture {
            self.selectOnboardingModel(model, preserveManualChoice: true)
        }
    }

    private func selectOnboardingModel(_ model: SettingsStore.SpeechModel, preserveManualChoice: Bool = false) {
        if self.settings.selectedSpeechModel != model {
            self.settings.selectedSpeechModel = model
            self.asr.resetTranscriptionProvider()
        }
        if preserveManualChoice {
            return
        }
        self.syncPreferredLanguageChoiceWithSelectedModel()
    }

    private var recommendedModelHeadline: String {
        if self.shouldShowLanguageChoice {
            switch self.preferredLanguageChoice {
            case .englishOnly:
                return "English only uses \(self.recommendedOnboardingModelDisplayName)"
            case .multipleLanguages:
                return "FluidVoice recommends Parakeet TDT v3 and Cohere"
            case .other:
                return "Whisper and more options"
            }
        }

        return "Recommended for this Mac: \(self.recommendedOnboardingModelDisplayName)"
    }

    private func preferredLanguageOptionCard(for option: PreferredLanguageChoice) -> some View {
        let isSelected = self.preferredLanguageChoice == option

        return Button {
            self.preferredLanguageChoice = option
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(option.title)
                        .font(self.theme.typography.bodyStrong)
                        .foregroundStyle(self.theme.palette.primaryText)

                    if option != .other {
                        Text("FluidVoice Recommended")
                            .font(self.theme.typography.badge)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(self.theme.palette.accent.opacity(0.18)))
                            .foregroundStyle(self.theme.palette.accent)
                    }
                }

                Text(option.subtitle)
                    .font(self.theme.typography.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fluidOnboardingSelectableSurface(isSelected: isSelected, selectedBorderOpacity: 0.55)
        }
        .buttonStyle(.plain)
    }

    private func syncPreferredLanguageChoiceWithSelectedModel() {
        guard self.shouldShowLanguageChoice else { return }

        switch self.settings.selectedSpeechModel {
        case .parakeetTDTv2:
            self.preferredLanguageChoice = .englishOnly
        case .parakeetRealtime:
            self.preferredLanguageChoice = .englishOnly
        case .parakeetTDT, .cohereTranscribeSixBit:
            self.preferredLanguageChoice = .multipleLanguages
        default:
            self.preferredLanguageChoice = .other
        }
    }

    private func handleMicrophoneAction() {
        if self.asr.micStatus == .notDetermined {
            self.asr.requestMicAccess()
        } else {
            self.asr.openSystemSettingsForMic()
        }
    }

    private func goBack() {
        self.currentStep = max(0, self.currentStep - 1)
    }

    private func goNext() {
        self.currentStep = min(Step.allCases.count - 1, self.currentStep + 1)
    }

    private func handlePrimaryAction() {
        if self.step == .playground {
            if !self.settings.onboardingPlaygroundValidated {
                self.markPlaygroundValidated()
            }
            self.finishOnboarding()
            return
        }
        self.goNext()
    }

    private func togglePlaygroundRecording() {
        Task { @MainActor in
            if self.asr.isRunning {
                let transcribed = await self.asr.stop()
                _ = self.asr.consumeLastCompletedAudioSnapshot()
                self.asr.finalText = ASRService.applyGAAVFormatting(transcribed)
                if !self.asr.finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.markPlaygroundValidated()
                }
            } else {
                self.asr.finalText = ""
                await self.asr.start()
            }
        }
    }
}
