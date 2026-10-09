import AppKit
import ApplicationServices

/// The app being dictated into.
enum FrontApp {
    /// Asks Accessibility for the focused app: a live answer. `NSWorkspace.frontmostApplication`
    /// is a cached value updated by notifications, and in some launches it stayed on
    /// `com.apple.loginwindow` for every dictation, so it is only the fallback.
    static func bundleID() -> String? {
        var focused: CFTypeRef?
        if AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedApplicationAttribute as CFString,
                                         &focused) == .success, let focused,
           CFGetTypeID(focused) == AXUIElementGetTypeID() {
            var pid: pid_t = 0
            if AXUIElementGetPid(focused as! AXUIElement, &pid) == .success,
               let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier {
                return bundleID
            }
        }
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
}
