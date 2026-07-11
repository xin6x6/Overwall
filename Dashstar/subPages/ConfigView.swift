//
//  ConfigView.swift
//  Dashstar
//
//  Created by Ng1nx on 7/10/26.
//

import SwiftUI

struct ConfigView: View {
    @Environment(ProxyStore.self) private var store
    @Environment(TunnelController.self) private var tunnel
    @State private var operationError: String?
    @State private var routingTestInput = ""
    @State private var routingTestResult: RoutingTestResult?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    routingTestCard.padding(.bottom, 30)

                    Form(
                        height: configListHeight,
                        verticalContentMargin: 8,
                        allowsScrolling: false
                    ) {
                        ForEach(store.snapshot.routeConfigs) { config in
                            ConfigBar(
                                config: configBinding(config.id),
                                isSelected: store.snapshot.selectedConfigID == config.id,
                                onDelete: { deleteConfig(config.id) },
                                onRefresh: { Task { await refreshConfig(config.id) } },
                                onCommit: { Task { await tunnel.reload(snapshot: store.snapshot) } }
                            ) {
                                store.mutate { $0.selectedConfigID = config.id }
                                Task { await tunnel.reload(snapshot: store.snapshot) }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle("Config")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.mutate { snapshot in
                            let config = StoredRouteConfig(name: String(localized: "New Config"))
                            snapshot.routeConfigs.append(config)
                            snapshot.selectedConfigID = config.id
                        }
                        Task { await tunnel.reload(snapshot: store.snapshot) }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("Config Error", isPresented: errorBinding) {
                Button("OK") { operationError = nil }
            } message: {
                Text(operationError ?? "Unknown error")
            }
        }
    }

    private var routingTestCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Routing Test", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.headline)

            HStack(spacing: 10) {
                TextField("URL or host name", text: $routingTestInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .onSubmit { runRoutingTest() }

                Button("Test") { runRoutingTest() }
                    .buttonStyle(.borderedProminent)
                    .disabled(routingTestInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let result = routingTestResult {
                HStack(alignment: .top, spacing: 10) {
                    Text(result.target.displayName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(result.target.resultColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(result.target.resultColor.opacity(0.12), in: Capsule())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(result.reason).font(.subheadline.weight(.semibold))
                        Text(result.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .compatibleGlassSurface(cornerRadius: 30)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func runRoutingTest() {
        InteractionFeedback.tap()
        do {
            routingTestResult = try RoutingRuleTester().test(routingTestInput, snapshot: store.snapshot)
        } catch {
            routingTestResult = nil
            operationError = error.localizedDescription
        }
    }

    private var configListHeight: CGFloat {
        // A custom Form inside a ScrollView cannot discover an unconstrained
        // height on its first layout pass. Each ConfigBar is exactly 52 pt.
        CGFloat(max(store.snapshot.routeConfigs.count, 1)) * 52 + 16
    }

    private func configBinding(_ id: UUID) -> Binding<ConfigProfile> {
        Binding {
            let config = store.snapshot.routeConfigs.first(where: { $0.id == id })
            return ConfigProfile(
                id: id,
                name: config?.name ?? "",
                subscriptionURL: config?.subscriptionURL ?? "",
                rules: config?.rules ?? [],
                remoteRuleSets: config?.remoteRuleSets ?? [],
                generalOptions: config?.generalOptions ?? [],
                isBuiltIn: config?.isBuiltIn == true
            )
        } set: { edited in
            store.mutate { snapshot in
                guard let index = snapshot.routeConfigs.firstIndex(where: { $0.id == id }) else { return }
                snapshot.routeConfigs[index].name = edited.name
                snapshot.routeConfigs[index].subscriptionURL = edited.subscriptionURL.isEmpty ? nil : edited.subscriptionURL
                snapshot.routeConfigs[index].rules = edited.rules
                snapshot.routeConfigs[index].remoteRuleSets = edited.remoteRuleSets
                snapshot.routeConfigs[index].generalOptions = edited.generalOptions
            }
        }
    }

    private func deleteConfig(_ id: UUID) {
        guard store.snapshot.routeConfigs.first(where: { $0.id == id })?.isBuiltIn != true else {
            return
        }
        store.mutate { snapshot in
            snapshot.routeConfigs.removeAll { $0.id == id }
            if snapshot.selectedConfigID == id { snapshot.selectedConfigID = snapshot.routeConfigs.first?.id }
        }
        Task { await tunnel.reload(snapshot: store.snapshot) }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { operationError != nil }, set: { if !$0 { operationError = nil } })
    }

    private func refreshConfig(_ id: UUID) async {
        guard let config = store.snapshot.routeConfigs.first(where: { $0.id == id }),
              let subscriptionURL = config.subscriptionURL, !subscriptionURL.isEmpty else {
            operationError = String(localized: "Add a subscribe URL before refreshing this config.")
            return
        }
        do {
            let imported = try await SubscriptionService().fetchRouteConfig(from: subscriptionURL)
            store.mutate { snapshot in
                guard let index = snapshot.routeConfigs.firstIndex(where: { $0.id == id }) else { return }
                snapshot.routeConfigs[index].rules = imported.rules
                snapshot.routeConfigs[index].remoteRuleSets = imported.remoteRuleSets
                snapshot.routeConfigs[index].generalOptions = imported.generalOptions
            }
            await tunnel.reload(snapshot: store.snapshot)
        } catch {
            operationError = error.localizedDescription
        }
    }
}

private extension RouteTarget {
    var displayName: LocalizedStringKey {
        switch self {
        case .proxy: "Proxy"
        case .direct: "Direct"
        case .block: "Reject"
        }
    }

    var resultColor: Color {
        switch self {
        case .proxy: .orange
        case .direct: .green
        case .block: .red
        }
    }
}

#Preview {
    ContentView()
        .environment(ProxyStore())
        .environment(TunnelController())
        .environment(StatisticsPiPController())
}
