# LOCOLO V2 — Roadmap: Social Depth · Marketplace · Web3

> **Audience:** AI agents and humans planning the next phase.
> **Companion specs:** `LOCOLO_V2_MARKETPLACE.md` (blockchain/trading/payments/portfolio), `LOCOLO_V2_SOCIAL_AND_UI.md` (social features + Gen-Z design), `LOCOLO_V2_SECURITY.md` (security & compliance).
> **Builds on:** `LOCOLO_AR_STATUS.md` (what exists today — read it first). V1 = a working AR social app; V2 = make it feel like a real social network and add a real-world-asset marketplace with crypto-secured trading.
> **Status (2026-09-28):** **Client ship-ready** (stage 19, uncommitted). **CLAUDE: ACTION REQUIRED** — apply §5.10–§5.28 SQL. Remaining external: partner onramp keys, contract audit, App Store legal, APNs, Firebase SA, Widget Extension target, device QA. Plan: `LOCOLO_V2_COMPLETION_PLAN.md`.

---

## 1. The vision

Locolo is "Instagram for real life": people leave 3D art at real GPS coordinates, and others discover it in AR. V2 turns each placed asset into something you can **collect, trade, and truly own** — while making the social layer deep enough to retain a Gen-Z audience.

Three pillars, designed to reinforce each other:

1. **Social depth** — the loops that make people come back daily: stories, remixes, collections, hashtags, leaderboards, gamified Explorer Passport, richer chat. (`LOCOLO_V2_SOCIAL_AND_UI.md`)
2. **Marketplace + Web3** — mint an AR creation as an NFT, list/auction/offer, trade it with **USDC on an L2 chain**, creator royalties enforced on-chain, provenance you can verify. Fiat on-ramp via Apple Pay. **Portfolio graphs** for what you own. (`LOCOLO_V2_MARKETPLACE.md`)
3. **Security & trust** — the non-negotiable foundation once money and keys are involved: wallet key custody, smart-contract safety, AML/KYC posture, fraud/wash-trade defense, content/IP moderation, and the App Store + regulatory minefield. (`LOCOLO_V2_SECURITY.md`)

## 2. Why these fit together

The AR-at-a-real-place mechanic is the moat. A generic NFT marketplace is a commodity; **"own the AR dragon that lives on top of the Sydney Opera House"** is not. Scarcity is naturally geographic (a place can hold only so much curated art), discovery is physical (you had to *be there*), and provenance is social (who found it, who owned it). Trading gives creators real income → more/better drops → more reasons to explore → more trades. The graphs make ownership feel like an asset class, which is the Gen-Z crypto-native hook.

## 3. The hard decisions (resolve before building the marketplace)

These are called out in detail in the marketplace/security specs; collected here so they aren't missed. Each has a **recommended default** so work can start.

