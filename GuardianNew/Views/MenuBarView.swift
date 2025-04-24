import SwiftUI

struct MenuBarView: View {
    @ObservedObject var menuBarController: MenuBarController
    @StateObject private var securityStatus = SecurityStatus()
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Guardian")
                    .font(.headline)
                Spacer()
                if hasPermissionIssues {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                        .help("Permission issues detected")
                }
            }
            .padding(.bottom, 5)
            
            if hasPermissionIssues {
                permissionWarningSection
            }
            
            // Tab selector with three options: Status, Rules, and Profiles
            Picker("View", selection: $selectedTab) {
                Text("Status").tag(0)
                Text("Rules").tag(1)
                Text("Profiles").tag(2)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.bottom, 5)
            
            if selectedTab == 0 {
                // Security Status Section
                Section(header: Text("Security Status").font(.headline)) {
                    HStack {
                        Image(systemName: securityStatus.littleSnitchStatus == .secure ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                            .foregroundColor(securityStatus.littleSnitchStatus == .secure ? .green : .red)
                        Text("Little Snitch")
                            .frame(width: 100, alignment: .leading)
                        Text(securityStatus.littleSnitchStatus == .secure ? "Active" : "Not Detected")
                            .foregroundColor(securityStatus.littleSnitchStatus == .secure ? .green : .red)
                    }
                    
                    HStack {
                        Image(systemName: securityStatus.santaStatus == .secure ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                            .foregroundColor(securityStatus.santaStatus == .secure ? .green : .red)
                        Text("Santa")
                            .frame(width: 100, alignment: .leading)
                        Text(securityStatus.santaStatus == .secure ? "Active" : "Not Detected")
                            .foregroundColor(securityStatus.santaStatus == .secure ? .green : .red)
                    }
                    
                    HStack {
                        Image(systemName: securityStatus.profilesStatus == .secure ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                            .foregroundColor(securityStatus.profilesStatus == .secure ? .green : .red)
                        Text("Profiles")
                            .frame(width: 100, alignment: .leading)
                        Text(securityStatus.profilesStatus == .secure ? "Detected" : "Not Detected")
                            .foregroundColor(securityStatus.profilesStatus == .secure ? .green : .red)
                    }
                    
                    // Show error message if any
                    if let errorMessage = securityStatus.profileMonitor.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    // Santa information if running
                    if securityStatus.santaMonitor.isRunning {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                            Text("Santa Mode:")
                                .frame(width: 100, alignment: .leading)
                            Text(securityStatus.santaMonitor.mode)
                                .foregroundColor(securityStatus.santaMonitor.isValidMode ? .green : .orange)
                        }
                        
                        HStack {
                            Image(systemName: "list.bullet")
                                .foregroundColor(.blue)
                            Text("Rules Count:")
                                .frame(width: 100, alignment: .leading)
                            Text("\(securityStatus.santaMonitor.ruleCount)")
                        }
                        
                        Button("View Rules") {
                            selectedTab = 1
                        }
                        .font(.caption)
                        .padding(.top, 5)
                    }
                    
                    // Profiles summary info
                    if !securityStatus.profileMonitor.profilesInfo.isEmpty {
                        HStack {
                            Image(systemName: "list.bullet")
                                .foregroundColor(.blue)
                            Text("Profiles Count:")
                                .frame(width: 100, alignment: .leading)
                            Text("\(securityStatus.profileMonitor.profilesInfo.count)")
                        }
                        
                        Button("View Profiles") {
                            selectedTab = 2
                        }
                        .font(.caption)
                        .padding(.top, 5)
                    }
                }
            } else if selectedTab == 1 {
                // Rules Section
                SantaRulesView(santaMonitor: securityStatus.santaMonitor)
            } else {
                // Profiles Section (new!)
                ProfilesDetailView(profileMonitor: securityStatus.profileMonitor)
            }
            
            Divider()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            
            // Footer with version info
            HStack {
                Spacer()
                Text("Guardian \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                    .font(.caption)
                    .foregroundColor(.gray)
                Spacer()
            }
        }
        .padding()
        .frame(width: 350, height: 700) // Added fixed height to ensure enough vertical space
        .environmentObject(securityStatus)
    }
    
    // Group profiles for better organization
    private func getGroupedProfiles() -> [ProfileGroup] {
        let profiles = securityStatus.profileMonitor.profilesInfo
        
        // Group 1: MDM Profiles
        let mdmProfiles = profiles.filter { $0.key.contains("mdm") || $0.key.contains("manageengine") || $0.key.contains("zoho") }
        
        // Group 2: Security Profiles
        let securityProfiles = profiles.filter { $0.key.contains("restrict") || $0.key.contains("security") || $0.key.contains("santa") }
        
        // Group 3: Network Profiles
        let networkProfiles = profiles.filter { $0.key.contains("tailscale") || $0.key.contains("vpn") || $0.key.contains("network") }
        
        // Group 4: App Configuration Profiles
        let appProfiles = profiles.filter { $0.key.contains("arc") || $0.key.contains("app") || $0.key.contains("browser") }
        
        // Group 5: Other Profiles
        let otherProfileKeys = Set(profiles.keys)
            .subtracting(mdmProfiles.keys)
            .subtracting(securityProfiles.keys)
            .subtracting(networkProfiles.keys)
            .subtracting(appProfiles.keys)
        let otherProfiles = profiles.filter { otherProfileKeys.contains($0.key) }
        
        var result: [ProfileGroup] = []
        
        if !mdmProfiles.isEmpty {
            result.append(ProfileGroup(type: "MDM Profiles", profiles: mdmProfiles))
        }
        
        if !securityProfiles.isEmpty {
            result.append(ProfileGroup(type: "Security Profiles", profiles: securityProfiles))
        }
        
        if !networkProfiles.isEmpty {
            result.append(ProfileGroup(type: "Network Profiles", profiles: networkProfiles))
        }
        
        if !appProfiles.isEmpty {
            result.append(ProfileGroup(type: "App Profiles", profiles: appProfiles))
        }
        
        if !otherProfiles.isEmpty {
            result.append(ProfileGroup(type: "Other Profiles", profiles: otherProfiles))
        }
        
        return result.isEmpty ? [ProfileGroup(type: "Profiles", profiles: profiles)] : result
    }
    
    private var hasPermissionIssues: Bool {
        !securityStatus.santaMonitor.hasPermission || 
        !securityStatus.littleSnitchMonitor.hasPermission ||
        !securityStatus.profileMonitor.hasPermission
    }
    
    private var permissionWarningSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("⚠️ Permission Issues Detected")
                .font(.headline)
                .foregroundColor(.yellow)
            
            Text("Guardian needs Full Disk Access to monitor security tools.")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            
            HStack {
                Button("Open Security Settings") {
                    openSecuritySettings()
                }
                
                Spacer()
                
                Button("Refresh Status") {
                    refreshAllMonitors()
                }
                .help("Click after granting permissions to update status")
            }
            .padding(.vertical, 5)
            
            Divider()
        }
    }
    
    private func openSecuritySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }
    
    private func refreshAllMonitors() {
        securityStatus.santaMonitor.checkStatus()
        securityStatus.littleSnitchMonitor.checkStatus()
        securityStatus.profileMonitor.checkStatus()
    }
}

