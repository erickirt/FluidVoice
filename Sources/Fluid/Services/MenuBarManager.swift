import AppKit
import Combine
import PromiseKit
import SwiftUI

@MainActor
final class MenuBarManager: ObservableObject {
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private var isSetup: Bool = false
    
    // Cached menu items to avoid rebuilding entire menu
    private var statusMenuItem: NSMenuItem?
    private var aiMenuItem: NSMenuItem?
    
    // References to app state
    private weak var asrService: ASRService?
    private var cancellables = Set<AnyCancellable>()
    
    // Overlay management (persistent, independent of window lifecycle)
    private var overlayVisible: Bool = false
    
    @Published var isRecording: Bool = false
    @Published var aiProcessingEnabled: Bool = false
    
    // Track current overlay mode for notch
    private var currentOverlayMode: OverlayMode = .dictation
    
    // Track pending overlay operations to prevent spam
    private var pendingShowOperation: DispatchWorkItem?
    private var pendingHideOperation: DispatchWorkItem?
    
    init() {
        // Don't setup menu bar immediately - defer until app is ready
        // Initialize from persisted setting
        aiProcessingEnabled = SettingsStore.shared.enableAIProcessing
        // Reflect changes to menu when toggled from elsewhere (e.g., General tab)
        $aiProcessingEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateMenu()
            }
            .store(in: &cancellables)
    }
    
    func initializeMenuBar() {
        guard !isSetup else { return }
        
        // Ensure we're on main thread and app is active
        DispatchQueue.main.async { [weak self] in
            self?.setupMenuBarSafely()
        }
    }
    
    deinit {
        statusItem = nil
    }
    
    func configure(asrService: ASRService) {
        self.asrService = asrService
        
        // Subscribe to recording state changes
        asrService.$isRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRunning in
                self?.isRecording = isRunning
                self?.updateMenuBarIcon()
                self?.updateMenu()
                
                // Handle overlay lifecycle (independent of window state)
                self?.handleOverlayState(isRunning: isRunning, asrService: asrService)
            }
            .store(in: &cancellables)
        
        // Subscribe to partial transcription updates for streaming preview
        asrService.$partialTranscription
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newText in
                guard self != nil else { return }
                NotchOverlayManager.shared.updateTranscriptionText(newText)
            }
            .store(in: &cancellables)
        
        // Subscribe to AI processing state
        aiProcessingEnabled = SettingsStore.shared.enableAIProcessing
    }
    
    private func handleOverlayState(isRunning: Bool, asrService: ASRService) {
        // Prevent rapid state changes that could cause cycles
        guard overlayVisible != isRunning else { return }
        
        let delay: DispatchTimeInterval = .milliseconds(150)
        if isRunning {
            // Cancel any pending hide operation
            pendingHideOperation?.cancel()
            pendingHideOperation = nil
            
            overlayVisible = true
            
            let showItem = DispatchWorkItem { [weak self] in
                guard let self = self, self.overlayVisible else { return }
                
                // Show notch overlay
                NotchOverlayManager.shared.show(
                    audioLevelPublisher: asrService.audioLevelPublisher,
                    mode: self.currentOverlayMode
                )
                
                self.pendingShowOperation = nil
            }
            pendingShowOperation = showItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: showItem)
        } else {
            // Cancel any pending show operation
            pendingShowOperation?.cancel()
            pendingShowOperation = nil
            
            overlayVisible = false
            
            let hideItem = DispatchWorkItem { [weak self] in
                guard let self = self, !self.overlayVisible else { return }
                
                // Hide notch overlay
                NotchOverlayManager.shared.hide()
                
                self.pendingHideOperation = nil
            }
            pendingHideOperation = hideItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: hideItem)
        }
    }
    
    // MARK: - Public API for overlay management
    func updateOverlayTranscription(_ text: String) {
        NotchOverlayManager.shared.updateTranscriptionText(text)
    }
    
    func setOverlayMode(_ mode: OverlayMode) {
        currentOverlayMode = mode
        NotchOverlayManager.shared.setMode(mode)
    }
    
    func setProcessing(_ processing: Bool) {
        if processing {
            // Cancel any pending hide - we want to keep the overlay visible for AI processing
            pendingHideOperation?.cancel()
            pendingHideOperation = nil
            overlayVisible = true
        } else {
            // When processing ends, schedule the hide
            overlayVisible = false
            let hideItem = DispatchWorkItem { [weak self] in
                guard let self = self, !self.overlayVisible else { return }
                NotchOverlayManager.shared.hide()
                self.pendingHideOperation = nil
            }
            pendingHideOperation = hideItem
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100), execute: hideItem)
        }
        NotchOverlayManager.shared.setProcessing(processing)
    }
    
    private func setupMenuBarSafely() {
        // Check if window server connection is available
        guard NSApp.isActive || NSApp.isRunning else {
            // Retry after a short delay if app isn't ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.setupMenuBarSafely()
            }
            return
        }
        
        do {
            try setupMenuBar()
            isSetup = true
        } catch {
            // If setup fails, retry after delay
            print("MenuBar setup failed, retrying: \(error)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.setupMenuBarSafely()
            }
        }
    }
    
    private func setupMenuBar() throws {
        // Ensure we're not already set up
        guard !isSetup else { return }
        
        // Create status item with error handling
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        guard let statusItem = statusItem else { 
            throw NSError(domain: "MenuBarManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create status item"])
        }
        
        // Set initial icon
        updateMenuBarIcon()
        
        // Create menu
        menu = NSMenu()
        statusItem.menu = menu
        
        updateMenu()
    }
    
    private func updateMenuBarIcon() {
        guard let statusItem = statusItem else { return }
        
        // Use custom F icon instead of microphone
        let image = createFluidIcon(isRecording: isRecording)
        
        statusItem.button?.image = image
        statusItem.button?.imagePosition = .imageOnly
    }
    
    private func createFluidIcon(isRecording: Bool) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size)
        
        image.lockFocus()
        
        // Create F shape path
        let path = NSBezierPath()
        let lineWidth: CGFloat = 2.0
        
        // F shape coordinates (scaled to 16x16)
        let leftX: CGFloat = 2
        let rightX: CGFloat = 12
        let topY: CGFloat = 14
        let bottomY: CGFloat = 2
        let middleY: CGFloat = 8.5
        
        // Vertical line (left side of F)
        path.move(to: NSPoint(x: leftX, y: bottomY))
        path.line(to: NSPoint(x: leftX, y: topY))
        
        // Top horizontal line (full width)
        path.line(to: NSPoint(x: rightX, y: topY))
        
        // Middle horizontal line
        path.move(to: NSPoint(x: leftX, y: middleY))
        path.line(to: NSPoint(x: rightX - 2, y: middleY))
        
        // Set color based on recording state
        let color = isRecording ? NSColor.systemRed : NSColor.controlAccentColor
        color.set()
        
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
        
        image.unlockFocus()
        image.isTemplate = true
        
        return image
    }
    
    private func buildMenuStructure() {
        guard let menu = menu else { return }
        
        menu.removeAllItems()
        
        // Status indicator with hotkey info
        statusMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        statusMenuItem?.isEnabled = false
        menu.addItem(statusMenuItem!)
        
        menu.addItem(.separator())
        
        // AI Processing Toggle
        aiMenuItem = NSMenuItem(title: "", action: #selector(toggleAIProcessing), keyEquivalent: "")
        aiMenuItem?.target = self
        menu.addItem(aiMenuItem!)
        
        menu.addItem(.separator())
        
        // Open Main Window
        let openItem = NSMenuItem(title: "Open FluidVoice", action: #selector(openMainWindow), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        
        // Show What's New (for testing)
        #if DEBUG
        let whatsNewItem = NSMenuItem(title: "Show What's New", action: #selector(showWhatsNew), keyEquivalent: "")
        whatsNewItem.target = self
        menu.addItem(whatsNewItem)
        #endif
        
        // Check for Updates
        let updateItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates(_:)), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)
        
        menu.addItem(.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "Quit FluidVoice", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)
        
        // Now update the text content
        updateMenuItemsText()
    }
    
    private func updateMenu() {
        // If menu structure hasn't been built yet, build it
        if statusMenuItem == nil {
            buildMenuStructure()
        } else {
            // Just update the text of existing items
            updateMenuItemsText()
        }
    }
    
    private func updateMenuItemsText() {
        // Update status text with hotkey info
        let hotkeyShortcut = SettingsStore.shared.hotkeyShortcut
        let hotkeyInfo = hotkeyShortcut.displayString.isEmpty ? "" : " (\(hotkeyShortcut.displayString))"
        let statusTitle = isRecording ? "Recording...\(hotkeyInfo)" : "Ready to Record\(hotkeyInfo)"
        statusMenuItem?.title = statusTitle
        
        // Update AI toggle text
        let aiTitle = aiProcessingEnabled ? "Disable AI Processing" : "Enable AI Processing"
        aiMenuItem?.title = aiTitle
    }
    
    @objc private func toggleAIProcessing() {
        aiProcessingEnabled.toggle()
        // Persist and broadcast change
        SettingsStore.shared.enableAIProcessing = aiProcessingEnabled
        // If a ContentView has bound to MenuBarManager, its onChange sync will mirror this
        updateMenu()
    }
    
    @objc private func checkForUpdates(_ sender: Any?) {
        print("🔎 Menu action: Check for Updates…")
        NSLog("🔎 Menu action: Check for Updates…")

        // Call the AppDelegate's manual update check method if available
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.checkForUpdatesManually()
            return
        }

        // Fallback: perform direct, tolerant check so the menu item always does something
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
                    msg.messageText = "You’re Up To Date"
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
    
    @objc private func showWhatsNew() {
        // Post notification to show What's New view
        NotificationCenter.default.post(name: NSNotification.Name("ShowWhatsNew"), object: nil)
    }
    
    @objc private func openMainWindow() {
        // First, unhide the app if it's hidden
        if NSApp.isHidden {
            NSApp.unhide(nil)
        }
        
        // Activate the app and bring it to the front
        NSApp.activate(ignoringOtherApps: true)
        
        // Find and restore the main window
        var foundWindow = false
        for window in NSApp.windows {
            if window.title.contains("FluidVoice") || window.isMainWindow || window.contentView != nil {
                // Handle minimized windows
                if window.isMiniaturized {
                    window.deminiaturize(nil)
                }
                
                // Bring to current space and make key
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
                foundWindow = true
                break
            }
        }
        
        // If no window found, try to activate any available window
        if !foundWindow && !NSApp.windows.isEmpty {
            if let firstWindow = NSApp.windows.first {
                if firstWindow.isMiniaturized {
                    firstWindow.deminiaturize(nil)
                }
                firstWindow.makeKeyAndOrderFront(nil)
                firstWindow.orderFrontRegardless()
                foundWindow = true
            }
        }
        
        // Final attempt: ensure app is active and visible
        if foundWindow {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
