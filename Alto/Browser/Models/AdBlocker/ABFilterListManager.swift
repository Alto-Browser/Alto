//
//  ABFilterListManager.swift
//  Alto
//
//  Created by Kami on 23/06/2025.
//

import Foundation
import OSLog

/// Manages filter lists and rule compilation
@MainActor
public final class ABFilterListManager: ObservableObject {
    private let logger = Logger(subsystem: "com.alto.adblock", category: "ABFilterListManager")

    // MARK: - Properties

    @Published public var availableFilterLists: [ABFilterList] = []
    @Published public var isUpdating = false

    private let networkSession = URLSession.shared
    private let cacheUpdateInterval: TimeInterval = 86400 // 24 hours
    private var filterListCache: [String: (content: String, timestamp: Date)] = [:]

    // File-based storage paths
    private let applicationSupportURL: URL
    private let filterListsURL: URL
    private let filterCacheURL: URL

    // Rule limits for memory efficiency
    private let maxRulesPerList = 5000
    private let totalMaxRules = 25000
    private let maxParsingRules = 10000

    // MARK: - Initialization

    public init() {
        let fileManager = FileManager.default
        let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        applicationSupportURL = appSupportDir.appendingPathComponent("Alto/AdBlock")
        filterListsURL = applicationSupportURL.appendingPathComponent("FilterLists.json")
        filterCacheURL = applicationSupportURL.appendingPathComponent("FilterCache")

        for item in [applicationSupportURL, filterCacheURL] {
            try? fileManager.createDirectory(at: item, withIntermediateDirectories: true)
        }

        setupDefaultFilterLists()
        loadFilterListsFromFile()
        loadCacheFromFiles()
        logger.info("📋 AdBlock storage initialized at: \(self.applicationSupportURL.path)")
    }

    // MARK: - Setup

    private func setupDefaultFilterLists() {
        availableFilterLists = [
            ("easylist", "EasyList", "https://easylist.to/easylist/easylist.txt", true),
            ("easyprivacy", "EasyPrivacy", "https://easylist.to/easylist/easyprivacy.txt", true),
            (
                "ublock-filters",
                "uBlock filters",
                "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters.txt",
                true
            ),
            ("adguard-base", "AdGuard Base", "https://filters.adtidy.org/extension/chromium/filters/2.txt", false),
            ("fanboys-annoyance", "Fanboy's Annoyance", "https://easylist.to/easylist/fanboy-annoyance.txt", false)
        ].map { id, name, url, enabled in
            ABFilterList(id: id, name: name, url: url, isBuiltIn: true, isEnabled: enabled)
        }
    }

    // MARK: - Filter List Management

    /// Toggle a filter list on/off
    public func toggleFilterList(_ filterList: ABFilterList) {
        guard let index = availableFilterLists.firstIndex(where: { $0.id == filterList.id }) else { return }

        availableFilterLists[index].isEnabled.toggle()
        saveFilterListsToFile()

        logger.info("🔄 Toggled filter list \(filterList.name): \(self.availableFilterLists[index].isEnabled ? "ON" : "OFF")")
    }

    /// Add a custom filter list
    public func addCustomFilterList(name: String, url: String) {
        let customList = ABFilterList(
            id: UUID().uuidString,
            name: name,
            url: url,
            isBuiltIn: false,
            isEnabled: true
        )

        availableFilterLists.append(customList)
        saveFilterListsToFile()
        logger.info("➕ Added custom filter list: \(name)")
    }

    /// Remove a filter list
    public func removeFilterList(_ filterList: ABFilterList) {
        guard !filterList.isBuiltIn else {
            logger.warning("⚠️ Cannot remove built-in filter list")
            return
        }

        availableFilterLists.removeAll { $0.id == filterList.id }

        let cacheFile = filterCacheURL.appendingPathComponent("\(filterList.id).txt")
        try? FileManager.default.removeItem(at: cacheFile)

        saveFilterListsToFile()
        logger.info("🗑️ Removed filter list: \(filterList.name)")
    }

