# LOCOLO V2 — Security, Trust & Compliance Requirements

> The foundation everything else stands on once money, keys, and real-world location are involved. Read with `LOCOLO_V2_MARKETPLACE.md`. Extends the applied V1 hardening (RLS on all tables, E2E chat, blocks/reports, account deletion — `LOCOLO_AR_STATUS.md` §4.6/4.7).
> **Rule:** no Phase B/C code ships until it passes the matching **Gate** in §12.

---

## 1. Threat model (who we defend against)
- **Curious/malicious users** — reading others' data, spoofing identity, forging ownership/hype/offers, scraping location.
- **Fraudsters** — wash trading, fake volume, sybil accounts, stolen-card on-ramp, chargebacks, fake royalties.
- **Attackers** — smart-contract exploits, wallet drainers/phishing, API abuse, key theft.
- **Bad content actors** — CSAM, IP theft (uploading others' 3D models), harassment, unsafe real-world placements (private property, dangerous locations).
- **Us (operational)** — leaked secrets, over-broad service-role use, honeypot custody, insider access.

## 2. Identity & authentication
- **🔴 Close the chat identity gap first (V1 debt).** Firebase auth is anonymous → `senderId` is spoofable. Bind identity: mint a Firebase custom token from the verified Supabase JWT (`uid = supabase user id`) or move chat to Supabase Realtime+RLS, then deploy `firestore.rules`. **Prerequisite for group chat and for any money feature that trusts identity.** (Status §5.8.)
- **MFA** for accounts holding value (TOTP/passkey) — require before first payout or high-value trade.
- **Passkeys** as the primary auth for the embedded wallet (Coinbase Smart Wallet / Privy) — no passwords, no seed phrases.
- **Session hygiene:** short-lived access tokens, refresh rotation, revoke-on-logout (already wipes local state), device list + remote sign-out.
- **App Attest / DeviceCheck** on sensitive endpoints (mint, buy, payout) to blunt scripted abuse; **jailbreak detection** as signal (not hard block).

## 3. Key management (the crown jewels)
- **Wallet keys are NON-CUSTODIAL and never touch Locolo servers.** Embedded smart wallet = passkey-secured / MPC-sharded by the provider; Locolo stores only the public address (`wallets` table).
- **Chat identity key** (X25519) stays in the **Keychain**, `…ThisDeviceOnly`, mint-only-on-`errSecItemNotFound` (already hardened).
- **Signing UX:** every transaction sign shows human-readable intent ("Buy 'Neon Koi' for $25, incl. $1.88 creator royalty") — **transaction simulation** (e.g. Blockaid/Tenderly) before sign to catch drainers; warn on unlimited ERC-20 approvals; prefer per-trade exact approvals.
- **Server secrets** (APNs key, on-ramp keys, service role, RPC provider keys) in Supabase secrets / a vault — never in the repo, never in the client. Rotate on staff changes.

## 4. Backend / data security (extend V1 RLS)
- **RLS on every new table** (`wallets`, `listings`, `bids`, `trades`, `payment_intents`, `portfolio_snapshots`, social tables) — owner-scoped writes, considered reads. Financial rows (`payment_intents`, `payouts`) readable only by their owner; `trades` public for provenance but no counterparty PII beyond handles.
- **Server is the authority for value.** Ownership, balances, listing validity, offer acceptance are validated in edge fns against the DB/chain — **never trust client-submitted price, owner, or fee.** Idempotent, replay-safe (webhooks retry).
- **The chain indexer webhook is the sole writer of confirmed trades/ownership** (Marketplace §2 golden rule). Verify webhook signatures; confirm tx depth before settling.
- **Service-role minimization:** edge fns use least-privilege; no `run_sql`/`exec_sql` exposure (already revoked).
- **Right-to-be-forgotten vs immutable chain:** account deletion removes DB rows (exists) but **cannot delete on-chain history** — disclose this in the privacy policy; store minimal PII on-chain (never email/name — only addresses + token metadata).

## 5. Smart-contract security (Phase C gate)
- **External audit** (e.g. a reputable firm) of `Locolo721` + any custom escrow before mainnet; fix all high/criticals.
- Patterns: **checks-effects-interactions**, reentrancy guards, `SafeERC20`, pull-over-push payouts, integer-safe (Solidity ≥0.8), explicit access control (`AccessControl`), **`Pausable`** kill-switch, event emission for every state change.
- **Upgradeability:** prefer immutable contracts + migration over a rushed proxy; if a proxy, use audited OpenZeppelin UUPS with a timelock + multisig admin.
- **Admin keys in a multisig** (Gnosis Safe), never a single EOA; timelock on privileged ops.
- **Testnet burn-in** on Base Sepolia; **bug bounty** (Immunefi) before/at mainnet; monitored via Tenderly alerts.
- Royalty enforcement: EIP-2981 + marketplace-level enforcement; document that some venues ignore royalties.

## 6. Payment security (Phase B gate)
- **PCI scope = zero.** Card data never touches Locolo — Stripe/on-ramp partner handles it; we store only their reference (`payment_intents.provider_ref`).
- **Webhook signature verification** on all payment callbacks; idempotency keys; reconcile against provider as source of truth.
- **Chargeback/refund policy** for fiat; escrow release only after payment settles (not on intent creation).
- **Payouts:** MFA-gated, velocity limits, holdback window for new sellers, sanctions screening via the payout partner.

## 7. Anti-fraud & market integrity
- **Wash-trading detection:** flag trades between linked wallets/accounts (shared funding source, rapid round-trips, self-follow graphs); exclude suspected wash volume from public stats and leaderboards.
- **Sybil resistance:** device/App Attest signals, phone/email verification for payouts, rate limits on account creation.
- **Bot/scripting defense:** rate limits + App Attest on mint/buy/list; anomaly alerts on volume spikes.
- **Price-manipulation guards:** sanity-bound listings (e.g. block obviously fat-fingered 1000× floor), cool-downs, display "est. value" basis honestly (Marketplace §7).
- **Bid/escrow integrity:** funds locked on bid, released on outbid/expire; no double-spend of escrow.

## 8. Content, IP & real-world safety
- **Upload moderation:** scan uploaded models/thumbnails/media (hash-match + ML) for CSAM (report per legal obligation), nudity, violence; **IP/copyright** checks (this is a *creation* marketplace — stolen 3D models are a real risk). DMCA takedown flow + repeat-infringer policy.
- **Provenance ≠ authenticity:** minting doesn't prove the creator made it — surface reporting + takedown; verified-creator program for trust.
- **Real-world placement safety:** block/flag placements on private property, hazardous or sensitive locations (schools, critical infrastructure); "unsafe_location" report reason already exists — wire enforcement.
- **Moderation ops:** `content_reports` queue reviewed daily (exists); add comment/asset/user/trade report types; appeals; audit log of moderator actions.

## 9. Privacy (heightened — AR = precise location + camera)
- **Location is sensitive.** Precise GPS + a social graph is a stalking risk. Coarsen public location where possible; never expose a user's real-time position; presence/"nearby" is opt-in and fuzzed; let users hide a placement's exact spot until discovered.
- **Camera/photos:** on-device only unless the user shares; snapshots uploaded only on explicit share.
- **Data minimization on-chain** (see §4). **GDPR/CCPA:** export + delete (delete exists); consent for analytics; DPA with processors (Supabase, Firebase, on-ramp, indexer).
- **Minors:** if under-13/16 possible, COPPA/GDPR-K obligations — recommend **16+ (or 18+ for trading)** with age gate; crypto/payments strongly imply 18+.

## 10. App & infra hardening
- Certificate pinning on API calls; ATS enforced; no secrets in the bundle (`Secrets.swift` gitignored — keep it that way).
- Rate limiting / WAF on public endpoints; abuse monitoring + alerting; structured audit logs for financial and moderation actions.
- Dependency scanning (SPM + edge-fn deps); no `SECURITY DEFINER` view/function without a re-applied visibility predicate (V1 lesson — the `digital_assets_flat` fix); pinned `search_path` on all new functions.
- Backups + tested restore; incident-response runbook + on-call; status/comms plan.

## 11. Regulatory & App Store (get legal sign-off — do not guess)
- **App Store (highest launch risk):** NFT sale + crypto is allowed *only* within Apple's narrow rules (3.1.5(b) crypto on approved exchanges; NFT viewing; 3.1.3(e) external goods/services). The **real-world-anchored collectible/experience** framing + external on-ramp is the intended path but **must be legally reviewed**; have a **free/testnet collect mode** so the app is reviewable without the paid rails, and be ready to geo-gate paid trading.
- **Money transmission:** non-custodial + partner on-ramp keeps Locolo out of most MT licensing — **confirm with counsel per jurisdiction.** Platform fee handling may still trigger obligations.
- **Securities:** no native token in V2 (Roadmap D7) avoids the worst of this; NFTs of art are lower-risk but fractionalization/"investment" framing is not — avoid promising returns.
- **AML/KYC/sanctions:** lean on partner KYC; add Locolo KYC above a payout threshold; OFAC screening of addresses; geo-block sanctioned regions.
- **Tax:** provide users a transactions export for their own reporting; 1099-style reporting may apply to payouts (partner-dependent).

## 12. Security gates (a phase cannot ship until its gate passes)
- **Gate A (off-chain marketplace):** RLS on all new tables verified (anon + cross-user probes); server-side ownership/price validation; advisor clean (no new RLS-disabled / SECURITY DEFINER-view findings); wash-trade/self-trade blocked in the ledger.
- **Gate B (fiat):** PCI-zero confirmed (no card data in logs/DB); webhook signatures verified + idempotent; payout MFA + velocity limits; refund/chargeback flow; legal sign-off on the payment model.
- **Gate C (on-chain):** contract audit passed (no open highs/criticals); testnet burn-in; multisig + timelock admin; tx simulation + approval hygiene in the signing UX; indexer-webhook is the sole settlement writer with signature verification; bug bounty live.
- **Cross-cutting (before public launch):** chat identity binding done (§2); upload CSAM/IP moderation live; location-privacy defaults on; age gate; incident-response runbook; privacy policy + DPAs covering location, camera, chat E2E, crypto, deletion.

## 13. Priority order
1. **Chat identity binding** (unblocks trust for everything; already the last 🔴 in V1).
2. **Gate-A backend security** for the off-chain marketplace (RLS + server authority + anti-self-trade).
3. **Content/IP/CSAM moderation pipeline** (needed the moment uploads have monetary value).
4. **Payment security** (Gate B) with legal review of the App Store + MT model.
5. **Smart-contract audit + on-chain hardening** (Gate C).
6. **Location-privacy hardening** and **anti-fraud/wash-trade** — continuous, but must meet the gates above at each phase.
