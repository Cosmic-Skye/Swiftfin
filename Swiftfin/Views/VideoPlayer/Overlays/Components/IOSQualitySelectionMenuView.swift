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
        VStack(alignment: .leading) {
            Text("Video Quality")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top)

            if videoPlayerManager.availableQualityLevels.isEmpty {
                Text("No quality levels available.")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                List {
                    ForEach(videoPlayerManager.availableQualityLevels, id: \.id) { qualityLevel in
                        Button(action: {
                            videoPlayerManager.selectQualityLevel(qualityLevel)
                            isPresented = false
                        }) {
                            HStack {
                                Text(qualityLevel.name)
                                    .foregroundColor(.primary)
                                Spacer()
                                if videoPlayerManager.selectedQualityLevel == qualityLevel {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .listStyle(PlainListStyle())
            }
        }
        .frame(width: 300, height: 200)
    }
}
