//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2025 Jellyfin & Jellyfin Contributors
//

import SwiftUI

struct QualitySelectionMenuView: View {
    @ObservedObject
    var videoPlayerManager: VideoPlayerManager // Changed to base class
    @Binding
    var isPresented: Bool // To control the presentation of this menu

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Select Video Quality")
                .font(.headline)
                .padding(.bottom, 5)

            if videoPlayerManager.availableQualityLevels.isEmpty {
                Text("No quality levels available.")
                    .foregroundColor(.gray)
            } else {
                ScrollView {
                    ForEach(videoPlayerManager.availableQualityLevels, id: \.id) { qualityLevel in
                        Button(action: {
                            videoPlayerManager.selectQualityLevel(qualityLevel)
                            isPresented = false // Dismiss after selection
                        }) {
                            HStack {
                                Text(qualityLevel.name)
                                    .foregroundColor(videoPlayerManager.selectedQualityLevel == qualityLevel ? .accentColor : .primary)
                                Spacer()
                                if videoPlayerManager.selectedQualityLevel == qualityLevel {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button("Close") {
                isPresented = false
            }
            .padding(.top)
        }
        .padding()
        .background(Material.regular)
        .cornerRadius(12)
        .frame(maxWidth: 400)
    }
}
