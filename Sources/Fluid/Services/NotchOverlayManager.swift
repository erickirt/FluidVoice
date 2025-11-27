//
//  NotchOverlayManager.swift
//  Fluid
//
//  Created by Assistant
//

import DynamicNotchKit
import SwiftUI
import Combine
import AppKit

// MARK: - Overlay Mode
enum OverlayMode: String {
    case dictation = "Dictation"
    case rewrite = "Rewrite"
    case write = "Write"
    case command = "Command"
}

@MainActor
final class NotchOverlayManager {
    static let shared = NotchOverlayManager()
    
    private var notch: DynamicNotch<NotchExpandedView, NotchCompactLeadingView, NotchCompactTrailingView>?
    private var currentMode: OverlayMode = .dictation
    
    // Store last audio publisher for re-showing during processing
    private var lastAudioPublisher: AnyPublisher<CGFloat, Never>?
    
    // State machine to prevent race conditions
    private enum State {
        case idle
        case showing
        case visible
        case hiding
    }
    private var state: State = .idle
    
    // Generation counter to track show/hide cycles and prevent race conditions
    // Uses UInt64 to avoid overflow concerns in long-running sessions
    private var generation: UInt64 = 0
    
    // Track pending retry task for cancellation
    private var pendingRetryTask: Task<Void, Never>?
    
    private init() {}
    
    func show(audioLevelPublisher: AnyPublisher<CGFloat, Never>, mode: OverlayMode) {
        // Cancel any pending retry operations
        pendingRetryTask?.cancel()
        pendingRetryTask = nil
        
        // If already visible or in transition, wait for cleanup to complete
        if notch != nil || state != .idle {
            // Increment generation to invalidate stale operations
            generation &+= 1
            let targetGeneration = generation
            
            // Start async cleanup and retry
            pendingRetryTask = Task { [weak self] in
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
        
        showInternal(audioLevelPublisher: audioLevelPublisher, mode: mode)
    }
    
    private func showInternal(audioLevelPublisher: AnyPublisher<CGFloat, Never>, mode: OverlayMode) {
        guard state == .idle else { return }
        
        // Store for potential re-show during processing
        lastAudioPublisher = audioLevelPublisher
        
        // Increment generation for this operation
        generation &+= 1
        let currentGeneration = generation
        
        state = .showing
        currentMode = mode
        
        // Update shared content state immediately
        NotchContentState.shared.mode = mode
        NotchContentState.shared.updateTranscription("")
        
        // Create notch with SwiftUI views
        let newNotch = DynamicNotch(
            hoverBehavior: [.keepVisible, .hapticFeedback],
            style: .notch(topCornerRadius: 12, bottomCornerRadius: 18)
        ) {
            NotchExpandedView(audioPublisher: audioLevelPublisher)
        } compactLeading: {
            NotchCompactLeadingView()
        } compactTrailing: {
            NotchCompactTrailingView()
        }
        
        self.notch = newNotch
        
        // Show in expanded state
        Task {
            await newNotch.expand()
            // Only update state if we're still the active generation
            guard self.generation == currentGeneration else { return }
            self.state = .visible
        }
    }
    
    func hide() {
        // Cancel any pending retry operations
        pendingRetryTask?.cancel()
        pendingRetryTask = nil
        
        // Safety: reset processing state when hiding
        NotchContentState.shared.setProcessing(false)
        
        // Increment generation to invalidate any pending show tasks
        generation &+= 1
        let currentGeneration = generation
        
        // Handle visible or showing states (can hide while still expanding)
        guard state == .visible || state == .showing, let currentNotch = notch else {
            // Force cleanup if stuck or in inconsistent state
            Task { await performCleanup() }
            return
        }
        
        state = .hiding
        
        Task {
            await currentNotch.hide()
            // Only clear if we're still the active operation
            guard self.generation == currentGeneration else { return }
            self.notch = nil
            self.state = .idle
        }
    }
    
    /// Async cleanup that properly waits for hide to complete
    private func performCleanup() async {
        // Cancel any pending retry operations
        pendingRetryTask?.cancel()
        pendingRetryTask = nil
        
        if let existingNotch = notch {
            await existingNotch.hide()
        }
        notch = nil
        state = .idle
    }
    
    func setMode(_ mode: OverlayMode) {
        // Always update NotchContentState to ensure UI stays in sync
        // (can get out of sync during show/hide transitions)
        currentMode = mode
        NotchContentState.shared.mode = mode
    }
    
    func updateTranscriptionText(_ text: String) {
        NotchContentState.shared.updateTranscription(text)
    }
    
    func setProcessing(_ processing: Bool) {
        NotchContentState.shared.setProcessing(processing)
        
        if processing {
            // If notch isn't visible, re-show it for processing state
            if state == .idle || state == .hiding {
                // Use stored publisher or create empty one
                let publisher = lastAudioPublisher ?? Empty<CGFloat, Never>().eraseToAnyPublisher()
                show(audioLevelPublisher: publisher, mode: currentMode)
            }
        }
    }
}