    // MARK: - Rule Compilation

    /// Get compiled rules as JSON string for WebKit
    public func getCompiledRules(excludingDomains: Set<String> = []) async -> String {
        let allRules = await getAllCompiledRules(excludingDomains: excludingDomains)

        // Apply the old 25k limit for backward compatibility
        let limitedRules = Array(allRules.prefix(totalMaxRules))

        let result = encodeRules(limitedRules) ?? "[]"
        logger.info("✅ Compiled \(limitedRules.count) rules (limited from \(allRules.count) total)")
        return result
    }

    /// Get all compiled rules as objects (without 25k limit for multi-list support)
    public func getAllCompiledRules(excludingDomains: Set<String> = []) async -> [ABContentRule] {
        // Start with built-in blocking rules first
        var allRules = getBuiltInBlockingRules()
        logger.info("📝 Added \(allRules.count) built-in blocking rules")

        let enabledLists = availableFilterLists.filter(\.isEnabled)
        logger.info("🔍 Enabled filter lists: \(enabledLists.map(\.name).joined(separator: ", "))")

        // Log exclusions
        if !excludingDomains.isEmpty {
            logger.info("⚠️ Excluding domains: \(Array(excludingDomains).joined(separator: ", "))")
        }

        guard !enabledLists.isEmpty else {
            logger.info("✅ No external filter lists enabled - using built-in rules only")

            // Add site-specific whitelist rules at the END (they use ignore-previous-rules)
            let youtubeRules = getYouTubeWhitelistRules()
            let redditRules = getRedditWhitelistRules()
            allRules.append(contentsOf: youtubeRules)
            allRules.append(contentsOf: redditRules)
            logger
                .info(
                    "📝 Added \(youtubeRules.count) YouTube + \(redditRules.count) Reddit whitelist rules (total: \(allRules.count))"
                )

            return allRules
        }

        for filterList in enabledLists {
            do {
                logger.info("⬇️ Processing filter list: \(filterList.name) from \(filterList.url)")
                let filterContent = try await getCachedOrDownloadFilterList(filterList)
                logger.info("📥 Downloaded \(filterContent.count) characters from \(filterList.name)")

                let rules = parseAdBlockFilters(filterContent, excludingDomains: excludingDomains)
                allRules.append(contentsOf: rules) // Don't limit per-list anymore

                logger.info("📝 Added \(rules.count) rules from \(filterList.name) (total now: \(allRules.count))")
            } catch {
                logger.error("❌ Failed to get filter list \(filterList.name): \(error)")
            }
        }

        // Add site-specific whitelist rules at the END (they use ignore-previous-rules to override blocking)
        let youtubeRules = getYouTubeWhitelistRules()
        let redditRules = getRedditWhitelistRules()
        allRules.append(contentsOf: youtubeRules)
        allRules.append(contentsOf: redditRules)
        logger
            .info(
                "📝 Added \(youtubeRules.count) YouTube + \(redditRules.count) Reddit whitelist rules at end (total: \(allRules.count))"
            )

        logger
            .info("✅ Generated \(allRules.count) total rules from \(enabledLists.count) filter lists + site whitelists")
        return allRules
    }

    private func encodeRules(_ rules: [ABContentRule]) -> String? {
        do {
            let jsonData = try JSONEncoder().encode(rules)
            return String(data: jsonData, encoding: .utf8)
        } catch {
            logger.error("❌ Failed to encode rules: \(error)")
            return nil
        }
    }

    // MARK: - Built-in Rules

