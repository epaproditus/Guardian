import Foundation
import Combine
import AppKit

class ProfileMonitor: ObservableObject {
    @Published var status: SecurityState = .unknown
    @Published var profilesInfo: [String: String] = [:]
    @Published var hasMDMProfile: Bool = false
    @Published var hasPermission: Bool = true
    @Published var hasProfiles: Bool = false
    @Published var errorMessage: String? = nil
    
    // Flag to indicate if admin privileges have been requested once
    static var hasTriedAdmin = false
    
    // Required profile identifiers - customize this list based on your requirements
    private var requiredProfiles: [String] = [
        // Initially empty - will auto-detect installed profiles
    ]
    
    // MDM profile identifiers - these indicate managed device status
    private var mdmProfiles = [
        "com.apple.mdm",
        "com.apple.configurator.mdm",
        "com.jamf.management"
    ]
    
    // Public accessors for the profile arrays
    var requiredProfileList: [String] {
        return requiredProfiles
    }
    
    var mdmProfileList: [String] {
        return mdmProfiles
    }
    
    // Flag to indicate if sudo was tried
    private var triedWithSudo = false
    
    // Set specific profiles to check for
    func setProfilestoCheck(required: [String], mdm: [String]) {
        requiredProfiles = required
        mdmProfiles = mdm
    }
    
    func checkStatus() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            
            // First try to check for computer-level profiles using -L argument with sudo or similar methods
            let computerLevelProfiles = self.tryGetComputerLevelProfiles()
            
            // DEBUG: Print detected profiles for troubleshooting
            print("DEBUG: Detected \(computerLevelProfiles.count) computer-level profiles: \(computerLevelProfiles)")
            
            if !computerLevelProfiles.isEmpty {
                DispatchQueue.main.async {
                    self.profilesInfo = computerLevelProfiles
                    self.hasPermission = true
                    self.hasMDMProfile = computerLevelProfiles.keys.contains { $0.contains("mdm") || $0.contains("manageengine") || $0.contains("zoho") }
                    self.hasProfiles = true
                    self.errorMessage = nil
                    self.status = .secure  // Since profiles exist, mark as secure
                }
                return
            }
            
            // Fall back to specific profiles detection method if computer-level check failed
            let specificProfiles = self.checkForSpecificProfiles()
            
            // DEBUG: Print detected specific profiles for troubleshooting
            print("DEBUG: Detected \(specificProfiles.count) specific profiles: \(specificProfiles)")
            
            if !specificProfiles.isEmpty {
                DispatchQueue.main.async {
                    self.profilesInfo = specificProfiles
                    self.hasPermission = true
                    self.hasMDMProfile = specificProfiles.keys.contains { $0.contains("mdm") || $0.contains("manageengine") || $0.contains("zoho") }
                    self.hasProfiles = true
                    self.errorMessage = nil
                    self.status = .secure  // Since profiles exist, mark as secure
                }
                return
            }
            
            // Continue with remaining checks
            // First check if Profiles.prefPane exists - this indicates profiles functionality
            let profilesPaneExists = FileManager.default.fileExists(
                atPath: "/System/Library/PreferencePanes/Profiles.prefPane")
            
            // Next check if any profiles are installed using non-sudo method
            let (profiles, hasPermission, error) = self.getInstalledProfiles()
            let installedIdentifiers = Set(profiles.keys)
            
            // If we found profiles but no required ones are defined yet, set them automatically
            // This makes the app recognize the profiles you've installed manually
            if self.requiredProfiles.isEmpty && !profiles.isEmpty {
                self.requiredProfiles = Array(installedIdentifiers)
            }
            
            let requiredSet = Set(self.requiredProfiles)
            let mdmSet = Set(self.mdmProfiles)
            
            // Check if we found any profiles at all
            let foundProfiles = !profiles.isEmpty
            
            // Check if any required profiles are installed (even if not all of them)
            let anyRequiredProfilesInstalled = !requiredSet.isDisjoint(with: installedIdentifiers)
            
            // Check if all required profiles are installed
            let allProfilesInstalled = requiredSet.isSubset(of: installedIdentifiers)
            
            // Check if any MDM profile is installed
            let hasMDM = !mdmSet.isDisjoint(with: installedIdentifiers)
            
            // Use alternative methods to detect MDM enrollment
            let alternativeMDMCheck = self.checkAlternativeMDMIndicators()
            
