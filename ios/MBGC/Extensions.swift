import SwiftUI

extension Color {
    /// "#RRGGBB" or "RRGGBB" → Color; nil if malformed.
    init?(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard h.count == 6, let int = UInt64(h, radix: 16) else { return nil }
        self.init(
            red:   Double((int >> 16) & 0xFF) / 255,
            green: Double((int >> 8)  & 0xFF) / 255,
            blue:  Double(int         & 0xFF) / 255
        )
    }
}

extension View {
    /// Tiny "dismiss an optional error message" alert — replaces the 7-line
    /// `Binding(get:set:)` wrangle that shows up at every view model error site.
    func errorAlert(_ message: Binding<String?>, title: String = "Error") -> some View {
        alert(title, isPresented: Binding(
            get: { message.wrappedValue != nil },
            set: { if !$0 { message.wrappedValue = nil } }
        )) {
            Button("OK") { message.wrappedValue = nil }
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }

    /// Horizontal-only right-edge drag fires `action` once. Used by the Finder
    /// quiz + result views to back out of the same way as the back chevron.
    /// `width>80, |height|<80` keeps a diagonal scroll from triggering it.
    func swipeBack(_ action: @escaping () -> Void) -> some View {
        gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { v in
                    if v.translation.width > 80, abs(v.translation.height) < 80 { action() }
                }
        )
    }
}

