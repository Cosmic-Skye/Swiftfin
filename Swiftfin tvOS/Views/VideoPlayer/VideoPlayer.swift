//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2025 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

// import VLCUI - Replaced with SpatialVideoPlayer

struct VideoPlayer: View {

    enum OverlayType {
        case chapters
        case confirmClose
        case main
        case smallMenu
    }

    @Environment(\.scenePhase)
    private var scenePhase

    @EnvironmentObject
    private var router: VideoPlayerCoordinator.Router

    @ObservedObject
    private var currentProgressHandler: VideoPlayerManager.CurrentProgressHandler
    @ObservedObject
    private var videoPlayerManager: VideoPlayerManager

    @State
    private var isPresentingOverlay: Bool = false
    @State
    private var isScrubbing: Bool = false

    @ViewBuilder
    private var playerView: some View {
        ZStack {
            SpatialVideoPlayerView(
                configuration: videoPlayerManager.currentViewModel.vlcVideoPlayerConfiguration,
                proxy: videoPlayerManager.proxy,
                onTicksUpdated: { ticks, _ in
                    let newSeconds = ticks / 1000
                    let totalSeconds = CGFloat(videoPlayerManager.currentViewModel.item.runTimeSeconds)
                    var newProgress: CGFloat

                    if totalSeconds > 0 {
                        newProgress = CGFloat(newSeconds) / totalSeconds
                        // Clamp progress between 0 and 1
                        newProgress = max(0, min(1, newProgress))
                    } else {
                        // If total duration is unknown, maintain current progress
                        newProgress = currentProgressHandler.progress
                    }

                    currentProgressHandler.progress = newProgress
                    currentProgressHandler.seconds = newSeconds

                    guard !isScrubbing else { return }
                    currentProgressHandler.scrubbedProgress = newProgress
                },
                onStateUpdated: { state, _ in
                    videoPlayerManager.onStateUpdated(newState: state)

                    if state == .ended {
                        if let _ = videoPlayerManager.nextViewModel,
                           Defaults[.VideoPlayer.autoPlayEnabled]
                        {
                            videoPlayerManager.selectNextViewModel()
                        } else {
                            router.dismissCoordinator()
                        }
                    }
                }
            )

            VideoPlayer.Overlay()
                .eraseToAnyView()
                .environmentObject(videoPlayerManager)
                .environmentObject(videoPlayerManager.currentProgressHandler)
                .environmentObject(videoPlayerManager.currentViewModel!)
                .environmentObject(videoPlayerManager.proxy)
                .environment(\.isPresentingOverlay, $isPresentingOverlay)
                .environment(\.isScrubbing, $isScrubbing)
        }
        .onChange(of: videoPlayerManager.currentProgressHandler.scrubbedProgress) { _, newValue in
            guard !newValue.isNaN && !newValue.isInfinite else {
                return
            }
            DispatchQueue.main.async {
                videoPlayerManager.currentProgressHandler
                    .scrubbedSeconds = Int(CGFloat(videoPlayerManager.currentViewModel.item.runTimeSeconds) * newValue)
            }
        }
    }

    @ViewBuilder
    private var loadingView: some View {
        Text(L10n.retrievingMediaInformation)
    }

    var body: some View {
        ZStack {

            Color.black

            if let _ = videoPlayerManager.currentViewModel {
                playerView
            } else {
                loadingView
            }
        }
        .ignoresSafeArea()
        .onChange(of: isScrubbing) { _, newValue in
            guard !newValue else { return }
            videoPlayerManager.proxy.setTime(.seconds(currentProgressHandler.scrubbedSeconds))
        }
        .onScenePhase(.active) {
            if Defaults[.VideoPlayer.Transition.playOnActive] {
                videoPlayerManager.proxy.play()
            }
        }
        .onScenePhase(.background) {
            if Defaults[.VideoPlayer.Transition.pauseOnBackground] {
                videoPlayerManager.proxy.pause()
            }
        }
    }
}

extension VideoPlayer {

    init(manager: VideoPlayerManager) {
        self.init(
            currentProgressHandler: manager.currentProgressHandler,
            videoPlayerManager: manager
        )
    }
}
