//
//  Extensions.swift
//  Overwall
//
//  Created by Ng1nx on 7/10/26.
//

import SwiftUI

extension Color {
    static let background = Color.gray.opacity(0.1)
}

/// A native SwiftUI form presented on the same glass surface as `GlassCard`.
///
/// The content is still hosted by `SwiftUI.Form`, so controls, sections,
/// scrolling, keyboard handling, accessibility, and form styles keep their
/// system behavior.
struct Form<Content: View>: View {
    private let content: Content
    private let heightOverride: CGFloat?
    private let verticalContentMargin: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fittedHeight: CGFloat?
    @State private var maximumHeight: CGFloat?

    init(
        height: CGFloat? = nil,
        verticalContentMargin: CGFloat = 8,
        @ViewBuilder content: () -> Content
    ) {
        self.heightOverride = height
        self.verticalContentMargin = verticalContentMargin
        self.content = content()
        self._fittedHeight = State(initialValue: height)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)

        SwiftUI.Form {
            content
                .listRowBackground(Color.clear)
        }
        .scrollContentBackground(.hidden)
        .contentMargins(.vertical, verticalContentMargin, for: .scrollContent)
        .background(Color.clear)
        .clipShape(shape)
        .onScrollGeometryChange(for: FormScrollMetrics.self) { geometry in
            FormScrollMetrics(
                contentHeight: geometry.contentSize.height,
                containerHeight: geometry.containerSize.height,
                isContentMeasured: geometry.contentSize.height > 1
            )
        } action: { _, metrics in
            updateHeight(using: metrics)
        }
        .frame(height: heightOverride ?? fittedHeight)
        .frame(maxWidth: .infinity)
        .compatibleGlassSurface(cornerRadius: 30)
        .padding(.horizontal)
    }

    private func updateHeight(using metrics: FormScrollMetrics) {
        // A fixed height represents a temporary collapsed presentation. Keep
        // the last measured expanded height so reopening can begin
        // immediately without waiting for another geometry callback.
        guard heightOverride == nil else {
            return
        }

        // A Form can emit an empty geometry value during its first layout
        // pass. Leaving the frame unconstrained gives its rows room to lay
        // out and produce the real content size on the following pass.
        guard metrics.isContentMeasured, metrics.containerHeight > 1 else {
            return
        }

        if maximumHeight == nil {
            // The first unconstrained layout is the height offered by the
            // parent. Preserve it as the point where Form starts scrolling.
            maximumHeight = metrics.containerHeight
        }

        let availableHeight = maximumHeight ?? metrics.containerHeight
        let nextHeight = min(metrics.contentHeight, availableHeight)

        if fittedHeight == nil || abs((fittedHeight ?? 0) - nextHeight) > 0.5 {
            if fittedHeight == nil || reduceMotion {
                fittedHeight = nextHeight
            } else {
                withAnimation(.smooth(duration: 0.24)) {
                    fittedHeight = nextHeight
                }
            }
        }
    }
}

private struct FormScrollMetrics: Equatable {
    let contentHeight: CGFloat
    let containerHeight: CGFloat
    let isContentMeasured: Bool
}

extension View {
    @ViewBuilder
    func compatibleGlassSurface(
        cornerRadius: CGFloat,
        tint: Color? = nil
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(iOS 26.0, *) {
            if let tint {
                self
                    .background(tint.opacity(0.16), in: shape)
                    .glassEffect(in: shape)
            } else {
                self.glassEffect(in: shape)
            }
        } else {
            self
                .background {
                    shape.fill(.ultraThinMaterial)

                    if let tint {
                        shape.fill(tint.opacity(0.16))
                    }
                }
                .overlay {
                    shape.stroke(.white.opacity(0.14), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        }
    }
}
