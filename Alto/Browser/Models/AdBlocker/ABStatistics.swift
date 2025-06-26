//
//  ABStatistics.swift
//  Alto
//
//  Created by Kami on 23/06/2025.
//

import Foundation
import OSLog

/// Manages ad blocking statistics and metrics
@MainActor
public final class ABStatistics: ObservableObject {
    private let logger = Logger(subsystem: "com.alto.adblock", category: "ABStatistics")

    // MARK: - Published Properties

    @Published public var totalBlockedRequests = 0
    @Published public var totalRequests = 0
    @Published public var sessionBlockedRequests = 0
    @Published public var sessionStartTime = Date()

    // MARK: - Private Properties

    private var pageStats: [String: ABPageStats] = [:]
    private var blockedDomains: [String: Int] = [:]
    private var bandwidthSaved = 0 // in bytes

    private let maxPageStats = 100
    private let defaultEstimatedSize = 1024

    // UserDefaults keys
    private enum Keys {
        static let totalBlockedRequests = "AltoBlock.totalBlockedRequests"
        static let totalRequests = "AltoBlock.totalRequests"
        static let bandwidthSaved = "AltoBlock.bandwidthSaved"
        static let blockedDomains = "AltoBlock.blockedDomains"
    }

    // MARK: - Initialization

    public init() {
        loadStatisticsFromUserDefaults()
        sessionStartTime = Date()
        logger.info("📊 ABStatistics initialized")
    }

    // MARK: - Request Tracking

    /// Record a blocked request
    public func recordBlockedRequest(url: URL, estimatedSize: Int = 1024) {
        recordBlockedRequest(url: url, onPage: url, estimatedSize: estimatedSize)
    }

    /// Record a blocked request with page context
    public func recordBlockedRequest(url: URL, onPage pageURL: URL, estimatedSize: Int = 1024) {
        updateBlockedRequestCounters(estimatedSize: estimatedSize)

        if let host = url.host {
            blockedDomains[host, default: 0] += 1
        }

        updatePageStats(for: pageURL, blockedRequest: true)
        saveStatisticsToUserDefaults()

        logger.debug("🚫 Blocked request: \(url.host ?? "unknown") on page: \(pageURL.host ?? "unknown")")
    }

    /// Record a total request
    public func recordRequest(url: URL) {
        totalRequests += 1
        updatePageStats(for: url, blockedRequest: false)
    }

    /// Record a page load
    public func recordPageLoad(url: URL) {
        let pageKey = getPageKey(for: url)
        pageStats[pageKey] = ABPageStats(url: url, loadTime: Date())
        cleanupOldPageStats()
    }

    // MARK: - Statistics Retrieval

    /// Get global statistics
    public func getGlobalStats() -> ABGlobalStats {
        ABGlobalStats(
            totalBlockedRequests: totalBlockedRequests,
            totalRequests: totalRequests,
            blockedDomainsCount: blockedDomains.count,
            sessionStartTime: sessionStartTime,
            bandwidthSaved: bandwidthSaved
        )
    }

    /// Get statistics for a specific page
    public func getPageStats(for url: URL) -> ABPageStats {
        let pageKey = getPageKey(for: url)
        return pageStats[pageKey] ?? ABPageStats(url: url)
    }

    /// Get top blocked domains
    public func getTopBlockedDomains(limit: Int = 10) -> [(domain: String, count: Int)] {
        blockedDomains
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { (domain: $0.key, count: $0.value) }
    }

    /// Get blocking percentage
    public var blockingPercentage: Double {
        guard totalRequests > 0 else { return 0 }
        return Double(totalBlockedRequests) / Double(totalRequests) * 100
    }

    /// Get session duration
    public var sessionDuration: TimeInterval {
        Date().timeIntervalSince(sessionStartTime)
    }