    private func getYouTubeWhitelistRules() -> [ABContentRule] {
        logger.info("🏗️ Building YouTube whitelist rules...")

        let youtubeWhitelistRules: [(String, [String], String)] = [
            // Core YouTube domains (broader patterns)
            (".*ytimg\\.com.*", ABResourceType.allWebKitTypes, "YouTube Images (whitelist)"),
            (".*yt3\\.ggpht\\.com.*", ABResourceType.allWebKitTypes, "YouTube Thumbnails (whitelist)"),
            (".*yt4\\.ggpht\\.com.*", ABResourceType.allWebKitTypes, "YouTube Thumbnails v4 (whitelist)"),
            (".*googlevideo\\.com.*", ABResourceType.allWebKitTypes, "YouTube Videos (whitelist)"),

            // YouTube API and internal (more comprehensive)
            (".*youtube\\.com\\/api.*", ABResourceType.allWebKitTypes, "YouTube API (whitelist)"),
            (".*youtube\\.com\\/youtubei.*", ABResourceType.allWebKitTypes, "YouTube Internal API (whitelist)"),
            (".*youtube\\.com\\/ptracking.*", ABResourceType.allWebKitTypes, "YouTube Analytics (whitelist)"),
            (".*youtube\\.com\\/generate_204.*", ABResourceType.allWebKitTypes, "YouTube Analytics (whitelist)"),

            // YouTube static assets - MUCH broader patterns to catch all variations
            (".*youtube\\.com\\/s\\/.*", ABResourceType.allWebKitTypes, "YouTube /s/ Assets (whitelist)"),
            (".*youtube\\.com\\/yts\\/.*", ABResourceType.allWebKitTypes, "YouTube /yts/ Assets (whitelist)"),
            (".*youtube\\.com.*cssbin.*", ABResourceType.allWebKitTypes, "YouTube CSS Bins (whitelist)"),
            (".*youtube\\.com.*\\/js\\/.*", ABResourceType.allWebKitTypes, "YouTube JS Assets (whitelist)"),
            (".*youtube\\.com.*\\/ss\\/.*", ABResourceType.allWebKitTypes, "YouTube SS Assets (whitelist)"),

            // Essential YouTube file types (specific patterns to override blocking)
            (".*youtube\\.com.*\\.js.*", [ABResourceType.script.rawValue], "YouTube JS Files (whitelist)"),
            (".*youtube\\.com.*\\.css.*", [ABResourceType.styleSheet.rawValue], "YouTube CSS Files (whitelist)"),
            (".*youtube\\.com.*kevlar.*", ABResourceType.allWebKitTypes, "YouTube Kevlar Framework (whitelist)"),

            // Google services that YouTube depends on
            (".*gstatic\\.com.*", ABResourceType.allWebKitTypes, "Google Static Assets (whitelist)"),
            (".*googleapis\\.com.*", ABResourceType.allWebKitTypes, "Google APIs (whitelist)"),

            // YouTube subdomains (keep specific to YouTube)
            (".*\\.youtube\\.com.*", ABResourceType.allWebKitTypes, "YouTube Subdomains (whitelist)")
        ]

        var rules: [ABContentRule] = []
        for (pattern, resourceTypes, description) in youtubeWhitelistRules {
            let rule = ABContentRule(
                trigger: ABTrigger(urlFilter: pattern, resourceType: resourceTypes),
                action: ABAction(type: ABActionType.ignorePreviousRules.rawValue)
            )
            rules.append(rule)
            logger.debug("✅ YouTube whitelist rule (ignore-previous): \(description)")
        }

        logger.info("✅ Built \(rules.count) YouTube whitelist rules")
        return rules
    }

