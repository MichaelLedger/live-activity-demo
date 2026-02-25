# FreePrints Live Activity Demo

An iOS Swift demo showcasing **ActivityKit Live Activities** with push notification integration for promotional banners — free prints, flash sales, and order tracking.

---

## Project Structure

```
FreePrintsPromo.xcodeproj
├── FreePrintsPromo/               Main app target
│   ├── FreePrintsPromoApp.swift   App entry + AppDelegate (push permissions)
│   ├── ContentView.swift          Main UI, promo cards, push token dev panel
│   ├── LiveActivityManager.swift  Start / update / end activities + token observation
│   └── FreePrintsPromo.entitlements
├── Shared/
│   └── PromoActivityAttributes.swift  ActivityAttributes + PromoType model
└── PromoActivityWidget/           Widget Extension target
    ├── PromoActivityBundle.swift
    └── PromoLiveActivityView.swift    Lock Screen + Dynamic Island views
```

---

## Requirements

| Requirement | Version |
|---|---|
| Xcode | 15.2 + |
| iOS Deployment Target | 17.0 + |
| Push-to-Start token | iOS 17.2 + |
| Real device | Required for Live Activities & push |

> **Simulator limitation:** Live Activities render in the simulator, but push notifications require a real device with a signed build.

---

## Live Activity Types

| Type | Duration (demo) | Key UI feature |
|---|---|---|
| **Free Prints** | 2 min | Countdown timer, photo stack animation |
| **Flash Sale** | 2 min | Urgency countdown, "Shop Now" deep link |
| **Order Tracking** | 3 min | Live progress bar with step labels |

---

## How to Run

1. Open `FreePrintsPromo.xcodeproj` in Xcode.
2. Select the **FreePrintsPromo** scheme.
3. Choose a **real device** (iPhone with Face ID / Dynamic Island recommended).
4. Set your **Development Team** in *Signing & Capabilities*.
5. Build & Run (`⌘R`).
6. Tap a promo card to launch a Live Activity — it appears on the Lock Screen and Dynamic Island immediately.

---

## Testing Push Notifications on a Real Device

### Prerequisites

