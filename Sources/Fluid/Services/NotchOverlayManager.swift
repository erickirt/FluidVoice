//
//  NotchOverlayManager.swift
//  Fluid
//
//  Created by Assistant
//

import AppKit
import Combine
import DynamicNotchKit
import SwiftUI

// MARK: - Overlay Mode

enum OverlayMode: String {
    case dictation = "Dictation"
    case edit = "Edit"
    case rewrite = "Rewrite"
    case write = "Write"
    case command = "Command"
}

@MainActor
final class NotchOverlayManager {
    static let shared = NotchOverlayManager()

    struct NotchPresentationPolicy: Equatable {
        let usesCompactPresentation: Bool
        let showsPromptSelector: Bool
        let showsStreamingPreview: Bool
        let showsModeLabel: Bool
        let allowsCommandExpansion: Bool
        let allowsCommandActions: Bool
        let allowsExpandedCommandOutput: Bool
    }

    private var notch: DynamicNotch<NotchExpandedView, NotchCompactLeadingView, NotchCompactTrailingView, NotchCompactBottomView>?
    private var commandOutputNotch: DynamicNotch<
        NotchCommandOutputExpandedView,
        NotchCompactLeadingView,
        NotchCompactTrailingView,
        EmptyView
    >?
    private var currentMode: OverlayMode = .dictation

    /// Store last audio publisher for re-showing during processing
    private var lastAudioPublisher: AnyPublisher<CGFloat, Never>?

    /// Current audio publisher (can be updated for expanded notch recording)
    @Published private(set) var currentAudioPublisher: AnyPublisher<CGFloat, Never>?

    /// State machine to prevent race conditions
    private enum State {
        case idle
        case showing
        case visible
        case hiding
    }

    private var state: State = .idle
    private var commandOutputState: State = .idle

    /// Track if expanded command output is showing
    private(set) var isCommandOutputExpanded: Bool = false

    /// Track if bottom overlay is visible
    private(set) var isBottomOverlayVisible: Bool = false
    var isOverlayVisible: Bool { self.state == .visible }

    // Callbacks for command output interaction
    var onCommandOutputDismiss: (() -> Void)?
    var onCommandFollowUp: ((String) async -> Void)?
    var onNotchClicked: (() -> Void)? // Called when regular notch is clicked in command mode

    // Callbacks for chat management
    var onNewChat: (() -> Void)?
    var onSwitchChat: ((String) -> Void)?
    var onClearChat: (() -> Void)?

    // Generation counter to track show/hide cycles and prevent race conditions
    // Uses UInt64 to avoid overflow concerns in long-running sessions
    private var generation: UInt64 = 0
    private var commandOutputGeneration: UInt64 = 0

    /// Track pending retry task for cancellation
    private var pendingRetryTask: Task<Void, Never>?

    // Cancel shortcut monitors for dismissing notch / overlay
    private var globalEscapeMonitor: Any?
    private var localEscapeMonitor: Any?

    private(set) var currentNotchPresentationMode: SettingsStore.NotchPresentationMode = .standard
    private(set) var currentNotchPresentationPolicy = NotchPresentationPolicy.standard
    private(set) var currentScreenSupportsCompactPresentation = false
    private var presentationPolicyScreen: NSScreen?
    private static let transientOverlayStatusTexts: Set<String> = [
        "Transcribing",
        "Refining",
        "Thinking",
        "Working",
        "Transcribing...",
        "Refining...",
        "Thinking...",
        "Working...",
        "Reprocessing...",
    ]

    private init() {
        self.refreshNotchPresentationPolicy()
        self.setupEscapeKeyMonitors()
    }

    deinit {
        if let monitor = globalEscapeMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localEscapeMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    /// Setup cancel shortcut monitors - both global (other apps) and local (our app)
    private func setupEscapeKeyMonitors() {
        let escapeHandler: (NSEvent) -> NSEvent? = { [weak self] event in
            guard SettingsStore.shared.cancelRecordingHotkeyShortcut.matches(
                keyCode: event.keyCode,
                modifiers: event.modifierFlags
            ) else { return event }

            Task { @MainActor in
                guard self != nil else { return }
                NotchContentState.shared.onCancelRequested?()
            }
            return nil // Consume the event
        }

        // Global monitor - catches the cancel shortcut when OTHER apps have focus
        self.globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            _ = escapeHandler(event)
        }
    }

