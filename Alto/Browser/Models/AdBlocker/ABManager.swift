//
//  ABManager.swift
//  Alto
//
//  Created by Kami on 23/06/2025.
//

import CryptoKit
import Foundation
import OSLog
import WebKit

// MARK: - ABManager

/// Main manager for AltoBlock ad blocking functionality
@MainActor
public class ABManager: ObservableObject {
    public static let shared = ABManager()

    private let logger = Logger(subsystem: "com.alto.adblock", category: "ABManager")

    // MARK: - Published Properties

    @Published public var isEnabled = true
    @Published public var totalBlockedRequests = 0
    @Published public var blockedRequestsThisSession = 0
    @Published public var whitelistedDomains: Set<String> = []

    // MARK: - Core Components

    public let contentBlocker = ABContentBlocker()
    public let filterListManager = ABFilterListManager()
    public let statisticsManager = ABStatistics()

    // MARK: - WebKit Content Rules State

    private var compiledRuleList: WKContentRuleList?
    private var lastRuleCompilationHash: String?
    private var isInitialized = false

    // MARK: - Settings Storage

    private let settingsFileURL: URL
    private let settingsKey = "ABManagerSettings"

    // MARK: - Rule Compilation Cache

    private var cachedRuleListsKey: String
    private var ruleHashKey: String

    // MARK: - Initialization State

    private enum InitializationState {
        case notInitialized
        case initializing
        case initialized
        case failed
    }

    private var initializationState: InitializationState = .notInitialized

    // File-based storage
    private let settingsURL: URL

    private init() {
        // Setup file-based storage for settings
        let fileManager = FileManager.default
        let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let adBlockDir = appSupportDir.appendingPathComponent("Alto/AdBlock")
        settingsURL = adBlockDir.appendingPathComponent("Settings.json")
        settingsFileURL = settingsURL

        // Generate or load random cache keys
        let cacheKeysURL = adBlockDir.appendingPathComponent("CacheKeys.json")
        if let data = try? Data(contentsOf: cacheKeysURL),
           let keys = try? JSONDecoder().decode(CacheKeys.self, from: data) {
            cachedRuleListsKey = keys.cachedRuleListsKey
            ruleHashKey = keys.ruleHashKey
        } else {
            // Generate new random keys
            cachedRuleListsKey = "CachedRuleLists_\(UUID().uuidString)"
            ruleHashKey = "RuleCompilationHash_\(UUID().uuidString)"
            // Save keys after all properties are initialized
        }

        // Create directory if needed
        try? fileManager.createDirectory(at: adBlockDir, withIntermediateDirectories: true)

        logger.info("🛡️ ABManager initializing...")

        // Clear old UserDefaults and migrate to file storage
        clearLegacyUserDefaults()
        loadSettings()

        // Load cached rule hash for cache validation
        loadCachedRuleHash()

        // Save cache keys if they were newly generated
        if !fileManager.fileExists(atPath: cacheKeysURL.path) {
            saveCacheKeys(to: cacheKeysURL)
        }

        logger.info("🛡️ ABManager basic setup complete, waiting for explicit initialization")
    }

    // MARK: - Public Interface

    /// Initialize content blocking system
    public func initializeContentBlocking() async {
        if initializationState != .notInitialized {
            logger.debug("🔄 Content blocking already initialized, skipping")
            return
        }

        initializationState = .initializing
        logger.info("🛡️ Initializing content blocking system...")

        // Check if we have cached compiled rules first
        let hasRules = await contentBlocker.hasCompiledRules()
        let isCacheValid = await isCacheValid()

        if hasRules, isCacheValid {
            logger.info("📋 Using cached compiled rules")
            initializationState = .initialized
            return
        }

        // Need to compile new rules
        logger.info("🔍 No compiled rules found, need to compile")

        do {
            await contentBlocker.compileAndApplyRules()
            initializationState = .initialized
            logger.info("✅ AdBlocker initialized successfully")
        } catch {
            logger.error("❌ Failed to initialize AdBlocker: \(error)")
            initializationState = .failed
        }
    }

