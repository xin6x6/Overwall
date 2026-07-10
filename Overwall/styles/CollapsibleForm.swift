//
//  CollapsibleForm.swift
//  Overwall
//
//  Created by Ng1nx on 7/10/26.
//

import SwiftUI

struct CollapsibleForm<Content: View>: View {
    let title: LocalizedStringKey
    private let collapsedHeight: CGFloat

    @State private var isExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let onEdit: () -> Void
    private let content: Content

    init(
        _ title: LocalizedStringKey,
        initiallyExpanded: Bool = true,
        collapsedHeight: CGFloat = 52,
        onEdit: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self._isExpanded = State(initialValue: initiallyExpanded)
        self.collapsedHeight = collapsedHeight
        self.onEdit = onEdit
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .top) {
            Form(
                height: isExpanded ? nil : collapsedHeight,
                verticalContentMargin: 4
            ) {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .listRowInsets(EdgeInsets())
                    .environment(\.defaultMinListRowHeight, 44)
                    .accessibilityHidden(true)

                if isExpanded {
                    content
                }
            }
            .environment(\.defaultMinListRowHeight, collapsedHeight)

            header
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .padding(.leading, 32)
                .padding(.trailing, 28)
                .padding(.top, 4)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(expansionAnimation) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))

                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 12)
                }
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse" : "Expand")
            .accessibilityValue(Text(title))

            Button(action: onEdit) {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit details")
            .accessibilityValue(Text(title))
        }
    }

    private var expansionAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.24)
    }
}

private struct CollapsibleFormPreview: View {
    @State private var isEnabled = false

    var body: some View {
        CollapsibleForm(
            "VPN Configuration",
            onEdit: {}
        ) {
            Toggle("Enable VPN", isOn: $isEnabled)
            LabeledContent("Routing", value: "Config")
        }
    }
}

#Preview {
    CollapsibleFormPreview()
}
