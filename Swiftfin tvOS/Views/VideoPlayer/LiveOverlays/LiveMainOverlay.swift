//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2025 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

extension LiveVideoPlayer {

    struct LiveMainOverlay: View {

        @Environment(\.currentOverlayType)
        @Binding
        private var currentOverlayType
        @Environment(\.isPresentingOverlay)
        @Binding
        private var isPresentingOverlay
        @Environment(\.isScrubbing)
        @Binding
        private var isScrubbing: Bool

        @EnvironmentObject
        private var currentProgressHandler: LiveVideoPlayerManager.CurrentProgressHandler
        @EnvironmentObject
        private var overlayTimer: TimerProxy
        // Ensure VideoPlayerManager is in the environment for the overlay and its children
        @EnvironmentObject
        private var videoPlayerManager: LiveVideoPlayerManager

        // State for presenting the new menus
        @State
        private var isPresentingAudioMenu: Bool = false
        @State
        private var isPresentingQualityMenu: Bool = false

        var body: some View {
            ZStack { // Use ZStack to allow sheets to overlay the content
                VStack {
                    Spacer()

                    // Pass the new bindings to LiveBottomBarView
                    // Note: LiveBottomBarView itself doesn't directly use these, but its child BarActionButtons does.
                    // We need to ensure BarActionButtons can receive these.
                    // This might require adjusting how BarActionButtons is instantiated or how environment objects/bindings are passed
                    // down.
                    // For now, assuming LiveBottomBarView can pass these down or BarActionButtons can access them via Environment.
                    // If BarActionButtons is directly part of LiveBottomBarView's body, it will need these bindings.
                    // Let's assume LiveBottomBarView is modified or BarActionButtons is instantiated here with these bindings.
                    // For simplicity, I'll modify the call to LiveBottomBarView if it directly contains BarActionButtons.
                    // However, BarActionButtons is within VideoPlayer.Overlay.LiveBottomBarView -> VideoPlayer.Overlay.BarActionButtons
                    // The BarActionButtons needs the bindings. The LiveBottomBarView will need to accept them and pass them.
                    // This requires modifying LiveBottomBarView as well.

                    // For now, let's assume we add the buttons directly here for simplicity of this step,
                    // or that LiveBottomBarView is adapted.
                    // A cleaner way is to have the sheet modifiers at this level.

                    Overlay.LiveBottomBarView(
                        isPresentingAudioMenu: $isPresentingAudioMenu,
                        isPresentingQualityMenu: $isPresentingQualityMenu
                    )
                    .padding()
                    .padding()
                    .background {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black.opacity(0.8), location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                }
                // The .environmentObject(videoPlayerManager) should ideally be set by the parent of LiveMainOverlay
                // to ensure it's available to all children including BarActionButtons.
                // If not, it needs to be explicitly passed or set here.
                // Assuming it's passed from LiveNativeVideoPlayer or its coordinator.
            }
            .sheet(isPresented: $isPresentingAudioMenu) {
                AudioSelectionMenuView(videoPlayerManager: videoPlayerManager, isPresented: $isPresentingAudioMenu)
                    .environmentObject(videoPlayerManager) // Ensure manager is available
            }
            .sheet(isPresented: $isPresentingQualityMenu) {
                QualitySelectionMenuView(videoPlayerManager: videoPlayerManager, isPresented: $isPresentingQualityMenu)
                    .environmentObject(videoPlayerManager) // Ensure manager is available
            }
            .environmentObject(overlayTimer)
            // Propagate videoPlayerManager if not already available from parent
            // .environmentObject(videoPlayerManager) // This should be done by the view that creates LiveMainOverlay
        }
    }
}

// We need to modify LiveBottomBarView to accept these bindings and pass them to BarActionButtons
// This change would be in 'LiveBottomBarView.swift'
// For example:
// struct LiveBottomBarView: View {
//     @Binding var isPresentingAudioMenu: Bool
//     @Binding var isPresentingQualityMenu: Bool
//     ...
//     VideoPlayer.Overlay.BarActionButtons(isPresentingAudioMenu: $isPresentingAudioMenu, isPresentingQualityMenu: $isPresentingQualityMenu)
//     ...
// }
// And then LiveMainOverlay would call:
// Overlay.LiveBottomBarView(isPresentingAudioMenu: $isPresentingAudioMenu, isPresentingQualityMenu: $isPresentingQualityMenu)

// For the current step, the sheet presentation logic is added to LiveMainOverlay.
// The trigger for these sheets (the buttons) are inside BarActionButtons.
// BarActionButtons needs access to $isPresentingAudioMenu and $isPresentingQualityMenu.
// This implies these bindings need to be passed down from LiveMainOverlay -> LiveBottomBarView -> BarActionButtons.
