import Foundation
import SwiftUI
import Combine

enum SecurityState: Equatable {
    case secure
    case insecure
    case unknown
    case partial
    
    var color: Color {
        switch self {
        case .secure:
            return .green
        case .insecure:
            return .red
        case .unknown:
            return .gray
        case .partial:
            return .yellow
        }
    }
    
    var icon: String {
        switch self {
        case .secure:
            return "shield.fill"
        case .insecure:
            return "shield.slash.fill"
        case .unknown:
            return "questionmark.circle.fill"
        case .partial:
            return "shield.lefthalf.fill"
        }
    }
    
    var description: String {
        switch self {
        case .secure:
            return "Secure"
        case .insecure:
            return "Insecure"
        case .unknown:
            return "Unknown"
        case .partial:
            return "Partial"
        }
    }
}

class SecurityStatus: ObservableObject {
    @Published var santaMonitor: SantaMonitor
    @Published var littleSnitchMonitor: LittleSnitchMonitor
    @Published var profileMonitor: ProfileMonitor
    
    @Published var santaStatus: SecurityState = .unknown
    @Published var littleSnitchStatus: SecurityState = .unknown
    @Published var profilesStatus: SecurityState = .unknown
    
    init() {
        self.santaMonitor = SantaMonitor()
        self.littleSnitchMonitor = LittleSnitchMonitor()
        self.profileMonitor = ProfileMonitor()
        
        // Setup bindings
        setupBindings()
        
        // Initial status check
        checkAllStatus()
    }
    
    private func setupBindings() {
        // Observe monitor statuses
        santaMonitor.$status
            .receive(on: RunLoop.main)
            .assign(to: &$santaStatus)
            
        littleSnitchMonitor.$status
            .receive(on: RunLoop.main)
            .assign(to: &$littleSnitchStatus)
            
        profileMonitor.$status
            .receive(on: RunLoop.main)
            .assign(to: &$profilesStatus)
    }
    
    func checkAllStatus() {
        santaMonitor.checkStatus()
        littleSnitchMonitor.checkStatus()
        profileMonitor.checkStatus()
    }
}