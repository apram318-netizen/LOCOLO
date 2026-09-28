# LOCOLO V2 — Marketplace, Web3 Trading, Payments & Portfolio

> Design spec. Read `LOCOLO_V2_ROADMAP.md` §3 for the locked-in defaults (chain, wallet, currency) this assumes. Read `LOCOLO_V2_SECURITY.md` before writing any contract or payment code.
> Reuses today's `offers` / `price_history` tables and `DigitalAsset` marketplace columns — **extend, don't replace**.

---

## 1. Concept: AR creations become ownable, tradable, real

Every placed AR asset can become a **collectible**: a 1-of-1 (or limited edition) tied to a real GPS location and its creator. Owning it means:
- your wallet holds the NFT (Phase C) / the DB ledger records you as owner (Phase A);
- your handle shows in its **provenance** ("found by… owned by…");
- you can **resell** it; the **original creator earns a royalty** on every resale, enforced on-chain;
- it appears in your **portfolio** with a live value and history graph.

Scarcity is geographic and social, not arbitrary — the moat over generic NFT markets.

## 2. Architecture at a glance

```
iOS app ──┬─ Wallet layer (embedded smart wallet: passkey login → Base address)
          ├─ TradeRepository (list / offer / buy / sell) ──► Supabase (ledger + RLS)
          ├─ PortfolioStore (holdings + valuation) ──► Swift Charts
          └─ OnrampService (Apple Pay / card → USDC) ──► on-ramp partner

Supabase (source of truth for UX; mirror of chain state)
   tables: wallets, nft_tokens, listings, bids, trades, royalties,
           portfolio_snapshots, payment_intents, payouts  (+ existing offers, price_history)
   edge fns: mint, list, buy, cancel, onramp-session, chain-webhook, price-oracle, snapshot-portfolio

Chain (Phase C — Base L2)
   Locolo721 (ERC-721 + EIP-2981 royalties, lazy mint)
   Seaport (listings/offers/auctions, signature-based)
   USDC (settlement), Paymaster (sponsored gas)
   Indexer (Alchemy/Moralis webhooks) ──► chain-webhook edge fn ──► reconcile DB
```

**Golden rule:** the DB is the fast UX layer; the chain (Phase C) is the settlement truth. A chain indexer webhook is the ONLY writer of "confirmed ownership/sale" — the client never marks a trade settled from its own optimistic state.

## 3. Data model (new tables — additive; RLS per Security spec)

```sql
-- A user's linked wallet address(es). Non-custodial: we store the address, never keys.
CREATE TABLE public.wallets (
  user_id     uuid REFERENCES users(user_id) ON DELETE CASCADE,
  address     text NOT NULL,                    -- checksummed 0x…
  chain       text NOT NULL DEFAULT 'base',
  provider    text,                             -- 'coinbase_smart_wallet' | 'privy' | 'external'
  is_primary  boolean NOT NULL DEFAULT true,
  linked_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, address, chain)
);

-- One row per asset that has been (or will be) tokenized.
CREATE TABLE public.nft_tokens (
  asset_id     uuid PRIMARY KEY REFERENCES digital_assets(asset_id) ON DELETE CASCADE,
  chain        text NOT NULL DEFAULT 'base',
  contract     text,                            -- Locolo721 address (null until minted)
  token_id     numeric,                         -- null until minted (lazy)
  metadata_uri text,                            -- ipfs://…  (name, desc, media, place, creator, attributes)
  edition_size int NOT NULL DEFAULT 1,
  royalty_bps  int NOT NULL DEFAULT 750,        -- 7.5% to creator (EIP-2981)
  mint_state   text NOT NULL DEFAULT 'unminted' -- unminted|pending|minted|failed
                 CHECK (mint_state IN ('unminted','pending','minted','failed')),
  owner_id     uuid REFERENCES users(user_id),  -- current owner (mirrors chain; indexer writes)
  minted_at    timestamptz
);

-- Active sell-side listings (fixed price or auction). Seaport order in Phase C.
CREATE TABLE public.listings (
  listing_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  asset_id     uuid NOT NULL REFERENCES digital_assets(asset_id) ON DELETE CASCADE,
  seller_id    uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  kind         text NOT NULL CHECK (kind IN ('fixed','auction')),
  price        numeric,                          -- fixed price (USDC), or reserve for auction
  currency     text NOT NULL DEFAULT 'USDC',
  ends_at      timestamptz,                      -- auctions
  seaport_order jsonb,                           -- signed order (Phase C)
  status       text NOT NULL DEFAULT 'active'
                 CHECK (status IN ('active','sold','cancelled','expired')),
  created_at   timestamptz NOT NULL DEFAULT now()
);

-- Buy-side bids/offers. Supersedes the narrow existing `offers` for auctions;
-- keep `offers` for simple "make an offer on a not-listed asset".
CREATE TABLE public.bids (
  bid_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  listing_id  uuid REFERENCES listings(listing_id) ON DELETE CASCADE,
  asset_id    uuid NOT NULL REFERENCES digital_assets(asset_id) ON DELETE CASCADE,
  bidder_id   uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  amount      numeric NOT NULL,
  currency    text NOT NULL DEFAULT 'USDC',
  status      text NOT NULL DEFAULT 'active'
                CHECK (status IN ('active','accepted','outbid','withdrawn','expired')),
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- Immutable record of every completed sale. Written by the chain-webhook (Phase C)
-- or the settle edge fn (Phase A). Feeds provenance + price_history + portfolio.
CREATE TABLE public.trades (
  trade_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  asset_id    uuid NOT NULL REFERENCES digital_assets(asset_id) ON DELETE CASCADE,
  seller_id   uuid REFERENCES users(user_id),
  buyer_id    uuid REFERENCES users(user_id),
  price       numeric NOT NULL,
  currency    text NOT NULL DEFAULT 'USDC',
  royalty_paid numeric NOT NULL DEFAULT 0,
  platform_fee numeric NOT NULL DEFAULT 0,
  tx_hash     text,                              -- null in Phase A (off-chain)
  settled_at  timestamptz NOT NULL DEFAULT now()
);

-- Daily portfolio valuation per user, for the value-over-time graph.
CREATE TABLE public.portfolio_snapshots (
  user_id    uuid REFERENCES users(user_id) ON DELETE CASCADE,
  day        date NOT NULL,
  total_value numeric NOT NULL,                  -- sum of est. value of holdings
  holdings_count int NOT NULL,
  currency   text NOT NULL DEFAULT 'USDC',
  PRIMARY KEY (user_id, day)
);

-- Fiat payment intents (Phase B) — Stripe/on-ramp reference only; NO card data.
CREATE TABLE public.payment_intents (
  intent_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  provider    text NOT NULL,                     -- 'stripe' | 'coinbase_onramp' | 'moonpay'
  provider_ref text NOT NULL,                    -- their id; we never see the PAN
  amount      numeric NOT NULL,
  currency    text NOT NULL,
  purpose     text NOT NULL,                     -- 'buy_asset' | 'onramp_usdc'
  asset_id    uuid REFERENCES digital_assets(asset_id),
  status      text NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending','succeeded','failed','refunded')),
  created_at  timestamptz NOT NULL DEFAULT now()
);
```