    private func getRedditWhitelistRules() -> [ABContentRule] {
        logger.info("🏗️ Building Reddit whitelist rules...")

        let redditWhitelistRules: [(String, [String], String)] = [
            // Core Reddit domains and assets
            (".*reddit\\.com.*", ABResourceType.allWebKitTypes, "Reddit Main Domain (whitelist)"),
            (".*redditstatic\\.com.*", ABResourceType.allWebKitTypes, "Reddit Static Assets (whitelist)"),
            (".*redd\\.it.*", ABResourceType.allWebKitTypes, "Reddit Short Links (whitelist)"),

            // Reddit API endpoints
            (".*reddit\\.com\\/api.*", ABResourceType.allWebKitTypes, "Reddit API (whitelist)"),
            (".*reddit\\.com\\/svc.*", ABResourceType.allWebKitTypes, "Reddit Services (whitelist)"),

            // Reddit static resources
            (".*reddit\\.com.*\\.js.*", [ABResourceType.script.rawValue], "Reddit JS Files (whitelist)"),
            (".*reddit\\.com.*\\.css.*", [ABResourceType.styleSheet.rawValue], "Reddit CSS Files (whitelist)"),
            (".*redditstatic\\.com.*\\.js.*", [ABResourceType.script.rawValue], "Reddit Static JS (whitelist)"),
            (".*redditstatic\\.com.*\\.css.*", [ABResourceType.styleSheet.rawValue], "Reddit Static CSS (whitelist)"),

            // Reddit Shreddit (new Reddit) components
            (
                ".*redditstatic\\.com\\/shreddit.*",
                ABResourceType.allWebKitTypes,
                "Reddit Shreddit Components (whitelist)"
            ),

            // Reddit images and media
            (".*i\\.redd\\.it.*", ABResourceType.allWebKitTypes, "Reddit Images (whitelist)"),
            (".*v\\.redd\\.it.*", ABResourceType.allWebKitTypes, "Reddit Videos (whitelist)"),
            (".*preview\\.redd\\.it.*", ABResourceType.allWebKitTypes, "Reddit Preview Images (whitelist)"),
            (".*external-preview\\.redd\\.it.*", ABResourceType.allWebKitTypes, "Reddit External Previews (whitelist)")
        ]

        var rules: [ABContentRule] = []
        for (pattern, resourceTypes, description) in redditWhitelistRules {
            let rule = ABContentRule(
                trigger: ABTrigger(urlFilter: pattern, resourceType: resourceTypes),
                action: ABAction(type: ABActionType.ignorePreviousRules.rawValue)
            )
            rules.append(rule)
            logger.debug("✅ Reddit whitelist rule (ignore-previous): \(description)")
        }

        logger.info("✅ Built \(rules.count) Reddit whitelist rules")
        return rules
    }

