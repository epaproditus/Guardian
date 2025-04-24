import Foundation
import Combine
import AppKit

class LittleSnitchMonitor: ObservableObject {
    @Published var status: SecurityState = .unknown
    @Published var isRunning: Bool = false
    @Published var isAlertMode: Bool = false
    @Published var hasPermission: Bool = true
    
    func checkStatus() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            
            // Check if Little Snitch daemon is running
            let (isRunning, hasPermission) = self.checkIfLittleSnitchIsRunning()
            
            // Check if Little Snitch is in alert mode
            let isAlertMode = self.checkIfLittleSnitchInAlertMode()
            
            // Update properties on main thread
            DispatchQueue.main.async {
                self.hasPermission = hasPermission
                self.isRunning = isRunning
                self.isAlertMode = isAlertMode
                
                // Update status based on checks
                if !hasPermission {
                    self.status = .unknown
                } else if isRunning && isAlertMode {
                    self.status = .secure
                } else if isRunning {
                    self.status = .insecure // Running but not in alert mode
                } else {
                    self.status = .insecure // Not running
                }
            }
        }
    }
    
    private func checkIfLittleSnitchIsRunning() -> (isRunning: Bool, hasPermission: Bool) {
        // First try using NSRunningApplication approach (sandbox-friendly)
        if let isRunning = checkProcessUsingWorkspace(processName: "Little Snitch Daemon") {
            return (isRunning, true)
        }
        
        // Fall back to the process approach if needed
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
                // Look for Little Snitch daemon process
                return (output.contains("Little Snitch Daemon") || output.contains("LittleSnitchDaemon"), true)
            }
        } catch {
            print("Error checking Little Snitch running status: \(error)")
            // If we get "Operation not permitted", it's a permission issue
            if let posixError = error as? POSIXError, posixError.code == .EPERM {
                return (false, false)
            }
        }
        
        return (false, true)
    }
    
    // New method: Sandbox-friendly process checking
    private func checkProcessUsingWorkspace(processName: String) -> Bool? {
        let launchedApps = NSWorkspace.shared.runningApplications
        
        // For system processes like daemons, this approach has limitations
        // but it's worth trying before falling back to ps command
        for app in launchedApps {
            if app.localizedName?.lowercased().contains(processName.lowercased()) == true ||
               app.bundleIdentifier?.lowercased().contains("littlesnitch") == true {
                return true
            }
        }
        
        // Check for the existence of Little Snitch installation files
        let lsFiles = [
            "/Library/Extensions/LittleSnitch.kext",
            "/Applications/Little Snitch.app",
            "/Library/Little Snitch"
        ]
        
        for path in lsFiles {
            if FileManager.default.fileExists(atPath: path) {
                return checkLittleSnitchUsingFileExistence()
            }
        }
        
        // Try using shell command that might work better in sandbox
        let task = Process()
        task.launchPath = "/usr/bin/pgrep"
        task.arguments = ["-f", "Little Snitch"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        let errorPipe = Pipe()
        task.standardError = errorPipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            // Check for errors in pgrep command
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            if let errorOutput = String(data: errorData, encoding: .utf8), !errorOutput.isEmpty {
                print("pgrep warning in LittleSnitchMonitor: \(errorOutput)")
                return checkLittleSnitchUsingFileExistence()
            }
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            return !output.isEmpty
        } catch {
            // If this fails, try alternative methods
            print("Error checking process using pgrep in LittleSnitchMonitor: \(error)")
            return checkLittleSnitchUsingFileExistence()
        }
    }
    
    // New alternative method that doesn't rely on process listing
    private func checkLittleSnitchUsingFileExistence() -> Bool? {
        // Check for runtime files/sockets that would indicate Little Snitch is running
        let runtimeFiles = [
            "/Library/Little Snitch/Databases/socket",
            "/var/run/little-snitch"
        ]
        
        for file in runtimeFiles {
            if FileManager.default.fileExists(atPath: file) {
                return true
            }
        }
        
        // Check via launchctl for Little Snitch daemons
        let servicesToCheck = [
            "at.obdev.littlesnitch.daemon",
            "at.obdev.littlesnitchd",
            "at.obdev.LittleSnitchHelper"
        ]
        
        for service in servicesToCheck {
            let task = Process()
            task.launchPath = "/bin/launchctl"
            task.arguments = ["list", service]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            
            do {
                try task.run()
                task.waitUntilExit()
                
                if task.terminationStatus == 0 {
                    return true
                }
            } catch {
                print("Error checking launchctl for \(service): \(error)")
            }
        }
        
        // Check network information for Little Snitch processes
        let netstatTask = Process()
        netstatTask.launchPath = "/usr/sbin/lsof"
        netstatTask.arguments = ["-i"]
        
        let netstatPipe = Pipe()
        netstatTask.standardOutput = netstatPipe
        
        do {
            try netstatTask.run()
            netstatTask.waitUntilExit()
            
            let data = netstatPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            if output.lowercased().contains("little snitch") || output.lowercased().contains("littlesnitch") {
                return true
            }
        } catch {
            print("Error checking network connections: \(error)")
        }
        
        // If we've exhausted options, return nil to let the caller try other methods
        return nil
    }
    
    private func findLittleSnitchCLI() -> String? {
        let possiblePaths = [
            "/Library/Little Snitch/Script Commands/littlesnitch",
            "/usr/local/bin/littlesnitch",
            "/opt/homebrew/bin/littlesnitch",
            "/Applications/Little Snitch.app/Contents/Resources/littlesnitch",
            "/Applications/Little Snitch.app/Contents/Components/littlesnitch" // Found on your system
        ]
        
        let fileManager = FileManager.default
        for path in possiblePaths {
            if fileManager.fileExists(atPath: path) {
                return path
            }
        }
        
        print("Little Snitch CLI tool not found in any expected location")
        return nil
    }
    
    private func checkIfLittleSnitchInAlertMode() -> Bool {
        // Try to find Little Snitch CLI tool
        guard let littleSnitchCLI = findLittleSnitchCLI() else {
            return false
        }
        
        let task = Process()
        task.launchPath = littleSnitchCLI
        task.arguments = ["get-config", "alert-mode"]
        
        let outputPipe = Pipe()
        task.standardOutput = outputPipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                return output == "enabled" || output == "true" || output == "1"
            }
        } catch {
            print("Error checking Little Snitch alert mode: \(error)")
        }
        
        return false
    }
    
    func restoreSecureState() {
        if !isRunning {
            // Attempt to start Little Snitch if it's not running
            openLittleSnitchApplication()
        } else if !isAlertMode {
            // If running but not in alert mode, enable alert mode
            enableLittleSnitchAlertMode()
        }
    }
    
    private func openLittleSnitchApplication() {
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-a", "Little Snitch"]
        
        do {
            try task.run()
        } catch {
            print("Error opening Little Snitch: \(error)")
        }
    }
    
    private func enableLittleSnitchAlertMode() {
        // Try to find Little Snitch CLI tool
        guard let littleSnitchCLI = findLittleSnitchCLI() else {
            return
        }
        
        let task = Process()
        task.launchPath = littleSnitchCLI
        task.arguments = ["set-config", "alert-mode", "enabled"]
        
        do {
            try task.run()
            task.waitUntilExit()
            
            // Verify the change
            self.checkStatus()
        } catch {
            print("Error enabling Little Snitch alert mode: \(error)")
        }
    }
}