import SwiftUI

struct PermissionsView: View {
    @State private var fullDiskAccessGranted = false
    
    var body: some View {
        VStack(alignment: .center, spacing: 20) {
            Image(systemName: "shield.fill")
                .font(.system(size: 48))
                .foregroundColor(.blue)
            
            Text("Guardian Security Monitor")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Guardian needs Full Disk Access to monitor security components on your Mac.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button(action: openSecurityPreferences) {
                Text("Open Security Preferences")
                    .fontWeight(.medium)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .padding(.horizontal, 40)
            .padding(.top, 10)
            
            Text("Instructions:\n1. Click 'Full Disk Access' in the left sidebar\n2. Click the lock icon to make changes\n3. Add Guardian to the list of allowed apps")
                .font(.caption)
                .multilineTextAlignment(.leading)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
            
            HStack {
                Button("Hide Window") {
                    hidePermissionWindow()
                }
                .buttonStyle(.plain)
                .foregroundColor(.blue)
                .padding(.bottom)
            }
        }
        .padding()
        .frame(width: 400, height: 400)
        .onAppear {
            checkPermissionsStatus()
            // After a delay, hide this window if permissions likely granted
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if fullDiskAccessGranted {
                    hidePermissionWindow()
                }
            }
        }
    }
    
    private func openSecurityPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }
    
    private func hidePermissionWindow() {
        if let window = NSApp.windows.first(where: { $0.contentView?.subviews.first?.subviews.contains(where: { $0 is NSHostingView<PermissionsView> }) ?? false }) {
            window.orderOut(nil)
        }
    }
    
    private func checkPermissionsStatus() {
        // Check if we can access a protected path
        // This is just an approximation as there's no direct API to check FDA
        let fileManager = FileManager.default
        do {
            _ = try fileManager.contentsOfDirectory(atPath: "/Library/Application Support/com.apple.TCC")
            fullDiskAccessGranted = true
        } catch {
            fullDiskAccessGranted = false
        }
    }
}