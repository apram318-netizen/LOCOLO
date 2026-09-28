//
//  PayoutsCard.swift
//  Locolo
//
//  Phase B creator payout history (read-only). Cash-out writes come from the
//  partner webhook after §5.18 + off-ramp are live.
//

import SwiftUI

struct PayoutsCard: View {
    @State private var rows: [PaymentService.PayoutRow] = []
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Payouts", systemImage: "banknote")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("Cash-out via partner")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
            }

            if !loaded {
                ProgressView().tint(.purple)
            } else if rows.isEmpty {
                Text(PaymentService.shared.available
                     ? "No payouts yet — earnings stay in your portfolio until you cash out."
                     : "Payout history appears after §5.18 SQL is applied.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(rows.prefix(5)) { row in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(format: "$%.2f %@", row.amount, row.currency))
                                .font(.subheadline.weight(.semibold))
                            Text(row.provider)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(row.status.capitalized)
                            .font(.caption.weight(.bold))
                            .foregroundColor(row.status == "paid" ? .green : .secondary)
                        Text(row.createdAt.shortRelative)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Button {
                // Partner off-ramp — no client insert (RLS SELECT-only).
            } label: {
                Text("Request cash-out · coming soon")
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.purple.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .disabled(true)
        }
        .padding(14)
        .arGlassCard(cornerRadius: 16)
        .task {
            rows = await PaymentService.shared.listPayouts()
            loaded = true
        }
    }
}
