//
//  ContentView.swift
//  Dashstar
//
//  Created by Ng1nx on 7/10/26.
//

import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(StatisticsPiPController.self) private var statisticsPiP
    @Environment(ProxyStore.self) private var store
    @Environment(TunnelController.self) private var tunnel
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("lastInspectedPasteboardChange") private var lastInspectedPasteboardChange = -1
    @AppStorage("didRequestInitialNetworkAccess") private var didRequestInitialNetworkAccess = false
    @State private var isShowingClipboardImport = false
    @State private var clipboardImportError: String?
    var body: some View {
        TabView {
            MainView().tabItem {
                Label("Main", systemImage: "terminal")
            }
            
            ConfigView().tabItem {
                Label("Config", systemImage: "folder")
            }
            
            StatisticsView().tabItem {
                Label("Statistics", systemImage: "chart.bar")
            }
            
            SettingsView().tabItem {
                Label("Settings", systemImage: "gear")
            }
        }
        .globalInteractionFeedback()
        .overlay(alignment: .topLeading) {
            PiPSampleBufferHost(controller: statisticsPiP)
                .frame(width: 320, height: 180)
                .offset(x: -1_000, y: -1_000)
                .allowsHitTesting(false)
        }
        .alert("Import Subscription?", isPresented: $isShowingClipboardImport) {
            Button("Import") { Task { await importClipboardSubscription() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A possible subscription URL was found in the clipboard. Would you like to import it as a new group?")
        }
        .alert("Clipboard Import", isPresented: clipboardErrorBinding) {
            Button("OK") { clipboardImportError = nil }
        } message: {
            Text(clipboardImportError ?? "Unable to import the subscription.")
        }
        .task {
            await requestInitialNetworkAccessIfNeeded()
            await inspectClipboard()
        }
        .onReceive(NotificationCenter.default.publisher(for: .importSubscriptionFromClipboard)) { _ in
            Task { await importClipboardSubscription() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await inspectClipboard() }
        }
    }

    private var clipboardErrorBinding: Binding<Bool> {
        Binding(
            get: { clipboardImportError != nil },
            set: { if !$0 { clipboardImportError = nil } }
        )
    }

    private func inspectClipboard() async {
        let pasteboard = UIPasteboard.general
        let changeCount = pasteboard.changeCount
        guard changeCount != lastInspectedPasteboardChange else { return }
        do {
            let probableURL = \UIPasteboard.DetectedValues.probableWebURL
            let patterns = try await pasteboard.detectedPatterns(for: [probableURL])
            lastInspectedPasteboardChange = changeCount
            if patterns.contains(probableURL) { isShowingClipboardImport = true }
        } catch {
            // Pattern detection can be unavailable under managed pasteboard policies.
        }
    }

    /// iOS does not expose a standalone API for its first-use network permission.
    /// Starting a real request presents that system prompt on affected devices.
    private func requestInitialNetworkAccessIfNeeded() async {
        guard !didRequestInitialNetworkAccess else { return }
        didRequestInitialNetworkAccess = true

        guard let url = URL(string: "https://captive.apple.com/hotspot-detect.html") else { return }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 8
        request.httpMethod = "HEAD"
        _ = try? await URLSession.shared.data(for: request)
    }

    private func importClipboardSubscription() async {
        let rawValue = UIPasteboard.general.url?.absoluteString ?? UIPasteboard.general.string ?? ""
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            clipboardImportError = "The clipboard does not contain a valid HTTP or HTTPS subscription URL."
            return
        }
        guard !store.snapshot.groups.contains(where: { $0.subscriptionURL == value }) else {
            clipboardImportError = "This subscription has already been imported."
            return
        }

        let groupID = UUID()
        do {
            let imported = try await SubscriptionService().fetchGroupSubscription(
                from: value,
                groupID: groupID
            )
            let groupName = url.host(percentEncoded: false)?.replacingOccurrences(of: "www.", with: "")
                ?? "Imported Subscription"
            store.mutate { snapshot in
                let anotherGroupIsSelected = snapshot.groups.contains { $0.selectedServerID != nil }
                let group = StoredProxyGroup(
                    id: groupID,
                    name: groupName,
                    subscriptionURL: value,
                    selectedServerID: anotherGroupIsSelected ? nil : imported.servers.first?.id,
                    servers: imported.servers,
                    subscriptionUsage: imported.usage
                )
                snapshot.groups.append(group)
                if let route = imported.routeConfig {
                    let config = StoredRouteConfig(
                        name: "\(groupName) Default",
                        subscriptionURL: value,
                        rules: route.rules,
                        remoteRuleSets: route.remoteRuleSets,
                        sourceGroupID: groupID,
                        generalOptions: route.generalOptions
                    )
                    snapshot.routeConfigs.append(config)
                    if snapshot.selectedConfigID == nil { snapshot.selectedConfigID = config.id }
                }
            }
            await tunnel.reload(snapshot: store.snapshot)
        } catch {
            clipboardImportError = error.localizedDescription
        }
    }
}

extension Notification.Name {
    static let importSubscriptionFromClipboard = Notification.Name(
        "Dashstar.importSubscriptionFromClipboard"
    )
}

private struct GlobalInteractionFeedback: ViewModifier {
    @State private var dragFeedback = 0
    @State private var didTriggerDrag = false

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        let distance = hypot(value.translation.width, value.translation.height)
                        if distance > 12, !didTriggerDrag {
                            didTriggerDrag = true
                            dragFeedback += 1
                        }
                    }
                    .onEnded { _ in
                        didTriggerDrag = false
                    }
            )
            .sensoryFeedback(.impact(weight: .light), trigger: dragFeedback)
    }
}

private extension View {
    func globalInteractionFeedback() -> some View {
        modifier(GlobalInteractionFeedback())
    }
}

#Preview {
    ContentView()
        .environment(ProxyStore())
        .environment(TunnelController())
        .environment(StatisticsPiPController())
}
