# LOCOLO AR — App Store release checklist (2026-10-03)

Built from a pass over every doc in `docs/`, checked against the live Supabase project and
the Xcode project. Supersedes the scattered lists in `LOCOLO_AR_STATUS.md` §5.9 / §7,
`LOCOLO_V2_COMPLETION_PLAN.md` §1 and `LOCOLO_V3_FEEDBACK.md` "Owner actions".

Decisions (owner, 2026-10-03): **minting stays paid via In-App Purchase**, **marketplace hidden
for launch**, **ship as `com.apram.locolo` (team RB24MJ38LB)**.

## Done in this pass
- V3 SQL applied: `v3_offers_fix`, `v3_memories_posts_growth`, `v3_storage_paths`, `v3_advisor_fixes`.
- **Release signing** now `com.apram.locolo` / RB24MJ38LB (was `edu.monash.Locolo` / Monash team).
- **`PrivacyInfo.xcprivacy`** added (App Store Connect rejects uploads without one). Keep the
  App Privacy answers in App Store Connect consistent with it.
- Calendar usage strings added (legacy `AddToCalendarView` links EventKit — ITMS-90683 otherwise).
- **Mint fee via StoreKit 2** (`MintPurchaseService`): consumable `com.apram.locolo.mint`, order id as
  `appAccountToken`, finished only after server verification; interrupted purchases settle on next
  sign-in. The external `onramp-session` checkout is no longer used for minting.
- Coupon field is **DEBUG-only** (3.1.1: no own codes unlocking paid features). Use App Store offer
  codes for promos.
- Marketplace hidden behind `app_config.marketplace_enabled` (`AppFeatures`): list/buy/auction,
  storefront buttons, wallet, payouts. Offers stay (non-binding). Missing flag = off.
- Internal jargon ("§5.18", "Phase B/C", "needs SQL") removed from user-facing strings.
- Debug + Release simulator builds green; `LocoloTests` pass.

## 🔴 Blocking — needs you
1. **Apply `docs/migrations/2026_v3_release_gates.sql`** (my apply was blocked by the tool
   permission classifier). Without it:
   - any user can set their own `mint_orders.status = 'paid'` (owner UPDATE policy) and mint free;
   - the fee isn't enforced server-side at all — `digital_assets` INSERT only checks `user_id`;
   - `iap_transactions` doesn't exist, so `verify-mint-purchase` can't record purchases;
   - the DB doesn't refuse listings/bids/trades while the marketplace is "off".
2. **Deploy `verify-mint-purchase`** (after 1): `supabase functions deploy verify-mint-purchase`.
   Uses only built-in secrets. Not type-checked locally (no Deno on this Mac) — watch the first logs.
   Until it's live, paid mints charge the user but can't post (the purchase stays unfinished and
   settles automatically once the function is up — but don't ship before it's deployed).
3. **App Store Connect:** create consumable **`com.apram.locolo.mint`** (price tier ≈ $2.99 to match
   `app_config.mint_fee_usd`), add it to the version for review; Paid Apps agreement + banking/tax.
   Sandbox tester to QA the purchase on device.
4. **Apple Developer (team RB24MJ38LB, paid membership):** App ID `com.apram.locolo` with
   Sign in with Apple + In-App Purchase (+ Push, see 7).
5. **Supabase Auth:** email templates with `{{ .Token }}` (Confirm signup + Magic Link); custom SMTP
   (built-in sender only reaches team addresses); enable Apple + Google providers and add
   `locolo://login-callback`. Today only email identities exist. Optionally turn on leaked-password
   protection.
6. **Chat identity binding** (Security §2, Status §5.8 — listed as cross-cutting before public launch):
   Firebase auth is anonymous, so `senderId` is spoofable and `firestore.rules` isn't deployed.
   Needs `FIREBASE_SERVICE_ACCOUNT_JSON` + real `createCustomToken` in `firebase-custom-token`.
7. **Push** (optional for launch, alerts are local until then): APNs key, Push capability on the
   target (adds `aps-environment`), deploy `send-push` + webhook, then `push_enabled = true`.
   No edge functions are deployed today.
8. **Device QA** — status §5.7 matrix, plus: buy a mint in Sandbox → asset posts; kill the app
   mid-purchase → relaunch → asset can post; marketplace entry points absent.
9. **Listing / review:** privacy policy URL (location, camera, photos, E2E chat, deletion, IAP),
   support URL, demo account in review notes, note that GPS mode works anywhere, justify
   background location + audio modes, age rating questionnaire.

## 🟡 Should do, not blocking
- `media` bucket limit is 3 MB — longer memory clips will fail to upload.
- Deactivate or limit the 100%-off coupons `LOCOLO100` / `TESTAPRAM6800621` (anyone who knows them
  can still call `create_mint_order` with them; release builds hide the field).
- Deploy `embed-asset` / `update-taste` / `embed-query` + `OPENAI_API_KEY` + backfill (0/10 assets
  embedded) — until then For You is newest-first and search is keyword-only.
- `purge-storage` deploy + schedule (needs `pg_cron` / `pg_net`, neither enabled).
- `update_asset_offer_stats` appends a `price_history` row on every offer update (incl. rejected
  amounts); `notify_on_offer` notifies the creator rather than the current owner after a resale.
- Confirm the truncated "Chats: just like …" feedback item.
- Park legacy non-AR screens; localization; Widget target; Crashlytics dSYM upload.
