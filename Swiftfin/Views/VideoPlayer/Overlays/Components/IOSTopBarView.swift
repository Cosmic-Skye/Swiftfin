//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2025 Jellyfin & Jellyfin Contributors
//

import SwiftUI

struct IOSTopBarView: View {
    var dismissAction: () -> Void

    var body: some View {
        HStack {
            Button(action: dismissAction) {
                Image(systemName: "chevron.backward")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding() // Add some padding around the button for easier tapping
            }
            Spacer()
        }
        .padding(.top, topInset()) // Adjust for safe area
        .padding(.horizontal) // Padding for the bar from screen edges
    }

    private func topInset() -> CGFloat {
        let scenes = UIApplication.shared.connectedScenes
        guard let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow })
        else {
            // Fallback: Avoid deprecated API. Return 0 if modern API fails.
            return 0
        }
        return window.safeAreaInsets.top
    }
}
