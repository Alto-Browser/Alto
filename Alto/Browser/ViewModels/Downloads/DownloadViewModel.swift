//
//  DownloadViewModel.swift
//  Alto
//
//  Created by Kami on 23/06/2025.
//

import Foundation
import OSLog
import SwiftUI

// MARK: - DownloadViewModel

/// ViewModel for the downloads UI
@MainActor
@Observable
public class DownloadViewModel {
    private let logger = Logger(subsystem: "com.alto.downloads", category: "DownloadViewModel")

    private let downloadManager = DownloadManager.shared

    // UI State
    public var isShowingDownloads = false
    public var hoveredDownloadId: UUID?

    public init() {}

    // MARK: - Computed Properties

    /// Recent downloads (last 5)
    public var recentDownloads: [DownloadItem] {
        Array(downloadManager.downloads.prefix(5))
    }

    /// All active downloads (downloading or paused)
    public var activeDownloads: [DownloadItem] {
        downloadManager.downloads.filter { $0.state == .downloading || $0.state == .paused }
    }

    /// Count of active downloads
    public var activeDownloadCount: Int {
        activeDownloads.count
    }

    /// Whether there are any active downloads
    public var hasActiveDownloads: Bool {
        activeDownloadCount > 0
    }

    /// Overall progress of all active downloads (0.0 to 1.0)
    public var overallProgress: Double {
        let activeDownloads = activeDownloads

        guard !activeDownloads.isEmpty else {
            return 0.0
        }

        let totalProgress = activeDownloads.reduce(0.0) { sum, download in
            sum + download.progress
        }

        return totalProgress / Double(activeDownloads.count)
    }

    /// Whether we have any downloads
    public var hasDownloads: Bool {
        !downloadManager.downloads.isEmpty
    }

    /// Download statistics
    public var statistics: DownloadStatistics {
        downloadManager.statistics
    }

    /// Download button state
    public var downloadButtonState: DownloadButtonState {
        if hasActiveDownloads {
            .active(count: activeDownloads.count)
        } else if hasDownloads {
            .available
        } else {
            .empty
        }
    }

    // MARK: - Formatted Properties

    /// Formatted overall download speed
    public var formattedOverallSpeed: String {
        let totalSpeed = activeDownloads.reduce(0.0) { sum, download in
            guard download.state == .downloading else { return sum }
            return sum + download.speed
        }

        guard totalSpeed > 0 else { return "" }

        return ByteCountFormatter.string(fromByteCount: Int64(totalSpeed), countStyle: .file) + "/s"
    }

    /// Summary text for active downloads
    public var downloadSummary: String {
        let activeCount = activeDownloadCount

        if activeCount == 0 {
            return "No active downloads"
        } else if activeCount == 1 {
            return "1 download active"
        } else {
            return "\(activeCount) downloads active"
        }
    }

    // MARK: - Public Methods

    /// Toggle downloads panel
    public func toggleDownloads() {
        withAnimation(.spring(duration: 0.3)) {
            isShowingDownloads.toggle()
        }
        logger.info("📥 Downloads panel toggled: \(isShowingDownloads ? "shown" : "hidden")")
    }

    /// Close downloads panel
    public func closeDownloads() {
        withAnimation(.spring(duration: 0.3)) {
            isShowingDownloads = false
        }
    }

    /// Start a download
    public func startDownload(from url: URL, filename: String? = nil) {
        downloadManager.startDownload(from: url, filename: filename)
        logger.info("📥 Started download from ViewModel: \(url.absoluteString)")
    }

    /// Cancel a download
    public func cancelDownload(_ downloadItem: DownloadItem) {
        downloadManager.cancelDownload(downloadItem)
        logger.info("❌ Cancelled download from ViewModel: \(downloadItem.filename)")
    }

    /// Pause a download
    public func pauseDownload(_ downloadItem: DownloadItem) {
        downloadManager.pauseDownload(downloadItem)
        logger.info("⏸️ Paused download from ViewModel: \(downloadItem.filename)")
    }

    /// Resume a download
    public func resumeDownload(_ downloadItem: DownloadItem) {
        downloadManager.resumeDownload(downloadItem)
        logger.info("▶️ Resumed download from ViewModel: \(downloadItem.filename)")
    }

    /// Remove a download
    public func removeDownload(_ downloadItem: DownloadItem) {
        downloadManager.removeDownload(downloadItem)
        logger.info("🗑️ Removed download from ViewModel: \(downloadItem.filename)")
    }

    /// Clear completed downloads
    public func clearCompleted() {
        downloadManager.clearCompleted()
        logger.info("🧹 Cleared completed downloads from ViewModel")
    }

    /// Open download in Finder
    public func openInFinder(_ downloadItem: DownloadItem) {
        downloadManager.openInFinder(downloadItem)
        logger.info("📁 Opened in Finder from ViewModel: \(downloadItem.filename)")
    }

    /// View all downloads (open Downloads folder)
    public func viewAllDownloads() {
        let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let altoDownloadsDirectory = downloadsDirectory.appendingPathComponent("Alto Downloads")

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: altoDownloadsDirectory, withIntermediateDirectories: true)

        NSWorkspace.shared.open(altoDownloadsDirectory)
        logger.info("📁 Opened Alto Downloads directory")
    }

    /// Set hovered download
    public func setHoveredDownload(_ downloadId: UUID?) {
        hoveredDownloadId = downloadId
    }

    /// Get icon for download state
    public func iconForDownloadState(_ state: DownloadState) -> String {
        switch state {
        case .pending:
            "clock"
        case .downloading:
            "arrow.down.circle"
        case .paused:
            "pause.circle"
        case .completed:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        case .cancelled:
            "xmark.circle.fill"
        }
    }

    /// Get color for download state
    public func colorForDownloadState(_ state: DownloadState) -> Color {
        switch state {
        case .pending:
            .orange
        case .downloading:
            .blue
        case .paused:
            .yellow
        case .completed:
            .green
        case .failed:
            .red
        case .cancelled:
            .gray
        }
    }

    /// Format file size for display
    public func formatFileSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Format time duration
    public func formatTimeDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return "\(Int(duration))s"
        } else if duration < 3600 {
            return "\(Int(duration / 60))m"
        } else {
            let hours = Int(duration / 3600)
            let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(minutes)m"
        }
    }
}
