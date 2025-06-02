//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2025 Jellyfin & Jellyfin Contributors
//

import Foundation

extension FixedWidthInteger {

    var timeLabel: String {
        let hours = self / 3600
        let minutes = (self % 3600) / 60
        let seconds = self % 3600 % 60

        let hourText = hours > 0 ? String(hours).appending(":") : ""
        let minutesText = hours > 0 ? String(minutes).leftPad(maxWidth: 2, with: "0").appending(":") : String(minutes)
            .appending(":")
        let secondsText = String(seconds).leftPad(maxWidth: 2, with: "0")

        return hourText
            .appending(minutesText)
            .appending(secondsText)
    }
}

extension Int {
    /// Converts seconds into a time label string (e.g., "01:23:45" or "23:45") using DateComponentsFormatter.
    var timeLabel: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional

        let totalSeconds = TimeInterval(self)
        let hours = Int(totalSeconds) / 3600

        if hours > 0 {
            formatter.allowedUnits = [.hour, .minute, .second]
        } else {
            formatter.allowedUnits = [.minute, .second]
        }
        formatter.zeroFormattingBehavior = .pad

        return formatter.string(from: totalSeconds) ?? "00:00"
    }

    /// Label if the current value represents milliseconds
    var millisecondLabel: String {
        let isNegative = self < 0
        let value = abs(self)
        let seconds = "\(value / 1000)"
        let milliseconds = "\(value % 1000)".first ?? "0"

        return seconds
            .appending(".")
            .appending(milliseconds)
            .appending("s")
            .prepending("-", if: isNegative)
    }

    /// Label if the current value represents seconds
    var secondLabel: String {
        let isNegative = self < 0
        let value = abs(self)
        let seconds = "\(value)"

        return seconds
            .appending("s")
            .prepending("-", if: isNegative)
    }

    init?(_ source: CGFloat?) {
        if let source = source {
            self.init(source)
        } else {
            return nil
        }
    }
}
