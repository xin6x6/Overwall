//
//  MainView.swift
//  Overwall
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
    @State private var isOnVPN = false // Toggle VPN
    @State private var routing: Routing = .config // Routing method
    @State private var testConnectivityMethod: TCM = .tcp
    @State private var addDestination: AddProxyDestination?
    @State private var groups = [ProxyGroupOption(name: "Default")]
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading) {
                // Head
                Form {
                    // Toggle VPN
                Toggle(isOn: $isOnVPN) {
                    Label("Toggle VPN", systemImage: isOnVPN ? "shield.fill" : "shield.slash")
                }
                
                    // Routing
                Picker(selection: $routing) {
                    Text("Global").tag(Routing.global)
                    Text("Config").tag(Routing.config)
                    Text("Direct").tag(Routing.direct)
                } label : {
                    Label("Routing", systemImage: routing == .config ? "arrow.branch" : (routing == .direct ? "arrow.left.and.right" : "globe"))
                }
                
                    // Test Connectivity
                Picker(selection: $testConnectivityMethod) {
                    Text("TCP").tag(TCM.tcp)
                    Text("ICMP").tag(TCM.icmp)
                    Text("Connect").tag(TCM.connect)
                } label: {
                    Label("Test Connectivity", systemImage: "arrow.2.circlepath")
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                    // Test Connectivity Code
                            }
                        )
                }
                }
                .padding(.bottom, 50)
            
                // Body
                ForEach(groups) { group in
                    CollapsibleForm(LocalizedStringKey(group.name), onEdit: {}) {
                    
                    }
                }
            }
            
            
            
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
                        AddServerView(groups: groups)
                    case .group:
                        AddGroupView { draft in
                            let subscriptionURL = draft.subscriptionURL
                                .trimmingCharacters(in: .whitespacesAndNewlines)

                            groups.append(
                                ProxyGroupOption(
                                    name: draft.resolvedName,
                                    subscriptionURL: subscriptionURL.isEmpty ? nil : subscriptionURL
                                )
                            )
                        }
                    }
                }
                .presentationDetents([.large])
            }
        }
    }
}


#Preview {
    ContentView()
}