    /// Apply content blocking to a WebView
    public func applyContentBlocking(to webView: WKWebView) async {
        let webViewURL = webView.url?.absoluteString ?? "no URL"

        guard isEnabled, let ruleList = compiledRuleList else {
            logger.info("⏭️ Content blocking disabled or no rules compiled for WebView: \(webViewURL)")
            return
        }

        logger.info("🛡️ Applying content blocking to WebView: \(webViewURL)")

        // Remove existing rules first
        await webView.configuration.userContentController.removeAllContentRuleLists()
        logger.debug("🗑️ Removed existing content rules from WebView")

        // Add new rules
        await webView.configuration.userContentController.add(ruleList)
        logger.info("✅ Added new content rules to WebView: \(webViewURL)")

        // Register for navigation events to track blocked requests
        contentBlocker.registerWebView(webView)
        logger.debug("📝 Registered WebView for statistics tracking: \(webViewURL)")
    }

    /// Remove content blocking from a WebView
    public func removeContentBlocking(from webView: WKWebView) async {
        logger.debug("🚫 Removing content blocking from WebView")

        await webView.configuration.userContentController.removeAllContentRuleLists()

        contentBlocker.unregisterWebView(webView)
    }

    /// Toggle ad blocking on/off
    public func toggleAdBlocking() {
        isEnabled.toggle()
        saveSettings()

        if isEnabled {
            Task {
                await contentBlocker.enableForAllWebViews()
            }
        } else {
            Task {
                await contentBlocker.disableForAllWebViews()
            }
        }

        logger.info("🔄 Ad blocking toggled: \(self.isEnabled ? "ON" : "OFF")")

        // Trigger UI update
        objectWillChange.send()
    }

    /// Check if a domain is whitelisted
    public func isDomainWhitelisted(_ domain: String) -> Bool {
        whitelistedDomains.contains(domain.lowercased())
    }

    /// Add domain to whitelist
    public func addToWhitelist(domain: String) {
        let cleanDomain = domain.lowercased().replacingOccurrences(of: "www.", with: "")
        whitelistedDomains.insert(cleanDomain)
        saveSettings()

        Task {
            await contentBlocker.compileAndApplyRules()
        }

        logger.info("✅ Added \(cleanDomain) to whitelist")

        // Trigger UI update
        objectWillChange.send()
    }

    /// Remove domain from whitelist
    public func removeFromWhitelist(domain: String) {
        let cleanDomain = domain.lowercased().replacingOccurrences(of: "www.", with: "")
        whitelistedDomains.remove(cleanDomain)
        saveSettings()

        Task {
            await contentBlocker.compileAndApplyRules()
        }

        logger.info("🗑️ Removed \(cleanDomain) from whitelist")

        // Trigger UI update
        objectWillChange.send()
    }

    /// Get blocking statistics for the current page
    public func getPageStatistics(for url: URL) -> ABPageStats {
        statisticsManager.getPageStats(for: url)
    }

    /// Get global blocking statistics
    public func getGlobalStatistics() -> ABGlobalStats {
        statisticsManager.getGlobalStats()
    }

    /// Update filter lists
    public func updateFilterLists() async {
        logger.info("🔄 Updating filter lists...")

        do {
            await filterListManager.updateAllFilterLists()
            await contentBlocker.compileAndApplyRules()
            logger.info("✅ Filter lists updated successfully")
        } catch {
            logger.error("❌ Failed to update filter lists: \(error)")
        }
    }

    /// Get the current compiled rule list for immediate application to WebViews
    public func getCurrentCompiledRuleList() async -> WKContentRuleList? {
        compiledRuleList
    }

    /// Set the compiled rule list (used by ABContentBlocker to keep in sync)
    public func setCompiledRuleList(_ ruleList: WKContentRuleList) async {
        compiledRuleList = ruleList
    }

    // MARK: - Private Methods

    private func compileContentRules() async {
        // Delegate to ABContentBlocker to avoid duplication
        await contentBlocker.compileAndApplyRules()

        // Cache the rule hash for future cache validation
        await cacheCurrentRuleHash()
    }

