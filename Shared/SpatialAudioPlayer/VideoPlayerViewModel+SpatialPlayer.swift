//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2025 Jellyfin & Jellyfin Contributors
//

import Defaults
import Factory
import Foundation
import JellyfinAPI
import UIKit

// Extension to provide SpatialVideoPlayer compatibility
extension VideoPlayerViewModel {

    var spatialVideoPlayerConfiguration: SpatialVideoPlayer.Configuration {
        var configuration = SpatialVideoPlayer.Configuration(url: playbackURL)
        configuration.autoPlay = true
        configuration.startTime = max(0, item.startTimeSeconds - Defaults[.VideoPlayer.resumeOffset])

        if audioStreams.first?.path != nil {
            configuration.audioTrackIndex = selectedAudioStreamIndex
        }

        configuration.subtitleTrackIndex = selectedSubtitleStreamIndex

        // Add external subtitles
        configuration.externalSubtitles = subtitleStreams
            .filter { $0.deliveryMethod == .external }
            .compactMap(\.asExternalSubtitle)

        return configuration
    }

    // Note: vlcVideoPlayerConfiguration is defined in the main VideoPlayerViewModel.swift
    // The spatialVideoPlayerConfiguration above provides the new-style configuration
}

// Extension to handle external subtitle conversion for SpatialVideoPlayer
extension MediaStream {

    var asExternalSubtitle: SpatialVideoPlayer.ExternalSubtitle? {
        guard let deliveryURL,
              let client = Container.shared.currentUserSession()?.client,
              deliveryMethod == .external,
              type == .subtitle else { return nil }

        let deliveryPath = deliveryURL.removingFirst(if: client.configuration.url.absoluteString.last == "/")

        guard let fullURL = client.fullURL(with: deliveryPath) else { return nil }

        return SpatialVideoPlayer.ExternalSubtitle(
            url: fullURL,
            languageCode: language,
            displayName: displayTitle ?? "External Subtitle",
            isForced: isForced ?? false,
            isDefault: isDefault ?? false
        )
    }

    // Note: asPlaybackChild is defined in the original MediaStream.swift extension
    // and now works with our SpatialVideoPlayer.PlaybackChild compatibility layer
}
