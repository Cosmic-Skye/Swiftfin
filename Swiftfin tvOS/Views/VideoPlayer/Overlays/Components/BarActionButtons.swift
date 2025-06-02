//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2025 Jellyfin & Jellyfin Contributors
//

import SwiftUI

// TODO: add subtitles button

extension VideoPlayer.Overlay {

    struct BarActionButtons: View {

        @Environment(\.currentOverlayType)
        @Binding
        private var currentOverlayType

        // Bindings to control presentation of new menus
        @Binding
        var isPresentingAudioMenu: Bool
        @Binding
        var isPresentingQualityMenu: Bool

        @EnvironmentObject
        private var viewModel: VideoPlayerViewModel
        // Access to LiveVideoPlayerManager to check if options are available
        @EnvironmentObject
        var videoPlayerManager: LiveVideoPlayerManager

        @ViewBuilder
        private var autoPlayButton: some View {
            if viewModel.item.type == .episode {
                ActionButtons.AutoPlay()
            }
        }

        @ViewBuilder
        private var chaptersButton: some View {
            if viewModel.chapters.isNotEmpty {
                ActionButtons.Chapters()
            }
        }

        @ViewBuilder
        private var playNextItemButton: some View {
            if viewModel.item.type == .episode {
                ActionButtons.PlayNextItem()
            }
        }

        @ViewBuilder
        private var playPreviousItemButton: some View {
            if viewModel.item.type == .episode {
                ActionButtons.PlayPreviousItem()
            }
        }

        @ViewBuilder
        private var menuItemButton: some View {
            SFSymbolButton(
                systemName: "ellipsis.circle",
                systemNameFocused: "ellipsis.circle.fill"
            )
            .onSelect {
                currentOverlayType = .smallMenu
            }
            .frame(maxWidth: 30, maxHeight: 30)
        }

        @ViewBuilder
        private var audioTracksButton: some View {
            if !videoPlayerManager.availableAudioTracks.isEmpty {
                SFSymbolButton(
                    systemName: "speaker.wave.2.circle",
                    systemNameFocused: "speaker.wave.2.circle.fill"
                )
                .onSelect {
                    isPresentingAudioMenu = true
                }
                .frame(maxWidth: 30, maxHeight: 30)
            }
        }

        @ViewBuilder
        private var videoQualityButton: some View {
            // Assuming quality levels are always available (at least "Auto")
            // Add a check if !videoPlayerManager.availableQualityLevels.isEmpty if that can happen
            SFSymbolButton(
                systemName: "dial.low", // Using dial.low, could be others like "slider.horizontal.3" or "gearshape"
                systemNameFocused: "dial.low.fill"
            )
            .onSelect {
                isPresentingQualityMenu = true
            }
            .frame(maxWidth: 30, maxHeight: 30)
        }

        var body: some View {
            HStack {
                playPreviousItemButton

                playNextItemButton

                autoPlayButton

                audioTracksButton // Added audio tracks button

                videoQualityButton // Added video quality button

                chaptersButton

                menuItemButton
            }
        }
    }
}