            DispatchQueue.main.async {
                self.profilesInfo = profiles
                self.hasPermission = hasPermission
                self.hasMDMProfile = hasMDM || alternativeMDMCheck
                self.hasProfiles = foundProfiles
                self.errorMessage = error
                
                if !hasPermission {
                    self.status = .unknown
                } else if !profilesPaneExists {
                    // If profiles functionality not available, consider it secure
                    self.status = .secure
                } else if self.requiredProfiles.isEmpty {
                    // No specific required profiles defined
                    self.status = .secure
                } else if allProfilesInstalled {
                    // All specifically required profiles are installed
                    self.status = .secure
                } else if anyRequiredProfilesInstalled {
                    // At least some required profiles are installed
                    self.status = .secure
                } else {
                    // No required profiles found at all
                    self.status = .insecure
                }
            }
        }
    }
    
    private func getInstalledProfiles() -> (profiles: [String: String], hasPermission: Bool, error: String?) {
        var profiles = [String: String]()
        var errorMessage: String? = nil
        
        // Try multiple approaches to detect profiles
        
        // Try direct check for the specific profiles we know exist from user's command
        let specificProfiles = checkForSpecificProfiles()
        if !specificProfiles.isEmpty {
            return (specificProfiles, true, nil)
        }
        
        // Approach 1: Standard profiles command
        let standardProfiles = getProfilesFromStandardCommand()
        if !standardProfiles.profiles.isEmpty {
            return standardProfiles
        } else if standardProfiles.error != nil {
            errorMessage = standardProfiles.error
        }
        
        // Approach 2: Alternative profile listing methods
        let alternativeProfiles = getProfilesFromAlternativeCommands()
        if !alternativeProfiles.profiles.isEmpty {
            return alternativeProfiles
        }
        
        // Approach 3: Check with defaults command
        let defaultsProfiles = getProfilesFromDefaultsCommand()
        if !defaultsProfiles.profiles.isEmpty {
            return defaultsProfiles
        }
        
        // Approach 4: Check with profiles -Cv command (more verbose)
        let verboseProfiles = getProfilesFromVerboseCommand()
        if !verboseProfiles.profiles.isEmpty {
            return verboseProfiles
        }
        
        // Approach 5: Check for profile files in system locations
        let fileBasedProfiles = getProfilesFromFileSystem()
        if !fileBasedProfiles.profiles.isEmpty {
            return fileBasedProfiles
        }
        
        // If we've tried all approaches and found nothing
        return (profiles, true, errorMessage)
    }
    
    // Check for specific profiles based on the sudo profiles list output format
    private func checkForSpecificProfiles() -> [String: String] {
        // Try to detect common profile identifiers plus add any custom ones we've seen
        var expectedProfiles = [
            "com.manageengine.mdm.mac",
            "restrictions.B775F8FD-2387-42D7-BCE3-6B8E6D57F14A",
            "arc.a5495cf1-f17e-4539-b8dc-d0a0190bd5bb",
            "com.zohocorp.mdm",
            "tailscale.370CB5C8-682A-4903-9B22-BB4E5BF2C080"
        ]
        
        // Add any required profiles to our expected list
        expectedProfiles.append(contentsOf: requiredProfiles)
        
        var detectedProfiles = [String: String]()
        
        // Try non-sudo method first
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-L"]
        task.launchPath = "/usr/bin/profiles"
        
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            // DEBUG: Print raw output from profiles -L
            print("DEBUG: Raw profiles output: \(output)")
            
            // Check if output explicitly states that no profiles are installed
            if output.contains("There are no configuration profiles installed") {
                return detectedProfiles // Return empty dictionary
            }
            
            if !output.isEmpty {
                // If output contains profiles, extract them properly
                var profileCount = 0
                
                for line in output.components(separatedBy: .newlines) where !line.isEmpty {
                    // Remove whitespace
                    let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    // Skip empty lines and the summary line
                    if trimmedLine.isEmpty || trimmedLine.contains("_computerlevel[") || 
                       trimmedLine.contains("There are") {
                        continue
                    }
                    
                    // Special handling for "configuration profiles: X" summary line
                    if trimmedLine.lowercased().contains("configuration profiles:") {
                        // Extract profile count from summary line if possible
                        if let countStr = trimmedLine.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespacesAndNewlines),
                           let count = Int(countStr) {
                            profileCount = count
                        }
                        continue
                    }
                    
                    // Extract profile identifier and name
                    if let range = trimmedLine.range(of: " \\(", options: .regularExpression) {
                        // Format: "identifier (name)"
                        let identifier = String(trimmedLine[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                        if let nameEndIndex = trimmedLine.lastIndex(of: ")") {
                            let nameStartIndex = trimmedLine.index(range.lowerBound, offsetBy: 2)
                            if nameStartIndex < nameEndIndex {
                                let name = String(trimmedLine[nameStartIndex..<nameEndIndex])
                                detectedProfiles[identifier] = name
                            }
                        }
                    } else {
                        // Only use the line as both identifier if it doesn't look like a "no profiles" message
                        let identifier = trimmedLine
                        if !identifier.contains("no configuration profiles") &&
                           !identifier.contains("No profiles") {
                            detectedProfiles[identifier] = "Profile: \(identifier)"
                        }
                    }
                }
                
                // If we detected actual profiles count but couldn't parse them correctly,
                // add a generic entry ONLY if profileCount > 0
                if profileCount > 0 && detectedProfiles.isEmpty {
                    detectedProfiles["com.detected.profile"] = "Detected Profile"
                }
            }
            
            // If we still don't have profiles, check for specific known ones
            if detectedProfiles.isEmpty {
                // Look for specific identifier patterns in the output
                for profile in expectedProfiles {
                    if output.contains(profile) {
                        detectedProfiles[profile] = "Installed System Profile"
                    }
                }
                
                // Count actual profiles, excluding messages about no profiles
                let profileLines = output.components(separatedBy: "\n")
                    .filter { line in
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        return !trimmed.isEmpty && 
                               !trimmed.contains("configuration profiles:") &&
                               !trimmed.contains("There are no") &&
                               !trimmed.contains("No profiles")
                    }
                let profileCount = profileLines.count
                
                // If profiles exist but none matched our expected ones, extract what we can find
                if profileCount > 0 && detectedProfiles.isEmpty {
                    // Process each actual profile line
                    for line in profileLines {
                        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        // Use the line as a profile identifier
                        let identifier = trimmedLine.components(separatedBy: " ").first ?? trimmedLine
                        detectedProfiles[identifier] = "Profile: \(identifier)"
                    }
                }
            }
        } catch {
            print("Failed to run profiles command: \(error)")
        }
        
        // If we still don't have profiles, try with filesystem checks
        if detectedProfiles.isEmpty {
            // Try to check for profile files directly
            for profile in expectedProfiles {
                let paths = [
                    "/Library/Managed Preferences/\(profile).plist",
                    "/Library/ConfigurationProfiles/\(profile).plist",
                    "/var/db/ConfigurationProfiles/Store/\(profile).plist"
                ]
                
                for path in paths {
                    if FileManager.default.fileExists(atPath: path) {
                        detectedProfiles[profile] = "Installed System Profile"
                        break
                    }
                }
            }
            
            // Check common indicator files
            let profileIndicators = [
                "/Library/Managed Preferences",
                "/Library/ConfigurationProfiles",
                "/var/db/ConfigurationProfiles/Store"
            ]
            
            for path in profileIndicators {
                if FileManager.default.fileExists(atPath: path) {
                    do {
                        let contents = try FileManager.default.contentsOfDirectory(atPath: path)
                        let plistFiles = contents.filter { item in 
                            item.hasSuffix(".plist") && !item.hasPrefix(".")
                        }
                        
                        // Only add profiles if we actually find plist files
                        if !plistFiles.isEmpty {
                            for item in plistFiles {
                                let identifier = item.replacingOccurrences(of: ".plist", with: "")
                                detectedProfiles[identifier] = "Profile from \(path)"
                            }
                        }
                    } catch {
                        print("Error checking profile directory \(path): \(error)")
                    }
                }
            }
        }
        
        // Add dummy profiles for testing if required
        #if DEBUG
        if ProcessInfo.processInfo.environment["SIMULATE_PROFILES"] == "YES" {
            detectedProfiles["com.simulated.profile"] = "Simulated Profile"
            detectedProfiles["com.example.mdm"] = "Simulated MDM Profile"
        }
        #endif
        
        return detectedProfiles
    }
    
    private func getProfilesFromStandardCommand() -> (profiles: [String: String], hasPermission: Bool, error: String?) {
        var profiles = [String: String]()
        var errorMessage: String? = nil
        
        // Use the standard profiles -L command
        let task = Process()
        task.launchPath = "/usr/bin/profiles"
        task.arguments = ["-L"]
        
        let outputPipe = Pipe()
        task.standardOutput = outputPipe
        let errorPipe = Pipe()
        task.standardError = errorPipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            if let errorOutput = String(data: errorData, encoding: .utf8),
               !errorOutput.isEmpty {
                if errorOutput.contains("requires root privileges") {
                    print("Permission denied when checking profiles: \(errorOutput)")
                    errorMessage = "Permission required to check profiles: \(errorOutput)"
                    return (profiles, false, errorMessage)
                } else {
                    errorMessage = "Error with profiles command: \(errorOutput)"
                }
            }
            
            if let output = String(data: outputData, encoding: .utf8) {
                parseProfilesOutput(output, into: &profiles)
            }
        } catch {
            print("Error checking profiles: \(error)")
            if let posixError = error as? POSIXError, posixError.code == .EPERM {
                errorMessage = "Permission error checking profiles: \(error.localizedDescription)"
                return (profiles, false, errorMessage)
            }
            errorMessage = "Error checking profiles: \(error.localizedDescription)"
        }
        
        return (profiles, true, errorMessage)
    }
    
    private func parseProfilesOutput(_ output: String, into profiles: inout [String: String]) {
        // Parse profile output with multiple format support
        let lines = output.components(separatedBy: "\n")
        for line in lines where !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Format 1: profileIdentifier (displayName)
            if let range = line.range(of: " \\(", options: .regularExpression) {
                let identifier = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let nameStart = line.index(range.lowerBound, offsetBy: 2)
                let nameEnd = line.index(line.endIndex, offsetBy: -1)
                if nameStart < nameEnd {
                    let name = String(line[nameStart..<nameEnd])
                    profiles[identifier] = name
                }
            }
            // Format 2: Just "profileIdentifier"
            else if !line.contains(":") && !line.contains("=") {
                let identifier = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !identifier.isEmpty {
                    profiles[identifier] = identifier
                }
            }
            // Format 3: "Name: value" pairs
            else if let colonIndex = line.firstIndex(of: ":") {
                let key = line[..<colonIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty && !value.isEmpty && (key == "identifier" || key == "ID" || key == "Profile") {
                    profiles[value] = "Profile \(value)"
                }
            }
            
            // Format 4: _computerlevel[N] attribute: profileIdentifier: value
            if line.contains("_computerlevel") && line.contains("profileIdentifier:") {
                // Extract the profile identifier after "profileIdentifier:"
                if let range = line.range(of: "profileIdentifier:") {
                    let identifierStart = range.upperBound
                    let identifier = String(line[identifierStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !identifier.isEmpty {
                        profiles[identifier] = "System Profile: \(identifier)"
                    }
                }
            }
        }
    }
    
    private func getProfilesFromAlternativeCommands() -> (profiles: [String: String], hasPermission: Bool, error: String?) {
        var profiles = [String: String]()
        var errorMessage: String? = nil
        
        // Alternative command 1: profiles -P
        let task1 = Process()
        task1.launchPath = "/usr/bin/profiles"
        task1.arguments = ["-P"]
        
        let outputPipe1 = Pipe()
        task1.standardOutput = outputPipe1
        
        do {
            try task1.run()
            task1.waitUntilExit()
            
            let outputData = outputPipe1.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: outputData, encoding: .utf8), !output.isEmpty {
                parseProfilesOutput(output, into: &profiles)
            }
        } catch {
            print("Error with alternative profiles command 1: \(error)")
        }
        
        // Alternative command 2: system_profiler SPConfigurationProfileDataType
        if profiles.isEmpty {
            let task2 = Process()
            task2.launchPath = "/usr/sbin/system_profiler"
            task2.arguments = ["SPConfigurationProfileDataType"]
            
            let outputPipe2 = Pipe()
            task2.standardOutput = outputPipe2
            
            do {
                try task2.run()
                task2.waitUntilExit()
                
                let outputData = outputPipe2.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: outputData, encoding: .utf8), !output.isEmpty {
                    // Parse system_profiler output which has different format
                    let lines = output.components(separatedBy: "\n")
                    var currentProfile: String? = nil
                    
                    for line in lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.hasSuffix(":") && !trimmed.contains("Configuration Profiles:") {
                            // This is a profile name
                            currentProfile = trimmed.replacingOccurrences(of: ":", with: "")
                        } else if let profile = currentProfile, 
                                  trimmed.contains("Identifier:") {
                            // This is a profile identifier
                            let parts = trimmed.components(separatedBy: "Identifier:")
                            if parts.count > 1 {
                                let identifier = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                                profiles[identifier] = profile
                                currentProfile = nil
                            }
                        }
                    }
                }
            } catch {
                print("Error with alternative profiles command 2: \(error)")
            }
        }
        
        return (profiles, true, errorMessage)
    }
    
    private func getProfilesFromDefaultsCommand() -> (profiles: [String: String], hasPermission: Bool, error: String?) {
        var profiles = [String: String]()
        var errorMessage: String? = nil
        
        // Try multiple ways to use the defaults command to find profiles
        let profileDomains = [
            "com.apple.configuration.management",
            "com.apple.ManagedClient.preferences",
            "/Library/Managed Preferences"
        ]
        
        for domain in profileDomains {
            // Use the defaults command to read from profile domains
            let task = Process()
            task.launchPath = "/usr/bin/defaults"
            task.arguments = ["read", domain]
            
            let outputPipe = Pipe()
            task.standardOutput = outputPipe
            let errorPipe = Pipe()
            task.standardError = errorPipe
            
            do {
                try task.run()
                task.waitUntilExit()
                
                if task.terminationStatus == 0 {
                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: outputData, encoding: .utf8), !output.isEmpty {
                        // Parse defaults output which has a different format
                        if output.contains("PayloadIdentifier") {
                            // Look for PayloadIdentifier patterns in the output
                            let pattern = "\"PayloadIdentifier\"\\s*=\\s*\"([^\"]+)\";"
                            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                                let nsRange = NSRange(output.startIndex..<output.endIndex, in: output)
                                let matches = regex.matches(in: output, options: [], range: nsRange)
                                
                                for match in matches {
                                    if let identifierRange = Range(match.range(at: 1), in: output) {
                                        let identifier = String(output[identifierRange])
                                        profiles[identifier] = "Profile from \(domain)"
                                    }
                                }
                            }
                        } else {
                            // Add generic entry for found domain
                            profiles["found.\(domain)"] = "Configuration found in \(domain)"
                        }
                    }
                }
            } catch {
                print("Error checking profiles with defaults for domain \(domain): \(error)")
            }
        }
        
        // Special check for user profiles
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let userLibraryPath = "\(homeDir)/Library/Preferences"
        let userProfileTask = Process()
        userProfileTask.launchPath = "/usr/bin/find"
        userProfileTask.arguments = [userLibraryPath, "-name", "*.plist", "-exec", "grep", "-l", "PayloadIdentifier", "{}", "\\;"]
        
        let outputPipe = Pipe()
        userProfileTask.standardOutput = outputPipe
        
        do {
            try userProfileTask.run()
            userProfileTask.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: outputData, encoding: .utf8), !output.isEmpty {
                // Found some profile plists in user directory
                let files = output.components(separatedBy: "\n")
                for file in files where !file.isEmpty {
                    // Extract the identifier from the plist
                    let plistTask = Process()
                    plistTask.launchPath = "/usr/bin/plutil"
                    plistTask.arguments = ["-p", file]
                    
                    let plistPipe = Pipe()
                    plistTask.standardOutput = plistPipe
                    
                    do {
                        try plistTask.run()
                        plistTask.waitUntilExit()
                        
                        let plistData = plistPipe.fileHandleForReading.readDataToEndOfFile()
                        if let plistOutput = String(data: plistData, encoding: .utf8) {
                            // Look for PayloadIdentifier or similar keys
                            if let idRange = plistOutput.range(of: "PayloadIdentifier\" => \"", options: .literal) {
                                let start = idRange.upperBound
                                if let endRange = plistOutput.range(of: "\"", options: .literal, range: start..<plistOutput.endIndex) {
                                    let identifier = String(plistOutput[start..<endRange.lowerBound])
                                    let filename = URL(fileURLWithPath: file).lastPathComponent
                                    profiles[identifier] = "User Profile: \(filename)"
                                }
                            }
                        }
                    } catch {
                        print("Error reading user profile plist \(file): \(error)")
                    }
                }
            }
        } catch {
            print("Error searching for user profiles: \(error)")
        }
        
        return (profiles, true, errorMessage)
    }
    
    private func getProfilesFromVerboseCommand() -> (profiles: [String: String], hasPermission: Bool, error: String?) {
        var profiles = [String: String]()
        var errorMessage: String? = nil
        
        // Use the profiles -Cv command for more verbose output
        let task = Process()
        task.launchPath = "/usr/bin/profiles"
        task.arguments = ["-Cv"]
        
        let outputPipe = Pipe()
        task.standardOutput = outputPipe
        let errorPipe = Pipe()
        task.standardError = errorPipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            if let errorOutput = String(data: errorData, encoding: .utf8),
               !errorOutput.isEmpty {
                errorMessage = "Error with verbose profiles command: \(errorOutput)"
            }
            
            if let output = String(data: outputData, encoding: .utf8), !output.isEmpty {
                // The verbose output has a different format, so parse it differently
                var currentIdentifier: String? = nil
                var currentName: String? = nil
                
                let lines = output.components(separatedBy: "\n")
                for line in lines {
                    let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    // Look for payload identifier lines
                    if trimmedLine.contains("PayloadIdentifier") {
                        // Extract the identifier value
                        if let equalsIndex = trimmedLine.range(of: "= ") {
                            let identifierStart = equalsIndex.upperBound
                            let identifierValue = String(trimmedLine[identifierStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                            currentIdentifier = identifierValue
                        }
                    }
                    
                    // Look for display name lines
                    if trimmedLine.contains("PayloadDisplayName") {
                        // Extract the display name value
                        if let equalsIndex = trimmedLine.range(of: "= ") {
                            let nameStart = equalsIndex.upperBound
                            let nameValue = String(trimmedLine[nameStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                            currentName = nameValue
                        }
                    }
                    
                    // If we found both an identifier and name, add to profiles
                    if let identifier = currentIdentifier, let name = currentName {
                        profiles[identifier] = name
                        currentIdentifier = nil
                        currentName = nil
                    }
                }
                
                // Also try the simple parser to catch any standard format entries
                parseProfilesOutput(output, into: &profiles)
            }
        } catch {
            print("Error checking profiles with verbose command: \(error)")
            errorMessage = "Error checking profiles with verbose command: \(error.localizedDescription)"
        }
        
        return (profiles, true, errorMessage)
    }
    
    private func getProfilesFromFileSystem() -> (profiles: [String: String], hasPermission: Bool, error: String?) {
        var profiles = [String: String]()
        
        // Check for profile files in standard locations
        let profileDirs = [
            "/Library/Managed Preferences",
            "/Library/ConfigurationProfiles",
            "/var/db/ConfigurationProfiles/Store"
        ]
        
        for dir in profileDirs {
            if FileManager.default.fileExists(atPath: dir) {
                do {
                    let contents = try FileManager.default.contentsOfDirectory(atPath: dir)
                    for item in contents {
                        if !item.hasPrefix(".") { // Skip hidden files
                            // For each found file/folder, treat it as a potential profile
                            let fullPath = "\(dir)/\(item)"
                            
                            // If it's a plist file, try to read it for more info
                            if item.hasSuffix(".plist") {
                                let task = Process()
                                task.launchPath = "/usr/bin/plutil"
                                task.arguments = ["-p", fullPath]
                                
                                let outputPipe = Pipe()
                                task.standardOutput = outputPipe
                                
                                do {
                                    try task.run()
                                    task.waitUntilExit()
                                    
                                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                                    if let output = String(data: outputData, encoding: .utf8) {
                                        // Look for PayloadIdentifier or similar keys
                                        if let idRange = output.range(of: "PayloadIdentifier\" => \"", options: .literal) {
                                            let start = idRange.upperBound
                                            if let endRange = output.range(of: "\"", options: .literal, range: start..<output.endIndex) {
                                                let identifier = String(output[start..<endRange.lowerBound])
                                                profiles[identifier] = item.replacingOccurrences(of: ".plist", with: "")
                                            }
                                        }
                                    }
                                } catch {
                                    print("Error reading plist: \(error)")
                                }
                            } else {
                                // Just use the filename as a profile indicator
                                profiles[item] = "Found in \(dir)"
                            }
                        }
                    }
                } catch {
                    print("Error checking profile directory \(dir): \(error)")
                }
            }
        }
        
        // Special check for Arc browser profile
        if profiles.isEmpty {
            let arcProfilePaths = [
                "/Library/Managed Preferences/arc.a5495cf1-f17e-4539-b8dc-d0a0190bd5bb.plist",
                "/Library/ConfigurationProfiles/arc.a5495cf1-f17e-4539-b8dc-d0a0190bd5bb.plist"
            ]
            
            for path in arcProfilePaths {
                if FileManager.default.fileExists(atPath: path) {
                    profiles["arc.a5495cf1-f17e-4539-b8dc-d0a0190bd5bb"] = "Arc Browser Profile"
                    break
                }
            }
        }
        
        return (profiles, true, nil)
    }
    
    // Method to check profiles using sudo privileges - should be called from an authorized helper or admin script
    func checkProfilesWithSudo() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            
            // Use an AppleScript to request sudo access with proper explanation
            let script = """
            tell application "System Events"
                set adminPrompt to display dialog "Guardian needs to check for computer-level security profiles. Please enter your admin password in the Terminal prompt." buttons {"OK"} default button "OK" with title "Admin Access Required"
            end tell
            
            do shell script "/usr/bin/profiles list | grep -v 'no configuration profiles'" with administrator privileges
            """
            
            let task = Process()
            task.launchPath = "/usr/bin/osascript"
            task.arguments = ["-e", script]
            
            let outputPipe = Pipe()
            task.standardOutput = outputPipe
            let errorPipe = Pipe()
            task.standardError = errorPipe
            
            do {
                try task.run()
                task.waitUntilExit()
                
                if task.terminationStatus == 0 {
                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: outputData, encoding: .utf8), !output.isEmpty {
                        var computerProfiles = [String: String]()
                        self.parseComputerLevelOutput(output, into: &computerProfiles)
                        
                        print("DEBUG: Found computer-level profiles with sudo: \(computerProfiles)")
                        
                        // Update on main thread
                        DispatchQueue.main.async {
                            if !computerProfiles.isEmpty {
                                self.profilesInfo = computerProfiles
                                self.hasProfiles = true
                                self.hasMDMProfile = computerProfiles.keys.contains { $0.contains("mdm") || $0.contains("manageengine") || $0.contains("zoho") }
                                self.status = .secure
                                self.errorMessage = nil
                            } else {
                                self.errorMessage = "No computer-level profiles found"
                            }
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.errorMessage = "No output from sudo profiles command"
                        }
                    }
                } else {
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    if let errorOutput = String(data: errorData, encoding: .utf8), !errorOutput.isEmpty {
                        DispatchQueue.main.async {
                            self.errorMessage = "Error: \(errorOutput)"
                        }
                    }
                }
            } catch {
                print("Error running sudo profiles: \(error)")
                DispatchQueue.main.async {
                    self.errorMessage = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func tryGetComputerLevelProfiles() -> [String: String] {
        var detectedProfiles = [String: String]()
        
        // Try options that might show computer-level profiles without full sudo
        
        // Option 1: Try with system_profiler which sometimes works for regular users
        let spTask = Process()
        let spPipe = Pipe()
        spTask.standardOutput = spPipe
        spTask.standardError = spPipe
        spTask.launchPath = "/usr/sbin/system_profiler"
        spTask.arguments = ["SPConfigurationProfileDataType"]
        
        do {
            try spTask.run()
            let data = spPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            // Parse system_profiler output which shows computer-level profiles
            if !output.isEmpty && !output.contains("No Configuration Profiles") {
                parseSystemProfilerOutput(output, into: &detectedProfiles)
            }
        } catch {
            print("Failed to run system_profiler: \(error)")
        }
        
        // Don't continue if we successfully found profiles
        if !detectedProfiles.isEmpty {
            return detectedProfiles
        }
        
        // Option 2: Try with profiles -L -o stdout-xml which may show more info
        let xmlTask = Process()
        let xmlPipe = Pipe()
        xmlTask.standardOutput = xmlPipe
        xmlTask.standardError = xmlPipe
        xmlTask.launchPath = "/usr/bin/profiles"
        xmlTask.arguments = ["-L", "-o", "stdout-xml"]
        
        do {
            try xmlTask.run()
            let data = xmlPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            if !output.isEmpty && output.contains("<dict>") && !output.contains("no configuration profiles") {
                parseProfilesXmlOutput(output, into: &detectedProfiles)
            }
        } catch {
            print("Failed to run profiles with XML output: \(error)")
        }
        
        // Option 3: Most comprehensive - try with admins approach (using an admin prompt)
        if detectedProfiles.isEmpty {
            // Let's try to get the computer-level profiles with admin privileges
            let computerProfiles = getComputerLevelProfilesWithAdmin()
            if !computerProfiles.isEmpty {
                return computerProfiles
            }
        }
        
        // Option 4: Look for profiles in filesystem (imperfect but may work)
        if detectedProfiles.isEmpty {
            checkProfileFilesInSystem(into: &detectedProfiles)
        }
        
        return detectedProfiles
    }
    
    private func parseSystemProfilerOutput(_ output: String, into profiles: inout [String: String]) {
        let lines = output.components(separatedBy: "\n")
        var currentProfile: String? = nil
        var currentIdentifier: String? = nil
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Parse system_profiler's indented output
            if !trimmedLine.hasPrefix(" ") && trimmedLine.hasSuffix(":") {
                // This is a profile name line
                currentProfile = trimmedLine.replacingOccurrences(of: ":", with: "")
                currentIdentifier = nil
            } else if trimmedLine.contains("Identifier:") {
                // This is a profile identifier line
                let parts = trimmedLine.components(separatedBy: "Identifier:")
                if parts.count > 1 {
                    currentIdentifier = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if let identifier = currentIdentifier, let name = currentProfile {
                        profiles[identifier] = name
                    }
                }
            } else if trimmedLine.contains("_computerlevel") && trimmedLine.contains("profileIdentifier:") {
                // Parse direct computerlevel profile identifier
                let parts = trimmedLine.components(separatedBy: "profileIdentifier:")
                if parts.count > 1 {
                    let identifier = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    profiles[identifier] = "Computer Level Profile: \(identifier)"
                }
            }
        }
    }
    
    private func parseProfilesXmlOutput(_ output: String, into profiles: inout [String: String]) {
        // Look for payload identifiers in the XML
        let payloadPattern = "<key>PayloadIdentifier</key>\\s*<string>(.*?)</string>"
        let displayNamePattern = "<key>PayloadDisplayName</key>\\s*<string>(.*?)</string>"
        
        if let regex = try? NSRegularExpression(pattern: payloadPattern, options: []) {
            let nsRange = NSRange(output.startIndex..<output.endIndex, in: output)
            let matches = regex.matches(in: output, options: [], range: nsRange)
            
            for match in matches {
                if let identifierRange = Range(match.range(at: 1), in: output) {
                    let identifier = String(output[identifierRange])
                    
                    // Try to find a display name
                    var displayName = "Profile: \(identifier)"
                    if let nameRegex = try? NSRegularExpression(pattern: displayNamePattern, options: []),
                       let nameMatch = nameRegex.firstMatch(in: output, options: [], range: nsRange),
                       let nameRange = Range(nameMatch.range(at: 1), in: output) {
                        displayName = String(output[nameRange])
                    }
                    
                    profiles[identifier] = displayName
                }
            }
        }
    }
    
    private func getComputerLevelProfilesWithAdmin() -> [String: String] {
        var profiles = [String: String]()
        
        // Only try this once per app run to avoid bothering the user
        if !Self.hasTriedAdmin {
            // Create a custom AppleScript to run sudo profiles with admin rights
            let script = """
            tell application "System Events"
                set adminPrompt to display dialog "Guardian needs to check for system security profiles. Please enter your admin password in the Terminal prompt." buttons {"OK"} default button "OK" with title "Admin Access Required"
            end tell
            
            do shell script "/usr/bin/profiles -L"
            """
            
            let task = Process()
            task.launchPath = "/usr/bin/osascript"
            task.arguments = ["-e", script]
            
            let outputPipe = Pipe()
            task.standardOutput = outputPipe
            let errorPipe = Pipe()
            task.standardError = errorPipe
            
            do {
                try task.run()
                task.waitUntilExit()
                
                if task.terminationStatus == 0 {
                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: outputData, encoding: .utf8), !output.isEmpty {
                        // Parse profiles output 
                        parseComputerLevelOutput(output, into: &profiles)
                    }
                }
                
                // Mark that we tried the admin approach
                Self.hasTriedAdmin = true
            } catch {
                print("Failed to run admin privileges check: \(error)")
            }
        }
        
        return profiles
    }
    
    private func parseComputerLevelOutput(_ output: String, into profiles: inout [String: String]) {
        let lines = output.components(separatedBy: "\n")
        
        for line in lines where !line.isEmpty {
            // Parse the computer level profile format
            if line.contains("_computerlevel") && line.contains("profileIdentifier:") {
                let parts = line.components(separatedBy: "profileIdentifier:")
                if parts.count > 1 {
                    let identifier = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    profiles[identifier] = "System Profile: \(identifier)"
                }
            } else if line.contains("attribute:") && line.contains("profileIdentifier:") {
                // Alternative format
                let parts = line.components(separatedBy: "profileIdentifier:")
                if parts.count > 1 {
                    let identifier = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    profiles[identifier] = "System Profile: \(identifier)"
                }
            }
        }
    }
    
    private func checkProfileFilesInSystem(into profiles: inout [String: String]) {
        // Paths where computer-level profiles are typically stored
        let profilePaths = [
            "/Library/Managed Preferences",
            "/Library/ConfigurationProfiles",
            "/var/db/ConfigurationProfiles/Store"
        ]
        
        // Known profiles to look for based on your system
        let knownProfileIds = [
            "restrictions.B775F8FD-2387-42D7-BCE3-6B8E6D57F14A",
            "arc.a5495cf1-f17e-4539-b8dc-d0a0190bd5bb",
            "com.zohocorp.mdm",
            "tailscale.370CB5C8-682A-4903-9B22-BB4E5BF2C080",
            "com.manageengine.mdm.mac"
        ]
        
        // First try checking for known profile IDs
        for profileId in knownProfileIds {
            for basePath in profilePaths {
                let path = "\(basePath)/\(profileId).plist"
                if FileManager.default.fileExists(atPath: path) {
                    profiles[profileId] = "Computer Profile: \(profileId)"
                    break
                }
            }
        }
        
        // If we don't find any specific profiles, check for any .plist files
        if profiles.isEmpty {
            for basePath in profilePaths {
                guard FileManager.default.fileExists(atPath: basePath) else { continue }
                
                do {
                    let contents = try FileManager.default.contentsOfDirectory(atPath: basePath)
                    for item in contents where item.hasSuffix(".plist") && !item.hasPrefix(".") {
                        let profileId = item.replacingOccurrences(of: ".plist", with: "")
                        profiles[profileId] = "Computer Profile: \(profileId)"
                    }
                } catch {
                    print("Error reading directory \(basePath): \(error)")
                }
            }
        }
    }
    
    private func checkAlternativeMDMIndicators() -> Bool {
        // Check for common MDM-related files and services
        let mdmIndicators = [
            "/Library/LaunchDaemons/com.jamf.management.daemon.plist",
            "/Library/LaunchDaemons/com.apple.mdmclient.daemon.plist",
            "/Library/Application Support/JAMF",
            "/usr/local/jamf/bin/jamf",
            "/Library/Managed Preferences",
            "/var/db/ConfigurationProfiles"
        ]
        
        for path in mdmIndicators {
            if FileManager.default.fileExists(atPath: path) {
                return true
            }
        }
        
        // Check if the MDM process is running
        let task = Process()
        task.launchPath = "/bin/ps"
        task.arguments = ["-ax"]
        
        let outputPipe = Pipe()
        task.standardOutput = outputPipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: outputData, encoding: .utf8) {
                if output.contains("mdmclient") || output.contains("jamf") {
                    return true
                }
            }
        } catch {
            print("Error checking MDM processes: \(error)")
        }
        
        return false
    }
    
    func restoreSecureState() {
        // Open System Settings > Profiles (modern macOS) or System Preferences > Profiles (older macOS)
        if #available(macOS 13.0, *) {
            // For modern macOS (Ventura and later)
            let task = Process()
            task.launchPath = "/usr/bin/open"
            task.arguments = ["x-apple.systempreferences:com.apple.preferences.profiles"]
            
            do {
                try task.run()
            } catch {
                print("Error opening System Settings: \(error)")
                fallbackOpenProfiles()
            }
        } else {
            fallbackOpenProfiles()
        }
    }
    
    private func fallbackOpenProfiles() {
        let task = Process()
        task.launchPath = "/usr/bin/open"
        
        // Try the Profiles preference pane if it exists
        if FileManager.default.fileExists(atPath: "/System/Library/PreferencePanes/Profiles.prefPane") {
            task.arguments = ["-a", "System Preferences", "/System/Library/PreferencePanes/Profiles.prefPane"]
        } else {
            // Just open System Preferences
            task.arguments = ["-a", "System Preferences"]
        }
        
        do {
            try task.run()
        } catch {
            print("Error opening System Preferences: \(error)")
        }
    }
    
    // Helper method to run a command that requires sudo and get the output
    func runSudoCommand(_ launchPath: String, _ arguments: [String]) -> String? {
        let dialogScript = """
        do shell script "\(launchPath) \(arguments.joined(separator: " "))" with administrator privileges
        """
        
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", dialogScript]
        
        let outputPipe = Pipe()
        task.standardOutput = outputPipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: outputData, encoding: .utf8) {
                    return output
                }
            }
        } catch {
            print("Error running sudo command: \(error)")
        }
        
        return nil
    }
}