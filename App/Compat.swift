import SwiftUI

// macOS 13 (Ventura) support: SwiftUI APIs that are macOS 14+, with their macOS 13 equivalents.

extension View {
    /// `onChange(of:)` that hands over the new value, on both the macOS 14 and the older macOS 13 API.
    @ViewBuilder func onChangeCompat<V: Equatable>(of value: V, perform: @escaping (V) -> Void) -> some View {
        if #available(macOS 14.0, *) {
            onChange(of: value) { _, new in perform(new) }
        } else {
            onChange(of: value, perform: perform)
        }
    }

    /// No focus ring (macOS 14+ only; macOS 13 keeps the system ring).
    @ViewBuilder func focusEffectDisabledCompat() -> some View {
        if #available(macOS 14.0, *) { focusEffectDisabled() } else { self }
    }
}

/// VoiceOver announcement on macOS 14+ and macOS 13.
@MainActor
func announce(_ text: String) {
    if #available(macOS 14.0, *) {
        AccessibilityNotification.Announcement(text).post()
    } else {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}
