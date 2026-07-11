//
//  OverwallApp.swift
//  Overwall
//
//  Created by Ng1nx on 7/10/26.
//

import SwiftUI

@main
struct OverwallApp: App {
    @State private var proxyStore = ProxyStore()
    @State private var tunnelController = TunnelController()
    @AppStorage("appAppearance") private var appearanceRawValue = AppAppearance.system.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(proxyStore)
                .environment(tunnelController)
                .preferredColorScheme(
                    AppAppearance(rawValue: appearanceRawValue)?.colorScheme
                )
        }
    }
}
