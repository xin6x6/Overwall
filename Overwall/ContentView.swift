//
//  ContentView.swift
//  Overwall
//
//  Created by Ng1nx on 7/10/26.
//

import SwiftUI

struct ContentView: View {
    @Environment(StatisticsPiPController.self) private var statisticsPiP
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
    }
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
