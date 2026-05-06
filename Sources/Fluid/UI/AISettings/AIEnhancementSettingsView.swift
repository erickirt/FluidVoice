import SwiftUI

struct AIEnhancementSettingsView: View {
    @ObservedObject var viewModel: AIEnhancementSettingsViewModel
    @ObservedObject var settings: SettingsStore
    @ObservedObject var promptTest: DictationPromptTestCoordinator
    let theme: AppTheme
    @State var expandedProviderID: String? = nil
    @State var providerSearchText: String = ""
    @State var fluid1InterestEmail: String = ""
    @State var fluid1InterestErrorMessage: String = ""
    @State var fluid1InterestIsSubmitting: Bool = false
    @State var hoveredPromptCardKey: String? = nil
    @State var selectedPromptMode: SettingsStore.PromptMode = .dictate
    @State var hoveredPromptModeKey: String? = nil
    @State var hoveredCleanupControlKey: String? = nil
    @State var hoveredPromptScopeKey: String? = nil

    var body: some View {
        self.aiConfigurationCard
            .onAppear {
                self.viewModel.onAppear()
            }
            .onChange(of: self.viewModel.connectionStatus) { oldValue, newValue in
                if oldValue == .success && newValue != .success {
                    self.expandedProviderID = self.viewModel.selectedProviderID
                }
            }
            .onChange(of: self.viewModel.showKeychainPermissionAlert) { _, isPresented in
                guard isPresented else { return }
                self.viewModel.presentKeychainAccessAlert(message: self.viewModel.keychainPermissionMessage)
                self.viewModel.showKeychainPermissionAlert = false
            }
            .alert("Delete Prompt?", isPresented: self.$viewModel.showingDeletePromptConfirm) {
                Button("Delete", role: .destructive) {
                    self.viewModel.deletePendingPrompt()
                }
                Button("Cancel", role: .cancel) {
                    self.viewModel.clearPendingDeletePrompt()
                }
            } message: {
                if self.viewModel.pendingDeletePromptName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("This cannot be undone.")
                } else {
                    Text("Delete “\(self.viewModel.pendingDeletePromptName)”? This cannot be undone.")
                }
            }
            .alert(
                "Couldn't Add App Override",
                isPresented: Binding(
                    get: { !self.viewModel.appPromptBindingErrorMessage.isEmpty },
                    set: { isPresented in
                        if !isPresented {
                            self.viewModel.appPromptBindingErrorMessage = ""
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {
                    self.viewModel.appPromptBindingErrorMessage = ""
                }
            } message: {
                Text(self.viewModel.appPromptBindingErrorMessage)
            }
    }
}