// Model to represent a group of profiles
struct ProfileGroup: Identifiable {
    let id = UUID()
    let type: String
    let profiles: [String: String]
}

// View for a group of profiles
struct ProfileGroupView: View {
    let profileGroup: ProfileGroup
    @State private var isExpanded = false
    
    var body: some View {
        DisclosureGroup(
            isExpanded: $isExpanded,
            content: {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(profileGroup.profiles.sorted(by: { $0.key < $1.key }), id: \.key) { id, name in
                        ProfileItemView(id: id, name: name)
                    }
                }
                .padding(.leading, 8)
            },
            label: {
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundColor(.blue)
                    Text(profileGroup.type)
                        .font(.caption)
                        .bold()
                    Spacer()
                    Text("\(profileGroup.profiles.count)")
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(10)
                }
            }
        )
    }
}

// View for an individual profile item
struct ProfileItemView: View {
    let id: String
    let name: String
    @State private var showDetail = false
    
    var body: some View {
        Button(action: {
            showDetail.toggle()
        }) {
            HStack {
                Image(systemName: "doc.fill")
                    .foregroundColor(.blue)
                Text(name)
                    .font(.caption)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: showDetail ? "chevron.up.circle.fill" : "chevron.down.circle")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        
        if showDetail {
            Text(id)
                .font(.caption2)
                .foregroundColor(.gray)
                .padding(.leading, 24)
                .transition(.opacity)
        }
    }
}

// New component to display Santa rules with filtering
struct SantaRulesView: View {
    @ObservedObject var santaMonitor: SantaMonitor
    @State private var searchText = ""
    @State private var selectedRuleType = "All"
    @State private var selectedPolicy = "All"
    @State private var isLoading = false
    @State private var isRequestingAdmin = false
    
