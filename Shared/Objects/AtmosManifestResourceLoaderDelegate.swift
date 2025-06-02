//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2025 Jellyfin & Jellyfin Contributors
//

import AVFoundation
import os.log

class AtmosManifestResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate {

    static let customScheme = "atmosmanifest"
    private static let logger = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.swiftfin.player", category: "AtmosManifestLoader")
    var masterPlaylistOriginalURL: URL? // To store the original URL of the master playlist

    // Helper to construct the custom URL that triggers this delegate
    static func customURL(from originalURL: URL) -> URL? {
        // Embed the original URL directly after the custom scheme.
        // Example: atmosmanifest://https://server.com/path/to/master.m3u8
        let customURLString = "\(customScheme)://\(originalURL.absoluteString)"
        let url = URL(string: customURLString)
        os_log(
            "Original URL: %{public}@, Custom URL: %{public}@",
            log: logger,
            type: .debug,
            originalURL.absoluteString,
            url?.absoluteString ?? "nil (Error creating custom URL string: \(customURLString))"
        )
        return url
    }

    // Helper to extract the original URL from our custom scheme
    private func originalURL(from customURL: URL) -> URL? {
        // Custom URL is like: atmosmanifest://https://server.com/path/to/master.m3u8
        // We need to extract: https://server.com/path/to/master.m3u8
        var originalURLString = customURL.absoluteString
        if let schemeRange = originalURLString.range(of: "\(Self.customScheme)://") {
            originalURLString.removeSubrange(schemeRange)
            return URL(string: originalURLString)
        }
        return nil
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard let interceptedRequestURL = loadingRequest.request.url else {
            os_log("Invalid URL in loading request.", log: Self.logger, type: .error)
            loadingRequest.finishLoading(with: NSError(
                domain: "AtmosManifestLoader",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid URL in loading request"]
            ))
            return false
        }

        os_log("Intercepted request for URL: %{public}@", log: Self.logger, type: .debug, interceptedRequestURL.absoluteString)

        guard interceptedRequestURL.scheme == Self.customScheme,
              let actualURLToFetch = originalURL(from: interceptedRequestURL)
        else {
            os_log(
                "Request URL is not using the custom scheme or original URL could not be extracted: %{public}@",
                log: Self.logger,
                type: .error,
                interceptedRequestURL.absoluteString
            )
            loadingRequest.finishLoading(with: NSError(
                domain: "AtmosManifestLoader",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Invalid custom scheme or URL format"]
            ))
            return false
        }

        // Determine if this is the master playlist request
        // The AVURLAsset's URL is the custom URL for the master playlist.
        var isMasterPlaylistRequest = false
        if let knownMasterURL = self.masterPlaylistOriginalURL {
            isMasterPlaylistRequest = (actualURLToFetch == knownMasterURL)
            os_log(
                "Delegate's known master URL: %{public}@. Current request's actual URL: %{public}@. Is Master: %d",
                log: Self.logger,
                type: .debug,
                knownMasterURL.absoluteString,
                actualURLToFetch.absoluteString,
                isMasterPlaylistRequest
            )
        } else {
            os_log(
                "Master playlist original URL not set on delegate. Cannot reliably determine if this is the master playlist request. Assuming not master.",
                log: Self.logger,
                type: .default
            )
        }

        os_log("Fetching data for URL: %{public}@", log: Self.logger, type: .debug, actualURLToFetch.absoluteString)

        let task = URLSession.shared.dataTask(with: actualURLToFetch) { data, response, error in
            if let error = error {
                os_log(
                    "Error fetching URL %{public}@: %{public}@",
                    log: Self.logger,
                    type: .error,
                    actualURLToFetch.absoluteString,
                    error.localizedDescription
                )
                loadingRequest.finishLoading(with: error)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                os_log("Non-successful HTTP status code: %d", log: Self.logger, type: .error, statusCode)
                loadingRequest.finishLoading(with: NSError(
                    domain: "AtmosManifestLoader",
                    code: statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to fetch manifest with status: \(statusCode)"]
                ))
                return
            }

            guard let fetchedData = data else {
                os_log("No data received for URL: %{public}@", log: Self.logger, type: .error, actualURLToFetch.absoluteString)
                loadingRequest.finishLoading(with: NSError(
                    domain: "AtmosManifestLoader",
                    code: -4,
                    userInfo: [NSLocalizedDescriptionKey: "No data received"]
                ))
                return
            }

            var dataToProvide = fetchedData
            var finalContentType = response?.mimeType ?? "application/octet-stream"

            if isMasterPlaylistRequest {
                os_log("Processing as master playlist: %{public}@", log: Self.logger, type: .debug, actualURLToFetch.absoluteString)
                finalContentType = "application/vnd.apple.mpegurl" // Master playlists should have this type

                guard var manifestString = String(data: fetchedData, encoding: .utf8) else {
                    os_log("Could not decode master playlist data to string.", log: Self.logger, type: .error)
                    loadingRequest.finishLoading(with: NSError(
                        domain: "AtmosManifestLoader",
                        code: -5,
                        userInfo: [NSLocalizedDescriptionKey: "Could not decode master playlist data"]
                    ))
                    return
                }

                os_log(
                    "Original master playlist snippet (first 500 chars): %{public}@",
                    log: Self.logger,
                    type: .debug,
                    String(manifestString.prefix(500))
                )

                let initialManifestString = manifestString
                var modifiedLines = [String]()
                var manifestWasModified = false

                manifestString.enumerateLines { line, _ in
                    var currentLine = line
                    if currentLine.hasPrefix("#EXT-X-STREAM-INF:") && !currentLine.contains("CHANNELS=") {
                        os_log("Original EXT-X-STREAM-INF: %{public}@", log: Self.logger, type: .debug, currentLine)
                        currentLine.append(",CHANNELS=\"6/JOC\"")
                        os_log("Modified EXT-X-STREAM-INF: %{public}@", log: Self.logger, type: .debug, currentLine)
                        manifestWasModified = true
                    } else if currentLine.hasPrefix("#EXT-X-MEDIA:") && currentLine.contains("TYPE=AUDIO") && !currentLine
                        .contains("CHARACTERISTICS=")
                    {
                        os_log("Original EXT-X-MEDIA (Audio): %{public}@", log: Self.logger, type: .debug, currentLine)
                        let characteristicToAdd = "CHARACTERISTICS=\"com.apple.audio-atmos\""
                        if let uriRange = currentLine.range(of: "URI=") {
                            if currentLine[currentLine.index(before: uriRange.lowerBound)] == "," {
                                currentLine.insert(contentsOf: "\(characteristicToAdd),", at: uriRange.lowerBound)
                            } else {
                                currentLine.insert(contentsOf: ",\(characteristicToAdd),", at: uriRange.lowerBound)
                            }
                        } else {
                            currentLine.append((currentLine.isEmpty || currentLine.last == "," ? "" : ",") + characteristicToAdd)
                        }
                        os_log("Modified EXT-X-MEDIA (Audio): %{public}@", log: Self.logger, type: .debug, currentLine)
                        manifestWasModified = true
                    }
                    modifiedLines.append(currentLine)
                }

                if manifestWasModified {
                    manifestString = modifiedLines.joined(separator: "\n")
                    if !manifestString.hasSuffix("\n") { // Ensure trailing newline for HLS
                        manifestString.append("\n")
                    }
                    os_log(
                        "Master playlist modified. Snippet (first 500 chars): %{public}@",
                        log: Self.logger,
                        type: .debug,
                        String(manifestString.prefix(500))
                    )
                    if let modifiedDataFromString = manifestString.data(using: .utf8) {
                        dataToProvide = modifiedDataFromString
                    } else {
                        os_log(
                            "Failed to encode modified master playlist string to data. Sending original.",
                            log: Self.logger,
                            type: .error
                        )
                        // dataToProvide remains original fetchedData
                    }
                } else {
                    os_log("Master playlist not modified (no relevant tags found or already compliant).", log: Self.logger, type: .debug)
                }
            } else {
                os_log(
                    "Processing as sub-resource (not master playlist): %{public}@",
                    log: Self.logger,
                    type: .debug,
                    actualURLToFetch.absoluteString
                )
                // For sub-resources (media playlists, segments), use the fetched data as is.
                // Content type should be derived from the response.
            }

            if let contentInformationRequest = loadingRequest.contentInformationRequest {
                contentInformationRequest.contentType = finalContentType
                contentInformationRequest.contentLength = Int64(dataToProvide.count)
                contentInformationRequest.isByteRangeAccessSupported = false // Typically false for HLS manifests/segments
            }

            loadingRequest.dataRequest?.respond(with: dataToProvide)
            loadingRequest.finishLoading()
            os_log(
                "Successfully provided data for %{public}@ (Master: %d)",
                log: Self.logger,
                type: .info,
                actualURLToFetch.absoluteString,
                isMasterPlaylistRequest
            )
        }
        task.resume()
        return true // Indicates we are handling the request asynchronously
    }
}
