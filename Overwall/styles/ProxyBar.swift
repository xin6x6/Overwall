//
//  ProxyBar.swift
//  Overwall
//
//  Created by Ng1nx on 7/10/26.
//

import SwiftUI

struct ProxyNode: Identifiable, Hashable {
    let id: UUID
    var countryCode: String
    var name: String
    var server: String
    var port: Int
    var protocolName: String
    var latencyMilliseconds: Int?
    var speedMegabytesPerSecond: Double?

    init(
        id: UUID = UUID(),
        countryCode: String,
        name: String,
        server: String = "",
        port: Int = 443,
        protocolName: String = "Shadowsocks",
        latencyMilliseconds: Int? = nil,
        speedMegabytesPerSecond: Double? = nil
    ) {
        self.id = id
        self.countryCode = countryCode
        self.name = name
        self.server = server
        self.port = port
        self.protocolName = protocolName
        self.latencyMilliseconds = latencyMilliseconds
        self.speedMegabytesPerSecond = speedMegabytesPerSecond
    }
}

struct ProxyBar: View {
    @Binding private var node: ProxyNode
    @State private var isEditing = false
    @State private var isConfirmingDeletion = false
    private let isSelected: Bool
    private let onDelete: () -> Void
    private let onSelect: () -> Void

    init(
        node: Binding<ProxyNode>,
        isSelected: Bool,
        onDelete: @escaping () -> Void = {},
        onSelect: @escaping () -> Void
    ) {
        self._node = node
        self.isSelected = isSelected
        self.onDelete = onDelete
        self.onSelect = onSelect
    }

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onSelect) {
                HStack(spacing: 8) {
                    countryIcon

                    Text(node.name)
                        .font(.headline.weight(isSelected ? .bold : .semibold))
                        .foregroundStyle(isSelected ? selectedHighlightColor : Color.primary)
                        .shadow(
                            color: isSelected ? selectedHighlightColor.opacity(0.25) : .clear,
                            radius: isSelected ? 5 : 0
                        )
                        .lineLimit(2)
                        .minimumScaleFactor(0.65)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    connectionMetrics
                }
                .contentShape(Rectangle())
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.plain)
            .accessibilityLabel(node.name)
            .accessibilityValue(isSelected ? "Selected" : "Not selected")

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
            .accessibilityLabel("Edit \(node.name)")
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
        .alert("Delete Proxy?", isPresented: $isConfirmingDeletion) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \(node.name)? This action cannot be undone.")
        }
        .navigationDestination(isPresented: $isEditing) {
            ProxyNodeEditorView(node: $node)
        }
    }

    private var countryIcon: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.1))

            if let flag = node.countryCode.flagEmoji {
                Text(flag)
                    .font(.system(size: 21))
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.tint)
            }
        }
        .frame(width: 32, height: 32)
        .accessibilityHidden(true)
    }

    private var connectionMetrics: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: "timer")
                    .foregroundStyle(.secondary)

                Text(latencyText)
                    .foregroundStyle(latencyColor)
            }

            HStack(spacing: 3) {
                Image(systemName: "arrow.down")
                    .foregroundStyle(.secondary)

                Text(speedText)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption2.monospacedDigit())
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(2)
        .accessibilityElement(children: .combine)
    }

    private var latencyText: String {
        node.latencyMilliseconds.map { "\($0) ms" } ?? "-- ms"
    }

    private var latencyColor: Color {
        guard let latency = node.latencyMilliseconds else {
            return .secondary
        }

        switch latency {
        case ..<1500:
            return .green
        case 1500..<2000:
            return .yellow
        case 2000..<3000:
            return .orange
        default:
            return .red
        }
    }

    private var selectedHighlightColor: Color {
        node.latencyMilliseconds == nil ? .green : latencyColor
    }

    private var speedText: String {
        guard let speed = node.speedMegabytesPerSecond else {
            return "-- MB/s"
        }

        return speed.formatted(.number.precision(.fractionLength(1))) + " MB/s"
    }

}

struct ProxyNodeEditorView: View {
    @Binding var node: ProxyNode
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SwiftUI.Form {
            Section("Node") {
                TextField("Name", text: $node.name)
                TextField("Country code", text: $node.countryCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }

            Section("Server") {
                TextField("Address", text: $node.server)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                TextField("Port", value: $node.port, format: .number)
                    .keyboardType(.numberPad)

                TextField("Protocol", text: $node.protocolName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .navigationTitle("Edit Node")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}

private extension String {
    var flagEmoji: String? {
        let code = trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == 2,
              code.unicodeScalars.allSatisfy({ (65...90).contains(Int($0.value)) }) else {
            return nil
        }

        let scalars = code.unicodeScalars.compactMap {
            UnicodeScalar(127_397 + Int($0.value))
        }
        return String(String.UnicodeScalarView(scalars))
    }
}

private struct ProxyBarPreview: View {
    @State private var selectedNodeID: ProxyNode.ID?
    @State private var nodes = [
        ProxyNode(
            countryCode: "JP",
            name: "Tokyo Premium 01",
            server: "tokyo.example.com",
            latencyMilliseconds: 42,
            speedMegabytesPerSecond: 86.4
        ),
        ProxyNode(
            countryCode: "US",
            name: "Los Angeles 02",
            server: "la.example.com",
            latencyMilliseconds: 2380
        )
    ]

    var body: some View {
        NavigationStack {
            CollapsibleForm("Default", onEdit: {}) {
                ForEach($nodes) { $node in
                    ProxyBar(
                        node: $node,
                        isSelected: selectedNodeID == node.id,
                        onDelete: {
                            nodes.removeAll { $0.id == node.id }
                            if selectedNodeID == node.id {
                                selectedNodeID = nil
                            }
                        }
                    ) {
                        selectedNodeID = node.id
                    }
                }
            }
            .padding(.top)
        }
    }
}

#Preview {
    ProxyBarPreview()
}
