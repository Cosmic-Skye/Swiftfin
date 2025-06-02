//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2025 Jellyfin & Jellyfin Contributors
//

import Foundation
import UIKit

// Type aliases to maintain compatibility during the transition from VLCKit
public typealias VLCVideoPlayer = SpatialVideoPlayer
public typealias VLCVideoPlayerView = SpatialVideoPlayerView

// Module placeholder to prevent import errors
public enum VLCUI {
    // Empty enum to act as namespace
}

// VLC-compatible value types
public struct VLCTime {
    public let value: Int64

    public init(value: Int64) {
        self.value = value
    }

    public static func ticks(_ ticks: Int) -> VLCTime {
        VLCTime(value: Int64(ticks))
    }

    public static func seconds(_ seconds: Int) -> VLCTime {
        VLCTime(value: Int64(seconds * 1000))
    }
}

public struct VLCPlaybackRate {
    public let value: Float

    public init(value: Float) {
        self.value = value
    }

    public static func absolute(_ rate: Float) -> VLCPlaybackRate {
        VLCPlaybackRate(value: rate)
    }
}

public struct VLCTextRendererColor {
    public let uiColor: UIColor

    public init(uiColor: UIColor) {
        self.uiColor = uiColor
    }

    public static func absolute(_ color: UIColor) -> VLCTextRendererColor {
        VLCTextRendererColor(uiColor: color)
    }
}

public struct VLCTextRendererSize {
    public let size: Float

    public init(size: Float) {
        self.size = size
    }

    public static func absolute(_ size: Float) -> VLCTextRendererSize {
        VLCTextRendererSize(size: size)
    }
}

// VLC PlaybackChild compatibility
public extension SpatialVideoPlayer {

    struct PlaybackChild {
        public let url: URL
        public let type: PlaybackChildType
        public let enforce: Bool

        public init(url: URL, type: PlaybackChildType, enforce: Bool) {
            self.url = url
            self.type = type
            self.enforce = enforce
        }
    }

    enum PlaybackChildType {
        case subtitle
        case audio
    }
}
