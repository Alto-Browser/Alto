//
//  DownloadManager.swift
//  Alto
//
//  Created by Kami on 23/06/2025.
//

import Foundation
import OpenADK
import OSLog
import WebKit

// MARK: - DownloadManager

/// Main manager for download functionality with real-time progress tracking
@Observable
public class DownloadManager: NSObject, ObservableObject {
    public static let shared = DownloadManager()

    private let logger = Logger(subsystem: "com.alto.downloads", category: "DownloadManager")

    // MARK: - Properties

    private let settingsDirectory: URL
    private let maxRecentDownloads = 10
    private var urlSession: URLSession!
    private var activeTasks: [URLSessionDownloadTask: DownloadItem] = [:]

    /// Current downloads directory from preferences
    public var downloadsDirectory: URL { PreferencesManager.shared.downloadPath }

    // Published properties for UI
    public var downloads: [DownloadItem] = []
    public var isShowingDownloads = false

    // MARK: - Computed Properties

    /// Get recent downloads for UI display
    public var recentDownloads: [DownloadItem] { Array(downloads.prefix(maxRecentDownloads)) }

    /// Get active downloads
    public var activeDownloads: [DownloadItem] { downloads.filter(\.state.isActive) }

    /// Get download statistics
    public var statistics: DownloadStatistics {
        let active = activeDownloads.count
        let completed = downloads.count { $0.state == .completed }
        let failed = downloads.count { $0.state == .failed }
        let totalBytes = downloads.reduce(0) { $0 + $1.receivedBytes }
        let currentSpeed = activeDownloads.reduce(0) { $0 + $1.speed }

        return DownloadStatistics(
            totalDownloads: downloads.count,
            activeDownloads: active,
            completedDownloads: completed,
            failedDownloads: failed,
            totalBytesDownloaded: totalBytes,
            currentSpeed: currentSpeed
        )
    }

    // MARK: - Initialization

    private override init() {
        // Set up settings directory in Application Support (for JSON storage)
        let fileManager = FileManager.default
        let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        settingsDirectory = appSupportDir.appendingPathComponent("Alto/Downloads")

        super.init()

        // Create settings directory if needed
        try? fileManager.createDirectory(at: settingsDirectory, withIntermediateDirectories: true)

        // Set up URLSession with delegate
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 0 // No timeout for downloads
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        logger.info("📥 DownloadManager initialized")

        // Load and auto-restart incomplete downloads
        loadAndRestartIncompleteDownloads()

        // Setup notifications
        setupNotifications()
    }

    deinit {
        urlSession.invalidateAndCancel()
    }

    // MARK: - Public Interface

    /// Toggle downloads display
    @MainActor
    public func toggleDownloads() {
        isShowingDownloads.toggle()
        // logger.info("📥 Downloads panel toggled: \(isShowingDownloads ? "shown" : "hidden")")
    }

    /// Start a download programmatically
    @MainActor
    public func startDownload(from url: URL, filename: String? = nil) {
        let suggestedFilename: String = if let filename, !filename.isEmpty {
            filename
        } else if !url.lastPathComponent.isEmpty {
            url.lastPathComponent
        } else {
            "download"
        }

        // Check if we already have a download for this URL
        if let existingDownload = downloads.first(where: { $0.url == url && $0.filename == suggestedFilename }) {
            handleExistingDownload(existingDownload)
            return
        }

        let downloadItem = DownloadItem(url: url, suggestedFilename: suggestedFilename)

        // Create unique destination
        downloadItem.destinationURL = createUniqueDestinationURL(for: suggestedFilename)

        // Add to downloads list at the beginning
        downloads.insert(downloadItem, at: 0)

        // Start actual download
        startDownloadTask(for: downloadItem)

        logger.info("📥 Started download: \(suggestedFilename)")

        // Trigger UI update and persistence
        updateUI()
    }

    // MARK: - Download Control Methods

    /// Cancel a download
    @MainActor
    public func cancelDownload(_ downloadItem: DownloadItem) {
        performDownloadAction(downloadItem, action: .cancel)
    }

    /// Pause a download
    @MainActor
    public func pauseDownload(_ downloadItem: DownloadItem) {
        performDownloadAction(downloadItem, action: .pause)
    }

    /// Resume a download
    @MainActor
    public func resumeDownload(_ downloadItem: DownloadItem) {
        performDownloadAction(downloadItem, action: .resume)
    }

    /// Retry a failed download
    @MainActor
    public func retryDownload(_ downloadItem: DownloadItem) {
        performDownloadAction(downloadItem, action: .retry)
    }

