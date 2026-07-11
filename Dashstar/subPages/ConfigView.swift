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

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
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

#Preview {
    ContentView()
        .environment(ProxyStore())
        .environment(TunnelController())
        .environment(StatisticsPiPController())
}