    func show(audioLevelPublisher: AnyPublisher<CGFloat, Never>, mode: OverlayMode) {
        self.refreshNotchPresentationPolicy()

        // Don't show regular notch if expanded command output is visible
        if self.isCommandOutputExpanded {
            // Just store the publisher for later use
            self.lastAudioPublisher = audioLevelPublisher
            return
        }

        // Cancel any pending retry operations
        self.pendingRetryTask?.cancel()
        self.pendingRetryTask = nil

        // If already visible or in transition, wait for cleanup to complete
        if self.notch != nil || self.state != .idle {
            // Increment generation to invalidate stale operations
            self.generation &+= 1
            let targetGeneration = self.generation

            // Start async cleanup and retry
            self.pendingRetryTask = Task { [weak self] in
                guard let self = self else { return }

                // Perform cleanup synchronously first
                await self.performCleanup()

                // Small delay to ensure cleanup completes
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

                // Check if we're still the active operation
                guard !Task.isCancelled, self.generation == targetGeneration else { return }

                // Retry show
                self.showInternal(audioLevelPublisher: audioLevelPublisher, mode: mode)
            }
            return
        }

        self.showInternal(audioLevelPublisher: audioLevelPublisher, mode: mode)
    }

    private func showInternal(audioLevelPublisher: AnyPublisher<CGFloat, Never>, mode: OverlayMode) {
        guard self.state == .idle else { return }

        // Store for potential re-show during processing
        self.lastAudioPublisher = audioLevelPublisher

        // Start monitoring active app changes (updates icon in real-time)
        ActiveAppMonitor.shared.startMonitoring()
        let targetScreen = OverlayScreenResolver.screenForCurrentPointer()

        // Route to bottom overlay if user preference is set
        if SettingsStore.shared.overlayPosition == .bottom {
            self.showBottomOverlay(audioLevelPublisher: audioLevelPublisher, mode: mode)
            return
        }

        // Otherwise show notch overlay (original behavior)
        self.showNotchOverlay(audioLevelPublisher: audioLevelPublisher, mode: mode, screen: targetScreen)
    }

    /// Show bottom overlay (alternative to notch)
    private func showBottomOverlay(audioLevelPublisher: AnyPublisher<CGFloat, Never>, mode: OverlayMode) {
        // Hide any existing notch first
        if self.notch != nil {
            Task { await self.performCleanup() }
        }

        self.lastAudioPublisher = audioLevelPublisher
        self.currentMode = self.normalizedOverlayMode(mode)

        BottomOverlayWindowController.shared.show(audioPublisher: audioLevelPublisher, mode: self.currentMode)
        self.isBottomOverlayVisible = true
    }

    /// Show notch overlay (original behavior)
    private func showNotchOverlay(audioLevelPublisher: AnyPublisher<CGFloat, Never>, mode: OverlayMode, screen: NSScreen?) {
        let targetScreen = screen ?? self.preferredPresentationScreen()
        self.presentationPolicyScreen = targetScreen
        self.refreshNotchPresentationPolicy(for: targetScreen)
        self.currentAudioPublisher = audioLevelPublisher
        // Hide bottom overlay if it was visible
        if self.isBottomOverlayVisible {
            BottomOverlayWindowController.shared.hide()
            self.isBottomOverlayVisible = false
        }

        // Increment generation for this operation
        self.generation &+= 1
        let currentGeneration = self.generation

        self.state = .showing
        self.currentMode = self.normalizedOverlayMode(mode)

        // Update shared content state immediately
        NotchContentState.shared.mode = self.currentMode
        self.syncPromptPickerMode(for: self.currentMode)
        NotchContentState.shared.updateTranscription("")

        // Create notch with SwiftUI views
        let newNotch = DynamicNotch(
            hoverBehavior: [.keepVisible],
            style: .auto
        ) {
            NotchExpandedView(audioPublisher: audioLevelPublisher)
        } compactLeading: {
            NotchCompactLeadingView()
        } compactTrailing: {
            NotchCompactTrailingView(audioPublisher: audioLevelPublisher)
        } compactBottom: {
            NotchCompactBottomView()
        }

        self.notch = newNotch
        let shouldUseCompactPresentation = self.currentNotchPresentationPolicy.usesCompactPresentation

        // Resolve presentation from policy so future notch modes don't require call-site changes.
        Task { [weak self] in
            if shouldUseCompactPresentation {
                await newNotch.compact(on: targetScreen)
            } else {
                await newNotch.expand(on: targetScreen)
            }
            // Only update state if we're still the active generation
            guard let self = self, self.generation == currentGeneration else { return }
            self.state = .visible
        }
    }