    // MARK: - UUID-based convenience methods

    /// Cancel download by ID
    @MainActor
    public func cancelDownload(_ downloadId: UUID) {
        performDownloadAction(downloadId, action: .cancel)
    }

    /// Pause download by ID
    @MainActor
    public func pauseDownload(_ downloadId: UUID) {
        performDownloadAction(downloadId, action: .pause)
    }

    /// Resume download by ID
    @MainActor
    public func resumeDownload(_ downloadId: UUID) {
        performDownloadAction(downloadId, action: .resume)
    }

    /// Retry download by ID
    @MainActor
    public func retryDownload(_ downloadId: UUID) {
        performDownloadAction(downloadId, action: .retry)
    }

    /// Remove download by ID
    @MainActor
    public func removeDownload(_ downloadId: UUID) {
        performDownloadAction(downloadId, action: .remove)
    }

    /// Remove a download from the list
    @MainActor
    public func removeDownload(_ downloadItem: DownloadItem) {
        // Cancel if still active
        if downloadItem.state.isActive {
            cancelDownload(downloadItem)
        }

        // Remove from list
        downloads.removeAll { $0.id == downloadItem.id }

        logger.info("🗑️ Removed download: \(downloadItem.filename)")
        updateUI()
    }

    /// Clear completed downloads
    @MainActor
    public func clearCompleted() {
        let completedCount = downloads.count { $0.state == .completed }
        downloads.removeAll { $0.state == .completed }

        logger.info("🧹 Cleared completed downloads: \(completedCount) removed")
        updateUI()
    }

