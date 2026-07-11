//
//  AddProxyViews.swift
//  Overwall
//

import SwiftUI

enum ServerType: String, CaseIterable, Identifiable {
    case shadowsocks = "Shadowsocks"
    case vmess = "VMess"
    case vless = "VLESS"

    var id: Self { self }
}

struct ProxyGroupOption: Identifiable, Hashable {
    let id: UUID
    var name: String
    var subscriptionURL: String?

    init(
        id: UUID = UUID(),
        name: String,
        subscriptionURL: String? = nil
    ) {
        self.id = id
        self.name = name
        self.subscriptionURL = subscriptionURL
    }
}

struct ServerDraft {
    var groupID: ProxyGroupOption.ID?
    var name = ""
    var type: ServerType = .shadowsocks
    var address = ""
    var port = "443"
    var password = ""
    var method = "aes-256-gcm"
    var userID = ""
    var alterID = "0"
    var security = "auto"
    var transport = "tcp"
    var tlsMode = "none"
    var serverName = ""
    var host = ""
    var path = ""
    var flow = "none"
    var realityPublicKey = ""
    var realityShortID = ""
    var allowInsecure = false
}

struct GroupDraft {
    var name = ""
    var subscriptionURL = ""

    var resolvedName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            return trimmedName
        }

        let trimmedURL = subscriptionURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return URLComponents(string: trimmedURL)?.host ?? "Subscription"
    }
}