    // Available rule type filters
    let ruleTypes = ["All", "binary", "certificate", "teamid", "signingid", "cdhash"]
    let policyTypes = ["All", "Allow", "Block"]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Santa Rules")
                .font(.headline)
            
            // Filter section
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                TextField("Search", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.caption)
            }
            
            HStack {
                Picker("Type", selection: $selectedRuleType) {
                    ForEach(ruleTypes, id: \.self) { type in
                        Text(type).tag(type)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(maxWidth: 130)
                
                Spacer()
                
                Picker("Policy", selection: $selectedPolicy) {
                    ForEach(policyTypes, id: \.self) { policy in
                        Text(policy).tag(policy)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(maxWidth: 100)
            }
            .font(.caption)
            
            // Rules count and refresh button
            HStack {
                Text("\(filteredRules.count) rules")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if hasAdminRules {
                    // Rules already fetched with admin
                    Button("Refresh") {
                        fetchRules()
                    }
                    .disabled(isLoading || isRequestingAdmin)
                } else {
                    HStack {
                        Button("Fetch Rules") {
                            fetchRules()
                        }
                        .disabled(isLoading || isRequestingAdmin)
                        
                        Button("Get Admin Access") {
                            requestAdminAccess()
                        }
                        .disabled(isLoading || isRequestingAdmin)
                        .help("Get full rule details with admin privileges")
                    }
                }
            }
            
            Divider()
            
            if isLoading || isRequestingAdmin {
                VStack {
                    ProgressView(isRequestingAdmin ? "Requesting admin access..." : "Loading rules...")
                        .padding()
                    
                    if isRequestingAdmin {
                        Text("Please enter your admin password when prompted")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } else if filteredRules.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 30))
                        .foregroundColor(.gray)
                    
                    if santaMonitor.rules.isEmpty {
                        Text("No rules found. Click 'Fetch Rules' to retrieve the Santa rules or 'Get Admin Access' to see all rules.")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.gray)
                            .padding(.horizontal)
                        
                        HStack {
                            Button("Fetch Rules") {
                                fetchRules()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            
                            Button("Get Admin Access") {
                                requestAdminAccess()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.top, 10)
                    } else {
                        Text("No rules match your filter criteria")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 30)
            } else {
                // Check if we need admin privileges banner
                if needsAdminPrivileges {
                    privilegeBanner
                }
                
                // Rules list
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(filteredRules.prefix(100)) { rule in
                            RuleItemView(rule: rule)
                        }
                        
                        // Show a message if we're truncating the list
                        if filteredRules.count > 100 {
                            HStack {
                                Spacer()
                                Text("Showing first 100 of \(filteredRules.count) matching rules")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                Spacer()
                            }
                            .padding(.top, 5)
                        }
                    }
                    .padding(.vertical, 5)
                }
                .frame(maxHeight: 600) // Increased from 450 to 600 for better visibility
            }
        }
        .onAppear {
            if santaMonitor.rules.isEmpty {
                fetchRules()
            }
        }
    }
    
    // UI for the admin privileges banner
    private var privilegeBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.shield")
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Limited rule details available")
                    .font(.caption.bold())
                
                Text("Some rule details require admin privileges")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Get Admin Access") {
                requestAdminAccess()
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(8)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
    
    // Check if we need to show the admin privileges banner
    private var needsAdminPrivileges: Bool {
        // Show the banner if any rule is a placeholder or has an info type
        return santaMonitor.rules.contains { 
            $0.identifier.contains("ADMIN PRIVILEGES REQUIRED") || 
            $0.type == "info" ||
            $0.identifier.starts(with: "[") // Placeholder rules
        }
    }
    
    // Check if we already have admin rules
    private var hasAdminRules: Bool {
        // No placeholder rules and no admin privilege notices
        return !santaMonitor.rules.isEmpty && !needsAdminPrivileges
    }
    
