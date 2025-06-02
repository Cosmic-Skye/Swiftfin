//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2025 Jellyfin & Jellyfin Contributors
//

import Foundation

struct QualityLevel: Identifiable, Hashable {
    let id: String
    let name: String
    let peakBitrate: Double? // bps (bits per second)
    let maxResolutionHeight: Int? // pixels

    static func == (lhs: QualityLevel, rhs: QualityLevel) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // Predefined quality levels
    static let auto = QualityLevel(id: "auto", name: "Auto", peakBitrate: nil, maxResolutionHeight: nil) // AVPlayer default
    static let fhd = QualityLevel(id: "1080p", name: "1080p", peakBitrate: 8_000_000, maxResolutionHeight: 1080) // Example bitrate
    static let hd = QualityLevel(id: "720p", name: "720p", peakBitrate: 5_000_000, maxResolutionHeight: 720) // Example bitrate
    static let sd = QualityLevel(id: "480p", name: "480p", peakBitrate: 2_500_000, maxResolutionHeight: 480) // Example bitrate
    static let low = QualityLevel(id: "360p", name: "360p", peakBitrate: 1_000_000, maxResolutionHeight: 360) // Example bitrate

    static let allPredefined: [QualityLevel] = [.auto, .fhd, .hd, .sd, .low]
}
