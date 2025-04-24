//
//  GuardianNewApp.swift
//  GuardianNew
//
//  Created by Abraham Romero on 4/24/25.
//

import SwiftUI
import UserNotifications

@main
struct GuardianNewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var menuBarController = MenuBarController()
    
    var body: some Scene {
        MenuBarExtra(content: {
            MenuBarView(menuBarController: menuBarController)
        }, label: {
            Image(systemName: getIconName(for: menuBarController.overallStatus, 
                                        hasPermissionIssues: hasPermissionIssues))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(getIconColor(for: menuBarController.overallStatus, 
                                           hasPermissionIssues: hasPermissionIssues))
        })
        .menuBarExtraStyle(.window)
        
        Settings {
            EmptyView()
        }
    }
    
    private var hasPermissionIssues: Bool {
        return !menuBarController.santaMonitor.hasPermission || 
               !menuBarController.littleSnitchMonitor.hasPermission ||
               !menuBarController.profileMonitor.hasPermission
    }
    
    private func getIconName(for status: SecurityState, hasPermissionIssues: Bool) -> String {
        if hasPermissionIssues {
            return "exclamationmark.shield" // This is a valid SF Symbol
        }
        
        switch status {
        case .secure:
            return "shield"
        case .insecure:
            return "shield.slash"
        case .unknown:
            return "questionmark.circle.fill" // Using the same icon as defined in SecurityState
        case .partial:
            return "shield.lefthalf.fill" // Using half-filled shield for partial security
        }
    }
    
    private func getIconColor(for status: SecurityState, hasPermissionIssues: Bool) -> Color {
        if hasPermissionIssues {
            return .yellow
        }
        
        switch status {
        case .secure:
            return .green
        case .insecure:
            return .red
        case .unknown:
            return .gray
        case .partial:
            return .yellow // Using yellow for partial security to match the SecurityState enum
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var permissionsWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize permissions window
        let permissionsView = PermissionsView()
        let hostingController = NSHostingController(rootView: permissionsView)
        
        permissionsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        permissionsWindow?.center()
        permissionsWindow?.setFrameAutosaveName("Permissions")
        permissionsWindow?.isReleasedWhenClosed = false
        permissionsWindow?.contentView = hostingController.view
        permissionsWindow?.title = "Guardian Permissions"
        
        // Request notification permissions
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }
}
