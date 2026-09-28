//
//  ReactionBarView.swift
//  Locolo
//
//  Compact emoji reaction strip for immersive feed / detail.
//

import SwiftUI

struct ReactionBarView: View {
    let assetId: UUID
    var compact: Bool = false

    @ObservedObject private var store = ReactionStore.shared

    var body: some View {
        if store.available {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: compact ? 6 : 8) {
                    ForEach(ReactionStore.palette, id: \.self) { emoji in
                        let count = store.summaries[assetId]?[emoji] ?? 0
                        let mine = store.mine[assetId] == emoji
                        Button {
                            ARHaptics.tick()
                            Task { await store.toggle(assetId: assetId, emoji: emoji) }
                        } label: {
                            HStack(spacing: 3) {
                                Text(emoji)
                                    .font(compact ? .caption : .subheadline)
                                if count > 0 {
                                    Text("\(count)")
                                        .font(.caption2.weight(.bold).monospacedDigit())
                                }
                            }
                            .padding(.horizontal, compact ? 7 : 9)
                            .padding(.vertical, compact ? 4 : 6)
                            .background(
                                Capsule()
                                    .fill(mine ? Color.white.opacity(0.28) : Color.white.opacity(0.12))
                            )
                            .overlay(
                                Capsule().strokeBorder(Color.white.opacity(mine ? 0.55 : 0.18), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("React \(emoji)")
                    }
                }
            }
        }
    }
}
