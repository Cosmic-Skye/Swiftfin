//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2025 Jellyfin & Jellyfin Contributors
//

import SwiftUI

// TODO: This view will need access to the VideoPlayerManager and VideoPlayerViewModel
//       similar to its tvOS counterpart to determine which buttons to show (e.g., chapters, next/prev episode).
//       It also needs bindings to toggle the presentation of various menus/overlays.

struct IOSBarActionButtons: View {

    @EnvironmentObject
    var videoPlayerManager: VideoPlayerManager
    @EnvironmentObject
    var viewModel: VideoPlayerViewModel // Assuming this is in the environment

    // Bindings to control presentation of new menus, passed from parent
    @Binding
    var isPresentingAudioMenu: Bool
    @Binding
    var isPresentingQualityMenu: Bool
    // Binding for other potential menus (e.g., chapters, subtitles)
    // @Binding var isPresentingChaptersMenu: Bool
    // @Binding var isPresentingSubtitlesMenu: Bool
    // @Binding var isPresentingGenericMenu: Bool // For ellipsis

    // Placeholder for other actions like chapters, subtitles, etc.
    // These would typically toggle other @State/@Binding variables
    // to present different sheets or navigate to different views.

    var body: some View {
        HStack(spacing: 20) { // Adjusted spacing for iOS
            // Previous Item Button
            if viewModel.item.type == .episode && videoPlayerManager.previousViewModel != nil {
                Button {
                    videoPlayerManager.selectPreviousViewModel()
                } label: {
                    Image(systemName: "backward.end.fill")
                }
            }

            // Skip Backward Button
            Button {
                videoPlayerManager.skipBackwardAction.send(15) // Send 15 seconds
            } label: {
                Image(systemName: "gobackward.15")
            }
            .accessibilityLabel("Skip Backward 15 seconds")

            // Play/Pause Button
            Button {
                if videoPlayerManager.state == .playing {
                    videoPlayerManager.pauseAction.send()
                } else {
                    videoPlayerManager.playAction.send()
                }
            } label: {
                Image(systemName: videoPlayerManager.state == .playing ? "pause.fill" : "play.fill")
            }
            .accessibilityLabel(videoPlayerManager.state == .playing ? "Pause" : "Play")

            // Skip Forward Button
            Button {
                videoPlayerManager.skipForwardAction.send(15) // Send 15 seconds
            } label: {
                Image(systemName: "goforward.15")
            }
            .accessibilityLabel("Skip Forward 15 seconds")

            // Next Item Button
            if viewModel.item.type == .episode && videoPlayerManager.nextViewModel != nil {
                Button {
                    videoPlayerManager.selectNextViewModel()
                } label: {
                    Image(systemName: "forward.end.fill")
                }
            }

            Spacer() // Pushes specific media controls (audio, quality, etc.) to the right

            // Audio Tracks Button
            if !videoPlayerManager.availableAudioStreams.isEmpty { // Changed to availableAudioStreams
                Button {
                    isPresentingAudioMenu = true
                } label: {
                    Image(systemName: "speaker.wave.2.circle")
                }
                .accessibilityLabel("Audio Tracks")
            }

            // Video Quality Button
            if !videoPlayerManager.availableQualityLevels.isEmpty {
                Button {
                    isPresentingQualityMenu = true
                } label: {
                    Image(systemName: "dial.low")
                }
                .accessibilityLabel("Video Quality")
            }

            // Example: Chapters Button
            // if viewModel.chapters.isNotEmpty {
            //     Button {
            //         // isPresentingChaptersMenu = true
            //     } label: {
            //         Image(systemName: "list.bullet")
            //     }
            // }

            // Example: More Options (ellipsis)
            // Button {
            //    // isPresentingGenericMenu = true
            // } label: {
            //    Image(systemName: "ellipsis.circle")
            // }
        }
        .font(.title2) // Apply a consistent font size to buttons
        .foregroundColor(.white)
    }
}