    /// Open download in Finder
    public func openInFinder(_ downloadItem: DownloadItem) {
        guard let destinationURL = downloadItem.destinationURL,
              FileManager.default.fileExists(atPath: destinationURL.path) else {
            logger.warning("📁 File not found for opening: \(downloadItem.filename)")
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
        logger.info("📁 Opened in Finder: \(downloadItem.filename)")
    }

    // MARK: - Private Methods

    private enum DownloadAction {
        case cancel
        case pause
        case resume
        case retry
        case remove
    }

    @MainActor
    private func performDownloadAction(_ downloadId: UUID, action: DownloadAction) {
        guard let downloadItem = downloads.first(where: { $0.id == downloadId }) else {
            logger.warning("⚠️ Download not found for: \(downloadId)")
            return
        }
        performDownloadAction(downloadItem, action: action)
    }

    @MainActor
    private func performDownloadAction(_ downloadItem: DownloadItem, action: DownloadAction) {
        switch action {
        case .cancel:
            cancelTask(for: downloadItem)
            downloadItem.state = .cancelled
            logger.info("❌ Cancelled download: \(downloadItem.filename)")
        case .pause:
            cancelTask(for: downloadItem)
            downloadItem.state = .paused
            logger.info("⏸️ Paused download: \(downloadItem.filename)")
        case .resume:
            logger.info("▶️ Resuming download: \(downloadItem.filename)")
            resetDownloadProgress(downloadItem)
            startDownloadTask(for: downloadItem)
        case .retry:
            logger.info("🔄 Retrying download: \(downloadItem.filename)")
            resetDownloadProgress(downloadItem)
            startDownloadTask(for: downloadItem)
        case .remove:
            removeDownload(downloadItem)
            return
        }

        if action != .resume, action != .retry {
            downloadItem.speed = 0
            downloadItem.timeRemaining = 0
        }
        updateUI()
    }

    @MainActor
    private func handleExistingDownload(_ existingDownload: DownloadItem) {
        switch existingDownload.state {
        case .paused:
            performDownloadAction(existingDownload, action: .resume)
        case .failed:
            performDownloadAction(existingDownload, action: .retry)
        default:
            if existingDownload.state.isActive {
                logger.info("📥 Download already active: \(existingDownload.filename)")
            }
        }
    }

    private func cancelTask(for downloadItem: DownloadItem) {
        if let task = activeTasks.first(where: { $0.value.id == downloadItem.id })?.key {
            task.cancel()
            activeTasks.removeValue(forKey: task)
        }
    }

    private func resetDownloadProgress(_ downloadItem: DownloadItem) {
        downloadItem.state = .downloading
        downloadItem.progress = 0.0
        downloadItem.receivedBytes = 0
        downloadItem.speed = 0
        downloadItem.timeRemaining = 0
        downloadItem.error = nil
    }

    /// Start the actual URLSession download task for a download item
    private func startDownloadTask(for downloadItem: DownloadItem) {
        let request = URLRequest(url: downloadItem.url)
        let downloadTask = urlSession.downloadTask(with: request)

        // Associate task with download item
        activeTasks[downloadTask] = downloadItem
        downloadItem.state = .downloading

        downloadTask.resume()
    }

    private func updateUI() {
        objectWillChange.send()
        persistDownloads()
    }

    private func setupNotifications() {
        // Listen for download requests from WebViews
        NotificationCenter.default.addObserver(
            forName: Notification.Name("AltoDownloadRequested"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let userInfo = notification.userInfo else {
                return
            }

            // Handle different notification formats
            if let urlString = userInfo["url"] as? String,
               let url = URL(string: urlString) {
                let filename = userInfo["filename"] as? String
                Task { @MainActor in
                    self.startDownload(from: url, filename: filename)
                }
            }
        }

        logger.info("👂 Download: Notification listeners registered")
    }

    private func createUniqueDestinationURL(for filename: String) -> URL {
        let baseURL = downloadsDirectory.appendingPathComponent(filename)

        guard FileManager.default.fileExists(atPath: baseURL.path) else {
            return baseURL
        }

        // Create unique filename by appending number
        let nameWithoutExtension = baseURL.deletingPathExtension().lastPathComponent
        let fileExtension = baseURL.pathExtension

        for i in 1...999 {
            let newFilename = fileExtension.isEmpty ?
                "\(nameWithoutExtension) \(i)" :
                "\(nameWithoutExtension) \(i).\(fileExtension)"

            let newURL = downloadsDirectory.appendingPathComponent(newFilename)

            if !FileManager.default.fileExists(atPath: newURL.path) {
                return newURL
            }
        }

        return baseURL // Fallback
    }

    @MainActor
    private func completeDownload(
        _ downloadItem: DownloadItem,
        downloadTask: URLSessionDownloadTask,
        success: Bool,
        error: Error? = nil
    ) {
        downloadItem.state = success ? .completed : .failed
        downloadItem.progress = success ? 1.0 : downloadItem.progress
        downloadItem.speed = 0
        downloadItem.timeRemaining = 0
        downloadItem.error = error

        // Clean up
        activeTasks.removeValue(forKey: downloadTask)

        let status = success ? "✅ Download completed" : "❌ Download failed"
        logger.info("\(status): \(downloadItem.filename)")

        // Auto-remove completed downloads from list but keep in persistence for history
        if success {
            downloads.removeAll { $0.id == downloadItem.id }
        }

        updateUI()
    }

    // MARK: - Persistence & Auto-Restart

    private func loadAndRestartIncompleteDownloads() {
        let persistenceURL = settingsDirectory.appendingPathComponent("downloads_metadata.json")

        guard FileManager.default.fileExists(atPath: persistenceURL.path) else {
            logger.info("📋 No persisted downloads found")
            return
        }

        do {
            let data = try Data(contentsOf: persistenceURL)
            let persistedDownloads = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
            let dateFormatter = ISO8601DateFormatter()
            var incompleteCount = 0
            var autoRestartCount = 0

            for downloadDict in persistedDownloads {
                guard let urlString = downloadDict["url"] as? String,
                      let url = URL(string: urlString),
                      let filename = downloadDict["filename"] as? String,
                      let suggestedFilename = downloadDict["suggestedFilename"] as? String,
                      let startTimeString = downloadDict["startTime"] as? String,
                      let startTime = dateFormatter.date(from: startTimeString),
                      let stateString = downloadDict["state"] as? String,
                      let state = DownloadState(rawValue: stateString) else {
                    continue
                }

                // Only load incomplete downloads (failed, paused, cancelled, or interrupted)
                guard state != .completed else { continue }

                let downloadItem = DownloadItem(url: url, suggestedFilename: suggestedFilename)
                downloadItem.filename = filename
                downloadItem.state = state
                downloadItem.progress = downloadDict["progress"] as? Double ?? 0.0
                downloadItem.totalBytes = downloadDict["totalBytes"] as? Int64 ?? 0
                downloadItem.receivedBytes = downloadDict["receivedBytes"] as? Int64 ?? 0

                if let destinationURLString = downloadDict["destinationURL"] as? String,
                   !destinationURLString.isEmpty {
                    downloadItem.destinationURL = URL(string: destinationURLString)
                }

                downloads.append(downloadItem)
                incompleteCount += 1

                // Auto-restart failed or interrupted downloads
                if state == .failed || state == .downloading || state == .paused {
                    Task { @MainActor in
                        self.performDownloadAction(downloadItem, action: .retry)
                    }
                    autoRestartCount += 1
                }
            }

            if incompleteCount > 0 {
                logger.info("📋 Loaded \(incompleteCount) incomplete downloads, auto-restarting \(autoRestartCount)")
            }

        } catch {
            logger.error("❌ Failed to load persisted downloads: \(error)")
        }
    }

    private func persistDownloads() {
        do {
            // Only persist incomplete downloads and recent completed ones for history
            let persistableDownloads = downloads.map { download in
                [
                    "id": download.id.uuidString,
                    "url": download.url.absoluteString,
                    "filename": download.filename,
                    "suggestedFilename": download.suggestedFilename,
                    "startTime": ISO8601DateFormatter().string(from: download.startTime),
                    "state": download.state.rawValue,
                    "progress": download.progress,
                    "totalBytes": download.totalBytes,
                    "receivedBytes": download.receivedBytes,
                    "destinationURL": download.destinationURL?.absoluteString ?? ""
                ]
            }

            let data = try JSONSerialization.data(withJSONObject: persistableDownloads, options: .prettyPrinted)
            let persistenceURL = settingsDirectory.appendingPathComponent("downloads_metadata.json")
            try data.write(to: persistenceURL)

        } catch {
            logger.error("❌ Failed to persist downloads: \(error)")
        }
    }
}

// MARK: URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {
    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let downloadItem = activeTasks[downloadTask] else { return }

        // Move file to final destination
        do {
            if let destinationURL = downloadItem.destinationURL {
                // Create destination directory if needed
                try FileManager.default.createDirectory(
                    at: destinationURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )

                // Remove existing file if it exists
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }

                // Move downloaded file to destination
                try FileManager.default.moveItem(at: location, to: destinationURL)

                Task { @MainActor in
                    self.completeDownload(downloadItem, downloadTask: downloadTask, success: true)
                }
            }
        } catch {
            Task { @MainActor in
                self.completeDownload(downloadItem, downloadTask: downloadTask, success: false, error: error)
            }
        }
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let downloadItem = activeTasks[downloadTask] else { return }

