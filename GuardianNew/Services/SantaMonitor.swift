import Foundation
import Combine
import AppKit
import SwiftUI  // Added SwiftUI import for Color type

class SantaMonitor: ObservableObject {
    @Published var status: SecurityState = .unknown
    @Published var isRunning: Bool = false
    @Published var isValidMode: Bool = false
    @Published var mode: String = "Unknown"
    @Published var ruleCount: Int = 0
    @Published var hasPermission: Bool = true
    @Published var errorMessage: String? = nil
    @Published var rules: [SantaRule] = []  // New property to store rules
    
    // Add path finder for santactl
    private lazy var santactlPath: String = {
        // Try multiple possible locations for santactl
        let possibleLocations = [
            "/usr/local/bin/santactl",
            "/opt/homebrew/bin/santactl",
            "/usr/bin/santactl",
            // Additional paths that might have santactl
            "/usr/sbin/santactl",
            "/opt/santa/bin/santactl"
        ]
        
        for path in possibleLocations {
            if FileManager.default.fileExists(atPath: path) {
                print("Found santactl at: \(path)")
                return path
            }
        }
        
        // Default path if not found
        print("santactl not found in standard locations, defaulting to /usr/local/bin/santactl")
        return "/usr/local/bin/santactl"
    }()
    
    // Fetch Santa rules using santactl
    func fetchRules() {
        print("Starting to fetch Santa rules")
        
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            
            // Use an appropriate limit based on the rule count we've detected
            // Add a buffer to ensure we capture all rules
            let limit = max(200, self.ruleCount * 2) 
            print("Using limit of \(limit) for rule fetching (detected rule count: \(self.ruleCount))")
            
            var fetchedRules: [SantaRule] = []
            
            // First try using the ruleCount information we already have from santactl status
            // This doesn't need admin privileges and gives us rule count by type
            let ruleCountsByType = self.getRuleCountsByType()
            print("Rule counts by type: \(ruleCountsByType)")
            
            if ruleCountsByType.values.reduce(0, +) > 0 {
                // Extract rules from the rule counts
                for (type, count) in ruleCountsByType {
                    for _ in 0..<count {
                        // Create placeholder rules representing the count
                        let rule = SantaRule(
                            identifier: "[\(type.capitalized) Rule]",
                            policy: .allow, // Default to allow since we don't know
                            type: type,
                            customMessage: "Details unavailable without admin privileges. Total count: \(count)"
                        )
                        fetchedRules.append(rule)
                    }
                }
            }
            
            // If we have at least some rules from the ruleCount approach, use those and mention the admin issue
            if fetchedRules.count > 0 && fetchedRules.count >= self.ruleCount / 2 {
                // Create info rule to explain privilege issue
                let infoRule = SantaRule(
                    identifier: "ADMIN PRIVILEGES REQUIRED",
                    policy: .allow,
                    type: "info",
                    customMessage: "Full rule details require admin privileges. Showing \(fetchedRules.count) rule placeholders based on rule counts."
                )
                fetchedRules.insert(infoRule, at: 0)
                
                // Create admin help rule
                let helpRule = SantaRule(
                    identifier: "HOW TO VIEW FULL RULES",
                    policy: .allow,
                    type: "info",
                    customMessage: "Run Guardian with sudo or from an admin account to see full rule details."
                )
                fetchedRules.insert(helpRule, at: 1)
            } else {
                // Try with other non-admin methods
                let allRules = self.fetchAllRulesWithRulesetDump()
                
                if !allRules.isEmpty {
                    // If ruleset dump worked, use those rules
                    print("Successfully fetched \(allRules.count) rules using ruleset dump")
                    fetchedRules = allRules
                } else {
                    // Fall back to individual rule type queries
                    print("Ruleset dump unsuccessful, falling back to individual type queries")
                    
                    // Try checking if we actually have admin privileges before running commands that require them
                    let hasAdminPrivileges = self.checkAdminPrivileges()
                    
                    if hasAdminPrivileges {
                        // If we have admin privileges, we can run the commands directly
                        let binaryRules = self.fetchRulesByType(type: "binary", limit: limit)
                        fetchedRules.append(contentsOf: binaryRules)
                        
                        let certificateRules = self.fetchRulesByType(type: "certificate", limit: limit)
                        fetchedRules.append(contentsOf: certificateRules)
                        
                        let teamIDRules = self.fetchRulesByType(type: "teamid", limit: limit)
                        fetchedRules.append(contentsOf: teamIDRules)
                        
                        let signingIDRules = self.fetchRulesByType(type: "signingid", limit: limit)
                        fetchedRules.append(contentsOf: signingIDRules)
                        
                        let cdHashRules = self.fetchRulesByType(type: "cdhash", limit: limit)
                        fetchedRules.append(contentsOf: cdHashRules)
                    } else {
                        // We don't have admin privileges, so add an info rule and placeholders
                        let infoRule = SantaRule(
                            identifier: "ADMIN PRIVILEGES REQUIRED",
                            policy: .allow,
                            type: "info",
                            customMessage: "Viewing Santa rules requires admin privileges. Run Guardian as admin to see details."
                        )
                        fetchedRules.insert(infoRule, at: 0)
                        
                        // Try to add placeholder rules based on what we know from the status
                        for i in 0..<self.ruleCount {
                            let rule = SantaRule(
                                identifier: "Rule #\(i+1)",
                                policy: .allow,
                                type: "unknown",
                                customMessage: "Rule details unavailable without admin privileges"
                            )
                            fetchedRules.append(rule)
                        }
                    }
                }
            }
            
            // Update the rules on main thread
            DispatchQueue.main.async {
                self.rules = fetchedRules
                print("Total fetched rules: \(fetchedRules.count). Expected: \(self.ruleCount)")
            }
        }
    }
    
    // Get rule counts by type from santactl status output (doesn't require admin privileges)
    private func getRuleCountsByType() -> [String: Int] {
        var ruleCountsByType = [String: Int]()
        
        let task = Process()
        task.launchPath = santactlPath
        task.arguments = ["status"]
        
        let outputPipe = Pipe()
        task.standardOutput = outputPipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: outputData, encoding: .utf8) {
                let lines = output.components(separatedBy: "\n")
                
                for line in lines {
                    // Check for different rule type lines
                    if line.contains("Binary Rules:") {
                        if let count = extractNumberFromLine(line) {
                            ruleCountsByType["binary"] = count
                        }
                    } else if line.contains("Certificate Rules:") {
                        if let count = extractNumberFromLine(line) {
                            ruleCountsByType["certificate"] = count
                        }
                    } else if line.contains("TeamID Rules:") {
                        if let count = extractNumberFromLine(line) {
                            ruleCountsByType["teamid"] = count
                        }
                    } else if line.contains("SigningID Rules:") {
                        if let count = extractNumberFromLine(line) {
                            ruleCountsByType["signingid"] = count
                        }
                    } else if line.contains("CDHash Rules:") {
                        if let count = extractNumberFromLine(line) {
                            ruleCountsByType["cdhash"] = count
                        }
                    }
                }
            }
        } catch {
            print("Error getting rule counts by type: \(error)")
        }
        
        return ruleCountsByType
    }
    
    // Helper to extract number from a line like "Binary Rules: 12"
    private func extractNumberFromLine(_ line: String) -> Int? {
        let components = line.components(separatedBy: ":")
        if components.count > 1,
           let lastComponent = components.last,
           let number = Int(lastComponent.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return number
        }
        return nil
    }
    
    // Check if we have admin privileges
    private func checkAdminPrivileges() -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/id"
        task.arguments = ["-u"]
        
        let outputPipe = Pipe()
        task.standardOutput = outputPipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: outputData, encoding: .utf8),
               let uid = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) {
                // UID 0 means root/admin privileges
                return uid == 0
            }
        } catch {
            print("Error checking admin privileges: \(error)")
        }
        
        return false
    }
    
    // Special function to fetch rules with admin privileges (used when user wants to see detailed rules)
    func fetchRulesWithAdmin() {
        print("Attempting to fetch rules with admin privileges")
        
        // Create a helper script to run santactl with admin privileges
        let scriptContent = """
        #!/bin/bash
        # Script to extract Santa rules with admin privileges
        
        # Use santactl to dump all rules
        BINARY_RULES=$(/usr/bin/sudo /usr/local/bin/santactl rule list --type binary --json 2>/dev/null || echo "{}")
        CERT_RULES=$(/usr/bin/sudo /usr/local/bin/santactl rule list --type certificate --json 2>/dev/null || echo "{}")
        TEAMID_RULES=$(/usr/bin/sudo /usr/local/bin/santactl rule list --type teamid --json 2>/dev/null || echo "{}")
        SIGNINGID_RULES=$(/usr/bin/sudo /usr/local/bin/santactl rule list --type signingid --json 2>/dev/null || echo "{}")
        CDHASH_RULES=$(/usr/bin/sudo /usr/local/bin/santactl rule list --type cdhash --json 2>/dev/null || echo "{}")
        
        # Create a JSON structure with all rules
        echo "{"
        echo "  \\"binary\\": $BINARY_RULES,"
        echo "  \\"certificate\\": $CERT_RULES,"
        echo "  \\"teamid\\": $TEAMID_RULES,"
        echo "  \\"signingid\\": $SIGNINGID_RULES,"
        echo "  \\"cdhash\\": $CDHASH_RULES"
        echo "}"
        """
        
        // Write the script to a temporary file
        let tempScriptPath = NSTemporaryDirectory() + "guardian_santa_helper.sh"
        do {
            try scriptContent.write(toFile: tempScriptPath, atomically: true, encoding: .utf8)
            
            // Make the script executable
            let chmodTask = Process()
            chmodTask.launchPath = "/bin/chmod"
            chmodTask.arguments = ["+x", tempScriptPath]
            try chmodTask.run()
            chmodTask.waitUntilExit()
            
            // Create an AppleScript to request admin privileges
            let appleScriptContent = """
            do shell script "\(tempScriptPath)" with administrator privileges
            """
            
            let appleScriptTask = Process()
            appleScriptTask.launchPath = "/usr/bin/osascript"
            appleScriptTask.arguments = ["-e", appleScriptContent]
            
            let outputPipe = Pipe()
            appleScriptTask.standardOutput = outputPipe
            
            try appleScriptTask.run()
            appleScriptTask.waitUntilExit()
            
            // Process the output JSON
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: outputData, encoding: .utf8) {
                print("Got admin script output, length: \(output.count)")
                
                // Parse the JSON output
                if let jsonData = output.data(using: .utf8) {
                    do {
                        if let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                            var adminRules: [SantaRule] = []
                            
                            // Process each rule type
                            let ruleTypes = ["binary", "certificate", "teamid", "signingid", "cdhash"]
                            for type in ruleTypes {
                                if let typeRules = json[type] as? [String: Any],
                                   let rules = typeRules["rules"] as? [[String: Any]] {
                                    for ruleDict in rules {
                                        if let identifier = ruleDict["identifier"] as? String,
                                           let policyStr = ruleDict["policy"] as? String {
                                            let policy: SantaRulePolicy = policyStr.lowercased().contains("block") ? .block : .allow
                                            let customMessage = ruleDict["custom_message"] as? String
                                            
                                            let rule = SantaRule(
                                                identifier: identifier,
                                                policy: policy,
                                                type: type,
                                                customMessage: customMessage
                                            )
                                            
                                            adminRules.append(rule)
                                        }
                                    }
                                }
                            }
                            
                            // Update the rules on the main thread
                            DispatchQueue.main.async {
                                if adminRules.isEmpty {
                                    // If we didn't get any rules, add an info message
                                    self.rules.append(SantaRule(
                                        identifier: "ADMIN PRIVILEGES RESULT",
                                        policy: .allow,
                                        type: "info",
                                        customMessage: "No rules found with admin privileges. This may indicate an issue with the Santa configuration."
                                    ))
                                } else {
                                    // Update the rules with what we found
                                    self.rules = adminRules
                                    print("Successfully updated rules with admin privileges. Found \(adminRules.count) rules.")
                                }
                            }
                        }
                    } catch {
                        print("Error parsing admin script JSON output: \(error)")
                        
                        // Add debug info rule
                        DispatchQueue.main.async {
                            self.rules.append(SantaRule(
                                identifier: "JSON PARSE ERROR",
                                policy: .allow,
                                type: "info",
                                customMessage: "Error parsing admin script output: \(error.localizedDescription)"
                            ))
                        }
                    }
                }
            }
            
            // Clean up the temporary script
            try FileManager.default.removeItem(atPath: tempScriptPath)
        } catch {
            print("Error running admin privileges script: \(error)")
            
            // Add error rule
            DispatchQueue.main.async {
                self.rules.append(SantaRule(
                    identifier: "ADMIN SCRIPT ERROR",
                    policy: .allow,
                    type: "info",
                    customMessage: "Error running admin script: \(error.localizedDescription)"
                ))
            }
        }
    }
    
    // Get Santa's mode and rules counts from status output
    private func getSantaStatus() -> (isValidMode: Bool, mode: String, ruleCount: Int) {
        let task = Process()
        task.launchPath = santactlPath
        task.arguments = ["status"]
        
        let outputPipe = Pipe()
        task.standardOutput = outputPipe
        let errorPipe = Pipe() // Add error pipe to check for errors
        task.standardError = errorPipe
        
        var isValidMode = false
        var currentMode = "Unknown"
        var ruleCount = 0
        
        do {
            try task.run()
            task.waitUntilExit()
            
            // Check for errors first
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            if let errorOutput = String(data: errorData, encoding: .utf8), !errorOutput.isEmpty {
                print("Error from santactl status: \(errorOutput)")
                return (false, "Error: \(errorOutput.prefix(50))", 0)
            }
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: outputData, encoding: .utf8) {
                // Debug output
                print("Raw santactl status output: \(output)")
                
                // Parse output for mode and rule count
                let lines = output.components(separatedBy: "\n")
                
                for line in lines {
                    if line.contains("Mode") {
                        // Extract the actual mode with more flexible parsing
                        if let modeStr = extractValueFromLine(line) {
                            currentMode = modeStr
                            // Both Lockdown and Monitor modes are valid
                            isValidMode = modeStr == "Lockdown" || modeStr == "Monitor"
                        }
                    } else if line.contains("Binary Rules") {
                        if let countStr = extractValueFromLine(line),
                           let count = Int(countStr) {
                            ruleCount = count
                        }
                    }
                    // Also check Certificate Rules
                    else if line.contains("Certificate Rules") {
                        if let countStr = extractValueFromLine(line),
                           let count = Int(countStr) {
                            ruleCount += count
                        }
                    }
                    // Also check TeamID Rules
                    else if line.contains("TeamID Rules") {
                        if let countStr = extractValueFromLine(line),
                           let count = Int(countStr) {
                            ruleCount += count
                        }
                    }
                    // Also check SigningID Rules
                    else if line.contains("SigningID Rules") {
                        if let countStr = extractValueFromLine(line),
                           let count = Int(countStr) {
                            ruleCount += count
                        }
                    }
                    // Also check CDHash Rules
                    else if line.contains("CDHash Rules") {
                        if let countStr = extractValueFromLine(line),
                           let count = Int(countStr) {
                            ruleCount += count
                        }
                    }
                }
            }
        } catch {
            print("Error getting Santa status: \(error)")
        }
        
        return (isValidMode, currentMode, ruleCount)
    }
    
    // Helper method to extract values from santactl output lines with different formats
    private func extractValueFromLine(_ line: String) -> String? {
        // Try pipe separator format first (common in newer Santa versions)
        if line.contains("|") {
            if let pipeValue = line.split(separator: "|").last?.trimmingCharacters(in: .whitespacesAndNewlines) {
                return pipeValue
            }
        }
        
        // Try colon separator format (common in older Santa versions)
        if line.contains(":") {
            if let colonValue = line.split(separator: ":").last?.trimmingCharacters(in: .whitespacesAndNewlines) {
                return colonValue
            }
        }
        
        // Try equals separator format (rare but possible)
        if line.contains("=") {
            if let equalsValue = line.split(separator: "=").last?.trimmingCharacters(in: .whitespacesAndNewlines) {
                return equalsValue
            }
        }
        
        return nil
    }
    
    func restoreSecureState() {
        if !isRunning {
            // Attempt to start Santa daemon
            startSantaDaemon()
        } else if !isValidMode {
            // Set Santa to Lockdown mode
            setSantaLockdownMode()
        }
    }
    
    private func startSantaDaemon() {
        // Try multiple possible launchd plist paths
        let possiblePlistPaths = [
            "/Library/LaunchDaemons/com.google.santa.plist",
            "/Library/LaunchDaemons/com.google.santad.plist",
            "/Library/LaunchDaemons/org.santa.daemon.plist"
        ]
        
        // Find the first plist that exists
        var plistPath: String? = nil
        for path in possiblePlistPaths {
            if FileManager.default.fileExists(atPath: path) {
                plistPath = path
                break
            }
        }
        
        guard let plistPath = plistPath else {
            print("Could not find Santa launchd plist")
            return
        }
        
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["load", plistPath]
        
        do {
            try task.run()
            task.waitUntilExit()
            
            // Verify the change
            self.checkStatus()
        } catch {
            print("Error starting Santa daemon: \(error)")
        }
    }
    
    private func setSantaLockdownMode() {
        let task = Process()
        task.launchPath = santactlPath
        task.arguments = ["config", "--set", "ClientMode", "2"]  // 2 is Lockdown mode
        
        do {
            try task.run()
            task.waitUntilExit()
            
            // Verify the change
            self.checkStatus()
        } catch {
            print("Error setting Santa to Lockdown mode: \(error)")
        }
    }
    
    // Method to fetch rules by using ruleset dump
    private func fetchAllRulesWithRulesetDump() -> [SantaRule] {
        var fetchedRules: [SantaRule] = []
        
        // Try to use the find command to locate Santa's ruleset database
        let task = Process()
        task.launchPath = "/usr/bin/find"
        task.arguments = ["/var/db/santa", "-name", "rules.db", "-o", "-name", "santa.db", "-type", "f"]
        
        let outputPipe = Pipe()
        task.standardOutput = outputPipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !output.isEmpty else {
                print("Could not find Santa rules database")
                return fetchedRules
            }
            
            print("🔍 DEBUG: Found Santa rules database at: \(output)")
            
            // Try to dump the rules using sqlite3
            // This might work without admin privileges depending on file permissions
            let sqliteTask = Process()
            sqliteTask.launchPath = "/usr/bin/sqlite3"
            sqliteTask.arguments = [output, "SELECT * FROM rules;"]
            
            let sqlitePipe = Pipe()
            sqliteTask.standardOutput = sqlitePipe
            let errorPipe = Pipe()
            sqliteTask.standardError = errorPipe
            
            try sqliteTask.run()
            sqliteTask.waitUntilExit()
            
            // Check for errors
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            if let errorOutput = String(data: errorData, encoding: .utf8), !errorOutput.isEmpty {
                print("Error dumping rules database: \(errorOutput)")
                return fetchedRules
            }
            
            let sqliteData = sqlitePipe.fileHandleForReading.readDataToEndOfFile()
            if let sqliteOutput = String(data: sqliteData, encoding: .utf8), !sqliteOutput.isEmpty {
                print("🔍 DEBUG: Got full rules dump of \(sqliteOutput.count) characters")
                
                // Parse the output line by line
                let lines = sqliteOutput.components(separatedBy: "\n")
                for line in lines where !line.isEmpty {
                    let fields = line.components(separatedBy: "|")
                    if fields.count >= 3 {
                        let policy: SantaRulePolicy = fields[2].lowercased().contains("block") ? .block : .allow
                        let ruleType = fields[1].lowercased()
                        let identifier = fields[0]
                        let customMessage = fields.count > 3 ? fields[3] : nil
                        
                        let rule = SantaRule(
                            identifier: identifier,
                            policy: policy,
                            type: ruleType,
                            customMessage: customMessage
                        )
                        fetchedRules.append(rule)
                    }
                }
            }
        } catch {
            print("Error with ruleset dump: \(error)")
        }
        
        return fetchedRules
    }
    
    // Fetch rules by specific type (binary, certificate, etc.)
    private func fetchRulesByType(type: String, limit: Int) -> [SantaRule] {
        var rules: [SantaRule] = []
        
        let task = Process()
        task.launchPath = santactlPath
        task.arguments = ["rule", "list", "--type", type, "--json"]
        
        let outputPipe = Pipe()
        task.standardOutput = outputPipe
        let errorPipe = Pipe()
        task.standardError = errorPipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            // Check if there was an error (likely permission issue)
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            if let errorOutput = String(data: errorData, encoding: .utf8), !errorOutput.isEmpty {
                print("Error fetching \(type) rules: \(errorOutput)")
                // Create a placeholder rule to indicate the error
                let errorRule = SantaRule(
                    identifier: "[\(type.uppercased()) FETCH ERROR]",
                    policy: .allow,
                    type: type,
                    customMessage: "Error: \(errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))"
                )
                return [errorRule]
            }
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: outputData, encoding: .utf8) {
                print("Raw santactl rule list output for \(type): \(output)")
                
                // Count lines in output for debugging
                let lines = output.components(separatedBy: "\n")
                print("Found \(lines.count) lines in output")
                
                // Try to parse as JSON
                if let jsonData = output.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let typeRules = json["rules"] as? [[String: Any]] {
                    
                    for ruleDict in typeRules {
                        if let identifier = ruleDict["identifier"] as? String,
                           let policyStr = ruleDict["policy"] as? String {
                            let policy: SantaRulePolicy = policyStr.lowercased().contains("block") ? .block : .allow
                            let customMessage = ruleDict["custom_message"] as? String
                            
                            let rule = SantaRule(
                                identifier: identifier,
                                policy: policy,
                                type: type,
                                customMessage: customMessage
                            )
                            rules.append(rule)
                            
                            if rules.count >= limit {
                                print("Reached rule limit of \(limit) for \(type) rules")
                                break
                            }
                        }
                    }
                } else {
                    // If JSON parsing failed, try basic line-based parsing
                    print("Could not parse rules for \(type), but output was not empty")
                    
                    // Create a placeholder rule to indicate this type exists but couldn't be parsed
                    let placeholderRule = SantaRule(
                        identifier: "[\(type.uppercased()) RULES]",
                        policy: .allow,
                        type: type,
                        customMessage: "Found \(lines.count) lines in output but couldn't parse details"
                    )
                    rules.append(placeholderRule)
                }
                
                print("Found \(rules.count) \(type) rules")
            }
        } catch {
            print("Error executing santactl for \(type) rules: \(error)")
        }
        
        return rules
    }
    
    // Check Santa status and update published properties
    func checkStatus() {
        print("Checking Santa status...")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let isInstalled = FileManager.default.fileExists(atPath: self.santactlPath)
            
            if !isInstalled {
                print("Santa not installed (santactl not found)")
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.status = .insecure
                    self.errorMessage = "Santa not installed (santactl not found)"
                }
                return
            }
            
            // Try to get Santa status
            let santaStatus = self.getSantaStatus()
            
            DispatchQueue.main.async {
                self.isRunning = true
                self.isValidMode = santaStatus.isValidMode
                self.mode = santaStatus.mode
                self.ruleCount = santaStatus.ruleCount
                
                // Check if we have permission issues
                self.hasPermission = !self.mode.contains("Error")
                
                // If we're running, valid mode, and have rules, consider secure
                if self.isRunning && self.isValidMode && self.ruleCount > 0 {
                    self.status = .secure
                } else if self.isRunning {
                    // Running but not in optimal configuration
                    self.status = .partial
                } else {
                    // Not running at all
                    self.status = .insecure
                }
                
                // Update error message if necessary
                if !self.hasPermission {
                    self.errorMessage = "Permission issues accessing Santa information"
                } else if !self.isValidMode {
                    self.errorMessage = "Santa running in invalid mode: \(self.mode)"
                } else if self.ruleCount == 0 {
                    self.errorMessage = "Santa has no rules configured"
                } else {
                    self.errorMessage = nil
                }
                
                print("Santa status: running=\(self.isRunning), mode=\(self.mode), rules=\(self.ruleCount)")
            }
        }
    }
}

