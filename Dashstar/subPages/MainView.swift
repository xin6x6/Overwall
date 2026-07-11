//
//  MainView.swift
//  Dashstar
//
//  Created by Ng1nx on 7/10/26.
//

import SwiftUI

enum Routing: String, CaseIterable, Identifiable {
    case config
    case global
    case direct
    
    var id: Self { self }
}
enum TCM: String, CaseIterable, Identifiable {
    case tcp
    case icmp
    case connect
    
    var id: Self { self }
}
private enum AddProxyDestination: String, Identifiable {
    case server
    case group

    var id: Self { self }
}

struct MainView: View {
    @Environment(ProxyStore.self) private var store
    @Environment(TunnelController.self) private var tunnel
    @State private var routing: Routing = .config // Routing method
    @State private var testConnectivityMethod: TCM = .tcp
    @State private var addDestination: AddProxyDestination?
    @State private var editingGroup: StoredProxyGroup?
    @State private var groupPendingDeletion: StoredProxyGroup?
    @State private var operationError: String?
    @State private var isTestingLatency = false
    @State private var isTestingSpeed = false
    @State private var refreshingGroupIDs: Set<UUID> = []
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                // Head
                Form(
                    height: 216,
                    verticalContentMargin: 4,
                    allowsScrolling: false
                ) {
                    // Toggle VPN
                Toggle(isOn: vpnBinding) {
                    Label("Toggle VPN", systemImage: tunnel.isConnected ? "shield.fill" : "shield.slash")
                }
                .disabled(tunnel.isBusy)
                
                    // Routing
                Picker(selection: $routing) {
                    Text("Global").tag(Routing.global)
                    Text("Rule").tag(Routing.config)
                    Text("Direct").tag(Routing.direct)
                } label : {
                    Label("Routing", systemImage: routing == .config ? "arrow.branch" : (routing == .direct ? "arrow.left.and.right" : "globe"))
                }
                .onChange(of: routing) { _, mode in
                    store.mutate { $0.routingMode = StoredRoutingMode(rawValue: mode.rawValue) ?? .config }
                    Task { await tunnel.reload(snapshot: store.snapshot) }
                }
                .sensoryFeedback(.selection, trigger: routing)
                
                    // Test Latency
                Picker(selection: $testConnectivityMethod) {
                    Text("TCP").tag(TCM.tcp)
                    Text("ICMP").tag(TCM.icmp)
                    Text("Connect").tag(TCM.connect)
                } label: {
                    Label {
                        Text("Test Latency")
                    } icon: {
                        TimelineView(.animation(
                            minimumInterval: 1.0 / 30.0,
                            paused: !isTestingLatency
                        )) { context in
                            Image(systemName: "arrow.2.circlepath")
                                .rotationEffect(testIconRotation(at: context.date, isActive: isTestingLatency))
                        }
                    }
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                Task { await testAllLatencies() }
                            }
                        )
                }
                .disabled(isTestingLatency || isTestingSpeed)
                .sensoryFeedback(.selection, trigger: testConnectivityMethod)

                Button {
                    Task { await testAllSpeeds() }
                } label: {
                    Label {
                        Text("Test Speed")
                    } icon: {
                        TimelineView(.animation(
                            minimumInterval: 1.0 / 30.0,
                            paused: !isTestingSpeed
                        )) { context in
                            Image(systemName: "speedometer")
                                .rotationEffect(testIconRotation(at: context.date, isActive: isTestingSpeed))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isTestingLatency || isTestingSpeed)
                }
                .environment(\.defaultMinListRowHeight, 52)
                .padding(.bottom, 30)
            
                // Body
                ForEach(store.snapshot.groups) { group in
                    CollapsibleForm(
                        LocalizedStringKey(group.name),
                        subscriptionUsage: group.subscriptionUsage,
                        // Keep the final node clear of the 30 pt bottom corner.
                        expandedHeight: CGFloat(group.servers.count + 1) * 52 + 8,
                        onRefresh: { Task { await refreshGroup(group.id) } },
                        onDelete: { groupPendingDeletion = group },
                        onEdit: { editingGroup = group }
                    ) {
                        ForEach(group.servers) { server in
                            ProxyBar(
                                node: proxyBinding(groupID: group.id, serverID: server.id),
                                isSelected: group.selectedServerID == server.id,
                                onDelete: { deleteServer(groupID: group.id, serverID: server.id) },
                                onCommit: { Task { await tunnel.reload(snapshot: store.snapshot) } }
                            ) {
                                selectServer(groupID: group.id, serverID: server.id)
                            }
                        }
                    }
                }
                }
            }
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle("Main")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            addDestination = .server
                        } label: {
                            Label("Add Server", systemImage: "server.rack")
                        }

                        Button {
                            addDestination = .group
                        } label: {
                            Label("Add Group", systemImage: "folder.badge.plus")
                        }


                        Button {
                            NotificationCenter.default.post(
                                name: .importSubscriptionFromClipboard,
                                object: nil
                            )
                        } label: {
                            Label("Add Via Clipboard", systemImage: "doc.on.clipboard")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add")
                }
            }
            .sheet(item: $addDestination) { destination in
                NavigationStack {
                    switch destination {
                    case .server:
                        AddServerView(groups: groupOptions) { addServer($0) }
                    case .group:
                        AddGroupView { draft in
                            let subscriptionURL = draft.subscriptionURL
                                .trimmingCharacters(in: .whitespacesAndNewlines)

                            store.mutate { snapshot in
                                let group = StoredProxyGroup(
                                    name: draft.resolvedName,
                                    subscriptionURL: subscriptionURL.isEmpty ? nil : subscriptionURL
                                )
                                snapshot.groups.append(group)
                            }
                            if !subscriptionURL.isEmpty,
                               let groupID = store.snapshot.groups.last?.id {
                                Task { await refreshGroup(groupID) }
                            }
                        }
                    }
                }
                .presentationDetents([.large])
            }
            .sheet(item: $editingGroup) { group in
                NavigationStack {
                    EditGroupView(group: group) { id, name, subscriptionURL in
                        store.mutate { snapshot in
                            guard let index = snapshot.groups.firstIndex(where: { $0.id == id }) else { return }
                            snapshot.groups[index].name = name
                            snapshot.groups[index].subscriptionURL = subscriptionURL
                        }
                        if subscriptionURL != nil {
                            Task { await refreshGroup(id) }
                        } else {
                            Task { await tunnel.reload(snapshot: store.snapshot) }
                        }
                    }
                }
            }
            .alert("Dashstar", isPresented: errorBinding) {
                Button("OK") {
                    tunnel.lastError = nil
                    operationError = nil
                }
            } message: {
                Text(tunnel.lastError ?? operationError ?? "Unknown error")
            }
            .confirmationDialog(
                "Delete Group?",
                isPresented: deleteGroupConfirmationBinding,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    guard let group = groupPendingDeletion else { return }
                    deleteGroup(group.id)
                    groupPendingDeletion = nil
                }
                Button("Cancel", role: .cancel) {
                    groupPendingDeletion = nil
                }
            } message: {
                Text("Deleting \(groupPendingDeletion?.name ?? "this group") will also delete all of its proxy nodes.")
            }
            .onAppear {
                routing = Routing(rawValue: store.snapshot.routingMode.rawValue) ?? .config
            }
        }
    }

    private var vpnBinding: Binding<Bool> {
        Binding(
            get: { tunnel.isConnected },
            set: { enabled in
                Task { await tunnel.setEnabled(enabled, snapshot: store.snapshot) }
            }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { tunnel.lastError != nil || operationError != nil },
            set: {
                if !$0 {
                    tunnel.lastError = nil
                    operationError = nil
                }
            }
        )
    }

    private var deleteGroupConfirmationBinding: Binding<Bool> {
        Binding(
            get: { groupPendingDeletion != nil },
            set: { if !$0 { groupPendingDeletion = nil } }
        )
    }

    private var groupOptions: [ProxyGroupOption] {
        store.snapshot.groups.map { ProxyGroupOption(id: $0.id, name: $0.name, subscriptionURL: $0.subscriptionURL) }
    }

    private func addServer(_ draft: ServerDraft) {
        guard let groupID = draft.groupID, let port = Int(draft.port) else { return }
        store.mutate { snapshot in
            guard let index = snapshot.groups.firstIndex(where: { $0.id == groupID }) else { return }
            let server = StoredProxyServer(
                groupID: groupID,
                name: draft.name.isEmpty ? draft.address : draft.name,
                type: ProxyProtocolKind(rawValue: draft.type.rawValue.lowercased()) ?? .shadowsocks,
                address: draft.address,
                port: port,
                password: draft.password,
                method: draft.method,
                userID: draft.userID,
                alterID: Int(draft.alterID) ?? 0,
                security: draft.security,
                transport: draft.transport,
                tlsMode: draft.tlsMode,
                serverName: draft.serverName,
                host: draft.host,
                path: draft.path,
                flow: draft.flow,
                realityPublicKey: draft.realityPublicKey,
                realityShortID: draft.realityShortID,
                allowInsecure: draft.allowInsecure
            )
            snapshot.groups[index].servers.append(server)
            if !snapshot.groups.contains(where: { $0.selectedServerID != nil }) {
                snapshot.groups[index].selectedServerID = server.id
            }
        }
        Task { await tunnel.reload(snapshot: store.snapshot) }
    }

    private func proxyBinding(groupID: UUID, serverID: UUID) -> Binding<ProxyNode> {
        Binding {
            let server = store.snapshot.groups.first(where: { $0.id == groupID })?.servers.first(where: { $0.id == serverID })
            return ProxyNode(
                id: serverID,
                countryCode: server?.countryCode ?? "",
                name: server?.name ?? "",
                server: server?.address ?? "",
                port: server?.port ?? 443,
                protocolName: server?.type.rawValue ?? "shadowsocks",
                password: server?.password ?? "",
                method: server?.method ?? "",
                userID: server?.userID ?? "",
                alterID: server?.alterID ?? 0,
                security: server?.security ?? "auto",
                transport: server?.transport ?? "tcp",
                tlsMode: server?.tlsMode ?? "none",
                serverName: server?.serverName ?? "",
                host: server?.host ?? "",
                path: server?.path ?? "",
                flow: server?.flow ?? "",
                realityPublicKey: server?.realityPublicKey ?? "",
                realityShortID: server?.realityShortID ?? "",
                allowInsecure: server?.allowInsecure ?? false,
                latencyMilliseconds: server?.latencyMilliseconds,
                speedMegabytesPerSecond: server?.speedMegabytesPerSecond
            )
        } set: { node in
            store.mutate { snapshot in
                guard let group = snapshot.groups.firstIndex(where: { $0.id == groupID }), let server = snapshot.groups[group].servers.firstIndex(where: { $0.id == serverID }) else { return }
                snapshot.groups[group].servers[server].name = node.name
                snapshot.groups[group].servers[server].countryCode = node.countryCode
                snapshot.groups[group].servers[server].address = node.server
                snapshot.groups[group].servers[server].port = node.port
                snapshot.groups[group].servers[server].type = ProxyProtocolKind(rawValue: node.protocolName.lowercased()) ?? .shadowsocks
                snapshot.groups[group].servers[server].password = node.password
                snapshot.groups[group].servers[server].method = node.method
                snapshot.groups[group].servers[server].userID = node.userID
                snapshot.groups[group].servers[server].alterID = node.alterID
                snapshot.groups[group].servers[server].security = node.security
                snapshot.groups[group].servers[server].transport = node.transport
                snapshot.groups[group].servers[server].tlsMode = node.tlsMode
                snapshot.groups[group].servers[server].serverName = node.serverName
                snapshot.groups[group].servers[server].host = node.host
                snapshot.groups[group].servers[server].path = node.path
                snapshot.groups[group].servers[server].flow = node.flow
                snapshot.groups[group].servers[server].realityPublicKey = node.realityPublicKey
                snapshot.groups[group].servers[server].realityShortID = node.realityShortID
                snapshot.groups[group].servers[server].allowInsecure = node.allowInsecure
            }
        }
    }

    private func selectServer(groupID: UUID, serverID: UUID) {
        store.mutate { snapshot in
            for groupIndex in snapshot.groups.indices {
                snapshot.groups[groupIndex].selectedServerID = nil
            }
            guard let index = snapshot.groups.firstIndex(where: { $0.id == groupID }) else { return }
            snapshot.groups[index].selectedServerID = serverID
        }
        Task { await tunnel.reload(snapshot: store.snapshot) }
    }

    private func deleteServer(groupID: UUID, serverID: UUID) {
        store.mutate { snapshot in
            guard let index = snapshot.groups.firstIndex(where: { $0.id == groupID }) else { return }
            snapshot.groups[index].servers.removeAll { $0.id == serverID }
            if snapshot.groups[index].selectedServerID == serverID { snapshot.groups[index].selectedServerID = snapshot.groups[index].servers.first?.id }
        }
        Task { await tunnel.reload(snapshot: store.snapshot) }
    }

    private func deleteGroup(_ groupID: UUID) {
        store.mutate { snapshot in
            snapshot.groups.removeAll { $0.id == groupID }
            let removedConfigIDs = Set(
                snapshot.routeConfigs
                    .filter { $0.sourceGroupID == groupID }
                    .map(\.id)
            )
            snapshot.routeConfigs.removeAll { $0.sourceGroupID == groupID }
            if let selectedConfigID = snapshot.selectedConfigID,
               removedConfigIDs.contains(selectedConfigID) {
                snapshot.selectedConfigID = snapshot.routeConfigs.first?.id
            }
        }
        Task { await tunnel.reload(snapshot: store.snapshot) }
    }

    private func refreshGroup(_ groupID: UUID) async {
        guard !refreshingGroupIDs.contains(groupID),
              let group = store.snapshot.groups.first(where: { $0.id == groupID }) else { return }
        refreshingGroupIDs.insert(groupID)
        defer { refreshingGroupIDs.remove(groupID) }

        do {
            if let subscriptionURL = group.subscriptionURL, !subscriptionURL.isEmpty {
                let subscription = try await SubscriptionService().fetchGroupSubscription(
                    from: subscriptionURL,
                    groupID: groupID
                )
                var imported = subscription.servers
                let oldServers = group.servers
                var reusableServers = Dictionary(grouping: oldServers, by: serverIdentity)
                for index in imported.indices {
                    let identity = serverIdentity(imported[index])
                    if var matches = reusableServers[identity], !matches.isEmpty {
                        let old = matches.removeFirst()
                        reusableServers[identity] = matches
                        imported[index].id = old.id
                        imported[index].latencyMilliseconds = old.latencyMilliseconds
                        imported[index].speedMegabytesPerSecond = old.speedMegabytesPerSecond
                    }
                }
                store.mutate { snapshot in
                    guard let index = snapshot.groups.firstIndex(where: { $0.id == groupID }) else { return }
                    let selected = snapshot.groups[index].selectedServerID
                    let anotherGroupIsSelected = snapshot.groups.contains {
                        $0.id != groupID && $0.selectedServerID != nil
                    }
                    snapshot.groups[index].servers = imported
                    snapshot.groups[index].subscriptionUsage = subscription.usage
                    snapshot.groups[index].selectedServerID = imported.contains(where: { $0.id == selected })
                        ? selected : (anotherGroupIsSelected ? nil : imported.first?.id)

                    if let importedConfig = subscription.routeConfig {
                        if let configIndex = snapshot.routeConfigs.firstIndex(where: {
                            $0.sourceGroupID == groupID
                        }) {
                            snapshot.routeConfigs[configIndex].subscriptionURL = subscriptionURL
                            snapshot.routeConfigs[configIndex].rules = importedConfig.rules
                            snapshot.routeConfigs[configIndex].remoteRuleSets = importedConfig.remoteRuleSets
                            snapshot.routeConfigs[configIndex].generalOptions = importedConfig.generalOptions
                        } else {
                            let config = StoredRouteConfig(
                                name: "\(snapshot.groups[index].name) Default",
                                subscriptionURL: subscriptionURL,
                                rules: importedConfig.rules,
                                remoteRuleSets: importedConfig.remoteRuleSets,
                                sourceGroupID: groupID,
                                generalOptions: importedConfig.generalOptions
                            )
                            snapshot.routeConfigs.append(config)
                            if snapshot.selectedConfigID == nil {
                                snapshot.selectedConfigID = config.id
                            }
                        }
                    } else {
                        let removedConfigIDs = Set(
                            snapshot.routeConfigs
                                .filter { $0.sourceGroupID == groupID }
                                .map(\.id)
                        )
                        snapshot.routeConfigs.removeAll { $0.sourceGroupID == groupID }
                        if let selectedConfigID = snapshot.selectedConfigID,
                           removedConfigIDs.contains(selectedConfigID) {
                            snapshot.selectedConfigID = snapshot.routeConfigs.first?.id
                        }
                    }
                }
            }
            await tunnel.reload(snapshot: store.snapshot)
            try await testLatencyServers(in: groupID)
        } catch {
            operationError = error.localizedDescription
        }
    }

    private func testAllLatencies() async {
        guard !isTestingLatency, !isTestingSpeed else { return }
        isTestingLatency = true
        defer { isTestingLatency = false }
        do {
            try await tunnel.prepareForConnectivityTest(speed: false, snapshot: store.snapshot)
            let targets = store.snapshot.groups.flatMap { group in
                group.servers.map { (group.id, $0) }
            }
            try await withThrowingTaskGroup(of: (UUID, UUID, Int?).self) { taskGroup in
                for (groupID, server) in targets {
                    taskGroup.addTask {
                        let result = try await tunnel.latencyTest(
                            method: testConnectivityMethod.rawValue,
                            servers: [server],
                            snapshot: store.snapshot
                        )[server.id]
                        return (groupID, server.id, result?.latency)
                    }
                }
                for try await (groupID, serverID, latency) in taskGroup {
                    updateLatency(latency, groupID: groupID, serverID: serverID)
                }
            }
        } catch {
            operationError = error.localizedDescription
        }
    }

    private func testAllSpeeds() async {
        guard !isTestingLatency, !isTestingSpeed else { return }
        isTestingSpeed = true
        defer { isTestingSpeed = false }
        do {
            try await tunnel.prepareForConnectivityTest(speed: true, snapshot: store.snapshot)
            let targets = store.snapshot.groups.flatMap { group in
                group.servers.map { (group.id, $0) }
            }
            // Downloads remain serial for an honest per-node result, but each
            // completed node is published immediately.
            for (groupID, server) in targets {
                let result = try await tunnel.speedTest(servers: [server], snapshot: store.snapshot)[server.id]
                updateSpeed(result?.speedMegabytesPerSecond, groupID: groupID, serverID: server.id)
            }
        } catch {
            operationError = error.localizedDescription
        }
    }

    private func testIconRotation(at date: Date, isActive: Bool) -> Angle {
        guard isActive else { return .zero }
        let turns = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: 0.8) / 0.8
        return .degrees(turns * 360)
    }

    private func testLatencyServers(in groupID: UUID) async throws {
        guard let servers = store.snapshot.groups.first(where: { $0.id == groupID })?.servers else { return }
        let results = try await tunnel.latencyTest(
            method: testConnectivityMethod.rawValue,
            servers: servers,
            snapshot: store.snapshot
        )
        store.mutate { snapshot in
            guard let groupIndex = snapshot.groups.firstIndex(where: { $0.id == groupID }) else { return }
            for serverIndex in snapshot.groups[groupIndex].servers.indices {
                let id = snapshot.groups[groupIndex].servers[serverIndex].id
                snapshot.groups[groupIndex].servers[serverIndex].latencyMilliseconds = results[id]?.latency
            }
        }
    }

    private func updateLatency(_ latency: Int?, groupID: UUID, serverID: UUID) {
        store.mutate { snapshot in
            guard let groupIndex = snapshot.groups.firstIndex(where: { $0.id == groupID }),
                  let serverIndex = snapshot.groups[groupIndex].servers.firstIndex(where: { $0.id == serverID }) else { return }
            snapshot.groups[groupIndex].servers[serverIndex].latencyMilliseconds = latency
        }
    }

    private func updateSpeed(_ speed: Double?, groupID: UUID, serverID: UUID) {
        store.mutate { snapshot in
            guard let groupIndex = snapshot.groups.firstIndex(where: { $0.id == groupID }),
                  let serverIndex = snapshot.groups[groupIndex].servers.firstIndex(where: { $0.id == serverID }) else { return }
            snapshot.groups[groupIndex].servers[serverIndex].speedMegabytesPerSecond = speed
        }
    }

    private func testSpeedServers(in groupID: UUID) async throws {
        guard let servers = store.snapshot.groups.first(where: { $0.id == groupID })?.servers else { return }
        let results = try await tunnel.speedTest(servers: servers, snapshot: store.snapshot)
        store.mutate { snapshot in
            guard let groupIndex = snapshot.groups.firstIndex(where: { $0.id == groupID }) else { return }
            for serverIndex in snapshot.groups[groupIndex].servers.indices {
                let id = snapshot.groups[groupIndex].servers[serverIndex].id
                snapshot.groups[groupIndex].servers[serverIndex].speedMegabytesPerSecond = results[id]?.speedMegabytesPerSecond
            }
        }
    }

    private func serverIdentity(_ server: StoredProxyServer) -> String {
        "\(server.type.rawValue)|\(server.address)|\(server.port)|\(server.userID)|\(server.method)"
    }
}


#Preview {
    ContentView()
        .environment(ProxyStore())
        .environment(TunnelController())
        .environment(StatisticsPiPController())
}
