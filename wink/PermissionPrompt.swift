//
//  PermissionPrompt.swift
//  wink
//

import SwiftUI

/// Shown in place of a feature that hasn't been granted access yet.
///
/// iOS shows its permission alert in the middle of the screen, where the case hides it, and the
/// alert blocks every touch until it's answered. So nothing asks on its own: the user taps here
/// first, and is told where to look.
struct PermissionPrompt: View {
    let title: LocalizedStringKey
    let request: () async -> Void

    @State private var isAsking = false

    var body: some View {
        Button {
            isAsking = true
            Task {
                await request()
                isAsking = false
            }
        } label: {
            VStack(spacing: pt(10)) {
                Text(title)
                    .font(.wink(28))
                    .foregroundStyle(WinkTheme.primaryText)
                Text(isAsking ? "Answer the prompt in the middle of the screen" : "Tap, then answer the prompt in the middle of the screen")
                    .font(.wink(20, weight: .medium))
                    .foregroundStyle(WinkTheme.secondaryText)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, pt(36))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(NoHighlightButtonStyle())
        .disabled(isAsking)
    }
}

#Preview {
    WindowPreview {
        PermissionPrompt(title: "Allow Music access") {}
    }
}