    private func getBuiltInBlockingRules() -> [ABContentRule] {
        logger.info("🏗️ Building built-in blocking rules...")

        // Core blocking rules
        let blockingRules: [(String, [String], String)] = [
            (
                ".*googlesyndication\\.com.*",
                [ABResourceType.script.rawValue, ABResourceType.fetch.rawValue],
                "Google Ads Syndication"
            ),
            (".*doubleclick\\.net.*", ABResourceType.allWebKitTypes, "DoubleClick Ad Network"),
            (".*googleadservices\\.com.*", ABResourceType.allWebKitTypes, "Google Ad Services"),
            (
                ".*google-analytics\\.com.*",
                [ABResourceType.script.rawValue, ABResourceType.fetch.rawValue, ABResourceType.image.rawValue],
                "Google Analytics"
            ),
            (
                ".*googletagmanager\\.com.*",
                [ABResourceType.script.rawValue, ABResourceType.fetch.rawValue],
                "Google Tag Manager"
            ),
            (
                ".*facebook\\.com/tr.*",
                [ABResourceType.image.rawValue, ABResourceType.fetch.rawValue],
                "Facebook Tracking"
            ),
            (".*connect\\.facebook\\.net.*", [ABResourceType.script.rawValue], "Facebook SDK"),
            (".*\\/ads\\/.*", ABResourceType.allWebKitTypes, "Generic /ads/ paths"),
            (".*\\/advertisement\\/.*", ABResourceType.allWebKitTypes, "Generic /advertisement/ paths"),
            (".*\\/banners\\/.*", ABResourceType.allWebKitTypes, "Generic /banners/ paths"),
            (".*.ads\\.", ABResourceType.allWebKitTypes, "Generic ads subdomains"),
            (".*\\/ads\\.js.*", [ABResourceType.script.rawValue], "Generic ads.js scripts"),
            (".*pagead2\\.googlesyndication\\.com.*", ABResourceType.allWebKitTypes, "Google PageAd2"),
            (".*\\/pagead\\.js.*", [ABResourceType.script.rawValue], "Generic pagead.js scripts"),
            (".*\\/widget\\/ads\\.", ABResourceType.allWebKitTypes, "Widget ads"),
            (".*hotjar\\.com.*", [ABResourceType.script.rawValue, ABResourceType.fetch.rawValue], "Hotjar Analytics"),
            (
                ".*sentry\\.io.*",
                [ABResourceType.script.rawValue, ABResourceType.fetch.rawValue],
                "Sentry Error Tracking"
            ),
            (
                ".*bugsnag\\.com.*",
                [ABResourceType.script.rawValue, ABResourceType.fetch.rawValue],
                "Bugsnag Error Tracking"
            ),
            (
                ".*yandex\\.ru\\/metrica.*",
                [ABResourceType.script.rawValue, ABResourceType.fetch.rawValue],
                "Yandex Metrica"
            ),
            (
                ".*mc\\.yandex\\.ru.*",
                [ABResourceType.script.rawValue, ABResourceType.fetch.rawValue],
                "Yandex Analytics"
            )
        ]

        var rules: [ABContentRule] = []
        for (pattern, resourceTypes, description) in blockingRules {
            let rule = ABContentRule(
                trigger: ABTrigger(urlFilter: pattern, resourceType: resourceTypes),
                action: ABAction(type: ABActionType.block.rawValue)
            )
            rules.append(rule)
            logger.debug("🛡️ Built-in rule: \(description) (\(resourceTypes.joined(separator: ",")))")
        }

        // Add cosmetic rule
        let cosmeticSelector =
            "[data-ad-client], [data-ad-slot], .google-ad, .adsense, #ads, .ads, .advertisement, .ad-banner, .ad-container"
        rules.append(ABContentRule(
            trigger: ABTrigger(urlFilter: ".*"),
            action: ABAction(
                type: ABActionType.cssDisplayNone.rawValue,
                selector: cosmeticSelector
            )
        ))
        logger.debug("🎨 Built-in cosmetic rule: \(cosmeticSelector)")

        logger.info("✅ Built \(rules.count) built-in blocking rules")
        return rules
    }

    // MARK: - Filter Parsing

    private func parseAdBlockFilters(_ content: String, excludingDomains: Set<String>) -> [ABContentRule] {
        let lines = content.components(separatedBy: .newlines)
        var rules: [ABContentRule] = []
        var skippedLines = 0
        var commentLines = 0
        var emptyLines = 0

        logger.info("🔍 Parsing filter content: \(lines.count) lines total")

        for (index, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmedLine.isEmpty {
                emptyLines += 1
                continue
            }

            if trimmedLine.hasPrefix("!") || trimmedLine.hasPrefix("[") {
                commentLines += 1
                continue
            }

            if let rule = parseBasicRule(trimmedLine, excludingDomains: excludingDomains) {
                rules.append(rule)
                if rules.count % 1000 == 0 {
                    logger.debug("📝 Parsed \(rules.count) rules so far...")
                }
            } else if let cosmeticRule = parseCosmeticRule(trimmedLine) {
                rules.append(cosmeticRule)
                if rules.count % 1000 == 0 {
                    logger.debug("📝 Parsed \(rules.count) rules so far...")
                }
            } else {
                skippedLines += 1
                if skippedLines < 10 || skippedLines % 100 == 0 {
                    logger.debug("⏭️ Skipped line \(index): \(String(trimmedLine.prefix(100)))")
                }
            }

            if rules.count >= maxParsingRules {
                logger.warning("⚠️ Reached maximum parsing rules limit (\(self.maxParsingRules))")
                break
            }
        }

        logger
            .info(
                "📊 Filter parsing summary: \(rules.count) rules, \(skippedLines) skipped, \(commentLines) comments, \(emptyLines) empty"
            )
        return rules
    }