struct AddServerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ServerDraft()

    let groups: [ProxyGroupOption]
    let onAdd: (ServerDraft) -> Void

    init(
        groups: [ProxyGroupOption] = [ProxyGroupOption(name: "Default")],
        onAdd: @escaping (ServerDraft) -> Void = { _ in }
    ) {
        self.groups = groups
        self.onAdd = onAdd
    }

    var body: some View {
        SwiftUI.Form {
            Section("Server") {
                Picker("Group", selection: $draft.groupID) {
                    ForEach(groups) { group in
                        Text(group.name).tag(Optional(group.id))
                    }
                }

                TextField("Name (Optional)", text: $draft.name)

                Picker("Type", selection: $draft.type) {
                    ForEach(ServerType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }

                TextField("Address", text: $draft.address)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField("Port", text: $draft.port)
                    .keyboardType(.numberPad)
            }

            authenticationSection
            transportSection
            tlsSection
        }
        .navigationTitle("Add Server")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    onAdd(draft)
                    dismiss()
                }
                .disabled(!isValid)
            }
        }
        .onChange(of: draft.type) { _, newType in
            applyDefaults(for: newType)
        }
        .onAppear {
            if draft.groupID == nil {
                draft.groupID = groups.first?.id
            }
        }
    }

    @ViewBuilder
    private var authenticationSection: some View {
        switch draft.type {
        case .shadowsocks:
            Section("Authentication") {
                SecureField("Password", text: $draft.password)

                Picker("Method", selection: $draft.method) {
                    ForEach(shadowsocksMethods, id: \.self) { method in
                        Text(method).tag(method)
                    }
                }
            }

        case .vmess:
            Section("Authentication") {
                TextField("UUID", text: $draft.userID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField("Alter ID", text: $draft.alterID)
                    .keyboardType(.numberPad)

                Picker("Security", selection: $draft.security) {
                    ForEach(vmessSecurityMethods, id: \.self) { method in
                        Text(method).tag(method)
                    }
                }
            }

        case .vless:
            Section("Authentication") {
                TextField("UUID", text: $draft.userID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Picker("Flow", selection: $draft.flow) {
                    Text("None").tag("none")
                    Text("XTLS Vision").tag("xtls-rprx-vision")
                }
            }
        }
    }

    private var transportSection: some View {
        Section("Transport") {
            Picker("Network", selection: $draft.transport) {
                Text("TCP").tag("tcp")
                Text("WebSocket").tag("ws")
                Text("gRPC").tag("grpc")
                Text("HTTP").tag("http")
            }

            if draft.transport == "ws" || draft.transport == "http" {
                TextField("Host (Optional)", text: $draft.host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField("Path (Optional)", text: $draft.path)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } else if draft.transport == "grpc" {
                TextField("Service Name (Optional)", text: $draft.path)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
    }

    @ViewBuilder
    private var tlsSection: some View {
        Section("TLS") {
            Picker("Security", selection: $draft.tlsMode) {
                Text("None").tag("none")
                Text("TLS").tag("tls")

                if draft.type == .vless {
                    Text("Reality").tag("reality")
                }
            }

            if draft.tlsMode != "none" {
                TextField("Server Name (SNI)", text: $draft.serverName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Toggle("Allow Insecure", isOn: $draft.allowInsecure)
            }

            if draft.tlsMode == "reality" {
                TextField("Public Key", text: $draft.realityPublicKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField("Short ID", text: $draft.realityShortID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
    }

    private var isValid: Bool {
        let selectedGroupIsValid = groups.contains { $0.id == draft.groupID }
        let addressIsValid = !draft.address.trimmed.isEmpty
        let portIsValid = Int(draft.port).map { (1...65_535).contains($0) } == true

        guard selectedGroupIsValid, addressIsValid, portIsValid else {
            return false
        }

        switch draft.type {
        case .shadowsocks:
            return !draft.password.isEmpty
        case .vmess, .vless:
            guard !draft.userID.trimmed.isEmpty else {
                return false
            }

            if draft.tlsMode == "reality" {
                return !draft.realityPublicKey.trimmed.isEmpty
            }

            return true
        }
    }

    private func applyDefaults(for type: ServerType) {
        switch type {
        case .shadowsocks:
            draft.method = "aes-256-gcm"
            if draft.tlsMode == "reality" {
                draft.tlsMode = "none"
            }
        case .vmess:
            draft.security = "auto"
            if draft.tlsMode == "reality" {
                draft.tlsMode = "none"
            }
        case .vless:
            draft.flow = "none"
        }
    }

    private let shadowsocksMethods = [
        "aes-128-gcm",
        "aes-256-gcm",
        "chacha20-ietf-poly1305",
        "2022-blake3-aes-128-gcm",
        "2022-blake3-aes-256-gcm"
    ]

    private let vmessSecurityMethods = [
        "auto",
        "aes-128-gcm",
        "chacha20-poly1305",
        "none"
    ]
}

struct AddGroupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft = GroupDraft()

    let onAdd: (GroupDraft) -> Void

    init(onAdd: @escaping (GroupDraft) -> Void = { _ in }) {
        self.onAdd = onAdd
    }

    var body: some View {
        SwiftUI.Form {
            Section {
                TextField("Group Name", text: $draft.name)

                TextField("Subscribe URL", text: $draft.subscriptionURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } footer: {
                Text("A group name is optional when a subscribe URL is provided. Leave the URL empty to create a local group.")
            }

            if !draft.subscriptionURL.trimmed.isEmpty && !subscriptionURLIsValid {
                Section {
                    Label("Enter a valid HTTP or HTTPS URL.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Add Group")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    onAdd(draft)
                    dismiss()
                }
                .disabled(!isValid)
            }
        }
    }

    private var isValid: Bool {
        let hasName = !draft.name.trimmed.isEmpty
        let hasSubscriptionURL = !draft.subscriptionURL.trimmed.isEmpty
        return (hasName || hasSubscriptionURL) && subscriptionURLIsValid
    }

    private var subscriptionURLIsValid: Bool {
        let value = draft.subscriptionURL.trimmed
        guard !value.isEmpty else {
            return true
        }

        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }

        return components.host?.isEmpty == false
    }
}

struct EditGroupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var subscriptionURL: String
    let groupID: UUID
    let onSave: (UUID, String, String?) -> Void

    init(group: StoredProxyGroup, onSave: @escaping (UUID, String, String?) -> Void) {
        groupID = group.id
        _name = State(initialValue: group.name)
        _subscriptionURL = State(initialValue: group.subscriptionURL ?? "")
        self.onSave = onSave
    }

    var body: some View {
        SwiftUI.Form {
            Section("Group") {
                TextField("Group Name", text: $name)
                TextField("Subscribe URL (Optional)", text: $subscriptionURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .navigationTitle("Edit Group")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    let url = subscriptionURL.trimmed
                    onSave(groupID, name.trimmed, url.isEmpty ? nil : url)
                    dismiss()
                }
                .disabled(name.trimmed.isEmpty || !subscriptionURLIsValid)
            }
        }
    }

    private var subscriptionURLIsValid: Bool {
        let value = subscriptionURL.trimmed
        guard !value.isEmpty else { return true }
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return false }
        return components.host?.isEmpty == false
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview("Add Server") {
    NavigationStack {
        AddServerView()
    }
}

#Preview("Add Group") {
    NavigationStack {
        AddGroupView()
    }
}