    /// Check if cached rules are still valid (no filter list changes)
    private func canUseCachedRules() async -> Bool {
        // Check if we have existing compiled rule lists in contentBlocker
        let hasCompiledRules = await contentBlocker.hasCompiledRules()
        guard hasCompiledRules else {
            logger.info("🔍 No compiled rules found, need to compile")
            return false
        }

        // Generate hash of current filter configuration
        let currentHash = await calculateCurrentRuleHash()

        // Check if hash matches cached hash
        if let cachedHash = lastRuleCompilationHash, currentHash == cachedHash {
            logger.info("✅ Rule configuration unchanged (hash: \(currentHash.prefix(8))...), using cached rules")
            return true
        } else {
            logger
                .info(
                    "🔄 Rule configuration changed (old: \(self.lastRuleCompilationHash?.prefix(8) ?? "none"), new: \(currentHash.prefix(8))), need to recompile"
                )
            return false
        }
    }

    /// Calculate hash representing current rule configuration
    private func calculateCurrentRuleHash() async -> String {
        // Include factors that would require recompilation:
        // 1. Enabled filter lists and their update times
        // 2. Whitelist domains
        // 3. Built-in rule configuration

        var hashComponents: [String] = []

        // Filter list fingerprint
        let filterLists = await filterListManager.getEnabledFilterLists()
        for filterList in filterLists {
            // Include name, URL, and last update time
            let component = "\(filterList.name)|\(filterList.url)|\(filterList.lastUpdated?.timeIntervalSince1970 ?? 0)"
            hashComponents.append(component)
        }

        // Whitelist domains
        let sortedWhitelist = Array(whitelistedDomains).sorted()
        hashComponents.append("whitelist:\(sortedWhitelist.joined(separator: ","))")

        // Built-in rules version (increment this if built-in rules change)
        hashComponents.append("builtin:v1.0")

        // Create combined hash
        let combined = hashComponents.joined(separator: "|")
        let data = combined.data(using: .utf8) ?? Data()
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Cache the current rule hash for future validation
    public func cacheCurrentRuleHash() async {
        lastRuleCompilationHash = await calculateCurrentRuleHash()

        // Persist to UserDefaults for next app launch
        UserDefaults.standard.set(lastRuleCompilationHash, forKey: ruleHashKey)
        logger.info("💾 Cached rule hash: \(self.lastRuleCompilationHash?.prefix(8) ?? "none")...")
    }

    /// Load cached rule hash from UserDefaults
    private func loadCachedRuleHash() {
        lastRuleCompilationHash = UserDefaults.standard.string(forKey: ruleHashKey)
        if let hash = lastRuleCompilationHash {
            logger.info("📁 Loaded cached rule hash: \(hash.prefix(8))...")
        }
    }

    /// Check if current cache is valid
    private func isCacheValid() async -> Bool {
        guard let cachedHash = lastRuleCompilationHash else {
            logger.debug("🔍 No cached hash found")
            return false
        }

        let currentHash = await calculateCurrentRuleHash()
        let isValid = cachedHash == currentHash

        if isValid {
            logger.info("✅ Cache is valid, using cached rules")
        } else {
            logger.info("❌ Cache is invalid, need to recompile")
            logger.debug("🔍 Cached hash: \(cachedHash.prefix(8))...")
            logger.debug("🔍 Current hash: \(currentHash.prefix(8))...")
        }

        return isValid
    }

    // MARK: - Cache Key Management

    private struct CacheKeys: Codable {
        let cachedRuleListsKey: String
        let ruleHashKey: String
    }

    private func loadCacheKeys(from url: URL) -> CacheKeys? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(CacheKeys.self, from: data)
        } catch {
            logger.error("❌ Failed to load cache keys: \(error)")
            return nil
        }
    }

    private func saveCacheKeys(to url: URL) {
        let keys = CacheKeys(
            cachedRuleListsKey: cachedRuleListsKey,
            ruleHashKey: ruleHashKey
        )

        do {
            let data = try JSONEncoder().encode(keys)
            try data.write(to: url, options: .atomic)
            logger.info("💾 Saved random cache keys")
        } catch {
            logger.error("❌ Failed to save cache keys: \(error)")
        }
    }

    // MARK: - Settings Persistence

    private struct ManagerSettings: Codable {
        let isEnabled: Bool
        let totalBlockedRequests: Int
        let blockedRequestsThisSession: Int
        let whitelistedDomains: Set<String>
    }

    private func clearLegacyUserDefaults() {
        // Clear all old UserDefaults keys
        let legacyKeys = [
            "AltoBlock.isEnabled",
            "AltoBlock.totalBlockedRequests",
            "AltoBlock.blockedRequestsThisSession",
            "AltoBlock.whitelistedDomains",
            "AltoBlock.filterLists",
            "AltoBlock.filterListCache"
        ]

        let defaults = UserDefaults.standard
        for key in legacyKeys {
            defaults.removeObject(forKey: key)
        }
        defaults.synchronize()

        logger.info("🗑️ Cleared legacy UserDefaults keys for AdBlock")
    }

    private func loadSettings() {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else {
            // Use defaults for fresh install
            isEnabled = true
            totalBlockedRequests = 0
            blockedRequestsThisSession = 0
            whitelistedDomains = []
            saveSettings() // Save defaults to file
            logger.info("📋 Using default settings for fresh install")
            return
        }

        do {
            let data = try Data(contentsOf: settingsURL)
            let settings = try JSONDecoder().decode(ManagerSettings.self, from: data)

            isEnabled = settings.isEnabled
            totalBlockedRequests = settings.totalBlockedRequests
            blockedRequestsThisSession = settings.blockedRequestsThisSession
            whitelistedDomains = settings.whitelistedDomains

            logger
                .info(
                    "📋 Loaded settings from file: enabled=\(self.isEnabled), blocked=\(self.totalBlockedRequests), whitelist=\(self.whitelistedDomains.count)"
                )
        } catch {
            logger.error("❌ Failed to load settings from file: \(error)")
            logger.info("📋 Using default settings")

            // Reset to defaults on load failure
            isEnabled = true
            totalBlockedRequests = 0
            blockedRequestsThisSession = 0
            whitelistedDomains = []
        }
    }

    private func saveSettings() {
        let settings = ManagerSettings(
            isEnabled: isEnabled,
            totalBlockedRequests: totalBlockedRequests,
            blockedRequestsThisSession: blockedRequestsThisSession,
            whitelistedDomains: whitelistedDomains
        )

        do {
            let data = try JSONEncoder().encode(settings)
            try data.write(to: settingsURL, options: .atomic)
            logger.debug("💾 Saved settings to file")
        } catch {
            logger.error("❌ Failed to save settings to file: \(error)")
        }
    }
}

// MARK: - Statistics Update Interface

extension ABManager {
    /// Called when a request is blocked
    func recordBlockedRequest(url: URL, onPage pageURL: URL) {
        totalBlockedRequests += 1
        blockedRequestsThisSession += 1
        statisticsManager.recordBlockedRequest(url: url, onPage: pageURL)
        saveSettings()

        logger.info("🚫 BLOCKED REQUEST: \(url.absoluteString) on page: \(pageURL.host ?? pageURL.absoluteString)")

        // Log special cases
        if url.host?.contains("youtube") == true || pageURL.host?.contains("youtube") == true {
            logger.warning("🎥 YouTube request blocked: \(url.absoluteString)")
        }

        if url.absoluteString.contains("img") || url.absoluteString.contains("thumb") {
            logger.warning("🖼️ Image/thumbnail request blocked: \(url.absoluteString)")
        }

        // Trigger UI update
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    /// Called when a page loads
    func recordPageLoad(url: URL) {
        statisticsManager.recordPageLoad(url: url)
        logger.info("📄 Page load recorded: \(url.absoluteString)")

        if url.host?.contains("youtube") == true {
            logger.info("🎥 YouTube page load: \(url.absoluteString)")
        }
    }
}
