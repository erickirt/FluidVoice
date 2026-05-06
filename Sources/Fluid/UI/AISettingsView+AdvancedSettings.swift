//
//  AISettingsView+AdvancedSettings.swift
//  fluid
//
//  Extracted from AISettingsView.swift to keep view body under lint limit.
//

import AppKit
import SwiftUI

extension AIEnhancementSettingsView {
    // MARK: - Advanced Settings Card

    var advancedSettingsCard: some View {
        ThemedCard(style: .prominent, hoverEffect: false) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text("Prompt Profiles")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(self.theme.palette.primaryText)
                            Text(" - Manage prompt bodies here. Shortcut assignment lives in Keyboard Shortcuts.")
                                .font(.system(size: 13))
                                .foregroundStyle(self.theme.palette.secondaryText)
                        }
                        .lineLimit(1)
                        .truncationMode(.tail)
                    }

                    self.promptControlsRow
                    self.promptModeViewport(mode: self.selectedPromptMode)
                }
                .padding(.horizontal, 4)
            }
            .padding(14)
        }
        .sheet(item: self.$viewModel.promptEditorMode) { mode in
            self.promptEditorSheet(mode: mode)
        }
    }

    private func promptModeViewport(mode: SettingsStore.PromptMode) -> some View {
        self.promptModeSection(mode: mode)
            .frame(
                maxWidth: .infinity,
                minHeight: AISettingsLayout.promptModeMinHeight,
                alignment: .topLeading
            )
            .transaction { transaction in
                transaction.animation = nil
            }
    }

    func promptProfileCard(
        cardKey: String,
        title: String,
        subtitle: String,
        mode: SettingsStore.PromptMode,
        isSelected: Bool,
        onUse: @escaping () -> Void,
        onManage: (() -> Void)? = nil,
        onResetDefault: (() -> Void)? = nil,
        canResetDefault: Bool = false,
        onDelete: (() -> Void)? = nil
    ) -> some View {
        let tone = self.modeAccentColor(mode)
        let selectedStrokeOpacity: Double = mode.normalized == .dictate ? 0.52 : 0.38
        let isHovering = self.hoveredPromptCardKey == cardKey
        return HStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(isHovering ? tone.opacity(0.5) : .clear)
                .frame(width: 3, height: 34)

            Button(action: onUse) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(self.theme.palette.primaryText)
                        if mode.normalized == .edit {
                            Text("Context: Auto")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(tone.opacity(0.12))
                                )
                                .foregroundStyle(tone)
                        }
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? tone : self.theme.palette.secondaryText.opacity(0.35))
                    .frame(width: 18, height: 18)

                if onManage != nil || onResetDefault != nil || onDelete != nil {
                    Menu {
                        if let onManage {
                            Button("Edit Prompt") { onManage() }
                        }
                        if mode == .edit {
                            Divider()
                            Text("Selected text context is added automatically when text is selected.")
                        }
                        if let onDelete {
                            Divider()
                            Button(role: .destructive, action: { onDelete() }) {
                                Label("Delete Prompt", systemImage: "trash")
                            }
                        } else if let onResetDefault {
                            Divider()
                            Button("Reset to Built-in Default", role: .destructive) { onResetDefault() }
                                .disabled(!canResetDefault)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: AISettingsLayout.controlHeight, height: AISettingsLayout.controlHeight)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(self.theme.palette.secondaryText)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(self.theme.palette.cardBackground.opacity(0.64))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isHovering ? tone.opacity(mode.normalized == .dictate ? 0.06 : 0.045) : .clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isHovering ? tone.opacity(selectedStrokeOpacity) : self.theme.palette.cardBorder.opacity(0.3), lineWidth: 1)
                )
        )
        .onHover { hovering in
            if hovering {
                self.hoveredPromptCardKey = cardKey
            } else if self.hoveredPromptCardKey == cardKey {
                self.hoveredPromptCardKey = nil
            }
        }
        .animation(.easeOut(duration: 0.1), value: isHovering)
    }

    private var promptControlsRow: some View {
        ZStack {
            HStack(alignment: .center, spacing: 12) {
                Button("+ Add Prompt") {
                    self.viewModel.openNewPromptEditor(prefillMode: self.selectedPromptMode)
                }
                .buttonStyle(CompactButtonStyle(isReady: true))
                .frame(minWidth: AISettingsLayout.actionMinWidth, minHeight: AISettingsLayout.controlHeight)

                Spacer(minLength: 8)

                self.promptProcessingControl
            }

            self.promptModeTabSelector
        }
        .frame(maxWidth: .infinity)
    }

    private var promptProcessingControl: some View {
        let isOff = self.viewModel.isPrimaryDictationPromptSelectionOff()

        return HStack(alignment: .center, spacing: 7) {
            Text("AI Cleanup")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(self.theme.palette.secondaryText)
                .lineLimit(1)

            self.cleanupSegmentedControl(isOff: isOff, mode: .dictate)
        }
        .help(isOff ? "Off: dictation types the raw transcript. Prompts and app overrides are paused." : "On: dictation follows the selected prompt scope.")
    }

    private var promptModeTabSelector: some View {
        HStack(spacing: 2) {
            ForEach(SettingsStore.PromptMode.visiblePromptModes) { mode in
                self.promptModeTabButton(mode: mode)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(self.theme.palette.contentBackground.opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(self.theme.palette.cardBorder.opacity(0.22), lineWidth: 1)
                )
        )
    }

    private func promptModeTabButton(mode: SettingsStore.PromptMode) -> some View {
        let isSelected = mode.normalized == self.selectedPromptMode.normalized
        let isHovering = self.hoveredPromptModeKey == mode.normalized.rawValue
        let tone = self.modeAccentColor(mode)
        let cornerRadius: CGFloat = 12

        return Button {
            self.selectedPromptMode = mode.normalized
        } label: {
            HStack(spacing: 7) {
                Image(systemName: self.modeSymbol(mode))
                    .font(.system(size: 11, weight: .semibold))
                Text(self.friendlyModeName(mode))
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(isSelected ? tone : (isHovering ? self.theme.palette.primaryText : self.theme.palette.secondaryText))
            .frame(width: self.promptTabWidth(for: mode), height: 32)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .fluidControlSurface(
                isSelected: isSelected,
                isHovered: isHovering,
                tone: tone,
                cornerRadius: cornerRadius
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            self.hoveredPromptModeKey = hovering ? mode.normalized.rawValue : nil
        }
    }

    private func promptTabWidth(for mode: SettingsStore.PromptMode) -> CGFloat {
        switch mode.normalized {
        case .dictate:
            return 116
        case .edit, .write, .rewrite:
            return 124
        }
    }

    @ViewBuilder
    private func promptModeSection(mode: SettingsStore.PromptMode) -> some View {
        let customProfiles = self.viewModel.dictationPromptProfiles
            .filter { $0.mode.normalized == mode }
        let tone = self.modeAccentColor(mode)
        let isSelectedAppsOnly = self.viewModel.promptRoutingScope(for: mode) == .selectedAppsOnly
        let isPromptRoutingPaused = mode.normalized == .dictate && self.viewModel.isPrimaryDictationPromptSelectionOff()

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: self.modeSymbol(mode))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(tone.opacity(mode.normalized == .dictate ? 0.85 : 0.65)))
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(mode.normalized == .dictate ? "Dictation Prompt Profiles" : "Edit Text Mode")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(self.theme.palette.primaryText)
                    Text(" - \(self.promptSectionDescription(for: mode))")
                        .font(.caption)
                        .foregroundStyle(self.theme.palette.secondaryText)
                }
                .lineLimit(1)
                .truncationMode(.tail)
            }
            .padding(.horizontal, 2)

            self.promptModeHintRow(mode: mode)

            VStack(alignment: .leading, spacing: 8) {
                self.promptRoutingScopeRow(mode: mode)

                if isSelectedAppsOnly {
                    self.selectedAppsOnlySummary(mode: mode)
                    self.appPromptBindingsSection(mode: mode, isEmphasized: true)
                } else {
                    self.promptProfileCard(
                        cardKey: "\(mode.normalized.rawValue)-default",
                        title: mode.normalized == .dictate ? "Built-in Default" : "Default \(self.friendlyModeName(mode))",
                        subtitle: self.viewModel.promptPreview(self.viewModel.defaultPromptBodyPreview(for: mode)),
                        mode: mode,
                        isSelected: mode.normalized == .dictate
                            ? (!self.viewModel.isPrimaryDictationPromptSelectionOff() && self.viewModel.selectedPromptID(for: mode) == nil)
                            : self.viewModel.selectedPromptID(for: mode) == nil,
                        onUse: {
                            self.viewModel.setSelectedPromptID(nil, for: mode)
                        },
                        onManage: { self.viewModel.openDefaultPromptViewer(for: mode) },
                        onResetDefault: { self.viewModel.resetDefaultPromptOverride(for: mode) },
                        canResetDefault: self.viewModel.hasDefaultPromptOverride(for: mode)
                    )

                    if customProfiles.isEmpty {
                        Text("No custom \(self.friendlyModeName(mode).lowercased()) prompts yet.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    } else {
                        ForEach(customProfiles) { profile in
                            self.promptProfileCard(
                                cardKey: "\(profile.mode.normalized.rawValue)-\(profile.id)",
                                title: profile.name.isEmpty ? "Untitled Prompt" : profile.name,
                                subtitle: SettingsStore.stripBasePrompt(for: profile.mode, from: profile.prompt).isEmpty
                                    ? "Empty prompt (uses Default)"
                                    : self.viewModel.promptPreview(SettingsStore.stripBasePrompt(for: profile.mode, from: profile.prompt)),
                                mode: profile.mode,
                                isSelected: self.viewModel.selectedPromptID(for: profile.mode) == profile.id,
                                onUse: {
                                    self.viewModel.setSelectedPromptID(profile.id, for: profile.mode)
                                },
                                onManage: { self.viewModel.openEditor(for: profile) },
                                onDelete: { self.viewModel.requestDeletePrompt(profile) }
                            )
                        }
                    }

                    self.appPromptBindingsSection(mode: mode)
                }
            }
            .opacity(isPromptRoutingPaused ? 0.34 : 1)
            .grayscale(isPromptRoutingPaused ? 0.75 : 0)
            .allowsHitTesting(!isPromptRoutingPaused)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(self.theme.palette.cardBackground.opacity(0.68))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(self.theme.palette.cardBorder.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private func promptModeHintRow(mode: SettingsStore.PromptMode) -> some View {
        HStack {
            if mode.normalized == .dictate {
                Text("Shortcut preview only. Assign shortcuts in Keyboard Shortcuts.")
                    .font(.caption2)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(height: AISettingsLayout.promptModeHintHeight, alignment: .topLeading)
        .padding(.horizontal, 4)
    }

    private func cleanupSegmentedControl(isOff: Bool, mode: SettingsStore.PromptMode) -> some View {
        let tone = self.modeAccentColor(mode)

        return
            HStack(spacing: 4) {
                self.cleanupSegmentButton(
                    title: "Off",
                    key: "off",
                    isSelected: isOff,
                    tone: tone,
                    action: { self.viewModel.selectPrimaryDictationPromptOff() }
                )

                self.cleanupSegmentButton(
                    title: "On",
                    key: "on",
                    isSelected: !isOff,
                    tone: tone,
                    action: { self.viewModel.setSelectedPromptID(nil, for: mode) }
                )
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(self.theme.palette.contentBackground.opacity(0.78))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(self.theme.palette.cardBorder.opacity(0.22), lineWidth: 1)
                    )
            )
    }

    private func cleanupSegmentButton(
        title: String,
        key: String,
        isSelected: Bool,
        tone: Color,
        action: @escaping () -> Void
    ) -> some View {
        let isHovering = self.hoveredCleanupControlKey == key
        let cornerRadius: CGFloat = 9

        return Button(title, action: action)
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .fluidControlSurface(
                isSelected: isSelected,
                isHovered: isHovering,
                tone: tone,
                cornerRadius: cornerRadius
            )
            .foregroundStyle(isSelected ? tone : (isHovering ? self.theme.palette.primaryText : self.theme.palette.secondaryText))
            .onHover { hovering in
                self.hoveredCleanupControlKey = hovering ? key : nil
            }
    }

    private func promptRoutingScopeRow(mode: SettingsStore.PromptMode) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(mode.normalized == .dictate ? "Use cleanup" : "Use prompts")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(self.theme.palette.secondaryText)
                .frame(width: AISettingsLayout.promptScopeLabelWidth, alignment: .leading)

            HStack(spacing: 4) {
                self.promptRoutingScopeButton(
                    title: "All apps",
                    scope: .allApps,
                    mode: mode
                )
                self.promptRoutingScopeButton(
                    title: "Selected apps only",
                    scope: .selectedAppsOnly,
                    mode: mode
                )
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(self.theme.palette.contentBackground.opacity(0.78))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(self.theme.palette.cardBorder.opacity(0.22), lineWidth: 1)
                    )
            )

            Spacer(minLength: 12)

            if mode.normalized == .edit {
                self.editModeInlineModelControls
            } else {
                Color.clear
                    .frame(height: AISettingsLayout.controlHeight)
            }
        }
        .frame(minHeight: AISettingsLayout.controlHeight)
        .padding(.top, 2)
        .padding(.horizontal, 4)
    }

    private func promptRoutingScopeButton(
        title: String,
        scope: SettingsStore.PromptRoutingScope,
        mode: SettingsStore.PromptMode
    ) -> some View {
        let selectedScope = self.viewModel.promptRoutingScope(for: mode)
        let isSelected = selectedScope == scope
        let key = "\(mode.normalized.rawValue)-\(scope.rawValue)"
        let isHovering = self.hoveredPromptScopeKey == key
        let tone = self.modeAccentColor(mode)
        let cornerRadius: CGFloat = 9

        return Button {
            self.viewModel.setPromptRoutingScope(scope, for: mode)
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? tone : (isHovering ? self.theme.palette.primaryText : self.theme.palette.secondaryText))
                .frame(width: scope == .allApps ? 72 : 132, height: 26)
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .fluidControlSurface(
                    isSelected: isSelected,
                    isHovered: isHovering,
                    tone: tone,
                    cornerRadius: cornerRadius
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            self.hoveredPromptScopeKey = hovering ? key : nil
        }
    }

    private func selectedAppsOnlySummary(mode: SettingsStore.PromptMode) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "target")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(self.theme.palette.accent)
                .frame(width: 18, height: 18)

            Text(mode.normalized == .dictate
                ? "No default cleanup. Add app overrides to use prompts in selected apps."
                : "Default edit stays built-in. App overrides can use custom prompts."
            )
            .font(.caption2)
            .foregroundStyle(self.theme.palette.secondaryText)
            .lineLimit(1)

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(self.theme.palette.cardBackground.opacity(0.34))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(self.theme.palette.cardBorder.opacity(0.22), lineWidth: 1)
                )
        )
    }

    private var editModeInlineModelControls: some View {
        let verified = self.editModeVerifiedProviders

        return HStack(alignment: .center, spacing: 10) {
            Text("Edit model")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(self.theme.palette.secondaryText)

            if verified.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("No verified provider")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                let providerID = self.activeEditModeProviderID
                let models = self.viewModel.models(for: providerID)
                Group {
                    Toggle("Sync", isOn: self.editModeLinkedToGlobalBinding)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: true, vertical: false)
                        .onChange(of: self.settings.rewriteModeLinkedToGlobal) { _, linked in
                            if linked {
                                self.syncEditModeToGlobalSelection()
                            } else {
                                self.normalizeEditModeProviderSelection()
                            }
                        }

                    Text("Provider")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("", selection: self.editModeProviderBinding) {
                        ForEach(verified) { provider in
                            Text(provider.name).tag(provider.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: AISettingsLayout.promptInlinePickerWidth)
                    .disabled(self.settings.rewriteModeLinkedToGlobal)

                    Text("Model")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    SearchableModelPicker(
                        models: models,
                        selectedModel: self.editModeModelBinding(for: providerID),
                        onRefresh: { await self.viewModel.fetchModels(for: providerID) },
                        isRefreshing: self.viewModel.refreshingProviderID == providerID,
                        refreshEnabled: !self.settings.rewriteModeLinkedToGlobal && self.canFetchModels(for: providerID),
                        selectionEnabled: !self.settings.rewriteModeLinkedToGlobal && !models.isEmpty,
                        controlWidth: AISettingsLayout.promptInlineModelWidth,
                        controlHeight: 26
                    )
                    .disabled(self.settings.rewriteModeLinkedToGlobal)
                }
                .opacity(self.settings.rewriteModeLinkedToGlobal ? 0.65 : 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .onAppear {
            self.ensureDefaultEditModeSyncState()
            if !verified.isEmpty {
                self.normalizeEditModeProviderSelection()
            }
        }
    }

    @ViewBuilder
    private func appPromptBindingsSection(mode: SettingsStore.PromptMode, isEmphasized: Bool = false) -> some View {
        let bindings = self.viewModel.appBindings(for: mode)
        let appTargets = self.viewModel.appBindingTargets(for: mode)
        let modeProfiles = self.viewModel.dictationPromptProfiles
            .filter { $0.mode.normalized == mode.normalized }

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Text("App Overrides")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(self.theme.palette.secondaryText)

                Menu {
                    if appTargets.isEmpty {
                        Text("No unassigned running apps")
                    } else {
                        ForEach(appTargets) { target in
                            Button(self.appBindingTargetMenuTitle(target)) {
                                self.viewModel.addAppPromptBinding(
                                    for: mode,
                                    appBundleID: target.bundleID,
                                    appName: target.name
                                )
                            }
                        }
                    }

                    Divider()

                    Button("Choose App…") {
                        self.viewModel.addAppPromptBindingFromFilePicker(for: mode)
                    }
                } label: {
                    Text("+ Add App")
                }
                .buttonStyle(CompactButtonStyle(isReady: true))
                .frame(minHeight: 26)

                Spacer(minLength: 8)
            }

            Text(isEmphasized ? "Use prompts only in selected apps." : "Use a different prompt only in selected apps.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            if bindings.isEmpty {
                Text("No app overrides yet. Add one to use a different prompt for a specific app.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            } else {
                ForEach(bindings) { binding in
                    self.appPromptBindingRow(
                        binding: binding,
                        mode: mode,
                        modeProfiles: modeProfiles
                    )
                }
            }
        }
        .padding(.top, isEmphasized ? 2 : 6)
    }

    @ViewBuilder
    private func appPromptBindingRow(
        binding: SettingsStore.AppPromptBinding,
        mode: SettingsStore.PromptMode,
        modeProfiles: [SettingsStore.DictationPromptProfile]
    ) -> some View {
        HStack(spacing: 10) {
            self.appIconView(bundleID: binding.appBundleID)

            VStack(alignment: .leading, spacing: 2) {
                Text(binding.appName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(self.theme.palette.primaryText)
                    .lineLimit(1)
                Text(binding.appBundleID)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Menu {
                Button("Default") {
                    self.viewModel.setPromptID(nil, for: binding)
                }

                Divider()

                Button("Create New Prompt…") {
                    self.viewModel.openNewPromptEditor(prefillMode: mode)
                }

                if !modeProfiles.isEmpty {
                    Divider()
                    ForEach(modeProfiles) { profile in
                        Button(profile.name.isEmpty ? "Untitled Prompt" : profile.name) {
                            self.viewModel.setPromptID(profile.id, for: binding)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(self.viewModel.promptName(for: mode, promptID: binding.promptID))
                        .font(.caption)
                        .foregroundStyle(self.theme.palette.primaryText)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(self.theme.palette.cardBackground.opacity(0.5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(self.theme.palette.cardBorder.opacity(0.35), lineWidth: 1)
                        )
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize(horizontal: true, vertical: false)

            Button {
                self.viewModel.removeAppPromptBinding(binding)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.red.opacity(0.9))
            }
            .buttonStyle(.plain)
            .help("Remove app-specific override")
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(self.theme.palette.cardBackground.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(self.theme.palette.cardBorder.opacity(0.2), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func appIconView(bundleID: String) -> some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(self.theme.palette.secondaryText)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(self.theme.palette.cardBackground.opacity(0.55))
                )
        }
    }

    private var editModeVerifiedProviders: [AIEnhancementSettingsViewModel.ProviderItemData] {
        self.viewModel.cachedVerifiedProviderItems.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var editModeSelectedProviderID: String {
        let current = self.settings.rewriteModeSelectedProviderID
        if self.editModeVerifiedProviders.contains(where: { $0.id == current }) {
            return current
        }
        return self.editModeVerifiedProviders.first?.id ?? current
    }

    private var activeEditModeProviderID: String {
        if self.settings.rewriteModeLinkedToGlobal {
            let global = self.viewModel.selectedProviderID
            if self.editModeVerifiedProviders.contains(where: { $0.id == global }) {
                return global
            }
            return self.editModeSelectedProviderID
        }
        return self.editModeSelectedProviderID
    }

    private var editModeLinkedToGlobalBinding: Binding<Bool> {
        Binding(
            get: { self.settings.rewriteModeLinkedToGlobal },
            set: { self.settings.rewriteModeLinkedToGlobal = $0 }
        )
    }

    private var editModeProviderBinding: Binding<String> {
        Binding(
            get: { self.activeEditModeProviderID },
            set: { newProviderID in
                guard !self.settings.rewriteModeLinkedToGlobal else { return }
                self.settings.rewriteModeSelectedProviderID = newProviderID
                let models = self.viewModel.models(for: newProviderID)
                let current = self.settings.rewriteModeSelectedModel ?? ""
                if !models.contains(current) {
                    self.settings.rewriteModeSelectedModel = models.first
                }
            }
        )
    }

    private func editModeModelBinding(for providerID: String) -> Binding<String> {
        Binding(
            get: {
                if self.settings.rewriteModeLinkedToGlobal {
                    let key = self.viewModel.providerKey(for: providerID)
                    return self.settings.selectedModelByProvider[key]
                        ?? self.settings.selectedModel
                        ?? self.viewModel.models(for: providerID).first
                        ?? ""
                }
                return self.settings.rewriteModeSelectedModel ?? self.viewModel.models(for: providerID).first ?? ""
            },
            set: { newModel in
                guard !self.settings.rewriteModeLinkedToGlobal else { return }
                self.settings.rewriteModeSelectedModel = newModel
            }
        )
    }

    private func normalizeEditModeProviderSelection() {
        guard let first = self.editModeVerifiedProviders.first else { return }
        let current = self.settings.rewriteModeSelectedProviderID
        if !self.editModeVerifiedProviders.contains(where: { $0.id == current }) {
            self.settings.rewriteModeSelectedProviderID = first.id
        }

        let providerID = self.settings.rewriteModeSelectedProviderID
        let models = self.viewModel.models(for: providerID)
        let currentModel = self.settings.rewriteModeSelectedModel ?? ""
        if !models.contains(currentModel) {
            self.settings.rewriteModeSelectedModel = models.first
        }
    }

    private func syncEditModeToGlobalSelection() {
        let global = self.viewModel.selectedProviderID
        let providerID: String
        if self.editModeVerifiedProviders.contains(where: { $0.id == global }) {
            providerID = global
        } else if let fallback = self.editModeVerifiedProviders.first?.id {
            providerID = fallback
        } else {
            providerID = global
        }
        self.settings.rewriteModeSelectedProviderID = providerID

        let key = self.viewModel.providerKey(for: providerID)
        let model = self.settings.selectedModelByProvider[key]
            ?? self.settings.selectedModel
            ?? self.viewModel.models(for: providerID).first
        self.settings.rewriteModeSelectedModel = model
    }

    private func ensureDefaultEditModeSyncState() {
        // If no persisted value exists yet, default Sync to ON.
        if UserDefaults.standard.object(forKey: "RewriteModeLinkedToGlobal") == nil {
            self.settings.rewriteModeLinkedToGlobal = true
            self.syncEditModeToGlobalSelection()
        }
    }

    private func canFetchModels(for providerID: String) -> Bool {
        let key = self.viewModel.providerKey(for: providerID)
        let apiKey = self.viewModel.providerAPIKeys[key] ?? ""
        let hasAPIKey = !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let baseURL: String
        if let saved = self.viewModel.savedProviders.first(where: { $0.id == providerID }) {
            baseURL = saved.baseURL
        } else {
            baseURL = ModelRepository.shared.defaultBaseURL(for: providerID)
        }
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let isLocal = self.viewModel.isLocalEndpoint(trimmedBaseURL)

        return isLocal ? !trimmedBaseURL.isEmpty : (hasAPIKey && !trimmedBaseURL.isEmpty)
    }

    private func promptSectionDescription(for mode: SettingsStore.PromptMode) -> String {
        switch mode {
        case .dictate:
            return "Create dictation prompt bodies here. The primary shortcut preview is shown here; both shortcut assignments are set in Keyboard Shortcuts."
        case .edit, .write, .rewrite:
            return "Uses selected text as context (when text is selected) - Edit or rewrite selected text - answer questions, summarize, convert to bullets etc."
        }
    }

    private func modeAccentColor(_ mode: SettingsStore.PromptMode) -> Color {
        _ = mode
        return self.theme.palette.accent
    }

    private func appBindingTargetMenuTitle(_ target: AIEnhancementSettingsViewModel.AppBindingTarget) -> String {
        if target.name.caseInsensitiveCompare(target.bundleID) == .orderedSame {
            return target.bundleID
        }
        return "\(target.name) (\(target.bundleID))"
    }

    private func modeSymbol(_ mode: SettingsStore.PromptMode) -> String {
        switch mode.normalized {
        case .dictate:
            return "mic.fill"
        case .edit, .write, .rewrite:
            return "square.and.pencil"
        }
    }

    private func friendlyModeName(_ mode: SettingsStore.PromptMode) -> String {
        switch mode.normalized {
        case .dictate:
            return "Dictate"
        case .edit, .write, .rewrite:
            return "Edit Text"
        }
    }

    func promptEditorSheet(mode: PromptEditorMode) -> some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text({
                        switch mode {
                        case let .defaultPrompt(promptMode): return "Default \(self.friendlyModeName(promptMode)) Prompt"
                        case let .newPrompt(prefillMode): return "New \(self.friendlyModeName(prefillMode)) Prompt"
                        case .edit: return "Edit Prompt"
                        }
                    }())
                        .font(.headline)
                    Text(mode.isDefault
                        ? "This is the built-in prompt. Create a custom prompt to override it."
                        : "Prompt text is appended to the hidden base prompt for the selected mode."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Mode")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: self.$viewModel.draftPromptMode) {
                    ForEach(SettingsStore.PromptMode.visiblePromptModes) { mode in
                        Text(self.friendlyModeName(mode)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(mode.isDefault)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                let isDefaultNameLocked = mode.isDefault
                TextField("Prompt name", text: self.$viewModel.draftPromptName)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isDefaultNameLocked)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Prompt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                PromptTextView(
                    text: self.$viewModel.draftPromptText,
                    isEditable: true,
                    font: NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
                )
                .id(self.viewModel.promptEditorSessionID)
                .frame(minHeight: 180)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(self.theme.palette.contentBackground.opacity(0.7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(self.theme.palette.cardBorder.opacity(0.35), lineWidth: 1)
                        )
                )
                .onChange(of: self.viewModel.draftPromptText) { _, newValue in
                    guard self.viewModel.draftPromptMode == .dictate else { return }
                    let combined = self.viewModel.combinedDraftPrompt(newValue, mode: self.viewModel.draftPromptMode)
                    self.promptTest.updateDraftPromptText(combined)
                }
            }

            if self.viewModel.draftPromptMode != .dictate {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Selected text is added automatically when text is selected.")
                        .font(.caption)
                        .foregroundStyle(self.theme.palette.secondaryText)

                    Text("Context block added automatically:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(SettingsStore.contextTemplateText())
                        .font(.system(.caption2, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(self.theme.palette.contentBackground.opacity(0.7))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(self.theme.palette.cardBorder.opacity(0.35), lineWidth: 1)
                                )
                        )
                }
            }

            // MARK: - Test Mode

            if self.viewModel.draftPromptMode == .dictate {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform")
                            .foregroundStyle(self.theme.palette.accent)
                        Text("Test")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                    }

                    let hotkeyDisplay = self.settings.hotkeyShortcut.displayString
                    let canTest = self.viewModel.isAIPostProcessingConfiguredForDictation()

                    Toggle(isOn: Binding(
                        get: { self.promptTest.isActive },
                        set: { enabled in
                            if enabled {
                                let combined = self.viewModel.combinedDraftPrompt(self.viewModel.draftPromptText, mode: self.viewModel.draftPromptMode)
                                self.promptTest.activate(draftPromptText: combined)
                            } else {
                                self.promptTest.deactivate()
                            }
                        }
                    )) {
                        Text("Enable Test Mode (Hotkey: \(hotkeyDisplay))")
                            .font(.caption)
                    }
                    .toggleStyle(.switch)
                    .disabled(!canTest)

                    if !canTest {
                        Text("Testing is disabled because AI post-processing is not configured.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if self.promptTest.isActive {
                        Text("Press the hotkey to start/stop recording. The transcription will be post-processed using your draft prompt and shown below (nothing will be typed into other apps).")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if self.promptTest.isActive {
                        if self.promptTest.isProcessing {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small).fixedSize()
                                Text("Processing…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if !self.promptTest.lastError.isEmpty {
                            Text(self.promptTest.lastError)
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Raw transcription")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            TextEditor(text: Binding(
                                get: { self.promptTest.lastTranscriptionText },
                                set: { _ in }
                            ))
                            .font(.system(.caption, design: .monospaced))
                            .frame(minHeight: 70)
                            .scrollContentBackground(.hidden)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(self.theme.palette.contentBackground.opacity(0.7))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(self.theme.palette.cardBorder.opacity(0.35), lineWidth: 1)
                                    )
                            )
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Post-processed output")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            TextEditor(text: Binding(
                                get: { self.promptTest.lastOutputText },
                                set: { _ in }
                            ))
                            .font(.system(.caption, design: .monospaced))
                            .frame(minHeight: 110)
                            .scrollContentBackground(.hidden)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(self.theme.palette.contentBackground.opacity(0.7))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(self.theme.palette.cardBorder.opacity(0.35), lineWidth: 1)
                                    )
                            )
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(self.theme.palette.accent.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(self.theme.palette.cardBorder.opacity(0.5), lineWidth: 1)
                        )
                )
            } else if self.promptTest.isActive {
                Text("Prompt test mode is available only for Dictate prompts.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .onAppear { self.promptTest.deactivate() }
            }

            HStack(spacing: 10) {
                Button(mode.isDefault ? "Close" : "Cancel") {
                    self.viewModel.closePromptEditor()
                }
                .buttonStyle(CompactButtonStyle())
                .frame(minWidth: AISettingsLayout.actionMinWidth, minHeight: AISettingsLayout.controlHeight)

                Button("Save") {
                    self.viewModel.savePromptEditor(mode: mode)
                }
                .buttonStyle(GlassButtonStyle(height: AISettingsLayout.controlHeight))
                .frame(minWidth: AISettingsLayout.actionMinWidth, minHeight: AISettingsLayout.controlHeight)
                .disabled(!mode.isDefault && self.viewModel.draftPromptName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 420)
        .onDisappear {
            self.promptTest.deactivate()
        }
        .onChange(of: self.viewModel.selectedProviderID) { _, _ in
            self.autoDisablePromptTestIfNeeded()
        }
        .onChange(of: self.viewModel.providerAPIKeys) { _, _ in
            self.autoDisablePromptTestIfNeeded()
        }
        .onChange(of: self.viewModel.savedProviders) { _, _ in
            self.autoDisablePromptTestIfNeeded()
        }
    }

    private func autoDisablePromptTestIfNeeded() {
        guard self.promptTest.isActive else { return }
        if !self.viewModel.isAIPostProcessingConfiguredForDictation() {
            self.promptTest.deactivate()
        }
    }

    func openDefaultPromptViewer(for mode: SettingsStore.PromptMode) {
        self.viewModel.openDefaultPromptViewer(for: mode)
    }

    func openNewPromptEditor(prefillMode: SettingsStore.PromptMode = .edit) {
        self.viewModel.openNewPromptEditor(prefillMode: prefillMode)
    }

    func openEditor(for profile: SettingsStore.DictationPromptProfile) {
        self.viewModel.openEditor(for: profile)
    }

    func closePromptEditor() {
        self.viewModel.closePromptEditor()
    }

    // MARK: - Prompt Test Gating

    func isAIPostProcessingConfiguredForDictation() -> Bool {
        self.viewModel.isAIPostProcessingConfiguredForDictation()
    }

    func savePromptEditor(mode: PromptEditorMode) {
        self.viewModel.savePromptEditor(mode: mode)
    }
}