- Mac with Xcode installed
- iPhone running iOS 17.0+ connected and trusted
- Apple Developer account (free or paid)
- A valid **APNs Auth Key** (`.p8`) **or** APNs certificate (`.pem`) from [developer.apple.com](https://developer.apple.com/account/resources/authkeys/list)

---

## Part 1 — Push-to-Update (Update a Running Activity)

Push-to-update lets your server change the content of an already-running Live Activity at any time, even when the app is in the background or killed.

### Step 1 — Get the Update Token from the app

1. Build and run the app on a **real device**.
2. Tap a promo card (e.g. **"10 FREE Prints"**) to start the activity.
3. The **"Push Token Dev Panel"** appears at the bottom of the screen.
4. Tap it to expand, then tap **Copy** next to the activity's update token.

The token looks like:

```
a1b2c3d4e5f6...  (64 hex characters)
```

---

### Step 2 — Prepare your APNs credentials

#### Option A — Auth Key (`.p8`, recommended)

1. Go to [developer.apple.com → Certificates, IDs & Profiles → Keys](https://developer.apple.com/account/resources/authkeys/list).
2. Create a new key with the **Apple Push Notifications service (APNs)** capability.
3. Download the `.p8` file and note the **Key ID** and your **Team ID**.

You will need:

| Variable | Where to find it |
|---|---|
| `KEY_ID` | Key detail page, e.g. `ABC1234567` |
| `TEAM_ID` | Top-right of your developer account, e.g. `ZA2PCCN27W` |
| `KEY_FILE` | Path to the downloaded `.p8` file |
| `BUNDLE_ID` | `com.freeprints.demo` (or your bundle identifier) |
| `DEVICE_TOKEN` | Copied from the Push Token Dev Panel |

Install the `apns2` or `token-gen` helper, or use the `jwt-cli` tool to generate the JWT bearer token. A simple alternative is the **[Push Notifications tool in Xcode](#option-b--xcode-push-notifications-tool)** below.

#### Option B — Xcode Push Notifications tool (easiest for testing)

1. In Xcode menu: **Debug → Simulate Push Notification…** — *Note: this only works in Simulator.*
2. For a real device, use the **[WWDC Sample `send-push-notification`](https://developer.apple.com/documentation/usernotifications/testing-notifications-using-the-push-notification-console)** script, or the free macOS app **[PushHero](https://onmyway133.com/pushhero/)** / **[Proxyman](https://proxyman.io)**.

---

### Step 3 — Send an update push via `curl`

Replace the placeholders with your values and run in Terminal:

```bash
# ── Variables ────────────────────────────────────────────────────────────────
BUNDLE_ID="com.freeprints.demo"
DEVICE_TOKEN="<paste update token here>"   # from Push Token Dev Panel
KEY_FILE="$HOME/Downloads/AuthKey_XXXXXXXX.p8"
KEY_ID="XXXXXXXX"          # 10-char Key ID from developer.apple.com
TEAM_ID="XXXXXXXXXX"       # 10-char Team ID from developer.apple.com
APNS_HOST="api.sandbox.push.apple.com"   # use api.push.apple.com for production

# ── Generate JWT bearer token (requires openssl + base64) ────────────────────
HEADER=$(echo -n '{"alg":"ES256","kid":"'"$KEY_ID"'"}' | base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n')
PAYLOAD=$(echo -n '{"iss":"'"$TEAM_ID"'","iat":'"$(date +%s)"'}' | base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n')
SIGN_INPUT="$HEADER.$PAYLOAD"
SIG=$(echo -n "$SIGN_INPUT" | openssl dgst -binary -sha256 -sign "$KEY_FILE" | base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n')
JWT="$SIGN_INPUT.$SIG"

# ── Send the update push ──────────────────────────────────────────────────────
curl -v \
  --http2 \
  -H "authorization: bearer $JWT" \
  -H "apns-push-type: liveactivity" \
  -H "apns-topic: $BUNDLE_ID.push-type.liveactivity" \
  -H "apns-priority: 10" \
  -H "Content-Type: application/json" \
  -d '{
    "aps": {
      "timestamp": '"$(date +%s)"',
      "event": "update",
      "content-state": {
        "promoTitle": "Updated via Push!",
        "promoSubtitle": "Server pushed this — no app needed",
        "discount": "FREE",
        "endTime": '"$(($(date +%s) + 120))"',
        "promoType": "freePrints",
        "progress": 0,
        "currentStep": "",
        "itemCount": 10
      }
    }
  }' \
  "https://$APNS_HOST/3/device/$DEVICE_TOKEN"
```

#### Expected result

- The Live Activity banner on the Lock Screen and Dynamic Island updates **instantly**.
- The app does **not** need to be running.

---

### Step 4 — Send an end push

To dismiss the Live Activity from the server:

```bash
curl -v \
  --http2 \
  -H "authorization: bearer $JWT" \
  -H "apns-push-type: liveactivity" \
  -H "apns-topic: $BUNDLE_ID.push-type.liveactivity" \
  -H "apns-priority: 10" \
  -H "Content-Type: application/json" \
  -d '{
    "aps": {
      "timestamp": '"$(date +%s)"',
      "event": "end",
      "dismissal-date": '"$(($(date +%s) + 5))"',
      "content-state": {
        "promoTitle": "Offer Ended",
        "promoSubtitle": "Thanks for your interest!",
        "discount": "",
        "endTime": '"$(date +%s)"',
        "promoType": "freePrints",
        "progress": 1.0,
        "currentStep": "Complete",
        "itemCount": 0
      }
    }
  }' \
  "https://$APNS_HOST/3/device/$DEVICE_TOKEN"
```

> `dismissal-date` is the Unix timestamp when the banner should fully disappear from the Lock Screen. Use `$(date +%s)` to dismiss immediately, or add seconds for a delay.

---

### Payload Field Reference — `content-state`

These fields map directly to `FreePrintsPromoAttributes.ContentState`:

| Field | Type | Example | Notes |
|---|---|---|---|
| `promoTitle` | String | `"10 FREE Prints!"` | Main headline |
| `promoSubtitle` | String | `"Just pay shipping"` | Supporting text |
| `discount` | String | `"FREE"` or `"50%"` | Badge text; empty string for order tracking |
| `endTime` | Unix timestamp | `1740000000` | Drives the countdown timer |
| `promoType` | String | `"freePrints"` / `"flashSale"` / `"orderTracking"` | Controls which banner layout is shown |
| `progress` | Double 0–1 | `0.7` | Order tracking progress bar fill |
| `currentStep` | String | `"Shipped"` | Highlighted step label |
| `itemCount` | Int | `25` | Number of prints shown in tracking banner |

---

### APNs Header Reference

| Header | Value | Notes |
|---|---|---|
| `apns-push-type` | `liveactivity` | Always required for Live Activity pushes |
| `apns-topic` | `<bundle-id>.push-type.liveactivity` | Must match the exact bundle identifier |
| `apns-priority` | `10` | Immediate delivery; use `5` for power-saving |
| `apns-expiration` | Unix timestamp or `0` | `0` = discard if device offline |
| `authorization` | `bearer <JWT>` | JWT signed with your `.p8` key |

---

## Part 2 — Push-to-Start (Start an Activity Without the App Open)

Push-to-start allows APNs to launch a new Live Activity even when the app is **completely killed**. This requires an additional Apple entitlement.

### Step 1 — Request the entitlement

The entitlement `com.apple.developer.activitykit.push-notification-authoring` is **not** enabled by default. You must request it:

1. Go to [developer.apple.com → Contact → Request a capability](https://developer.apple.com/contact/request/activitykit-push-notification-authoring).
2. Fill in the form explaining your use case.
3. Apple will enable it on your App ID within a few business days.
4. Re-download your provisioning profile after approval.

> The entitlement is already declared in `FreePrintsPromo.entitlements` — it just needs Apple's approval to be active.

---

### Step 2 — Get the Push-to-Start token

1. Build and run the app on a real device (iOS 17.2+).
2. Open the **"Push Token Dev Panel"** at the bottom of the screen.
3. Copy the **"Push-to-Start"** token (this is different from the update token).

---

### Step 3 — Kill the app completely

- Swipe up to close the app from the App Switcher.
- The Live Activity should **not** be running at this point.

---

### Step 4 — Send the push-to-start payload

```bash
# Use the push-to-start token (not the activity update token)
START_TOKEN="<paste push-to-start token here>"

curl -v \
  --http2 \
  -H "authorization: bearer $JWT" \
  -H "apns-push-type: liveactivity" \
  -H "apns-topic: $BUNDLE_ID.push-type.liveactivity" \
  -H "apns-priority: 10" \
  -H "Content-Type: application/json" \
  -d '{
    "aps": {
      "timestamp": '"$(date +%s)"',
      "event": "start",
      "content-state": {
        "promoTitle": "10 FREE Prints!",
        "promoSubtitle": "Started by push — app was not running",
        "discount": "FREE",
        "endTime": '"$(($(date +%s) + 120))"',
        "promoType": "freePrints",
        "progress": 0,
        "currentStep": "",
        "itemCount": 10
      },
      "attributes-type": "FreePrintsPromoAttributes",
      "attributes": {
        "promoId": "push-start-001",
        "productType": "4x6 Prints"
      },
      "alert": {
        "title": "New FreePrints Offer!",
        "body": "10 free prints are waiting for you"
      }
    }
  }' \
  "https://$APNS_HOST/3/device/$START_TOKEN"
```

#### Expected result

- The Live Activity appears on the Lock Screen and Dynamic Island **without the app ever being opened**.
- When the user taps the banner, the app launches and `syncWithRunningActivities()` restores the activity state correctly.

---

## Part 3 — Update Token for Order Tracking Progress

Order tracking has its own update token. To simulate a delivery progress update from the server:

```bash
ORDER_TOKEN="<paste orderTracking update token here>"

for STEP in "Printed 0.5" "Shipped 0.7" "Out for Delivery 0.9" "Delivered 1.0"; do
  NAME=$(echo $STEP | cut -d' ' -f1-3)
  PROGRESS=$(echo $STEP | awk '{print $NF}')
  SUBTITLE=$([ "$NAME" = "Delivered" ] && echo "Your prints have arrived!" || echo "Estimated delivery: 2-3 days")

  echo "→ Updating to: $NAME ($PROGRESS)"

  curl --silent --http2 \
    -H "authorization: bearer $JWT" \
    -H "apns-push-type: liveactivity" \
    -H "apns-topic: $BUNDLE_ID.push-type.liveactivity" \
    -H "apns-priority: 10" \
    -H "Content-Type: application/json" \
    -d '{
      "aps": {
        "timestamp": '"$(date +%s)"',
        "event": "update",
        "content-state": {
          "promoTitle": "Your Prints Are On The Way!",
          "promoSubtitle": "'"$SUBTITLE"'",
          "discount": "",
          "endTime": '"$(($(date +%s) + 180))"',
          "promoType": "orderTracking",
          "progress": '"$PROGRESS"',
          "currentStep": "'"$NAME"'",
          "itemCount": 25
        }
      }
    }' \
    "https://$APNS_HOST/3/device/$ORDER_TOKEN"

  sleep 4
done
```

Run this script and watch the progress bar on your Lock Screen advance through each step in real time.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `curl` returns 400 | Malformed JSON payload | Validate JSON with `echo '...' \| python3 -m json.tool` |
| `curl` returns 403 | Wrong topic or expired JWT | Check bundle ID matches; regenerate JWT |
| `curl` returns 404 | Invalid or expired device token | Copy a fresh token from the app; tokens rotate |
| `curl` returns 410 | Token has been invalidated | App was uninstalled or token rotated; get a new one |
| Activity doesn't appear | Push-to-start entitlement missing | Request approval from Apple; push-to-update works without it |
| Token field shows "Waiting…" | Running on Simulator | Use a real device; Simulator doesn't issue push tokens |
| Activity ends immediately | `endTime` in the past | Set `endTime` to `$(date +%s) + 120` or later |
| No Dynamic Island shown | Device is iPhone SE / older | Dynamic Island only on iPhone 14 Pro and later |

---

## Architecture Notes

### Token lifecycle

```
App launches
    └─▶ observePushToStartToken()    ← Type-level token for starting new activities
    └─▶ syncWithRunningActivities()  ← Restores state after app kill
            └─▶ observeActivity()
                    ├─▶ activityStateUpdates  ← Tracks .active / .stale / .ended / .dismissed
                    └─▶ pushTokenUpdates      ← Per-activity token for update/end pushes
```

### When to register tokens with your server

| Event | Action |
|---|---|
| `pushToStartToken` emitted | Register/update in your DB — lets server start activities proactively |
| `pushTokenUpdates` emits for an activity | Update token in your DB for that activity ID |
| Activity `.ended` or `.dismissed` | Delete the update token from your DB |
| App uninstall / token rotation | APNs returns 410 on next push — clean up your DB |

---

## Resources

- [Apple — Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- [Apple — Starting and updating Live Activities with ActivityKit push notifications](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications)
- [Apple — Pushing updates to your Live Activity](https://developer.apple.com/documentation/activitykit/pushing-updates-to-your-live-activity)
- [WWDC23 — Update Live Activities with push notifications](https://developer.apple.com/videos/play/wwdc2023/10185/)
- [Human Interface Guidelines — Live Activities](https://developer.apple.com/design/human-interface-guidelines/live-activities)
