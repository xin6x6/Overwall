//
//  SettingsView.swift
//  Dashstar
//
//  Created by Ng1nx on 7/10/26.
//

import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case simplifiedChinese

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .english: "English"
        case .simplifiedChinese: "Simplified Chinese"
        }
    }

    var locale: Locale? {
        switch self {
        case .system: nil
        case .english: Locale(identifier: "en")
        case .simplifiedChinese: Locale(identifier: "zh-Hans")
        }
    }
}

struct SettingsView: View {
    @AppStorage("appAppearance") private var appearanceRawValue = AppAppearance.system.rawValue
    @AppStorage("appLanguage") private var languageRawValue = AppLanguage.system.rawValue

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    Form(
                        height: 170,
                        verticalContentMargin: 8,
                        bottomContentMargin: 12,
                        allowsScrolling: false
                    ) {
                        Section("Appearance") {
                            Picker("Appearance", selection: $appearanceRawValue) {
                                ForEach(AppAppearance.allCases) { appearance in
                                    Label(LocalizedStringKey(appearance.title), systemImage: appearance.icon)
                                        .tag(appearance.rawValue)
                                }
                            }
                            .pickerStyle(.menu)
                            .onChange(of: appearanceRawValue) { _, _ in
                                InteractionFeedback.selection()
                            }
                        }

                        Section("Language") {
                            Picker("Language", selection: $languageRawValue) {
                                ForEach(AppLanguage.allCases) { language in
                                    Text(LocalizedStringKey(language.title))
                                        .tag(language.rawValue)
                                }
                            }
                            .pickerStyle(.menu)
                            .onChange(of: languageRawValue) { _, _ in
                                InteractionFeedback.selection()
                            }
                        }
                    }
                }
            }
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private extension AppAppearance {
    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }
}

#Preview {
    SettingsView()
}
