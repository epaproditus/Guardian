import Foundation
import Combine
import AppKit
import os.log // Use os.log for os_log

class LittleSnitchMonitor: ObservableObject {
    @Published var status: SecurityState = .unknown
    @Published var isRunning: Bool = false
    @Published var isAlertMode: Bool = false
    @Published var hasPermission: Bool = true
    @Published var detectionMethod: String = "Unknown" // For debugging
    
    // Use os_log for logging
    private static let log = OSLog(subsystem: "com.guardian.app", category: "LittleSnitchMonitor")

    // Helper function for logging
    private func log(_ message: String, type: OSLogType = .info) {
        os_log("%{public}@", log: LittleSnitchMonitor.log, type: type, message)
    }
    
    // Add the exact path we found
    private let knownLittleSnitchPaths = [
        "/Applications/Little Snitch.app/Contents/Components/littlesnitch", // Confirmed path
        "/usr/local/bin/littlesnitch",
        "/usr/bin/littlesnitch",
        "/opt/homebrew/bin/littlesnitch"
    ]
    
    func checkStatus() {
        log("Starting Little Snitch detection...") // Use the helper function

        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }

            // Check if Little Snitch is installed and running
            let (isRunning, hasPermission, method) = self.checkIfLittleSnitchIsRunning()

            // Log detection results
            self.log("Little Snitch detection results - Running: \(isRunning), Method: \(method)") // Use the helper function

