//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2025 Jellyfin & Jellyfin Contributors
//

import Defaults // For resumeOffset, though direct access here might be refactored
import SwiftUI

struct IOSBottomBarView: View {
    @EnvironmentObject
    var videoPlayerManager: VideoPlayerManager
    @EnvironmentObject
    var viewModel: VideoPlayerViewModel
    @EnvironmentObject
    var currentProgressHandler: VideoPlayerManager.CurrentProgressHandler

    // Bindings for menu presentation, passed to IOSBarActionButtons
    @Binding
    var isPresentingAudioMenu: Bool
    @Binding
    var isPresentingQualityMenu: Bool

    // @EnvironmentObject var overlayTimer: TimerProxy // If auto-hide is needed

    var body: some View {
        VStack(spacing: 8) {
            // Title
            Text(viewModel.item.displayTitle)
                .font(.headline)
                .foregroundColor(.white)
                .lineLimit(1)
                .padding(.horizontal)

            // Scrubber
            // Using standard SwiftUI Slider.
            SwiftUI.Slider(
                value: $currentProgressHandler.scrubbedProgress, // Binding to the scrubbedProgress
                in: 0 ... 1,
                onEditingChanged: { editing in
                    // Update the scrubbing state in the handler
                    currentProgressHandler.updateScrubbingState(
                        editing: editing,
                        currentSliderValue: currentProgressHandler.scrubbedProgress, // Pass the current value of the slider
                        totalDuration: viewModel.item.runTimeSeconds
                    )

                    // If scrubbing finished, send the seek action
                    if !editing {
                        let targetSeconds = currentProgressHandler.scrubbedProgress * CGFloat(viewModel.item.runTimeSeconds)
                        videoPlayerManager.seekToAction.send(TimeInterval(targetSeconds))
                    }
                }
            )
            .padding(.horizontal)

            // Time labels and action buttons
            HStack {
                Text(currentProgressHandler.scrubbedSeconds.timeLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.white)

                Spacer()

                IOSBarActionButtons(
                    isPresentingAudioMenu: $isPresentingAudioMenu,
                    isPresentingQualityMenu: $isPresentingQualityMenu
                )
                // Ensure environment objects are passed if not inherited automatically
                .environmentObject(videoPlayerManager)
                    .environmentObject(viewModel)

                Spacer()

                Text((viewModel.item.runTimeSeconds - currentProgressHandler.scrubbedSeconds).timeLabel.prepending("-"))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.white)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.7))
        .cornerRadius(12)
        .padding(.horizontal) // Padding for the whole bar from screen edges
        .padding(.bottom, 10) // Consistent bottom padding
    }
}
