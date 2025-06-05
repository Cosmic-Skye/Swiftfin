//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2025 Jellyfin & Jellyfin Contributors
//

import SwiftUI

struct IOSQualitySelectionMenuView: View { // Renamed struct
    @ObservedObject
    var videoPlayerManager: VideoPlayerManager
    @Binding
    var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { // Reduced spacing for popover
            Text("Video Quality") // Changed title slightly for popover context
                .font(.headline)
                .padding(.bottom, 5) // Add some padding below the title

            if videoPlayerManager.availableQualityLevels.isEmpty {
                Text("No quality levels available.")
                    .foregroundColor(.gray)
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(videoPlayerManager.availableQualityLevels, id: \.id) { qualityLevel in
                            Button(action: {
                                videoPlayerManager.selectQualityLevel(qualityLevel)
                                isPresented = false // This will dismiss the popover
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
                                .padding(.vertical, 8) // Add some padding to each button row
                            }
                            Divider() // Add a divider between items
                        }
                    }
                }
                // maxHeight constraint removed, will be applied by the caller in popover
            }
        }
        .padding() // Add padding around the VStack content
    }
}
