//
//  AssetPollCard.swift
//  Locolo
//
//  Compact poll vote UI for asset detail (§5.20).
//

import SwiftUI

struct AssetPollCard: View {
    let poll: AssetPoll

    @ObservedObject private var store = PollStore.shared

    private var total: Int { max(1, poll.counts.reduce(0, +)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(poll.question)
                .font(.caption.weight(.bold))
                .foregroundColor(.white)
            ForEach(Array(poll.options.enumerated()), id: \.offset) { idx, option in
                let count = idx < poll.counts.count ? poll.counts[idx] : 0
                let pct = Double(count) / Double(total)
                let mine = poll.myVote == idx
                Button {
                    ARHaptics.tick()
                    Task { await store.vote(pollId: poll.id, assetId: poll.assetId, optionIdx: idx) }
                } label: {
                    ZStack(alignment: .leading) {
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(mine ? 0.28 : 0.12))
                                .frame(width: geo.size.width * pct)
                        }
                        HStack {
                            Text(option)
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Text("\(count)")
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    }
                    .frame(height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(mine ? 0.5 : 0.15), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .foregroundColor(.white)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.08)))
    }
}
