import Foundation
import AppKit
import ApplicationServices

final class TextSelectionService {
    static let shared = TextSelectionService()
    
    private init() {}
    
    /// Attempts to get the currently selected text using Accessibility APIs
    func getSelectedText() -> String? {
        // Check accessibility permissions
        guard AXIsProcessTrusted() else {
            DebugLogger.shared.error("Accessibility permissions not granted", source: "TextSelectionService")
            return nil
        }
        
        // 1. Try to get the system-wide focused element
        if let focusedElement = getFocusedElement() {
            if let text = getSelectedText(from: focusedElement) {
                return text
            }
        }
        
        // 2. Fallback: Try to find focused element in frontmost app
        if let frontmostApp = NSWorkspace.shared.frontmostApplication {
            let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
            if let focusedElement = getFocusedElement(from: appElement) {
                if let text = getSelectedText(from: focusedElement) {
                    return text
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Private Helpers
    
    private func getFocusedElement() -> AXUIElement? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        
        let result = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        if result == .success {
            return (focusedElement as! AXUIElement)
        }
        
        return nil
    }
    
    private func getFocusedElement(from appElement: AXUIElement) -> AXUIElement? {
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        if result == .success {
            return (focusedElement as! AXUIElement)
        }
        
        return nil
    }
    
    private func getSelectedText(from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value)
        
        if result == .success, let text = value as? String {
            return text
        }
        
        // Fallback: If no text is selected, some apps might return the value attribute
        // But for "rewrite selected", we strictly want selected text.
        // We could optionally return all text if we wanted to rewrite the whole field.
        
        return nil
    }
}
