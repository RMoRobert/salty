//
//  SyncPasswordPrompt.swift
//  Salty
//
//  The one place Salty asks for the server password.
//
//  An alert rather than a permanent field, because a field that sits on the Settings screen forever
//  implies its contents are kept there. This is asked once, when connecting a device, and then not
//  again -- which is what an alert is for, and what Mail does for the same job.
//
//  Shared by Settings and by the sync triggers (pull-to-refresh, the "Last synced" footer, the Sync
//  Now command) so there is exactly one password UI in the app, worded the same way wherever it
//  appears. The username belongs to Settings and is shown here only as context.
//

import SwiftUI

extension View {
    /// Presents the password prompt for connecting this device.
    ///
    /// - Parameters:
    ///   - isPresented: raised by whatever needs the device connected; cleared by Cancel automatically.
    ///   - username: the account being connected, shown so the user knows which password is wanted.
    ///   - onSubmit: receives the typed password. The caller owns the connecting and any error it
    ///     produces, so this modifier holds no state beyond the field itself.
    func syncPasswordPrompt(
        isPresented: Binding<Bool>,
        username: String,
        onSubmit: @escaping (String) -> Void
    ) -> some View {
        modifier(SyncPasswordPromptModifier(isPresented: isPresented, username: username, onSubmit: onSubmit))
    }
}

private struct SyncPasswordPromptModifier: ViewModifier {
    @Binding var isPresented: Bool
    let username: String
    let onSubmit: (String) -> Void

    @State private var password = ""

    func body(content: Content) -> some View {
        content.alert("Connect This Device", isPresented: $isPresented) {
            SecureField("Password", text: $password)
            Button("Cancel", role: .cancel) { password = "" }
            Button("Connect") {
                // Read and clear before handing off, so the typed copy doesn't outlive the alert.
                let entered = password
                password = ""
                onSubmit(entered)
            }
        } message: {
            Text(username.isEmpty
                 ? "Enter your Salty Server password."
                 : "Enter the password for \(username).")
        }
    }
}