struct SantaRule: Identifiable {
    let id = UUID()
    let identifier: String
    let policy: SantaRulePolicy
    let type: String
    let customMessage: String?
    
    var policyString: String {
        switch policy {
        case .block:
            return "Block"
        case .allow:
            return "Allow"
        }
    }
    
    var displayName: String {
        // Try to show a more user-friendly name based on the type
        switch type {
        case "binary":
            return (identifier.components(separatedBy: "/").last ?? identifier)
        case "certificate":
            // Format: "Certificate: Organization Name (Team ID)"
            if let parts = customMessage?.components(separatedBy: "("),
               parts.count > 1,
               let orgName = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) {
                return orgName
            }
            return "Cert: \(identifier.prefix(16))..."
        case "teamid":
            return "Team ID: \(identifier)"
        case "signingid":
            return "Signing ID: \(identifier)"
        default:
            return identifier
        }
    }
    
    var typeIcon: String {
        switch type {
        case "binary":
            return "terminal"
        case "certificate":
            return "shield.checkerboard"
        case "teamid":
            return "person.badge.shield.checkmark"
        case "signingid":
            return "signature"
        default:
            return "doc"
        }
    }
    
    var color: Color {
        switch policy {
        case .block:
            return .red
        case .allow:
            return .green
        }
    }
}

enum SantaRulePolicy {
    case block
    case allow
}

extension SantaRule: Equatable {
    static func == (lhs: SantaRule, rhs: SantaRule) -> Bool {
        return lhs.identifier == rhs.identifier && 
               lhs.type == rhs.type &&
               lhs.policy == rhs.policy
    }
}

extension SantaRule: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
        hasher.combine(type)
        hasher.combine(policy == .allow)
    }
}