    func hide() {
        // Stop monitoring active app changes
        ActiveAppMonitor.shared.stopMonitoring()

        // Hide bottom overlay if visible
        if self.isBottomOverlayVisible {
            BottomOverlayWindowController.shared.hide()
            self.isBottomOverlayVisible = false
        }

        // Cancel any pending retry operations
        self.pendingRetryTask?.cancel()
        self.pendingRetryTask = nil

        // Safety: reset processing state when hiding
        NotchContentState.shared.setProcessing(false)

        // Increment generation to invalidate any pending show tasks
        self.generation &+= 1
        let currentGeneration = self.generation

        // Handle visible or showing states (can hide while still expanding)
        guard self.state == .visible || self.state == .showing, let currentNotch = notch else {
            // Force cleanup if stuck or in inconsistent state
            Task { [weak self] in await self?.performCleanup() }
            return
        }

        self.state = .hiding

        Task { [weak self] in
            await currentNotch.hide()
            // Only clear if we're still the active operation
            guard let self = self, self.generation == currentGeneration else { return }
            self.notch = nil
            self.state = .idle
        }
    }

    /// Async cleanup that properly waits for hide to complete
    private func performCleanup() async {
        // Cancel any pending retry operations
        self.pendingRetryTask?.cancel()
        self.pendingRetryTask = nil

        if let existingNotch = notch {
            await existingNotch.hide()
        }
        self.notch = nil
        self.state = .idle
    }

    func setMode(_ mode: OverlayMode) {
        self.refreshNotchPresentationPolicy()

        // Always update NotchContentState to ensure UI stays in sync
        // (can get out of sync during show/hide transitions)
        let normalized = self.normalizedOverlayMode(mode)
        self.currentMode = normalized
        NotchContentState.shared.mode = normalized
        self.syncPromptPickerMode(for: normalized)
    }

    func switchLiveOverlayMode(to promptMode: SettingsStore.PromptMode) {
        guard !NotchContentState.shared.isProcessing else { return }
        switch promptMode.normalized {
        case .dictate:
            self.setMode(.dictation)
        case .edit:
            self.setMode(.edit)
        case .write, .rewrite:
            self.setMode(.edit)
        }
    }

    func updateTranscriptionText(_ text: String) {
        guard self.shouldShowOrTrackLivePreviewText else {
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedText.isEmpty || Self.transientOverlayStatusTexts.contains(trimmedText) {
                NotchContentState.shared.updateTranscription(text)
            } else if !NotchContentState.shared.transcriptionText.isEmpty {
                NotchContentState.shared.updateTranscription("")
            }
            return
        }
        NotchContentState.shared.updateTranscription(text)
    }

    func setProcessing(_ processing: Bool) {
        NotchContentState.shared.setProcessing(processing)

        // If expanded command output is showing, don't mess with regular notch
        if self.isCommandOutputExpanded {
            return
        }

        // If bottom overlay is visible, update its processing state
        if self.isBottomOverlayVisible {
            BottomOverlayWindowController.shared.setProcessing(processing)
            return
        }

        if processing {
            // If notch isn't visible, re-show it for processing state
            if self.state == .idle || self.state == .hiding {
                // Use stored publisher or create empty one
                let publisher = self.lastAudioPublisher ?? Empty<CGFloat, Never>().eraseToAnyPublisher()
                self.show(audioLevelPublisher: publisher, mode: self.currentMode)
            }
        }
    }

    // MARK: - Expanded Command Output

