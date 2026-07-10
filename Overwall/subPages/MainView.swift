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

struct MainView: View {
    @State private var isOnVPN = false // Toggle VPN
    @State private var routing: Routing = .config // Routing method
    @State private var testConnectivityMethod: TCM = .tcp
    
    var body: some View {

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
                    Label("Routing", systemImage: "arrow.branch")
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
            CollapsibleForm("Default", onEdit: {}) {
                
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}


#Preview {
    ContentView()
}