`price_history` (exists) gains a `source text` column: `'sale' | 'listing' | 'oracle'` so the asset graph can distinguish real trades from ask prices. Extend `DigitalAsset` in lockstep only with **optional** fields (owner handle, floor, last-sale) — remember the 41-column RPC invariant and the two memberwise-init call sites.

## 4. Smart contracts (Phase C — Base, Solidity, audited before mainnet)

- **`Locolo721`** — ERC-721 with:
  - **EIP-2981 royalties** (`royaltyInfo` → creator address + `royalty_bps`).
  - **Lazy minting** via signed vouchers: creator signs `{asset_id, uri, price, royalty}` off-chain (gasless); the contract mints on the buyer's first purchase, so unsold art costs nothing.
  - `Ownable`/`AccessControl` for admin; **`Pausable`** kill-switch; **no arbitrary upgrade proxy** unless audited (prefer immutable + migration over a rushed upgradeable proxy).
  - Metadata `tokenURI` → `ipfs://` (pinned via nft.storage/Pinata; mirror on Arweave for permanence).
- **Trading** via **Seaport**: listings and offers are **signed orders** (gasless to create), settled when a counterparty fulfills. Handles fixed price, auctions (English/Dutch), and collection offers. Royalties enforced via Seaport's fee mechanism + on-chain EIP-2981.
- **Settlement currency:** USDC (ERC-20) on Base. **Paymaster** sponsors gas so buyers pay only USDC (no ETH needed) — critical for mainstream UX.
- **Contract security requirements** are in the Security spec §Smart Contracts (reentrancy, checks-effects-interactions, access control, audit, testnet burn-in, bug bounty, pausability, upgrade policy).

## 5. Trade flows

### 5.1 List for sale (seller)
1. Owner taps **Sell** on their asset → sheet: fixed price or auction, price in USDC (shown as `$`), duration.
2. Phase A: insert `listings` row; asset shows a price tag across the app.
   Phase C: app builds a Seaport order, wallet **signs** it (passkey — no gas), store the signed order in `listings.seaport_order`.
3. Listing appears in the marketplace feed, on the asset, and in map "for sale" pins.

### 5.2 Buy now (buyer)
1. Buyer taps **Buy** → confirm sheet shows price, creator royalty, platform fee, total, and their USDC balance (with a **top-up** button if short — §6).
2. Phase A: `trades` insert (escrowed off-chain), balance ledger debit/credit, ownership flips, `price_history` + `portfolio_snapshots` update.
   Phase C: wallet signs the Seaport fulfillment; tx submitted (gas sponsored); UI shows "settling…"; the **chain-webhook** confirms and is the sole writer of the `trades` row + ownership. Never flip ownership from the client's optimism alone.
3. On confirm: confetti + haptic, provenance updated, both parties notified (new `trade` notification type), creator gets a **royalty** notification.

