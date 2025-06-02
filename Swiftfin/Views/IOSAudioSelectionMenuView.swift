//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2025 Jellyfin & Jellyfin Contributors
//

import AVFoundation
import SwiftUI

struct IOSAudioSelectionMenuView: View { // Renamed struct
    @ObservedObject
    var videoPlayerManager: VideoPlayerManager
    @Binding
    var isPresented: Bool

    var body: some View {
        NavigationView { // Common for iOS sheet presentation
            VStack(alignment: .leading, spacing: 15) {
                Text("Select Audio Track")
                    .font(.headline)
                    .padding([.top, .leading, .trailing])

                if videoPlayerManager.availableAudioTracks.isEmpty {
                    Text("No audio tracks available.")
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    List { // Use List for iOS style
                        ForEach(videoPlayerManager.availableAudioTracks, id: \.self) { track in
                            Button(action: {
                                videoPlayerManager.selectAudioTrack(track)
                                isPresented = false
                            }) {
                                HStack {
                                    Text(track.displayName)
                                        .foregroundColor(videoPlayerManager.selectedAudioTrack == track ? .accentColor : .primary)
                                    Spacer()
                                    if videoPlayerManager.selectedAudioTrack == track {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Audio Tracks")
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

// Note: The AVMediaSelectionOption extension for displayName is still relevant
// and should ideally be in a shared location if not already.
// For now, assuming it's accessible or can be re-declared if needed.
// If it was part of the tvOS AudioSelectionMenuView.swift, it needs to be moved to Shared or duplicated.
// To avoid issues, I'll re-declare it here for now, but a shared location is better.

// extension AVMediaSelectionOption {
//     var displayName: String {
//         self.commonMetadata.first(where: { $0.commonKey == .commonKeyTitle })?.stringValue ??
//             self.displayName
//     }
// }
