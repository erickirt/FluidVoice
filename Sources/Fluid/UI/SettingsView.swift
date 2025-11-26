//
//  SettingsView.swift
//  fluid
//
//  App preferences and audio device settings
//

import SwiftUI
import AVFoundation
import PromiseKit

struct SettingsView: View {
    @ObservedObject var asr: ASRService
    @Environment(\.theme) private var theme
    @Binding var appear: Bool
    @Binding var showWhatsNewSheet: Bool
    @Binding var visualizerNoiseThreshold: Double
    @Binding var selectedInputUID: String
    @Binding var selectedOutputUID: String
    @Binding var inputDevices: [AudioDevice.Device]
    @Binding var outputDevices: [AudioDevice.Device]
    @Binding var accessibilityEnabled: Bool
    @Binding var hotkeyShortcut: HotkeyShortcut
    @Binding var isRecordingShortcut: Bool
    @Binding var rewriteShortcut: HotkeyShortcut
    @Binding var isRecordingRewriteShortcut: Bool
    @Binding var hotkeyManagerInitialized: Bool
    @Binding var pressAndHoldModeEnabled: Bool
    @Binding var enableStreamingPreview: Bool
    @Binding var copyToClipboard: Bool
    
    let hotkeyManager: GlobalHotkeyManager?
    let menuBarManager: MenuBarManager
    let startRecording: () -> Void
    let refreshDevices: () -> Void
    let openAccessibilitySettings: () -> Void
    let restartApp: () -> Void
    let revealAppInFinder: () -> Void
    let openApplicationsFolder: () -> Void
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 14) {
                // App Settings Card
                ThemedCard(style: .standard) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "power")
                                .font(.title2)
                                .foregroundStyle(.white)
                            Text("App Settings")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }

                        VStack(spacing: 14) {
                            // Launch at startup
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top, spacing: 16) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Launch at startup")
                                            .font(.headline)
                                        Text("Automatically start FluidVoice when you log in")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Toggle("", isOn: Binding(
                                        get: { SettingsStore.shared.launchAtStartup },
                                        set: { SettingsStore.shared.launchAtStartup = $0 }
                                    ))
                                    .toggleStyle(.switch)
                                    .tint(.green)
                                    .labelsHidden()
                                }
                                
                                Text("Note: Requires app to be signed for this to work.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary.opacity(0.7))
                                    .padding(.leading, 0)
                            }

                            Divider()

                            // Show in Dock
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top, spacing: 16) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Show in Dock")
                                            .font(.headline)
                                        Text("Display FluidVoice icon in the Dock")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Toggle("", isOn: Binding(
                                        get: { SettingsStore.shared.showInDock },
                                        set: { SettingsStore.shared.showInDock = $0 }
                                    ))
                                    .toggleStyle(.switch)
                                    .tint(.green)
                                    .labelsHidden()
                                }
                                
                                Text("Note: May require app restart to take effect.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary.opacity(0.7))
                                    .padding(.leading, 0)
                            }

                            Divider()

                            // Automatic Updates
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top, spacing: 16) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Automatic Updates")
                                            .font(.headline)
                                        Text("Check for updates automatically once per day")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Toggle("", isOn: Binding(
                                        get: { SettingsStore.shared.autoUpdateCheckEnabled },
                                        set: { SettingsStore.shared.autoUpdateCheckEnabled = $0 }
                                    ))
                                    .toggleStyle(.switch)
                                    .tint(.green)
                                    .labelsHidden()
                                }
                                
                                if let lastCheck = SettingsStore.shared.lastUpdateCheckDate {
                                    Text("Last checked: \(lastCheck.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary.opacity(0.7))
                                        .padding(.leading, 0)
                                }
                            }
                            
                            // Update Buttons - Left/Right aligned
                            HStack(spacing: 12) {
                                Button("Check for Updates") {
                                    // Direct update check - same as menu bar
                                    Task { @MainActor in
                                        do {
                                            try await SimpleUpdater.shared.checkAndUpdate(owner: "altic-dev", repo: "Fluid-oss")
                                            let ok = NSAlert()
                                            ok.messageText = "Update Found!"
                                            ok.informativeText = "A new version is available and will be installed now."
                                            ok.alertStyle = .informational
                                            ok.addButton(withTitle: "OK")
                                            ok.runModal()
                                        } catch {
                                            let msg = NSAlert()
                                            if let pmkError = error as? PMKError, pmkError.isCancelled {
                                                msg.messageText = "You're Up To Date"
                                                msg.informativeText = "You're already running the latest version of FluidVoice."
                                            } else {
                                                msg.messageText = "Update Check Failed"
                                                msg.informativeText = "Unable to check for updates. Please try again later.\n\nError: \(error.localizedDescription)"
                                            }
                                            msg.alertStyle = .informational
                                            msg.runModal()
                                        }
                                    }
                                }
                                .buttonStyle(PremiumButtonStyle(height: 40))
                                .buttonHoverEffect()
                                
                                Button("What's New") {
                                    showWhatsNewSheet = true
                                }
                                .buttonStyle(PremiumButtonStyle(height: 40))
                                .buttonHoverEffect()
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(14)
                }
                
                // Microphone Permission Card
                ThemedCard(style: .standard) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "mic.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                            Text("Microphone Permission")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                        
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 12) {
                                // Status indicator
                                Circle()
                                    .fill(asr.micStatus == .authorized ? theme.palette.success : theme.palette.warning)
                                    .frame(width: 10, height: 10)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(asr.micStatus == .authorized ? "Microphone access granted" : 
                                         asr.micStatus == .denied ? "Microphone access denied" :
                                         "Microphone access not determined")
                                        .fontWeight(.medium)
                                        .foregroundStyle(asr.micStatus == .authorized ? theme.palette.primaryText : theme.palette.warning)
                                    
                                    if asr.micStatus != .authorized {
                                        Text("Microphone access is required for voice recording")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                
                                // Action button
                                Group {
                                    if asr.micStatus == .notDetermined {
                                        Button {
                                            asr.requestMicAccess()
                                        } label: {
                                            HStack(spacing: 6) {
                                                Image(systemName: "mic.fill")
                                                Text("Grant Access")
                                                    .fontWeight(.medium)
                                            }
                                        }
                                        .buttonStyle(GlassButtonStyle())
                                        .buttonHoverEffect()
                                    } else if asr.micStatus == .denied {
                                        Button {
                                            asr.openSystemSettingsForMic()
                                        } label: {
                                            HStack(spacing: 6) {
                                                Image(systemName: "gear")
                                                Text("Open Settings")
                                                    .fontWeight(.medium)
                                            }
                                        }
                                        .buttonStyle(GlassButtonStyle())
                                        .buttonHoverEffect()
                                    }
                                }
                            }
                            
                            // Step-by-step instructions when microphone is not authorized
                            if asr.micStatus != .authorized {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "info.circle.fill")
                                            .foregroundStyle(theme.palette.accent)
                                            .font(.caption)
                                        Text("How to enable microphone access:")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        if asr.micStatus == .notDetermined {
                                            HStack(spacing: 8) {
                                                Text("1.")
                                                    .font(.caption2)
                                                    .foregroundStyle(theme.palette.accent)
                                                    .fontWeight(.semibold)
                                                    .frame(width: 16)
                                                Text("Click **Grant Access** above")
                                                    .font(.caption)
                                                    .foregroundStyle(.primary)
                                            }
                                            HStack(spacing: 8) {
                                                Text("2.")
                                                    .font(.caption2)
                                                    .foregroundStyle(theme.palette.accent)
                                                    .fontWeight(.semibold)
                                                    .frame(width: 16)
                                                Text("Choose **Allow** in the system dialog")
                                                    .font(.caption)
                                                    .foregroundStyle(.primary)
                                            }
                                        } else if asr.micStatus == .denied {
                                            HStack(spacing: 8) {
                                                Text("1.")
                                                    .font(.caption2)
                                                    .foregroundStyle(theme.palette.accent)
                                                    .fontWeight(.semibold)
                                                    .frame(width: 16)
                                                Text("Click **Open Settings** above")
                                                    .font(.caption)
                                                    .foregroundStyle(.primary)
                                            }
                                            HStack(spacing: 8) {
                                                Text("2.")
                                                    .font(.caption2)
                                                    .foregroundStyle(theme.palette.accent)
                                                    .fontWeight(.semibold)
                                                    .frame(width: 16)
                                                Text("Find **FluidVoice** in the microphone list")
                                                    .font(.caption)
                                                    .foregroundStyle(.primary)
                                            }
                                            HStack(spacing: 8) {
                                                Text("3.")
                                                    .font(.caption2)
                                                    .foregroundStyle(theme.palette.accent)
                                                    .fontWeight(.semibold)
                                                    .frame(width: 16)
                                                Text("Toggle **FluidVoice ON** to allow access")
                                                    .font(.caption)
                                                    .foregroundStyle(.primary)
                                            }
                                        }
                                    }
                                    .padding(.leading, 4)
                                }
                                .padding(12)
                                .background(theme.palette.accent.opacity(0.12))
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding(14)
                }
                
                // Global Hotkey Card
                ThemedCard(style: .standard) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "keyboard")
                                .font(.title2)
                                .foregroundStyle(.white)
                            Text("Global Hotkey")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                        
                        if accessibilityEnabled {
                            // Hotkey is enabled
                            VStack(alignment: .leading, spacing: 12) {
                                // Current Hotkey Display
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Current Hotkey")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.secondary)
                                    
                                    // Hotkey Display Row
                                    HStack(spacing: 16) {
                                        // Clean Hotkey Display
                                        HStack(spacing: 8) {
                                            Text(hotkeyShortcut.displayString)
                                                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                                                .foregroundStyle(.primary)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .fill(.quaternary.opacity(0.5))
                                                        .overlay(
                                                            RoundedRectangle(cornerRadius: 8)
                                                                .stroke(.primary.opacity(0.2), lineWidth: 1)
                                                        )
                                                )
                                        }
                                        
                                        Spacer()
                                        
                                        // Enhanced Change Button
                                        Button {
                                            DebugLogger.shared.debug("Starting to record new shortcut", source: "SettingsView")
                                            isRecordingShortcut = true
                                        } label: {
                                            HStack(spacing: 8) {
                                                Image(systemName: "pencil")
                                                    .font(.system(size: 13, weight: .semibold))
                                                Text("Change")
                                                    .fontWeight(.semibold)
                                            }
                                        }
                                        .buttonStyle(GlassButtonStyle())
                                        .buttonHoverEffect()
                                        
                                        // Restart button for accessibility changes
                                        if !hotkeyManagerInitialized && accessibilityEnabled {
                                            Button {
                                                DebugLogger.shared.debug("User requested app restart for accessibility changes", source: "SettingsView")
                                                restartApp()
                                            } label: {
                                                HStack(spacing: 6) {
                                                    Image(systemName: "arrow.clockwise.circle")
                                                        .font(.system(size: 12, weight: .semibold))
                                                    Text("Restart")
                                                        .font(.system(size: 12, weight: .semibold))
                                                }
                                            }
                                            .buttonStyle(InlineButtonStyle())
                                            .buttonHoverEffect()
                                        }
                                    }
                                }
                                
                                // Enhanced Status/Instruction Text
                                HStack(spacing: 10) {
                                    if isRecordingShortcut {
                                        Image(systemName: "hand.point.up.left.fill")
                                            .foregroundStyle(.white)
                                            .font(.system(size: 16, weight: .medium))
                                        Text("Press your new hotkey combination now...")
                                            .font(.system(.subheadline, weight: .medium))
                                            .foregroundStyle(.white)
                                    } else if hotkeyManagerInitialized {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                            .font(.system(size: 16))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Global Shortcut Active")
                                                .font(.system(.caption, weight: .semibold))
                                                .foregroundStyle(.white)
                                            Text(pressAndHoldModeEnabled
                                                 ? "Hold \(hotkeyShortcut.displayString) to record and release to stop"
                                                 : "Press \(hotkeyShortcut.displayString) anywhere to start/stop recording")
                                                .font(.system(.caption))
                                                .foregroundStyle(.secondary)
                                        }
                                    } else {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                            .frame(width: 16, height: 16)
                                            .foregroundStyle(.orange)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Hotkey Initializing...")
                                                .font(.system(.caption, weight: .semibold))
                                                .foregroundStyle(.orange)
                                            Text("Please wait while the global hotkey system starts up")
                                                .font(.system(.caption))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(.ultraThinMaterial.opacity(0.5))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(.white.opacity(0.1), lineWidth: 1)
                                        )
                                )
                                
                                // Press and hold toggle
                                VStack(alignment: .leading, spacing: 10) {
                                    Toggle("Press and Hold Mode", isOn: $pressAndHoldModeEnabled)
                                        .toggleStyle(GlassToggleStyle())
                                    Text("When enabled, the shortcut only records while you hold it down, giving you quick push-to-talk style control.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(.ultraThinMaterial.opacity(0.5))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(.white.opacity(0.08), lineWidth: 1)
                                        )
                                )
                                .onChange(of: pressAndHoldModeEnabled) { newValue in
                                    SettingsStore.shared.pressAndHoldMode = newValue
                                    hotkeyManager?.enablePressAndHoldMode(newValue)
                                }
                                
                                // Streaming preview toggle
                                VStack(alignment: .leading, spacing: 10) {
                                    Toggle("Show Live Preview", isOn: $enableStreamingPreview)
                                        .toggleStyle(GlassToggleStyle())
                                    Text("Display transcription text in real-time in the overlay as you speak. When disabled, only the animation is shown.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(.ultraThinMaterial.opacity(0.5))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(.white.opacity(0.08), lineWidth: 1)
                                        )
                                )
                                .onChange(of: enableStreamingPreview) { newValue in
                                    SettingsStore.shared.enableStreamingPreview = newValue
                                    menuBarManager.updateOverlayPreviewSetting(newValue)
                                    if !newValue {
                                        menuBarManager.updateOverlayTranscription("")
                                    }
                                }
                                
                                // Copy to clipboard toggle
                                VStack(alignment: .leading, spacing: 10) {
                                    Toggle("Copy to Clipboard", isOn: $copyToClipboard)
                                        .toggleStyle(GlassToggleStyle())
                                    Text("Automatically copy transcribed text to clipboard as a backup, useful when no text field is selected.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(.ultraThinMaterial.opacity(0.5))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(.white.opacity(0.08), lineWidth: 1)
                                        )
                                )
                                .onChange(of: copyToClipboard) { newValue in
                                    SettingsStore.shared.copyTranscriptionToClipboard = newValue
                                }
                                
                                Divider()
                                    .padding(.vertical, 4)
                                
                                // Rewrite Mode Shortcut
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Rewrite Mode Shortcut")
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                            Text("Select text, press shortcut, speak how to rewrite")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        // Shortcut display
                                        if isRecordingRewriteShortcut {
                                            Text("Press new shortcut...")
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundStyle(.orange)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 5)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .fill(.orange.opacity(0.2))
                                                )
                                        } else {
                                            Text(rewriteShortcut.displayString)
                                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                                .foregroundStyle(.primary)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 5)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .fill(.quaternary.opacity(0.5))
                                                        .overlay(
                                                            RoundedRectangle(cornerRadius: 6)
                                                                .stroke(.primary.opacity(0.2), lineWidth: 1)
                                                        )
                                                )
                                        }
                                        
                                        // Change button
                                        Button {
                                            isRecordingRewriteShortcut = true
                                        } label: {
                                            Text("Change")
                                                .font(.system(size: 12, weight: .medium))
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(isRecordingRewriteShortcut)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(.ultraThinMaterial.opacity(0.5))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(.white.opacity(0.08), lineWidth: 1)
                                        )
                                )
                            }
                        } else {
                            // Hotkey disabled - accessibility not enabled
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 12) {
                                    // Status indicator
                                    Circle()
                                        .fill(theme.palette.warning)
                                        .frame(width: 10, height: 10)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundStyle(theme.palette.warning)
                                            Text("Accessibility permissions required")
                                                .fontWeight(.medium)
                                                .foregroundStyle(theme.palette.warning)
                                        }
                                        Text("Required for global hotkey functionality")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    
                                    Button("Open Accessibility Settings") {
                                        openAccessibilitySettings()
                                    }
                                    .buttonStyle(GlassButtonStyle())
                                    .buttonHoverEffect()
                                }
                                
                                // Prominent step-by-step instructions
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "info.circle.fill")
                                            .foregroundStyle(theme.palette.accent)
                                            .font(.caption)
                                        Text("Follow these steps to enable Accessibility:")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack(spacing: 8) {
                                            Text("1.")
                                                .font(.caption2)
                                                .foregroundStyle(theme.palette.accent)
                                                .fontWeight(.semibold)
                                                .frame(width: 16)
                                            Text("Click **Open Accessibility Settings** above")
                                                .font(.caption)
                                                .foregroundStyle(.primary)
                                        }
                                        HStack(spacing: 8) {
                                            Text("2.")
                                                .font(.caption2)
                                                .foregroundStyle(theme.palette.accent)
                                                .fontWeight(.semibold)
                                                .frame(width: 16)
                                            Text("In the Accessibility window, click the **+ button**")
                                                .font(.caption)
                                                .foregroundStyle(.primary)
                                        }
                                        HStack(spacing: 8) {
                                            Text("3.")
                                                .font(.caption2)
                                                .foregroundStyle(theme.palette.accent)
                                                .fontWeight(.semibold)
                                                .frame(width: 16)
                                            Text("Navigate to Applications and select **FluidVoice**")
                                                .font(.caption)
                                                .foregroundStyle(.primary)
                                        }
                                        HStack(spacing: 8) {
                                            Text("4.")
                                                .font(.caption2)
                                                .foregroundStyle(theme.palette.accent)
                                                .fontWeight(.semibold)
                                                .frame(width: 16)
                                            Text("Click **Open**, then toggle **FluidVoice ON** in the list")
                                                .font(.caption)
                                                .foregroundStyle(.primary)
                                        }
                                    }
                                    .padding(.leading, 4)
                                    
                                    // Helper buttons
                                    HStack(spacing: 12) {
                                        Button("Reveal FluidVoice in Finder") {
                                            revealAppInFinder()
                                        }
                                        .buttonStyle(InlineButtonStyle())
                                        .buttonHoverEffect()
                                        
                                        Button("Open Applications Folder") {
                                            openApplicationsFolder()
                                        }
                                        .buttonStyle(InlineButtonStyle())
                                        .buttonHoverEffect()
                                    }
                                }
                                .padding(12)
                                .background(theme.palette.warning.opacity(0.12))
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding(14)
                }
                
                // Audio Devices Card
                ThemedCard(style: .standard) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                            Text("Audio Devices")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                        
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Input Device")
                                    .fontWeight(.medium)
                                Spacer()
                                Picker("Input Device", selection: $selectedInputUID) {
                                    ForEach(inputDevices, id: \.uid) { dev in
                                        Text(dev.name).tag(dev.uid)
                                    }
                                }
                                .frame(width: 280)
                                .onChange(of: selectedInputUID) { newUID in
                                    SettingsStore.shared.preferredInputDeviceUID = newUID
                                    _ = AudioDevice.setDefaultInputDevice(uid: newUID)
                                    if asr.isRunning {
                                        asr.stopWithoutTranscription()
                                        startRecording()
                                    }
                                }
                            }

                            HStack {
                                Text("Output Device")
                                    .fontWeight(.medium)
                                Spacer()
                                Picker("Output Device", selection: $selectedOutputUID) {
                                    ForEach(outputDevices, id: \.uid) { dev in
                                        Text(dev.name).tag(dev.uid)
                                    }
                                }
                                .frame(width: 280)
                                .onChange(of: selectedOutputUID) { newUID in
                                    SettingsStore.shared.preferredOutputDeviceUID = newUID
                                    _ = AudioDevice.setDefaultOutputDevice(uid: newUID)
                                }
                            }

                            HStack(spacing: 12) {
                                Button {
                                    refreshDevices()
                                } label: {
                                    Label("Refresh", systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(GlassButtonStyle())
                                .buttonHoverEffect()

                                Spacer()
                                
                                if let defIn = AudioDevice.getDefaultInputDevice()?.name, 
                                   let defOut = AudioDevice.getDefaultOutputDevice()?.name {
                                    Text("Default In: \(defIn) · Default Out: \(defOut)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding(14)
                }
                
                // Visualization Sensitivity Card
                ThemedCard(style: .standard) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "waveform")
                                .font(.title2)
                                .foregroundStyle(.white)
                            Text("Visualization")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                        
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Visualization Sensitivity")
                                        .font(.system(size: 16, weight: .semibold))
                                    Text("Control how sensitive the audio visualizer is to sound input")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Button("Reset") {
                                    visualizerNoiseThreshold = 0.4
                                    SettingsStore.shared.visualizerNoiseThreshold = visualizerNoiseThreshold
                                }
                                .font(.system(size: 12))
                                .buttonStyle(GlassButtonStyle())
                                .buttonHoverEffect()
                            }
                            
                            HStack(spacing: 12) {
                                Text("More Sensitive")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .frame(width: 90)
                                
                                Slider(value: $visualizerNoiseThreshold, in: 0.01...0.8, step: 0.01)
                                    .controlSize(.regular)
                                
                                Text("Less Sensitive")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .frame(width: 90)
                                
                                Text(String(format: "%.2f", visualizerNoiseThreshold))
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .frame(width: 40)
                            }
                        }
                    }
                    .padding(14)
                }
                
                // Debug Settings Card
                ThemedCard(style: .standard) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "ladybug.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                            Text("Debug Settings")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Button {
                                let url = FileLogger.shared.currentLogFileURL()
                                if FileManager.default.fileExists(atPath: url.path) {
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                } else {
                                    DebugLogger.shared.info("Log file not found at \(url.path)", source: "SettingsView")
                                }
                            } label: {
                                Label("Reveal Log File", systemImage: "doc.richtext")
                                    .labelStyle(.titleAndIcon)
                            }
                            .buttonStyle(GlassButtonStyle())
                            .buttonHoverEffect()

                            Text("Click to reveal the debug log file. This file contains detailed information about app operations and can help with troubleshooting issues.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 4)
                        }
                    }
                    .padding(14)
                }
            }
            .padding(14)
        }
        .onAppear {
            refreshDevices()
        }
        .onChange(of: visualizerNoiseThreshold) { newValue in
            SettingsStore.shared.visualizerNoiseThreshold = newValue
        }
    }
}