### 5.3 Make / accept offer (extends existing `offers`)
- Buyer offers below ask or on an unlisted asset (`bids`/`offers`). Owner sees offers on the asset + in Activity, taps **Accept** → same settlement path as Buy. Auto-expire stale offers; refund escrow on reject/expire.

### 5.4 Auctions
- English (bids ratchet up, anti-snipe: extend `ends_at` by 5 min on a late bid) and Dutch (price decays to reserve). Highest valid bid at `ends_at` settles. Escrow the leading bid; release when outbid.

## 6. Fiat & on-ramp (Phase B)

- **Buy USDC with Apple Pay / card** via **Coinbase Onramp** (or MoonPay): app opens a partner sheet → USDC lands in the user's smart wallet. Locolo never touches card data (PCI stays with the partner) and stays out of the money-transmission path.
- **Direct fiat purchase of an asset** (no crypto knowledge): partner buys USDC → immediately fulfills the trade in one flow; the user just sees "Buy $25 with Apple Pay."
- **Creator payouts:** creators can hold USDC or cash out via the partner's off-ramp. Locolo takes a **platform fee** (e.g. 2.5%) recorded on `trades.platform_fee`.
- **⚠️ App Store:** whether Apple treats this as external "goods & services" (no IAP) vs digital content (30% IAP) is **the** launch risk — see Roadmap D9 and Security §Compliance. Legal sign-off required before submission. Design a **testnet/"collect for free"** mode so review can proceed even if the paid path is gated by jurisdiction.

## 7. Portfolio & graphs (Phase A — ships early, no chain needed)

New **Portfolio** surface (tab in Creator Studio or its own tab). All charts use **Swift Charts** (already in the project) and the existing `ARDesign.chartCategorical` palette + `dataviz` skill conventions.

| Graph | Data source | Chart |
|---|---|---|
| **Portfolio value over time** | `portfolio_snapshots` (daily; `snapshot-portfolio` edge fn) | Area/line with gradient fill; range toggle 1W/1M/3M/1Y/All; big animated current-value number + % change pill |
| **Per-asset price history** | `price_history` (source-tagged) + `trades` | Line (asks) with sale dots; optional candlesticks for actively traded pieces; floor / last-sale / your-cost annotations |
| **Allocation by category** | current holdings × est. value | Donut, category colors, tap → filter |
| **Gain / loss** | `trades` (buys) vs current est. value | Stat tiles: total P/L, best performer, 24h change, realized vs unrealized |
| **Holding cards** | holdings + 7-day sparkline | Row with thumbnail, current value, sparkline, ▲/▼ % |
| **Activity / volume** | `trades` | Bar (sales per week) + provenance timeline per asset |

**Valuation model** (documented so it's honest, not magic): est. value = last sale if any, else lowest active listing (floor) for its edition/creator, else creator's median sale, else mint price. Always label the basis ("last sale" / "floor" / "est.") — never show a fake precise number. A `price-oracle` edge fn recomputes nightly and on trade.

Accessibility: every chart has a VoiceOver summary ("Portfolio up 12% this month, $340 total") and respects Reduce Motion (no count-up animation when set).

## 8. Edge functions (new)

| Function | Trigger | Does |
|---|---|---|
| `mint` | creator lists first time (Phase C) | pin metadata to IPFS, build lazy-mint voucher |
| `list` / `cancel` | sell / unlist | validate ownership, write `listings`, (C) verify Seaport signature |
| `buy` | purchase | Phase A: atomic ledger settle; Phase B: create payment intent; Phase C: relay/sponsor fulfillment |
| `chain-webhook` | Alchemy/Moralis on Transfer/OrderFulfilled | **sole writer** of confirmed `trades` + `nft_tokens.owner_id`; reconcile DB to chain |
| `onramp-session` | top-up | create partner session, return widget URL |
| `snapshot-portfolio` | nightly cron + post-trade | write `portfolio_snapshots` per active user |
| `price-oracle` | nightly + on trade | recompute est. values / floors |

All financial edge fns require a verified session (`_shared/auth.ts`), validate ownership server-side (never trust client), and are idempotent (webhooks retry).

## 9. Phasing recap (see Roadmap §4)

- **A (off-chain):** wallets(link-only), listings/bids/trades in DB, portfolio + graphs, trading UI. Real product, zero chain risk.
- **B (fiat):** on-ramp + Apple Pay purchase + payouts + platform fee + KYC thresholds.
- **C (on-chain):** embedded wallets, Locolo721 + Seaport on Base, USDC + paymaster, indexer reconciliation, provenance, royalties.

Each phase must pass its **Security gate** (Security spec §Gates) before shipping.

## 10. Open questions for the owner
- Edition model: strictly 1-of-1, or allow limited editions / open editions with decreasing value?
- Platform fee %, royalty default %, and who pays gas in Phase C (recommend: platform sponsors buyer gas).
- Geographic gating: is trading available everywhere day one, or allowlisted jurisdictions (crypto legality varies)?
- Do we let users bring an **external** wallet (MetaMask/Coinbase) in addition to the embedded one, or embedded-only for V2 simplicity?
