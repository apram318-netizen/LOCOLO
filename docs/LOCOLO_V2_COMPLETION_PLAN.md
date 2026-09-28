# LOCOLO V2 — Completion Plan (social · marketplace · polish · UX)

> Living plan. Owner applies SQL later (**CLAUDE: ACTION REQUIRED** markers in `LOCOLO_AR_STATUS.md` §5.10–§5.28). Client degrades until applied.
> Last updated: 2026-09-28 (stage 19 — **client ship-ready**; remaining work is owner/external).

---

## 0. Status snapshot

| Pillar | Client | SQL / infra | Blockers outside repo |
|---|---|---|---|
| Phase A marketplace | 🟢 list/buy/auction + post-trade refresh + payouts read UI | ✅ A applied; 🟡 §5.21 + §5.26 | — |
| Phase B fiat | 🟢 intent + `onramp-session` client wiring | 🟡 §5.18 | Partner keys, legal |
| Phase C on-chain | 🟡 foundation + edge stub | 🟡 §5.19 | Wallet SDK, audit |
| Phase D social Tier 1–3 | 🟢 complete | 🟡 §5.11–§5.17 + §5.20 + §5.22 | Apply SQL |
| AR polish | 🟢 stage 18+ triggers/clip/brushes/Live Activity | 🟡 §5.28 trigger CHECK | Device QA; Widget target |
| Gen-Z UX | 🟢 rails / HoloCard / Activity V2 filters | n/a | — |
| Engineering health | 🟢 Logger + Crashlytics/Analytics + LocoloTests + AR log hygiene | 🟡 §5.27 storage | Deploy edges; dSYM |
| Security gates B/C | docs only | — | Legal + audit |

**Dev-stage client work: complete.** Nothing else to code for ship except owner unlocks + post-ship polish (weather trigger, App Clip, park legacy).

---

## 1. Owner must-do (unlock everything already built)

1. Apply SQL in order: §5.10 → … → §5.28 (include **§5.28 trigger types** before QA mints with gaze/long-press/etc.).
2. Commit + push uncommitted V2 tree to `github/fresh-start`.
3. Device QA matrix (status §5.7 + mint/`LOCOLO100`, auctions, clip→Story, new triggers).
4. APNs + `send-push` + `push_enabled` (§5.3c); Firebase SA + Admin mint (§5.8).
5. Xcode Widget Extension target `LocoloWidgets`; run `LocoloTests`.
6. Deploy edges: `onramp-session`, `chain-webhook`, `snapshot-portfolio`, `firebase-custom-token`, `purge-storage`, embeds.

---

## 2. Phase completion checklist

### Phase A — Off-chain marketplace
- [x] Listings / buy / provenance / portfolio chart (client)
- [x] Post-buy asset refresh (client)
- [ ] Apply mint SQL §5.10
- [x] Auctions UI + place bid (client; settle via §5.21 RPC)
- [x] Portfolio studio surface
- [x] `snapshot-portfolio` edge stub
- [ ] Apply auction RPCs §5.21
- [ ] Apply owner_id RPCs §5.26

### Phase B — Fiat
- [x] `payment_intents` / `create_payment_intent` + `PaymentService`
- [x] Paid mint → intent + `startCheckout` → `onramp-session` (opens URL when partner returns one)
- [x] Edge stub `onramp-session`
- [x] Creator payouts **read** UI
- [ ] Live Apple Pay / Coinbase Onramp keys + webhook → succeed intent → mint/buy
- [ ] Legal sign-off (Roadmap D9)

### Phase C — On-chain
- [x] `nft_tokens` / `link_wallet` / Settings wallet
- [x] Edge stub `chain-webhook`
- [ ] Embedded wallet SDK / Locolo721 + Seaport audit / paymaster / indexer

### Phase D — Social (client complete)
Tier 1–3 + Activity V2 filter chips (Social / Sales). Group chat scaffold only (§5.23).

---

## 3. Amazing UX / polish — client done

All stage-18 AR polish + stage-19: Activity V2 filters, AR location usage copy, hot-path `LocoloLog` (no GPS in logs), Phase B checkout client, post-trade refresh, §5.28 trigger CHECK SQL.

**Deferred (not ship blockers):** weather trigger, multi-step sequences, App Clip, Widget Extension target, park legacy screens, localization.

---

## 4. Engineering / trust

| Item | Status |
|---|---|
| Unit tests | ✅ `LocoloTests` target + sources |
| `LocoloLog` | ✅ hot AR/mint paths migrated |
| Crashlytics + Analytics | ✅ SPM + façade |
| Storage cleanup | ✅ §5.27 SQL + purge edge |
| Trigger CHECK | ✅ §5.28 SQL file (owner apply) |
| Firebase custom token | ✅ client + stub |
| Park legacy | Deferred (owner, closer to release) |

---

## 5. Suggested ship order
1. Apply §5.10–§5.28 SQL + commit/push  
2. Deploy edges + APNs + Firebase SA  
3. Device QA  
4. Live Phase B onramp  
5. Phase C after audit + legal  

---

## 6. Still external (cannot finish in-repo)

- Apply all CLAUDE SQL markers (§5.10–§5.28)  
- Partner onramp / payout webhooks  
- Wallet SDK + contract audit  
- APNs credentials + Push capability  
- Firebase Admin mint  
- App Store legal (D9)  
- Crashlytics dSYM CI  
- Widget Extension target + App Clip  
- Legacy screen parking  
- Device QA matrix  
