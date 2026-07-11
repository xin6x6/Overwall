//
//  ConfigBar.swift
//  Overwall
//
//  Created by Ng1nx on 7/10/26.
//

import SwiftUI

struct ConfigProfile: Identifiable, Hashable {
    let id: UUID
    var name: String
    var subscriptionURL: String = ""
    var rules: [StoredRouteRule] = []
    var remoteRuleSets: [StoredRemoteRuleSet] = []

    init(
        id: UUID = UUID(),
        name: String,
        subscriptionURL: String = "",
        rules: [StoredRouteRule] = [],
        remoteRuleSets: [StoredRemoteRuleSet] = []
    ) {
        self.id = id
        self.name = name
        self.subscriptionURL = subscriptionURL
        self.rules = rules
        self.remoteRuleSets = remoteRuleSets
    }
}

struct ConfigBar: View {
    @Binding private var config: ConfigProfile
    @State private var isEditing = false
    @State private var isConfirmingDeletion = false

    private let isSelected: Bool
    private let onDelete: () -> Void
    private let onRefresh: () -> Void
    private let onCommit: () -> Void
    private let onSelect: () -> Void

    init(
        config: Binding<ConfigProfile>,
        isSelected: Bool,
        onDelete: @escaping () -> Void = {},
        onRefresh: @escaping () -> Void = {},
        onCommit: @escaping () -> Void = {},
        onSelect: @escaping () -> Void
    ) {
        self._config = config
        self.isSelected = isSelected
        self.onDelete = onDelete
        self.onRefresh = onRefresh
        self.onCommit = onCommit
        self.onSelect = onSelect
    }

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onSelect) {
                Text(config.name)
                    .font(.headline.weight(isSelected ? .bold : .semibold))
                    .foregroundStyle(isSelected ? Color.green : Color.primary)
                    .shadow(
                        color: isSelected ? Color.green.opacity(0.25) : .clear,
                        radius: isSelected ? 5 : 0
                    )
                    .lineLimit(2)
                    .minimumScaleFactor(0.65)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.plain)
            .accessibilityLabel(config.name)
            .accessibilityValue(isSelected ? "Selected" : "Not selected")

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Refresh \(config.name)")

            Button {
                isEditing = true
            } label: {
                Image(systemName: "pencil")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(config.name)")
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .animation(.smooth(duration: 0.22), value: isSelected)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .environment(\.defaultMinListRowHeight, 52)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                isConfirmingDeletion = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
        }
        .alert("Delete Config?", isPresented: $isConfirmingDeletion) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \(config.name)? This action cannot be undone.")
        }
        .navigationDestination(isPresented: $isEditing) {
            ConfigEditorView(config: $config, onCommit: onCommit)
        }
    }
}

struct ConfigEditorView: View {
    @Binding var config: ConfigProfile
    var onCommit: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SwiftUI.Form {
            Section("Config") {
                TextField("Name", text: $config.name)
                TextField("Subscribe URL (Optional)", text: $config.subscriptionURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section("Routing Rules") {
                ForEach($config.rules) { $rule in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Picker("Match", selection: $rule.matchKind) {
                                ForEach(RouteMatchKind.allCases) { Text($0.rawValue).tag($0) }
                            }
                            Picker("Route", selection: $rule.target) {
                                ForEach(RouteTarget.allCases) { Text($0.rawValue.capitalized).tag($0) }
                            }
                        }
                        TextField("Domain, CIDR, or rule-set tag", text: $rule.value)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Toggle("Enabled", isOn: $rule.enabled)
                    }
                }
                .onDelete { config.rules.remove(atOffsets: $0) }

                Button {
                    config.rules.append(StoredRouteRule(matchKind: .domainSuffix, value: "", target: .proxy))
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
            }

            Section("Remote Rule Sets") {
                ForEach($config.remoteRuleSets) { $ruleSet in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Tag", text: $ruleSet.tag)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("URL", text: $ruleSet.url)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        HStack {
                            Picker("Format", selection: $ruleSet.format) {
                                Text("Binary").tag("binary")
                                Text("Source JSON").tag("source")
                            }
                            TextField("Update", text: $ruleSet.updateInterval)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }
                }
                .onDelete { config.remoteRuleSets.remove(atOffsets: $0) }

                Button {
                    config.remoteRuleSets.append(StoredRemoteRuleSet(tag: "", url: ""))
                } label: {
                    Label("Add Remote Rule Set", systemImage: "plus")
                }
            }
        }
        .navigationTitle("Edit Config")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    onCommit()
                    dismiss()
                }
                .disabled(config.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

private struct ConfigBarPreview: View {
    @State private var selectedConfigID: ConfigProfile.ID?
    @State private var configs = [
        ConfigProfile(name: "Proxy"),
        ConfigProfile(name: "Direct"),
        ConfigProfile(name: "Block Ads")
    ]

    var body: some View {
        NavigationStack {
            Form {
                ForEach($configs) { $config in
                    ConfigBar(
                        config: $config,
                        isSelected: selectedConfigID == config.id,
                        onDelete: {
                            configs.removeAll { $0.id == config.id }
                            if selectedConfigID == config.id {
                                selectedConfigID = nil
                            }
                        }
                    ) {
                        selectedConfigID = config.id
                    }
                }
            }
            .padding(.top)
        }
    }
}

#Preview {
    ConfigBarPreview()
}