    /// Get formatted bandwidth saved
    public var formattedBandwidthSaved: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bandwidthSaved))
    }

    // MARK: - Reset

    /// Reset all statistics
    public func resetAllStats() {
        resetCounters()
        resetCollections()
        saveStatisticsToUserDefaults()
        logger.info("🔄 Reset all statistics")
    }

    /// Reset session statistics
    public func resetSessionStats() {
        sessionBlockedRequests = 0
        sessionStartTime = Date()
        logger.info("🔄 Reset session statistics")
    }

    // MARK: - Private Methods

    private func updateBlockedRequestCounters(estimatedSize: Int) {
        totalBlockedRequests += 1
        sessionBlockedRequests += 1
        bandwidthSaved += estimatedSize
    }

    private func getPageKey(for url: URL) -> String {
        url.host ?? url.absoluteString
    }

    private func updatePageStats(for url: URL, blockedRequest: Bool) {
        let pageKey = getPageKey(for: url)

        guard var stats = pageStats[pageKey] else { return }

        if blockedRequest {
            stats = ABPageStats(
                url: stats.url,
                blockedRequests: stats.blockedRequests + 1,
                totalRequests: stats.totalRequests + 1,
                blockedDomains: stats.blockedDomains.union([url.host].compactMap(\.self)),
                loadTime: stats.loadTime
            )
        } else {
            stats = ABPageStats(
                url: stats.url,
                blockedRequests: stats.blockedRequests,
                totalRequests: stats.totalRequests + 1,
                blockedDomains: stats.blockedDomains,
                loadTime: stats.loadTime
            )
        }

        pageStats[pageKey] = stats
    }

    private func cleanupOldPageStats() {
        guard pageStats.count > maxPageStats else { return }

        let sortedKeys = pageStats.keys.sorted { key1, key2 in
            (pageStats[key1]?.loadTime ?? .distantPast) > (pageStats[key2]?.loadTime ?? .distantPast)
        }

        for key in sortedKeys.dropFirst(maxPageStats) {
            pageStats.removeValue(forKey: key)
        }

        // logger.debug("🧹 Cleaned up old page stats, kept \(pageStats.count) entries")
    }

    private func resetCounters() {
        totalBlockedRequests = 0
        totalRequests = 0
        sessionBlockedRequests = 0
        sessionStartTime = Date()
        bandwidthSaved = 0
    }

    private func resetCollections() {
        pageStats.removeAll()
        blockedDomains.removeAll()
    }

    // MARK: - Persistence

    private func saveStatisticsToUserDefaults() {
        let defaults = UserDefaults.standard

        let statisticsData: [(String, Any)] = [
            (Keys.totalBlockedRequests, totalBlockedRequests),
            (Keys.totalRequests, totalRequests),
            (Keys.bandwidthSaved, bandwidthSaved)
        ]

        for (key, value) in statisticsData {
            defaults.set(value, forKey: key)
        }

        if let blockedDomainsData = try? JSONEncoder().encode(blockedDomains) {
            defaults.set(blockedDomainsData, forKey: Keys.blockedDomains)
        }
    }

    private func loadStatisticsFromUserDefaults() {
        let defaults = UserDefaults.standard

        totalBlockedRequests = defaults.integer(forKey: Keys.totalBlockedRequests)
        totalRequests = defaults.integer(forKey: Keys.totalRequests)
        bandwidthSaved = defaults.integer(forKey: Keys.bandwidthSaved)

        loadBlockedDomains(from: defaults)

        // logger.info("📊 Loaded statistics: \(totalBlockedRequests) blocked, \(totalRequests) total")
    }

    private func loadBlockedDomains(from defaults: UserDefaults) {
        guard let blockedDomainsData = defaults.data(forKey: Keys.blockedDomains),
              let loadedBlockedDomains = try? JSONDecoder().decode([String: Int].self, from: blockedDomainsData) else {
            return
        }

        blockedDomains = loadedBlockedDomains
    }
}
