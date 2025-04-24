import Foundation
import Combine
import SwiftUI
import UserNotifications

class MenuBarController: ObservableObject {
    @Published var overallStatus: SecurityState = .unknown
    @Published var lastStatusChange: Date?
    @Published var showNotification: Bool = false
    @Published var notificationMessage: String = ""
    
    let santaMonitor = SantaMonitor()
    let littleSnitchMonitor = LittleSnitchMonitor()
    let profileMonitor = ProfileMonitor()
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupMonitors()
        checkAllStatus()
    }
    
    private func setupMonitors() {
        // Combine all status publishers
        Publishers.CombineLatest3(
            santaMonitor.$status,
            littleSnitchMonitor.$status, 
            profileMonitor.$status
        )
        .sink { [weak self] (santaStatus, littleSnitchStatus, profileStatus) in
            self?.updateOverallStatus()
        }
        .store(in: &cancellables)
        
        // Monitor permission status changes
        Publishers.CombineLatest(
            santaMonitor.$hasPermission,
            littleSnitchMonitor.$hasPermission
        )
        .sink { [weak self] (_, _) in
            self?.updateOverallStatus()
        }
        .store(in: &cancellables)
    }
    
    func checkAllStatus() {
        santaMonitor.checkStatus()
        littleSnitchMonitor.checkStatus()
        profileMonitor.checkStatus()
    }
    
    private func updateOverallStatus() {
        // If any component lacks permission, set overall status to unknown
        if !santaMonitor.hasPermission || !littleSnitchMonitor.hasPermission || !profileMonitor.hasPermission {
            setNewStatus(.unknown)
            return
        }
        
        // Count actual security concerns
        var securityConcerns = 0
        var unknownComponents = 0
        var partialComponents = 0
        
        // Check Santa status if it's expected to be present
        if FileManager.default.fileExists(atPath: "/Library/LaunchDaemons/com.google.santad.plist") {
            if santaMonitor.status == .insecure {
                securityConcerns += 1
            } else if santaMonitor.status == .unknown {
                unknownComponents += 1
            } else if santaMonitor.status == .partial {
                partialComponents += 1
            }
        }
        
        // Check Little Snitch status if it's expected to be present
        if FileManager.default.fileExists(atPath: "/Library/LaunchDaemons/at.obdev.littlesnitch.daemon.plist") {
            if littleSnitchMonitor.status == .insecure {
                securityConcerns += 1
            } else if littleSnitchMonitor.status == .unknown {
                unknownComponents += 1
            } else if littleSnitchMonitor.status == .partial {
                partialComponents += 1
            }
        }
        
        // Check profile status only if required profiles are defined
        if !profileMonitor.requiredProfileList.isEmpty {
            if profileMonitor.status == .insecure {
                securityConcerns += 1
            } else if profileMonitor.status == .unknown {
                unknownComponents += 1
            } else if profileMonitor.status == .partial {
                partialComponents += 1
            }
        }
        
        if securityConcerns > 0 {
            setNewStatus(.insecure)
        } else if unknownComponents > 0 {
            setNewStatus(.unknown)
        } else if partialComponents > 0 {
            setNewStatus(.partial)
        } else {
            setNewStatus(.secure)
        }
    }
    
    private func setNewStatus(_ newStatus: SecurityState) {
        let oldStatus = overallStatus
        overallStatus = newStatus
        
        // When status changes from secure to insecure, show notification
        if oldStatus == .secure && newStatus == .insecure {
            notifyStatusChange(to: newStatus)
        }
        
        lastStatusChange = Date()
    }
    
    private func notifyStatusChange(to status: SecurityState) {
        showNotification = true
        
        switch status {
        case .secure:
            notificationMessage = "All security systems are active and secure."
        case .insecure:
            notificationMessage = "Security issue detected! Check Guardian for details."
        case .unknown:
            notificationMessage = "Security status cannot be determined."
        case .partial:
            notificationMessage = "Security systems are running, but not optimally configured."
        }
        
        sendNotification(title: "Guardian Security Alert", body: notificationMessage)
    }
    
    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error sending notification: \(error)")
            }
        }
    }
}