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
        .globalInteractionFeedback()
    }
}

private struct GlobalInteractionFeedback: ViewModifier {
    @State private var touchFeedback = 0
    @State private var dragFeedback = 0
    @State private var isTouching = false
    @State private var didTriggerDrag = false

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isTouching {
                            isTouching = true
                            touchFeedback += 1
                        }
                        let distance = hypot(value.translation.width, value.translation.height)
                        if distance > 12, !didTriggerDrag {
                            didTriggerDrag = true
                            dragFeedback += 1
                        }
                    }
                    .onEnded { _ in
                        isTouching = false
                        didTriggerDrag = false
                    }
            )
            .sensoryFeedback(.selection, trigger: touchFeedback)
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
}
