//
//  ContentView.swift
//  Overwall
//
//  Created by Ng1nx on 7/10/26.
//

import SwiftUI

struct ContentView: View {
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
    }
}

#Preview {
    ContentView()
}
