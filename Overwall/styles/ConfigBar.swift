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

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

struct ConfigBar: View {
    @Binding private var config: ConfigProfile
    @State private var isEditing = false
    @State private var isConfirmingDeletion = false

    private let isSelected: Bool
    private let onDelete: () -> Void
    private let onSelect: () -> Void

    init(
        config: Binding<ConfigProfile>,
        isSelected: Bool,
        onDelete: @escaping () -> Void = {},
        onSelect: @escaping () -> Void
    ) {
        self._config = config
        self.isSelected = isSelected
        self.onDelete = onDelete
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
            ConfigEditorView(config: $config)
        }
    }
}

struct ConfigEditorView: View {
    @Binding var config: ConfigProfile
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SwiftUI.Form {
            Section("Config") {
                TextField("Name", text: $config.name)
            }
        }
        .navigationTitle("Edit Config")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
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