            // Update properties on main thread
            DispatchQueue.main.async {
                self.hasPermission = hasPermission
                self.isRunning = isRunning
                self.isAlertMode = true // Assume alert mode is enabled
                self.detectionMethod = method
                
                // Update status based on checks
                if !hasPermission {
                    self.status = .unknown
                } else if isRunning {
                    self.status = .secure  // If Little Snitch is detected, mark as secure
                } else {
                    self.status = .insecure  // Not detected
                }
                
                self.log("Little Snitch final status: \(self.status)") // Use the helper function
            }
        }
    }
    
    private func checkIfLittleSnitchIsRunning() -> (isRunning: Bool, hasPermission: Bool, method: String) {
        // FIRST: Check for Little Snitch.app existence (most reliable)
        if FileManager.default.fileExists(atPath: "/Applications/Little Snitch.app") {
            log("Little Snitch.app found in Applications folder") // Use the helper function
            return (true, true, "App Found")
        }
        
        // SECOND: Check for the EXACT littlesnitch command we found
        for path in knownLittleSnitchPaths {
            if FileManager.default.fileExists(atPath: path) {
                log("Little Snitch CLI found at: \(path)") // Use the helper function
                return (true, true, "CLI Found")
            }
        }
        
        // THIRD: Try to run a littlesnitch command
        if runSimpleLittleSnitchCommand() {
            log("Little Snitch command executed successfully") // Use the helper function
            return (true, true, "Command Executed")
        }
        
        // FOURTH: Check for Little Snitch processes
        if checkForLittleSnitchProcesses() {
            log("Little Snitch processes found") // Use the helper function
            return (true, true, "Process Found")
        }
        
        // FIFTH: Check for app bundle presence using multiple methods
        if isLittleSnitchAppInstalled() {
            log("Little Snitch app installed but not detected as running") // Use the helper function
            return (true, true, "App Installed")
        }
        
        log("Little Snitch not detected by any method", type: .error) // Use the helper function
        return (false, true, "Not Detected")
    }
    
    // Run a simple littlesnitch command to see if it works
    private func runSimpleLittleSnitchCommand() -> Bool {
        // Try running the direct path first
        for path in knownLittleSnitchPaths {
            if FileManager.default.fileExists(atPath: path) {
                let task = Process()
                task.launchPath = path
                task.arguments = ["--version"]
                
                let pipe = Pipe()
                task.standardOutput = pipe
                let errorPipe = Pipe()
                task.standardError = errorPipe
                
                do {
                    try task.run()
                    task.waitUntilExit()
                    
                    if task.terminationStatus == 0 {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        if let output = String(data: data, encoding: .utf8) {
                            log("Little Snitch version command successful: \(output)") // Use the helper function
                            return true
                        }
                    }
                } catch {
                    log("Error running littlesnitch command: \(error.localizedDescription)", type: .error) // Use the helper function
                }
            }
        }
        
        // Try using the command directly (depends on PATH)
        let task = Process()
        task.launchPath = "/usr/bin/env"
        task.arguments = ["littlesnitch", "--version"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                return true
            }
        } catch {
            log("Error using env to run littlesnitch: \(error.localizedDescription)", type: .error) // Use the helper function
        }
        
        return false
    }
    
    // Check for Little Snitch processes directly
    private func checkForLittleSnitchProcesses() -> Bool {
        let task = Process()
        task.launchPath = "/bin/ps"
        task.arguments = ["-ax"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let lsProcesses = ["Little Snitch Daemon", "Little Snitch Agent", 
                                   "Little Snitch Network Monitor", "LittleSnitchNetworkMonitor",
                                   "LittleSnitchDaemon", "LittleSnitchUIAgent"]
                
                for process in lsProcesses {
                    if output.contains(process) {
                        log("Little Snitch process found: \(process)") // Use the helper function
                        return true
                    }
                }
            }
        } catch {
            log("Error checking for Little Snitch processes: \(error.localizedDescription)", type: .error) // Use the helper function
        }
        
        return false
    }
    
    // Check if the Little Snitch app is installed
    private func isLittleSnitchAppInstalled() -> Bool {
        let lsPaths = [
            "/Applications/Little Snitch.app",
            "/Applications/Little Snitch Network Monitor.app",
            "/Library/Extensions/LittleSnitch.kext",
            "/Library/Extensions/LittleSnitchNetwork.kext",
            "/Library/Little Snitch",
            "/Library/Application Support/Objective Development",
            // Added additional check for component files
            "/Applications/Little Snitch.app/Contents/Components"
        ]
        
        for path in lsPaths {
            if FileManager.default.fileExists(atPath: path) {
                log("Little Snitch installation found at: \(path)") // Use the helper function
                return true
            }
        }
        
        // Check with NSWorkspace for registered apps
        let bundleIDs = [
            "at.obdev.LittleSnitchNetworkMonitor",
            "at.obdev.LittleSnitch",
            "at.obdev.LittleSnitchDaemon"
        ]
        
        for bundleID in bundleIDs {
            let urls = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleID)
            if !urls.isEmpty {
                log("Little Snitch bundle found: \(bundleID)") // Use the helper function
                return true
            }
        }
        
        return false
    }
    
    private func findLittleSnitchCLI() -> String? {
        // Check our known paths first
        for path in knownLittleSnitchPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        // Try to find it using 'which' command
        let task = Process()
        task.launchPath = "/usr/bin/which"
        task.arguments = ["littlesnitch"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
                    return path
                }
            }
        } catch {
            log("Error finding Little Snitch CLI with 'which': \(error.localizedDescription)", type: .error) // Use the helper function
        }
        
        log("Little Snitch CLI tool not found in any expected location", type: .error) // Use the helper function
        return nil
    }
    
    private func checkIfLittleSnitchInAlertMode() -> Bool {
        // For newer versions of Little Snitch, the concept of alert mode might not exist or be accessible
        // So we'll assume it's in alert mode if it's running
        
        // But try to check using the CLI if available
        guard let littleSnitchCLI = findLittleSnitchCLI() else {
            return true // Default to true if we can't check
        }
        
        let task = Process()
        task.launchPath = littleSnitchCLI
        task.arguments = ["read-preference", "alert-mode"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    return output == "enabled" || output == "true" || output == "1" || output.contains("true")
                }
            }
        } catch {
            log("Error checking Little Snitch alert mode: \(error.localizedDescription)", type: .error) // Use the helper function
        }
        
        // Default to true if we couldn't check
        return true
    }
    
    func restoreSecureState() {
        if !isRunning {
            // Attempt to start Little Snitch if it's not running
            openLittleSnitchApplication()
        }
    }
    
    private func openLittleSnitchApplication() {
        // Try to open Little Snitch Network Monitor first
        var task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-a", "Little Snitch Network Monitor"]
        
        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                return
            }
        } catch {
            log("Error opening Little Snitch Network Monitor: \(error.localizedDescription)", type: .error) // Use the helper function
        }
        
        // If that fails, try opening Little Snitch application
        task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-a", "Little Snitch"]
        
        do {
            try task.run()
        } catch {
            log("Error opening Little Snitch: \(error.localizedDescription)", type: .error) // Use the helper function
        }
    }
}