        Task { @MainActor in
            downloadItem.receivedBytes = totalBytesWritten
            downloadItem.totalBytes = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : totalBytesWritten

            // Update progress
            if downloadItem.totalBytes > 0 {
                downloadItem.progress = Double(totalBytesWritten) / Double(downloadItem.totalBytes)
            }

            // Calculate speed and time remaining
            let elapsedTime = Date().timeIntervalSince(downloadItem.startTime)
            if elapsedTime > 0 {
                downloadItem.speed = Double(totalBytesWritten) / elapsedTime

                if downloadItem.speed > 0, downloadItem.totalBytes > 0 {
                    let remainingBytes = downloadItem.totalBytes - totalBytesWritten
                    downloadItem.timeRemaining = Double(remainingBytes) / downloadItem.speed
                }
            }

            downloadItem.state = .downloading
            self.objectWillChange.send()
        }
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didCompleteWithError error: Error?
    ) {
        guard let downloadItem = activeTasks[downloadTask], let error else { return }

        Task { @MainActor in
            self.completeDownload(downloadItem, downloadTask: downloadTask, success: false, error: error)
        }
        // Success case is handled in didFinishDownloadingTo
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didResumeAtOffset fileOffset: Int64,
        expectedTotalBytes: Int64
    ) {
        guard let downloadItem = activeTasks[downloadTask] else { return }

        Task { @MainActor in
            downloadItem.receivedBytes = fileOffset
            downloadItem.totalBytes = expectedTotalBytes
            downloadItem.state = .downloading

            if downloadItem.totalBytes > 0 {
                downloadItem.progress = Double(fileOffset) / Double(expectedTotalBytes)
            }

            self.logger.info("▶️ Download resumed: \(downloadItem.filename) at \(fileOffset) bytes")
            self.objectWillChange.send()
        }
    }
}

// MARK: URLSessionTaskDelegate

extension DownloadManager: URLSessionTaskDelegate {
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Additional task completion handling if needed
        if let downloadTask = task as? URLSessionDownloadTask,
           let downloadItem = activeTasks[downloadTask],
           let error,
           downloadItem.state != .completed {
            Task { @MainActor in
                self.completeDownload(downloadItem, downloadTask: downloadTask, success: false, error: error)
            }
        }
    }
}
