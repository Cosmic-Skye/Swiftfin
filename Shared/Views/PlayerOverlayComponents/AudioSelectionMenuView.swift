//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2025 Jellyfin & Jellyfin Contributors
//

import AVFoundation
import SwiftUI

struct AudioSelectionMenuView: View {
    @ObservedObject
    var videoPlayerManager: VideoPlayerManager // Changed to base class
    @Binding
    var isPresented: Bool // To control the presentation of this menu

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Select Audio Track")
                .font(.headline)
                .padding(.bottom, 5)

            if videoPlayerManager.availableAudioTracks.isEmpty {
                Text("No audio tracks available.")
                    .foregroundColor(.gray)
            } else {
                ScrollView {
                    ForEach(videoPlayerManager.availableAudioTracks, id: \.self) { track in
                        Button(action: {
                            videoPlayerManager.selectAudioTrack(track)
                            isPresented = false // Dismiss after selection
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
                        .buttonStyle(.plain) // Use plain style for tvOS list items
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
        .frame(maxWidth: 400) // Constrain width for a menu-like appearance
    }
}

extension AVMediaSelectionOption {
    // AVMediaSelectionOption doesn't directly conform to Hashable for ForEach id: \.self if not unique by reference.
    // However, for this context, instances from player.currentItem.asset.mediaSelectionGroup should be unique.
    // If issues arise, a custom Identifiable wrapper might be needed.
    // For now, \.self relies on its hashability.
    // A more robust way for displayName:
    var displayName: String {
        // The standard displayName is usually good.
        // If more detailed parsing is needed (e.g., separate language and codec):
        // self.extendedLanguageTag ?? "Unknown Language" + " (\(self.mediaType))"
        self.commonMetadata.first(where: { $0.commonKey == .commonKeyTitle })?.stringValue ??
            self.displayName // Fallback to system displayName
    }
}