| # | Decision | Recommended default | Why / risk |
|---|---|---|---|
| D1 | **Chain** | **Base** (Ethereum L2) | Cheap, EVM, Coinbase on-ramp + Smart Wallet, consumer momentum. Alt: Polygon PoS (mature NFT tooling). |
| D2 | **Wallet model** | **Embedded smart wallet** (Coinbase Smart Wallet or Privy) — passkey/email login, no seed phrase, gasless via paymaster | Seed-phrase self-custody kills mainstream conversion. MPC/smart-wallet = web2 UX, web3 ownership. |
| D3 | **Trade currency** | **USDC** (settlement) + sponsored gas | Price stability for a consumer marketplace; a volatile native token as the unit of account is a bad UX. |
| D4 | **Custody** | **Non-custodial** (user's smart wallet holds NFTs/funds); Locolo never holds keys | Custodial = money-transmitter licensing + honeypot liability. Non-custodial sidesteps the worst of it. |
| D5 | **Marketplace protocol** | **Seaport** (signature-based listings/offers, gasless to list) or a minimal audited escrow | Don't hand-roll settlement. Seaport is battle-tested. |
| D6 | **Minting** | **Lazy mint** (mint on first sale; metadata on IPFS via a pinning service) | Creators shouldn't pay gas to list something that may never sell. |
| D7 | **Native LOCOLO token?** | **No, not in V2** | A token is a securities/regulatory/ops black hole. Points/XP (off-chain) give the gamification without the legal exposure. Revisit post-scale. |
| D8 | **Fiat on-ramp** | **Coinbase Onramp** or **MoonPay** (card/Apple Pay → USDC into the user's wallet) | Keeps Locolo out of the money-transmission path. |
| D9 | **App Store compliance** | Treat tradable assets as **real-world-anchored collectibles/experiences** (guideline 3.1.3(e) "goods & services outside the app"), crypto via **approved-exchange** rails (3.1.5(b)). **Requires legal review before submission.** | This is the single biggest launch risk. Pure in-app digital goods would trigger 30% IAP; the real-world/AR-experience framing + external crypto exchange is the intended path but is not guaranteed. |
| D10 | **KYC** | Rely on the **on-ramp/exchange partner's KYC**; add Locolo-side KYC only above a payout threshold | Minimizes Locolo's own compliance burden early. |

## 4. Phasing

Marketplace is gated on decisions above and on security work; build in this order so nothing ships half-secure.

- **Phase A — Marketplace foundation (off-chain first):** wallet linking, a real listings/auction/offer model on top of the existing `offers`/`price_history` tables, **portfolio graphs** (Swift Charts, using data we already have), and the trading UI — all settling **off-chain in the DB ledger** initially. Ships value without the chain risk. (Marketplace spec §Phase A)
  - **DB: ✅ applied** (`2026_v2_marketplace_phase_a.sql`). Mint/coupons/provenance SQL in repo — **CLAUDE: ACTION REQUIRED** apply §5.10 (owner deferred).
  - **Product UI: 🟡 coded** (list/buy/cancel, provenance, portfolio chart) — uncommitted, build green.
  - **Mint paywall Swift: 🟡 coded** — uncommitted; prod coupons wait on §5.10.
- **Phase B — Fiat payments:** 🟡 foundation coded — `payment_intents` / `create_payment_intent` SQL (§5.18) + `PaymentService`; paid mint creates a pending intent. **Needs** `onramp-session` edge fn + partner keys for Apple Pay / card.
- **Phase C — On-chain:** 🟡 foundation coded — `nft_tokens` / `link_wallet` SQL (§5.19) + `WalletService` (Settings link). **Needs** embedded wallet SDK, Locolo721 + Seaport audit, indexer webhook.
- **Phase D — Social depth:** 🟢 client complete through Tier 2–3 (remix/react/polls/presence/events/mute/CF + polish). **CLAUDE: ACTION REQUIRED** apply §5.11–§5.17 + §5.20 + §5.22. Plan: `LOCOLO_V2_COMPLETION_PLAN.md`.
- **Cross-cutting — Security:** each phase has a security gate it must pass (Security spec §Gates).

## 5. How V2 maps onto today's code

| V2 area | Reuses / extends |
|---|---|
| Portfolio graphs | `price_history` table (exists), `current_value`/`bought_price`/`highest_offer` on `DigitalAsset`, Swift Charts already in `ARCreatorDashboardView` |
| Listings/auctions/offers | `offers` table + `OfferRepository` + `OfferViewModel` (exists; extend, don't replace) |
| Wallet / trades | new — `Services/Wallet*`, `Services/TradeRepository`, new tables (marketplace spec) |
| Trading UI | new tab or extend Creator Studio + `AssetDetailSheet` buy/offer section (the Buy Now stub was removed in v1 — reinstate as a real crypto/fiat flow) |
| Social features | extend `EngagementStore`, `ActivityStore`, feed cards, `ARExploreView`, notifications triggers |
| Gen-Z UI | extend `ARComponents.swift`, `ARDesign.swift`, `ARSocialComponents.swift` |
| Security | extend the applied RLS migrations; new financial-data isolation; smart-contract layer |

## 6. Guiding principles

- **Custody-light, compliance-light where legal.** Every gram of custody or KYC we can push to a partner is regulatory surface we don't carry.
- **Off-chain first, on-chain when it earns its complexity.** Users feel the product before we take on gas, reorgs, and indexer lag.
- **The chain is an implementation detail to the user.** No seed phrases, no "gwei", no manual gas. Passkey in, USDC balance shown as "$", "Buy" and "Sell" buttons.
- **Real-world value is the differentiator.** Keep leaning on place + AR + provenance, not generic PFP-NFT tropes.
- **Money changes the threat model.** Nothing in Phase B/C ships without passing its Security gate.