    private func parseBasicRule(_ line: String, excludingDomains: Set<String>) -> ABContentRule? {
        guard line.allSatisfy(\.isASCII),
              !line.contains("@@"),
              !line.contains("##") else {
            if line.contains("@@") {
                logger.debug("⚪ Skipping exception rule: \(String(line.prefix(50)))")
            } else if line.contains("##") {
                // This will be handled by parseCosmeticRule
                return nil
            } else if !line.allSatisfy(\.isASCII) {
                logger.debug("⚪ Skipping non-ASCII rule: \(String(line.prefix(50)))")
            }
            return nil
        }

        var pattern = line
        var resourceTypes: [String] = ABResourceType.allWebKitTypes
        var originalPattern = pattern

        // Check for domain exclusions
        for excludedDomain in excludingDomains {
            if pattern.contains(excludedDomain) {
                logger.debug("⚪ Skipping rule for excluded domain \(excludedDomain): \(String(pattern.prefix(50)))")
                return nil
            }
        }

        // Convert AdBlock pattern to regex
        if pattern.hasPrefix("||") {
            pattern = ".*" + NSRegularExpression.escapedPattern(for: String(pattern.dropFirst(2))) + ".*"
        } else if pattern.hasPrefix("|") {
            pattern = "^" + NSRegularExpression.escapedPattern(for: String(pattern.dropFirst())) + ".*"
        } else {
            pattern = ".*" + NSRegularExpression.escapedPattern(for: pattern) + ".*"
        }

        // Check for resource type modifiers
        if line.contains("$") {
            let parts = line.components(separatedBy: "$")
            if parts.count > 1 {
                let modifiers = parts[1].components(separatedBy: ",")
                var modifierTypes: [String] = []

                for modifier in modifiers {
                    let cleanModifier = modifier.trimmingCharacters(in: .whitespacesAndNewlines)
                    switch cleanModifier {
                    case "script": modifierTypes = [ABResourceType.script.rawValue]
                    case "image": modifierTypes = [ABResourceType.image.rawValue]
                    case "stylesheet": modifierTypes = [ABResourceType.styleSheet.rawValue]
                    case "document": modifierTypes = [ABResourceType.document.rawValue]
                    default:
                        if !cleanModifier.isEmpty {
                            // logger
                            //     .debug(
                            //         "❓ Unknown modifier: \(cleanModifier) in rule:
                            //         \(String(originalPattern.prefix(50)))"
                            //     )
                        }
                    }
                }

                if !modifierTypes.isEmpty {
                    resourceTypes = modifierTypes
                    // logger
                    //     .debug(
                    //         "🎯 Resource-specific rule: \(resourceTypes.joined(separator: ",")) for
                    //         \(String(originalPattern.prefix(30)))"
                    //     )
                }
            }
        }

        // Log potentially problematic rules for YouTube
        if originalPattern.lowercased().contains("youtube") || originalPattern.lowercased().contains("ytimg") {
            // logger.warning("🎥 YouTube-related rule: \(originalPattern) -> \(pattern)")
        }

        // Log image-related rules that might affect thumbnails
        if resourceTypes.contains(ABResourceType.image.rawValue),
           originalPattern.contains("img") || originalPattern.contains("thumb") {
            // logger.warning("🖼️ Image rule that might affect thumbnails: \(originalPattern)")
        }

        return ABContentRule(
            trigger: ABTrigger(urlFilter: pattern, resourceType: resourceTypes),
            action: ABAction(type: ABActionType.block.rawValue)
        )
    }

    private func parseCosmeticRule(_ line: String) -> ABContentRule? {
        guard line.contains("##") else { return nil }

        let parts = line.components(separatedBy: "##")
        guard parts.count == 2 else {
            logger.debug("⚪ Invalid cosmetic rule format: \(String(line.prefix(50)))")
            return nil
        }

        let domainPart = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let selector = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)

        // Log potentially problematic cosmetic rules
        if selector.contains("video") || selector.contains("player") || selector.contains("thumb") || selector
            .contains("img") {
            // logger.warning("🎨 Cosmetic rule that might affect media: \(line)")
        }

