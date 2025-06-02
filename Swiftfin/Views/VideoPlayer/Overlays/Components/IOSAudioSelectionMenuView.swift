//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2025 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI // For MediaStreamInfo
import SwiftUI

struct IOSAudioSelectionMenuView: View {
    @ObservedObject
    var videoPlayerManager: VideoPlayerManager
    @Binding
    var isPresented: Bool

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 15) {
                Text("Select Audio Track")
                    .font(.headline)
                    .padding([.top, .leading, .trailing])

                if videoPlayerManager.availableAudioStreams.isEmpty {
                    Text("No audio tracks available.")
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    List {
                        ForEach(videoPlayerManager.availableAudioStreams, id: \.index) { stream in
                            Button(action: {
                                videoPlayerManager.selectAudioStream(stream)
                                isPresented = false
                            }) {
                                HStack {
                                    Text(getDescriptiveStreamName(for: stream))
                                        .foregroundColor(videoPlayerManager.selectedAudioStream?.index == stream
                                            .index ? .accentColor : .primary
                                        )
                                    Spacer()
                                    if videoPlayerManager.selectedAudioStream?.index == stream.index {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Audio Tracks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
    }

    private func getDescriptiveStreamName(for stream: JellyfinAPI.MediaStream) -> String { // Changed MediaStreamInfo to MediaStream
        var nameParts: [String] = []

        // MediaStream uses .title, not .displayTitle typically for the main descriptive name.
        // It might also have a .codec or .language.
        if let title = stream.title, !title.isEmpty, title.lowercased() != "unknown", title.lowercased() != "und" {
            nameParts.append(title)
        } else if let displayTitle = stream.displayTitle, !displayTitle.isEmpty, displayTitle.lowercased() != "unknown",
                  displayTitle.lowercased() != "und"
        {
            // Fallback to displayTitle if .title is not useful
            nameParts.append(displayTitle)
        }

        if let language = stream.language {
            let locale = Locale(identifier: Locale.current.identifier)
            if let localizedLanguage = locale.localizedString(forLanguageCode: language) {
                if nameParts.isEmpty || !nameParts.contains(where: { $0.caseInsensitiveCompare(localizedLanguage) == .orderedSame }) {
                    nameParts.append(localizedLanguage)
                }
            } else if !nameParts.contains(where: { $0.caseInsensitiveCompare(language) == .orderedSame }) {
                nameParts.append(language) // Fallback to language code if localization fails
            }
        }

        if let codec = stream.codec, !codec.isEmpty {
            if nameParts.isEmpty || !nameParts.contains(where: { $0.caseInsensitiveCompare(codec) == .orderedSame }) {
                // nameParts.append(codec.uppercased()) // Optionally add codec, might be too verbose
            }
        }

        if nameParts.isEmpty {
            // stream.index is Int32?, so handle optionality
            return "Track \((stream.index ?? -1) + 1)" // Use 1-based indexing for display
        }

        return nameParts.joined(separator: " - ")
    }
}
