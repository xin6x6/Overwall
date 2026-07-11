//
//  ConfigBar.swift
//  Dashstar
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
    var generalOptions: [StoredConfigOption] = []
    var isBuiltIn = false

    init(
        id: UUID = UUID(),
        name: String,
        subscriptionURL: String = "",
        rules: [StoredRouteRule] = [],
        remoteRuleSets: [StoredRemoteRuleSet] = [],
        generalOptions: [StoredConfigOption] = [],
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.subscriptionURL = subscriptionURL
        self.rules = rules
        self.remoteRuleSets = remoteRuleSets
        self.generalOptions = generalOptions
        self.isBuiltIn = isBuiltIn
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
            Button {
                InteractionFeedback.selection()
                onSelect()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(config.name)
                        .font(.headline.weight(isSelected ? .bold : .semibold))
                        .foregroundStyle(isSelected ? Color.green : Color.primary)
                    Text("\(config.rules.filter { $0.enabled }.count) enabled rules")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.plain)
            .accessibilityLabel(config.name)
            .accessibilityValue(Text(isSelected ? "Selected" : "Not selected"))

            Button {
                InteractionFeedback.tap()
                onRefresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Refresh \(config.name)")

            Button {
                InteractionFeedback.tap()
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
            if !config.isBuiltIn {
                Button {
                    InteractionFeedback.tap()
                    isConfirmingDeletion = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(.red)
            }
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
    @State private var isAddingRule = false
    @State private var newRule = StoredRouteRule(matchKind: .domainSuffix, value: "", target: .proxy)

    var body: some View {
        SwiftUI.Form {
            Section("Config") {
                TextField("Name", text: $config.name)
                TextField("Subscribe URL (Optional)", text: $config.subscriptionURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section("General") {
                ForEach($config.generalOptions) { $option in
                    HStack(alignment: .firstTextBaseline) {
                        TextField("Option", text: $option.key)
                            .foregroundStyle(.secondary)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .frame(maxWidth: 150)
                        Spacer(minLength: 16)
                        TextField("Value", text: $option.value, axis: .vertical)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
                .onDelete { config.generalOptions.remove(atOffsets: $0) }
                Button("Add General Option", systemImage: "plus") {
                    config.generalOptions.append(StoredConfigOption(key: "option", value: ""))
                }
            }

            Section {
                ForEach($config.rules) { $rule in
                    NavigationLink {
                        RouteRuleEditorView(rule: $rule)
                    } label: {
                        RouteRuleRow(rule: rule)
                    }
                }
                .onDelete { config.rules.remove(atOffsets: $0) }
                .onMove { config.rules.move(fromOffsets: $0, toOffset: $1) }

                Button {
                    newRule = StoredRouteRule(matchKind: .domainSuffix, value: "", target: .proxy)
                    isAddingRule = true
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
            } header: {
                Text("Routing Rules (\(config.rules.count))")
            } footer: {
                Text("Rules are evaluated from top to bottom. FINAL controls traffic that matches no earlier rule.")
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
            ToolbarItem(placement: .topBarLeading) { EditButton() }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    onCommit()
                    dismiss()
                }
                .disabled(config.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .sheet(isPresented: $isAddingRule) {
            NavigationStack {
                RouteRuleEditorView(rule: $newRule, isNew: true) {
                    config.rules.append(newRule)
                    isAddingRule = false
                }
            }
        }
    }
}

private struct RouteRuleRow: View {
    let rule: StoredRouteRule

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: rule.matchKind.icon)
                .foregroundStyle(rule.enabled ? rule.target.color : Color.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.matchKind.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(rule.value)
                    .font(.body)
                    .lineLimit(2)
            }
            Spacer()
            Text(rule.target.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(rule.target.color)
        }
        .opacity(rule.enabled ? 1 : 0.45)
    }
}

private struct RouteRuleEditorView: View {
    @Binding var rule: StoredRouteRule
    var isNew = false
    var onAdd: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Rule") {
                Picker("Type", selection: $rule.matchKind) {
                    ForEach(RouteMatchKind.allCases) { Text($0.title).tag($0) }
                }
                if rule.matchKind != .final {
                    TextField(rule.matchKind.placeholder, text: $rule.value, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Picker("Policy", selection: $rule.target) {
                    ForEach(RouteTarget.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Enabled", isOn: $rule.enabled)
            }
            if rule.matchKind == .userAgent {
                Section { Text("USER-AGENT is preserved for Shadowrocket compatibility, but is not enforced by the current sing-box routing engine.") }
            }
        }
        .navigationTitle(Text(isNew ? "Add Rule" : "Edit Rule"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isNew {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { onAdd() }
                        .disabled(rule.matchKind != .final && rule.value.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

private extension RouteTarget {
    var title: String { self == .block ? "Reject" : rawValue.capitalized }
    var color: Color { self == .proxy ? .blue : (self == .direct ? .green : .red) }
}

private extension RouteMatchKind {
    var title: String {
        switch self {
        case .domain: "Domain"
        case .domainSuffix: "Domain Suffix"
        case .domainKeyword: "Domain Keyword"
        case .ipCIDR: "IP CIDR"
        case .ruleSet: "Rule Set"
        case .geoIP: "GeoIP"
        case .userAgent: "User Agent"
        case .final: "Final"
        }
    }
    var icon: String {
        switch self {
        case .domain, .domainSuffix, .domainKeyword: "globe"
        case .ipCIDR, .geoIP: "network"
        case .ruleSet: "list.bullet.rectangle"
        case .userAgent: "person.text.rectangle"
        case .final: "arrow.down.to.line"
        }
    }
    var placeholder: String {
        switch self {
        case .domain: "example.com"
        case .domainSuffix: "example.com"
        case .domainKeyword: "keyword"
        case .ipCIDR: "192.168.0.0/16"
        case .ruleSet: "rule-set tag"
        case .geoIP: "CN"
        case .userAgent: "Client*"
        case .final: ""
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