        if selector.contains("youtube") || domainPart.contains("youtube") {
            logger.warning("🎥 YouTube cosmetic rule: \(line)")
        }

        // logger
        //     .debug(
        //         "🎨 Cosmetic rule: \(domainPart.isEmpty ? "global" : domainPart) -> hide
        //         '\(String(selector.prefix(30)))'"
        //     )

        // Handle domain-specific rules
        var trigger: ABTrigger
        if !domainPart.isEmpty, domainPart != "*" {
            // Domain-specific cosmetic rule
            let domains = domainPart.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            trigger = ABTrigger(urlFilter: ".*", ifDomain: domains)
        } else {
            // Global cosmetic rule
            trigger = ABTrigger(urlFilter: ".*")
        }

        return ABContentRule(
            trigger: trigger,
            action: ABAction(type: ABActionType.cssDisplayNone.rawValue, selector: selector)
        )
    }

    // MARK: - Network Operations

    private func getCachedOrDownloadFilterList(_ filterList: ABFilterList) async throws -> String {
        let cacheFile = filterCacheURL.appendingPathComponent("\(filterList.id).txt")
        let cacheMetaFile = filterCacheURL.appendingPathComponent("\(filterList.id).meta.json")

        if FileManager.default.fileExists(atPath: cacheFile.path),
           FileManager.default.fileExists(atPath: cacheMetaFile.path) {
            do {
                let metaData = try Data(contentsOf: cacheMetaFile)
                let meta = try JSONDecoder().decode([String: Double].self, from: metaData)

                if let timestamp = meta["timestamp"] {
                    let cacheAge = Date().timeIntervalSince1970 - timestamp
                    if cacheAge < cacheUpdateInterval {
                        let content = try String(contentsOf: cacheFile, encoding: .utf8)
                        logger.info("📋 Using cached filter list: \(filterList.name) (age: \(Int(cacheAge / 3600))h)")
                        return content
                    } else {
                        logger.info("🕒 Cache expired for \(filterList.name), downloading fresh copy")
                    }
                }
            } catch {
                logger.warning("⚠️ Failed to read cache metadata for \(filterList.name): \(error)")
            }
        }

        let content = try await downloadFilterList(from: filterList.url)

        do {
            try content.write(to: cacheFile, atomically: true, encoding: .utf8)

            let meta = ["timestamp": Date().timeIntervalSince1970]
            let metaData = try JSONEncoder().encode(meta)
            try metaData.write(to: cacheMetaFile)

            logger.info("💾 Downloaded and cached filter list: \(filterList.name) (\(content.count) bytes)")
        } catch {
            logger.error("❌ Failed to cache filter list \(filterList.name): \(error)")
        }

        return content
    }

    private func downloadFilterList(from urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "ABFilterListManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        let (data, _) = try await networkSession.data(from: url)
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - File-based Persistence

    private func saveFilterListsToFile() {
        do {
            let data = try JSONEncoder().encode(availableFilterLists)
            try data.write(to: filterListsURL)
            logger.info("💾 Saved filter lists to file")
        } catch {
            logger.error("❌ Failed to save filter lists to file: \(error)")
        }
    }

    private func loadFilterListsFromFile() {
        guard FileManager.default.fileExists(atPath: filterListsURL.path) else {
            logger.info("📋 No saved filter lists found, using defaults")
            return
        }

        do {
            let data = try Data(contentsOf: filterListsURL)
            let loadedLists = try JSONDecoder().decode([ABFilterList].self, from: data)

            for loadedList in loadedLists {
                if let index = availableFilterLists.firstIndex(where: { $0.id == loadedList.id }) {
                    availableFilterLists[index] = loadedList
                } else if !loadedList.isBuiltIn {
                    availableFilterLists.append(loadedList)
                }
            }

            logger.info("📋 Loaded \(loadedLists.count) filter lists from file")
        } catch {
            logger.error("❌ Failed to load filter lists from file: \(error)")
        }
    }

    private func loadCacheFromFiles() {
        let fileManager = FileManager.default

        do {
            let cacheFiles = try fileManager.contentsOfDirectory(at: filterCacheURL, includingPropertiesForKeys: nil)
            let contentFiles = cacheFiles.filter { $0.pathExtension == "txt" }

            for contentFile in contentFiles {
                let id = contentFile.deletingPathExtension().lastPathComponent
                let metaFile = filterCacheURL.appendingPathComponent("\(id).meta.json")

                if fileManager.fileExists(atPath: metaFile.path) {
                    do {
                        let content = try String(contentsOf: contentFile, encoding: .utf8)
                        let metaData = try Data(contentsOf: metaFile)
                        let meta = try JSONDecoder().decode([String: Double].self, from: metaData)

                        if let timestamp = meta["timestamp"] {
                            filterListCache[id] = (content: content, timestamp: Date(timeIntervalSince1970: timestamp))
                        }
                    } catch {
                        logger.warning("⚠️ Failed to load cached filter \(id): \(error)")
                    }
                }
            }

            logger.info("📋 Loaded \(self.filterListCache.count) cached filter lists from files")
        } catch {
            logger.warning("⚠️ Failed to load filter cache directory: \(error)")
        }
    }

    // MARK: - Update Operations

    /// Update all filter lists
    public func updateAllFilterLists() async {
        await MainActor.run { isUpdating = true }

        for i in 0 ..< availableFilterLists.count {
            do {
                _ = try await downloadFilterList(from: availableFilterLists[i].url)
                await MainActor.run {
                    self.availableFilterLists[i].lastUpdated = Date()
                }
                logger.info("✅ Updated filter list: \(self.availableFilterLists[i].name)")
            } catch {
                logger.error("❌ Failed to update filter list \(self.availableFilterLists[i].name): \(error)")
            }
        }

        await MainActor.run {
            isUpdating = false
            saveFilterListsToFile()
        }
    }

    /// Load essential filter lists for immediate effectiveness
    public func loadEssentialFilterLists() async -> String {
        encodeRules(getBuiltInBlockingRules()) ?? "[]"
    }

    /// Get minimal rules for emergency fallback
    public func getMinimalRules() async -> String {
        // Start with basic blocking rules
        let basicBlockingRules = [
            ("googlesyndication", ABActionType.block.rawValue),
            ("doubleclick", ABActionType.block.rawValue),
            ("googleadservices", ABActionType.block.rawValue)
        ].map { pattern, action in
            ABContentRule(
                trigger: ABTrigger(urlFilter: pattern),
                action: ABAction(type: action)
            )
        }

        var minimalRules = basicBlockingRules

        // Add site-specific whitelist rules at the end (they use ignore-previous-rules)
        let youtubeRules = getYouTubeWhitelistRules()
        let redditRules = getRedditWhitelistRules()
        minimalRules.append(contentsOf: youtubeRules)
        minimalRules.append(contentsOf: redditRules)

        let result = encodeRules(minimalRules) ?? "[]"
        logger
            .info(
                "🚨 Using minimal rules fallback (\(minimalRules.count) rules: \(basicBlockingRules.count) blocking + \(youtubeRules.count) YouTube + \(redditRules.count) Reddit whitelist)"
            )
        return result
    }

    /// Force refresh all filter lists
    public func refreshAllFilterLists() async {
        await updateAllFilterLists()
    }

    /// Clear all cached filter data
    public func clearAllCaches() {
        let fileManager = FileManager.default

        do {
            let cacheContents = try fileManager.contentsOfDirectory(at: filterCacheURL, includingPropertiesForKeys: nil)
            for file in cacheContents {
                try fileManager.removeItem(at: file)
            }

            filterListCache.removeAll()
            logger.info("🗑️ Cleared all filter caches")
        } catch {
            logger.error("❌ Failed to clear caches: \(error)")
        }
    }

    /// Get all enabled filter lists
    public func getEnabledFilterLists() -> [ABFilterList] {
        availableFilterLists.filter(\.isEnabled)
    }
}
