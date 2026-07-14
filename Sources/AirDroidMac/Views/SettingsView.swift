import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Section("About this spike") {
                Text("The Mac control center launches stock scrcpy in its own mirror window. It does not embed or reimplement the scrcpy protocol.")
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 500)
    }
}