    private func fetchRules() {
        isLoading = true
        
        // Start a background task to fetch rules
        DispatchQueue.global(qos: .userInitiated).async {
            // Call the santaMonitor to fetch rules
            self.santaMonitor.fetchRules()
            
            // Add a small delay to show the loading indicator
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.isLoading = false
            }
        }
    }
    
    private func requestAdminAccess() {
        isRequestingAdmin = true
        
        // Start a background task to get admin privileges
        DispatchQueue.global(qos: .userInitiated).async {
            // Call the santaMonitor to fetch rules with admin privileges
            self.santaMonitor.fetchRulesWithAdmin()
            
            // Reset the flag after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.isRequestingAdmin = false
            }
        }
    }
    
    // Filter the rules based on search text and selected filters
    private var filteredRules: [SantaRule] {
        santaMonitor.rules.filter { rule in
            let typeMatches = selectedRuleType == "All" || rule.type == selectedRuleType
            let policyMatches = selectedPolicy == "All" || rule.policyString == selectedPolicy
            let searchMatches = searchText.isEmpty || 
                                rule.identifier.localizedCaseInsensitiveContains(searchText) ||
                                rule.displayName.localizedCaseInsensitiveContains(searchText) ||
                                (rule.customMessage ?? "").localizedCaseInsensitiveContains(searchText)
            
            return typeMatches && policyMatches && searchMatches
        }
    }
}

// Individual rule item view
struct RuleItemView: View {
    let rule: SantaRule
    @State private var showDetails = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: { showDetails.toggle() }) {
                HStack {
                    // Icon based on rule type
                    Image(systemName: rule.typeIcon)
                        .foregroundColor(rule.color)
                        .frame(width: 16)
                    
                    // Rule display name
                    Text(rule.displayName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .font(.caption)
                    
                    Spacer()
                    
                    // Policy tag (allow/block)
                    Text(rule.policyString)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(rule.policy == .allow ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                        .foregroundColor(rule.policy == .allow ? .green : .red)
                        .cornerRadius(4)
                    
                    Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            
            // Expandable details section
            if showDetails {
                VStack(alignment: .leading, spacing: 4) {
                    Group {
                        Text("Type: \(rule.type.capitalized)")
                        Text("Identifier: \(rule.identifier)")
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    
                    if let message = rule.customMessage, !message.isEmpty {
                        Text("Note: \(message)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.leading, 24)
                .padding(.top, 2)
                .padding(.bottom, 4)
                .transition(.opacity)
            }
        }
        .padding(.vertical, 2)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(4)
    }
}

// New component to display Profiles with filtering and detailed view
struct ProfilesDetailView: View {
    @ObservedObject var profileMonitor: ProfileMonitor
    @State private var searchText = ""
    @State private var selectedCategory = "All"
    @State private var showMDMOnly = false
    @State private var isRefreshing = false
    
    // Available profile type categories
    let categories = ["All", "MDM", "Security", "Network", "Apps", "Other"]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Configuration Profiles")
                .font(.headline)
            
            // Filter section
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                TextField("Search", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.caption)
            }
            
            HStack {
                Picker("Category", selection: $selectedCategory) {
                    ForEach(categories, id: \.self) { category in
                        Text(category).tag(category)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(maxWidth: 130)
                
                Spacer()
                
                Toggle(isOn: $showMDMOnly) {
                    Text("MDM Only")
                        .font(.caption)
                }
                .controlSize(.small)
                .toggleStyle(SwitchToggleStyle())
                .labelsHidden()
                .help("Show only MDM profiles")
            }
            .font(.caption)
            
            // Profiles count
            HStack {
                Text("\(filteredProfiles.count) profiles")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: {
                    refreshProfiles()
                }) {
                    HStack {
                        if isRefreshing {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                        }
                        Text("Refresh")
                            .font(.caption)
                    }
                }
                .disabled(isRefreshing)
            }
            
            Divider()
            
            if isRefreshing {
                VStack {
                    ProgressView("Loading profiles...")
                        .padding()
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } else if filteredProfiles.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 30))
                        .foregroundColor(.gray)
                    
                    if profileMonitor.profilesInfo.isEmpty {
                        Text("No profiles found. Your Mac might not have any profiles installed or you may need Full Disk Access permissions.")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.gray)
                            .padding(.horizontal)
                        
                        Button("Check Profiles") {
                            refreshProfiles()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .padding(.top, 10)
                    } else {
                        Text("No profiles match your filter criteria")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 30)
            } else {
                // Profiles list
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(filteredProfiles) { profile in
                            ProfileDetailItemView(profile: profile)
                        }
                    }
                    .padding(.vertical, 5)
                }
                .frame(maxHeight: 600) // Increased from 300 to 600 for better visibility
            }
        }
        .onAppear {
            // Ensure profiles are loaded when the view appears
            if profileMonitor.profilesInfo.isEmpty {
                refreshProfiles()
            }
        }
    }
    
    private func refreshProfiles() {
        isRefreshing = true
        
        // Start a background task to refresh profiles
        DispatchQueue.global(qos: .userInitiated).async {
            // Call the profileMonitor to check status
            self.profileMonitor.checkStatus()
            
            // Add a small delay to show the loading indicator
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.isRefreshing = false
            }
        }
    }
    
    // Transform dictionary to array of structured profiles
    private var allProfiles: [DetailedProfile] {
        return profileMonitor.profilesInfo.map { id, name in
            let category = categorizeProfile(id: id, name: name)
            let isMDM = id.contains("mdm") || 
                        id.contains("manageengine") || 
                        id.contains("zoho") ||
                        name.lowercased().contains("mdm") ||
                        category == "MDM"
            
            return DetailedProfile(
                id: id,
                name: name,
                category: category,
                isMDM: isMDM
            )
        }
    }
    
    // Filter the profiles based on search text and selected filters
    private var filteredProfiles: [DetailedProfile] {
        allProfiles.filter { profile in
            // Category filter
            let categoryMatches = selectedCategory == "All" || profile.category == selectedCategory
            
            // MDM filter
            let mdmMatches = !showMDMOnly || profile.isMDM
            
            // Search text
            let searchMatches = searchText.isEmpty ||
                                profile.id.localizedCaseInsensitiveContains(searchText) ||
                                profile.name.localizedCaseInsensitiveContains(searchText)
            
            return categoryMatches && mdmMatches && searchMatches
        }
    }
    
    // Categorize a profile based on its ID and name
    private func categorizeProfile(id: String, name: String) -> String {
        let idLower = id.lowercased()
        let nameLower = name.lowercased()
        
        if idLower.contains("mdm") || idLower.contains("manageengine") || 
           idLower.contains("zoho") || nameLower.contains("management") {
            return "MDM"
        } else if idLower.contains("restrict") || idLower.contains("security") || 
                  idLower.contains("santa") || nameLower.contains("security") {
            return "Security"
        } else if idLower.contains("tailscale") || idLower.contains("vpn") || 
                  idLower.contains("network") || nameLower.contains("network") {
            return "Network"
        } else if idLower.contains("arc") || idLower.contains("app") || 
                  idLower.contains("browser") || nameLower.contains("app") {
            return "Apps"
        } else {
            return "Other"
        }
    }
}

