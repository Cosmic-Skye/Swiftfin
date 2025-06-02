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
        NavigationView { // Common for iOS sheet presentation
            VStack(alignment: .leading, spacing: 15) {
                Text("Select Video Quality")
                    .font(.headline)
                    .padding([.top, .leading, .trailing])

                if videoPlayerManager.availableQualityLevels.isEmpty {
                    Text("No quality levels available.")
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    List { // Use List for iOS style
                        ForEach(videoPlayerManager.availableQualityLevels, id: \.id) { qualityLevel in
                            Button(action: {
                                videoPlayerManager.selectQualityLevel(qualityLevel)
                                isPresented = false
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
                        }
                    }
                }
            }
            .navigationTitle("Video Quality")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
    }
}