    /// Show expanded command output notch
    func showExpandedCommandOutput() {
        guard self.canShowExpandedCommandOutput else { return }

        // Hide regular notch first if visible
        if self.notch != nil {
            self.hide()
        }

        // Wait a bit for cleanup
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            await self?.showExpandedCommandOutputInternal()
        }
    }

    private func showExpandedCommandOutputInternal() async {
        guard self.canShowExpandedCommandOutput else { return }
        guard self.commandOutputState == .idle else { return }

        self.commandOutputGeneration &+= 1
        let currentGeneration = self.commandOutputGeneration

        self.commandOutputState = .showing
        self.isCommandOutputExpanded = true

        // Update content state
        NotchContentState.shared.mode = .command
        NotchContentState.shared.isExpandedForCommandOutput = true

        let publisher = self.lastAudioPublisher ?? Empty<CGFloat, Never>().eraseToAnyPublisher()

        let newNotch = DynamicNotch(
            hoverBehavior: [], // No keepVisible - allows closing with X/Escape even when cursor is on notch
            style: .auto
        ) {
            NotchCommandOutputExpandedView(
                audioPublisher: publisher,
                onDismiss: { [weak self] in
                    Task { @MainActor in
                        self?.hideExpandedCommandOutput()
                        self?.onCommandOutputDismiss?()
                    }
                },
                onSubmit: { [weak self] text in
                    guard let self, self.allowsCommandNotchActions else { return }
                    await self.onCommandFollowUp?(text)
                },
                onNewChat: { [weak self] in
                    Task { @MainActor in
                        guard let self, self.allowsCommandNotchActions else { return }
                        self.onNewChat?()
                        // Refresh recent chats in notch state
                        NotchContentState.shared.refreshRecentChats()
                    }
                },
                onSwitchChat: { [weak self] chatID in
                    Task { @MainActor in
                        guard let self, self.allowsCommandNotchActions else { return }
                        self.onSwitchChat?(chatID)
                        // Refresh recent chats in notch state
                        NotchContentState.shared.refreshRecentChats()
                    }
                },
                onClearChat: { [weak self] in
                    Task { @MainActor in
                        guard let self, self.allowsCommandNotchActions else { return }
                        self.onClearChat?()
                    }
                }
            )
        } compactLeading: {
            NotchCompactLeadingView()
        } compactTrailing: {
            NotchCompactTrailingView(audioPublisher: publisher)
        } compactBottom: {
            EmptyView()
        }

        self.commandOutputNotch = newNotch

        if let screen = self.presentationPolicyScreen ?? OverlayScreenResolver.screenForCurrentPointer() {
            await newNotch.expand(on: screen)
        } else {
            await newNotch.expand()
        }

        guard self.commandOutputGeneration == currentGeneration else { return }
        self.commandOutputState = .visible
    }

    private func syncPromptPickerMode(for mode: OverlayMode) {
        switch mode {
        case .dictation:
            NotchContentState.shared.promptPickerMode = .dictate
        case .edit, .write, .rewrite:
            NotchContentState.shared.promptPickerMode = .edit
        case .command:
            break
        }
    }

    private func normalizedOverlayMode(_ mode: OverlayMode) -> OverlayMode {
        switch mode {
        case .write, .rewrite:
            return .edit
        case .dictation, .edit, .command:
            return mode
        }
    }

    /// Hide expanded command output notch - force close regardless of hover state
    func hideExpandedCommandOutput() {
        self.commandOutputGeneration &+= 1
        let currentGeneration = self.commandOutputGeneration

        // Force cleanup state immediately
        self.isCommandOutputExpanded = false
        NotchContentState.shared.collapseCommandOutput()

        guard self.commandOutputState == .visible || self.commandOutputState == .showing,
              let currentNotch = commandOutputNotch
        else {
            self.commandOutputState = .idle
            return
        }

        self.commandOutputState = .hiding

        // Store reference and nil out immediately to prevent hover from keeping it alive
        let notchToHide = currentNotch
        self.commandOutputNotch = nil

        Task { [weak self] in
            // Try to hide gracefully, but we've already removed our reference
            await notchToHide.hide()
            guard let self = self, self.commandOutputGeneration == currentGeneration else { return }
            self.commandOutputState = .idle
        }
    }

    /// Toggle expanded command output (for hotkey handling)
    func toggleExpandedCommandOutput() {
        if self.isCommandOutputExpanded {
            self.hideExpandedCommandOutput()
        } else if self.canShowExpandedCommandOutput,
                  NotchContentState.shared.commandConversationHistory.isEmpty == false
        {
            // Only show if there's history to show
            self.showExpandedCommandOutput()
        }
    }

    var canShowExpandedCommandOutput: Bool {
        self.refreshNotchPresentationPolicy()
        return self.currentNotchPresentationPolicy.allowsExpandedCommandOutput
    }

    var canHandleNotchCommandTap: Bool {
        self.refreshNotchPresentationPolicy()
        return self.currentNotchPresentationPolicy.allowsCommandExpansion &&
            self.currentNotchPresentationPolicy.allowsCommandActions
    }

    var allowsCommandNotchActions: Bool {
        self.refreshNotchPresentationPolicy()
        return self.currentNotchPresentationPolicy.allowsCommandActions
    }

    var supportsCommandNotchUI: Bool {
        self.refreshNotchPresentationPolicy()
        return self.currentNotchPresentationPolicy.allowsCommandExpansion ||
            self.currentNotchPresentationPolicy.allowsExpandedCommandOutput ||
            self.currentNotchPresentationPolicy.allowsCommandActions
    }

    var shouldShowOrTrackLivePreviewText: Bool {
        guard SettingsStore.shared.enableStreamingPreview else { return false }
        if SettingsStore.shared.overlayPosition == .bottom {
            return true
        }

        self.refreshNotchPresentationPolicy()
        return self.currentNotchPresentationPolicy.showsStreamingPreview
    }

    var shouldSyncCommandConversationToNotch: Bool {
        if SettingsStore.shared.overlayPosition == .bottom {
            return true
        }

        guard self.enableNotchFeatures else { return false }

        self.refreshNotchPresentationPolicy()
        return self.currentNotchPresentationPolicy.allowsExpandedCommandOutput ||
            self.currentNotchPresentationPolicy.allowsCommandActions
    }

    private var enableNotchFeatures: Bool {
        SettingsStore.shared.overlayPosition == .top || self.supportsCommandNotchUI
    }

    /// Check if any notch (regular or expanded) is visible
    var isAnyNotchVisible: Bool {
        return self.state == .visible || self.state == .showing || self.isCommandOutputExpanded
    }

    /// Update audio publisher for expanded notch (when recording starts within it)
    func updateAudioPublisher(_ publisher: AnyPublisher<CGFloat, Never>) {
        self.lastAudioPublisher = publisher
        self.currentAudioPublisher = publisher
    }

    private func preferredPresentationScreen() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        if let screenUnderMouse = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return screenUnderMouse
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    private func supportsCompactPresentation(on screen: NSScreen) -> Bool {
        screen.auxiliaryTopLeftArea?.width != nil && screen.auxiliaryTopRightArea?.width != nil
    }

    private func refreshNotchPresentationPolicy(for screen: NSScreen? = nil) {
        let mode = SettingsStore.shared.notchPresentationMode
        self.currentNotchPresentationMode = mode
        let resolvedScreen = screen ?? self.presentationPolicyScreen ?? self.preferredPresentationScreen()
        self.currentScreenSupportsCompactPresentation = self.supportsCompactPresentation(on: resolvedScreen)
        self.currentNotchPresentationPolicy = .forMode(
            mode,
            supportsCompactPresentation: self.currentScreenSupportsCompactPresentation
        )
    }
}

private extension NotchOverlayManager.NotchPresentationPolicy {
    static let standard = Self(
        usesCompactPresentation: false,
        showsPromptSelector: true,
        showsStreamingPreview: true,
        showsModeLabel: true,
        allowsCommandExpansion: true,
        allowsCommandActions: true,
        allowsExpandedCommandOutput: true
    )

    static let minimal = Self(
        usesCompactPresentation: true,
        showsPromptSelector: false,
        showsStreamingPreview: true,
        showsModeLabel: true,
        allowsCommandExpansion: false,
        allowsCommandActions: false,
        allowsExpandedCommandOutput: false
    )

    static func forMode(_ mode: SettingsStore.NotchPresentationMode, supportsCompactPresentation: Bool) -> Self {
        switch mode {
        case .standard:
            return .standard
        case .minimal:
            return supportsCompactPresentation ? .minimal : .standard
        }
    }
}