// Detailed profile model
struct DetailedProfile: Identifiable {
    let id: String
    let name: String
    let category: String
    let isMDM: Bool
    
    var categoryIcon: String {
        switch category {
        case "MDM":
            return "iphone.homebutton.radiowaves.left.and.right"
        case "Security":
            return "lock.shield"
        case "Network":
            return "network"
        case "Apps":
            return "app.badge"
        default:
            return "doc.badge.gearshape"
        }
    }
    
    var categoryColor: Color {
        switch category {
        case "MDM":
            return .blue
        case "Security":
            return .red
        case "Network":
            return .green
        case "Apps":
            return .purple
        default:
            return .gray
        }
    }
}

// Individual profile item view
struct ProfileDetailItemView: View {
    let profile: DetailedProfile
    @State private var showDetails = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: { showDetails.toggle() }) {
                HStack {
                    // Icon based on category
                    Image(systemName: profile.categoryIcon)
                        .foregroundColor(profile.categoryColor)
                        .frame(width: 16)
                    
                    // Profile name
                    Text(profile.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .font(.caption)
                    
                    Spacer()
                    
                    // MDM badge if applicable
                    if profile.isMDM {
                        Text("MDM")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }
                    
                    // Category badge
                    Text(profile.category)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(profile.categoryColor.opacity(0.1))
                        .foregroundColor(profile.categoryColor)
                        .cornerRadius(4)
                    
                    Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            
            // Expandable details section
            if showDetails {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Identifier: \(profile.id)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text("Category: \(profile.category)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if profile.isMDM {
                        Text("MDM Profile: Yes")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }
                .padding(.leading, 24)
                .padding(.top, 2)
                .padding(.bottom, 4)
                .transition(.opacity)
            }
        }
        .padding(.vertical, 2)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(4)
    }
}

struct MenuBarView_Previews: PreviewProvider {
    static var previews: some View {
        MenuBarView(menuBarController: MenuBarController())
            .frame(width: 280)
            .padding()
    }
}