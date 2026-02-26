# Live Activity Push Notifications — EmojiRangers Setup Guide

## Overview

This document summarises the changes made to enable APNs push notifications and
push-to-start Live Activities in the EmojiRangers project, and the correct way
to send a push-to-start payload via `curl`.

---

## 1. Code Changes

### 1.1 `EmojiRangersApp.swift` — Added `AppDelegate`

The original app used a minimal SwiftUI `@main` struct with no `AppDelegate`,
so push notifications were never requested at launch.

**Changes:**

- Added `@UIApplicationDelegateAdaptor(AppDelegate.self)` to bridge UIKit's
  `AppDelegate` into the SwiftUI lifecycle.
- `AppDelegate` now:
  - Sets `UNUserNotificationCenter.current().delegate = self` on launch.
  - Calls `requestPushPermissions()` — prompts the user for notification
    permission and then calls `UIApplication.shared.registerForRemoteNotifications()`.
  - Calls `observePushToStartToken()` — listens to
    `Activity<AdventureAttributes>.pushToStartTokenUpdates` (iOS 17.2+) and
    logs the push-to-start token and the correct APNs topic.

```swift
@main
struct EmojiRangersApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

**Key log output on launch:**

```
[Push] APNs device token (regular notifications only): <32-byte hex>
[Push-to-Start] Token (use for Live Activity start push):
  token : <~75-byte hex>
  topic : com.example.apple-samplecode.Emoji-RangersSXQJRCS9S9.push-type.liveactivity
```

> **Important:** The APNs device token and the push-to-start token are
> completely different. Never mix them up — see the table below.

---

### 1.2 `AdventureViewModel.swift` — Fixed `printEncoded()` key encoding

The original `printEncoded()` used `.convertToSnakeCase`, which produced
misleading `snake_case` output. ActivityKit's APNs decoder expects **camelCase**
keys in the `content-state` payload field.

**Before:**
```swift
encoder.keyEncodingStrategy = .convertToSnakeCase
// logged: "current_health_level", "event_description"  ← WRONG for APNs
```

**After:**
```swift
// Default encoder — camelCase keys match what ActivityKit expects in APNs
encoder.outputFormatting = .prettyPrinted
// logged: "currentHealthLevel", "eventDescription"  ← CORRECT
```

---

### 1.3 `Emoji Rangers.entitlements` — No extra entitlement needed

`com.apple.developer.activitykit.push-notification-authoring` is **not** a
valid entitlement key and was removed after Xcode rejected it.

Push-to-start only requires:
- `aps-environment: development` (already present).
- **Push Notifications** capability enabled in Xcode → Signing & Capabilities.

---

## 2. Token Reference

| Token | Source | Length | Use for |
|---|---|---|---|
| APNs device token | `didRegisterForRemoteNotificationsWithDeviceToken` | ~32 bytes | Regular push notifications to the app |
| Push-to-start token | `Activity<AdventureAttributes>.pushToStartTokenUpdates` | ~75 bytes | Starting a Live Activity remotely via APNs |
| Push-to-update token | `activity.pushTokenUpdates` | ~75 bytes | Updating/ending a running Live Activity via APNs |

Push-to-start tokens **rotate** — always use the latest token logged at launch.

**Token rotation behaviour by environment:**

| Environment | Push-to-start token rotation frequency |
|---|---|
| Development (sandbox) | Every launch or every few minutes — aggressive rotation by design so you can test token handling |
| Production | Stable for days or weeks — only rotates periodically for security |

The APNs **device token** (32 bytes) is stable across launches in both environments.
When a new push-to-start token is issued, the previous one becomes **immediately invalid**.
Your server must always overwrite the stored token with the latest value received.

---

## 3. Sending a Push-to-Start

### 3.0 Using the Apple Push Notifications Dashboard (recommended for testing)

The official Apple Push Notifications dashboard at
[icloud.developer.apple.com/dashboard/notifications](https://icloud.developer.apple.com/dashboard/notifications)
supports Live Activity pushes **if you configure it correctly**.

**Steps:**

1. Open the dashboard and select your app
   (`com.example.apple-samplecode.Emoji-RangersSXQJRCS9S9`).
2. Click **Create Notification**.
3. Set **Notification Type** to **Live Activity**.
4. Paste the **push-to-start token** (the `~75-byte` hex string from the Xcode
   console — not the regular APNs device token) into the **Device Token** field.
5. The dashboard automatically sets the APNs topic to
   `<bundle-id>.push-type.liveactivity` when **Live Activity** type is selected —
   this is why it works, unlike the generic "Push" type which uses the plain
   bundle ID topic.
6. Paste the JSON payload (see Section 3.1) into the **Payload** field.
7. Click **Send**.

> **Why the generic "Push" type fails:**
> Selecting **Push** (not Live Activity) in the console sends to the plain
> bundle ID topic. Live Activity pushes require the
> `<bundle-id>.push-type.liveactivity` topic, so you get:
> `"reason": "The device token doesn't match the specified topic."`
> Always select **Live Activity** type in the dashboard.

---

### 3.1 Payload structure

> **`timestamp` note:** JSON does not support shell substitutions, so the
> examples below use a fixed placeholder value. **Always replace it with the
> current Unix time before sending.** In the `curl` commands (Section 3.2 /
> 4.3) `'"$(date +%s)"'` does this automatically. In the Apple dashboard
> payload field, type the current epoch value manually — get it by running
> `date +%s` in your terminal.

```json
{
  "aps": {
    "timestamp": "<current Unix time — run: date +%s>",
    "event": "start",
    "input-push-token": 1,
    "attributes-type": "AdventureAttributes",
    "attributes": {
      "hero": {
        "name": "Power Panda",
        "avatar": "🐼",
        "healthLevel": 0.14,
        "heroType": "Forest Dweller",
        "healthRecoveryRatePerHour": 0.25,
        "url": "game:///panda",
        "battleCode": "game:///panda/battle",
        "level": 3,
        "exp": 600,
        "bio": "Power Panda loves eating bamboo shoots and leaves."
      }
    },
    "content-state": {
      "currentHealthLevel": 0.99,
      "eventDescription": "Panda Adventure begun!",
      "supercharged": false
    },
    "alert": {
      "title": "Panda Adventure begun",
      "body": "Start your adventure now!"
    }
  }
}
```

**Field notes:**

| Field | Required | Notes |
|---|---|---|
| `timestamp` | Yes | Unix epoch seconds. In `curl`: `'"$(date +%s)"'` (auto). In dashboard/JSON: paste the output of `date +%s` manually. Never use a hardcoded or future value — the system silently drops updates with a stale or future timestamp. |
| `event` | Yes | `"start"` to start, `"update"` to update, `"end"` to end |
| `input-push-token` | Yes (iOS 18+) | `1` — tells APNs to issue a fresh push-to-start token in response |
| `attributes-type` | Yes | Exact Swift type name: `"AdventureAttributes"` |
| `attributes` | Yes | Static fields of `AdventureAttributes` — must include the full `EmojiRanger` object with all required fields |
| `content-state` | Yes | Dynamic fields of `AdventureAttributes.ContentState` — **camelCase keys** |

---

### 3.2 Alternative: `curl` command

```bash
PUSH_TO_START_TOKEN="<paste latest token from Xcode console here>"
BUNDLE_ID="com.example.apple-samplecode.Emoji-RangersSXQJRCS9S9"

curl -v \
  --http2 \
  --header "apns-topic: ${BUNDLE_ID}.push-type.liveactivity" \
  --header "apns-push-type: liveactivity" \
  --header "apns-priority: 10" \
  --header "content-type: application/json" \
  --cert /path/to/your/AuthKey.p8 \
  --data '{
    "aps": {
      "timestamp": '"$(date +%s)"',
      "event": "start",
      "input-push-token": 1,
      "attributes-type": "AdventureAttributes",
      "attributes": {
        "hero": {
          "name": "Power Panda",
          "avatar": "🐼",
          "healthLevel": 0.14,
          "heroType": "Forest Dweller",
          "healthRecoveryRatePerHour": 0.25,
          "url": "game:///panda",
          "battleCode": "game:///panda/battle",
          "level": 3,
          "exp": 600,
          "bio": "Power Panda loves eating bamboo shoots and leaves."
        }
      },
      "content-state": {
        "currentHealthLevel": 0.99,
        "eventDescription": "Panda Adventure begun!",
        "supercharged": false
      },
      "alert": {
        "title": "Panda Adventure begun",
        "body": "Start your adventure now!"
      }
    }
  }' \
  "https://api.sandbox.push.apple.com/3/device/${PUSH_TO_START_TOKEN}"
```

> Use `api.push.apple.com` (no `sandbox`) for production builds.

---

## 4. Sending an Update or End Push

Once a Live Activity is running, use the **push-to-update token** (different from
the push-to-start token) to update or end it.

### 4.1 Payload field rules by event type

| Field | `start` | `update` | `end` |
|---|---|---|---|
| `timestamp` | Required | Required | Required |
| `event` | Required | Required | Required |
| `input-push-token` | Optional (iOS 18+) | **Must omit** | **Must omit** |
| `attributes-type` | Required | **Must omit** | **Must omit** |
| `attributes` | Required | **Must omit** | **Must omit** |
| `content-state` | Required | Required | Optional (shows final state) |
| `alert` | Optional | Optional | Must omit |
| `dismissal-date` | — | — | Optional |
| `stale-date` | — | Optional | — |
| `relevance-score` | — | Optional (`0.0`–`1.0`, max `1`) | — |

### 4.3 Token to use per event type

| Event | Token | Where it's logged |
|---|---|---|
| `start` | Push-to-start token (~75 bytes) | `[Push-to-Start] Token:` on app launch |
| `update` / `end` | Push-to-update token (~75 bytes) | `New push token:` after tapping "Go on adventure!" |

> These are **completely different tokens**. Using the push-to-start token for
> an update push will be silently ignored by APNs.

### 4.4 Update payload

> **Critical:** For `update` and `end` events, **do NOT include**
> `input-push-token`, `attributes-type`, or `attributes`. Those fields are
> only valid for `start`. Including them in an update payload causes
> ActivityKit's decoder to reject the entire payload silently — the Live
> Activity will not update even though APNs returns `200 OK`.

All three `content-state` fields are required (`currentHealthLevel`,
`eventDescription`, `supercharged`). Missing any field causes JSON decoding to
fail and the update is silently dropped.

> **`timestamp` note:** Replace `<current Unix time>` with the actual value
> before sending. Run `date +%s` in your terminal to get it. The `curl`
> command in Section 4.5 handles this automatically via `'"$(date +%s)"'`.

> **`stale-date` note:** Set to `timestamp + 30` (seconds). Without this the
> system may defer the visual re-render. Required to reliably update the Lock
> Screen and Dynamic Island UI.

> **`relevance-score` note:** A float between `0.0` and `1.0` (maximum value
> is `1`). Higher values bring the Live Activity closer to the top of the Lock
> Screen and into the Dynamic Island when multiple activities are running.
> Use `0.3`–`0.5` for routine updates and `0.7`–`1.0` for urgent ones.

**Confirmed working payload (verified on device):**

```json
{
  "aps": {
    "timestamp": 1772086310,
    "event": "update",
    "stale-date": 1772086340,
    "relevance-score": 0.7,
    "content-state": {
      "currentHealthLevel": 0.866,
      "eventDescription": "Panda is full now!",
      "supercharged": false
    },
    "alert": {
      "title": "Panda is full now!",
      "body": "Just relax."
    }
  }
}
```

**Template (replace timestamps before sending):**

```json
{
  "aps": {
    "timestamp": "<current Unix time — run: date +%s>",
    "event": "update",
    "stale-date": "<timestamp + 30 — run: $(($(date +%s) + 30))>",
    "relevance-score": 0.7,
    "content-state": {
      "currentHealthLevel": 0.0,
      "eventDescription": "Power Panda has been knocked down!",
      "supercharged": false
    },
    "alert": {
      "title": "Power Panda is knocked down!",
      "body": "Use a potion to heal Power Panda!"
    }
  }
}
```

### 4.5 `curl` command for update

```bash
ACTIVITY_PUSH_TOKEN="<paste 'New push token:' value from Xcode console>"
BUNDLE_ID="com.example.apple-samplecode.Emoji-RangersSXQJRCS9S9"

curl -v \
  --http2 \
  --header "apns-topic: ${BUNDLE_ID}.push-type.liveactivity" \
  --header "apns-push-type: liveactivity" \
  --header "apns-priority: 10" \
  --header "authorization: bearer $AUTHENTICATION_TOKEN" \
  --data '{
    "aps": {
      "timestamp": '"$(date +%s)"',
      "event": "update",
      "stale-date": '"$(($(date +%s) + 30))"',
      "relevance-score": 0.7,
      "content-state": {
        "currentHealthLevel": 0.0,
        "eventDescription": "Power Panda has been knocked down!",
        "supercharged": false
      },
      "alert": {
        "title": "Power Panda is knocked down!",
        "body": "Use a potion to heal Power Panda!",
        "sound": "default"
      }
    }
  }' \
  "https://api.sandbox.push.apple.com/3/device/${ACTIVITY_PUSH_TOKEN}"
```

### 4.6 End payload

> **`timestamp` / `dismissal-date` note:** Both are Unix epoch seconds.
> Setting `dismissal-date` equal to `timestamp` dismisses the Live Activity
> immediately. Set it to a future time (e.g. `timestamp + 3600`) to keep the
> final state visible on the Lock Screen for a period after ending. Omit it
> entirely to let the system decide when to remove it.

> **`alert` note:** Including an `alert` in the `end` payload shows a
> notification banner at the moment of dismissal — useful to inform the user
> the activity has concluded.

**Confirmed working payload (verified on device):**

```json
{
  "aps": {
    "timestamp": 1772086595,
    "event": "end",
    "dismissal-date": 1772086595,
    "content-state": {
      "currentHealthLevel": 0.866,
      "eventDescription": "Adventure over! Power Panda is taking a nap.",
      "supercharged": false
    },
    "alert": {
      "title": "Adventure over!",
      "body": "Power Panda is taking a nap."
    }
  }
}
```

**Template (replace timestamps before sending):**

```json
{
  "aps": {
    "timestamp": "<current Unix time — run: date +%s>",
    "event": "end",
    "dismissal-date": "<same as timestamp for immediate dismiss, or timestamp + seconds to linger>",
    "content-state": {
      "currentHealthLevel": 1.0,
      "eventDescription": "Adventure over! Power Panda is taking a nap.",
      "supercharged": false
    },
    "alert": {
      "title": "Adventure over!",
      "body": "Power Panda is taking a nap."
    }
  }
}
```

**`dismissal-date` behaviour:**

| Value | Effect |
|---|---|
| Equal to `timestamp` | Dismissed immediately |
| `timestamp + N seconds` | Final state lingers on Lock Screen for N seconds |
| Omitted | System decides (default ~4 hours) |

---

## 5. Common Errors

| Error | Cause | Fix |
|---|---|---|
| `The device token doesn't match the specified topic` | Wrong token type or wrong APNs topic | Use the correct token for the event type; set topic to `<bundle-id>.push-type.liveactivity`; select **Live Activity** type in the dashboard |
| APNs accepted (`200 OK`) but Live Activity doesn't update | Wrong token, stale/future `timestamp`, `attributes-type`/`attributes`/`input-push-token` included in update payload, missing `content-state` field, or non-existent sound file | Use push-to-update token; use `$(date +%s)` for timestamp; remove `attributes-type`, `attributes`, `input-push-token` from update/end payloads; include all three `content-state` fields; use `"sound": "default"` |
| Widget extension logs "Updating content" but Lock Screen / Dynamic Island visual doesn't change | Missing `stale-date` in payload, or iOS Simulator rendering bug | Add `"stale-date"` to the payload (see note below); test on a **real device** — the Simulator does not reliably re-render Live Activity UI on push updates |
| APNs accepted for `start` but no Live Activity appears | Stale push-to-start token, incomplete `attributes`, or snake_case keys | Use latest token from launch log; include full `EmojiRanger` object; use camelCase keys |
| Alert title/body shows raw key like `%@ is knocked down!` | `loc-key` not found in `.strings` file | Add a `Localizable.strings` file to the app target, or use plain string values |
| `Entitlement not found` in Xcode | `com.apple.developer.activitykit.push-notification-authoring` is not a valid key | Remove it — only `aps-environment` is needed |
| Live Activity starts but shows wrong data | `content-state` keys are snake_case | Use default `JSONEncoder` (no `keyEncodingStrategy`) — camelCase is required |

---

## 6. Displaying Images in Live Activities

Live Activities support custom images, but with strict constraints that cause
**silent failures** (blank space, no error, no crash) if violated.

### 6.1 How images work in Live Activities

The widget extension is a **separate process** from the main app. It cannot:
- Load images from the main app's asset catalog
- Use `AsyncImage` or make network requests at render time
- Reliably use `@AppStorage` / `UserDefaults` to pass image data
- Accept image data through `ContentState` (4KB limit — a photo blows through this instantly)

What it **can** do:
- Render images from its **own asset catalog** (build-time assets only)
- Load images from a **shared App Group container file** using `UIImage(contentsOfFile:)`

### 6.2 Correct approach for user-selected runtime images

```
Main app                          Widget extension
─────────────────────────────     ──────────────────────────────────
User picks photo via PhotosPicker
→ Scale to 108×108 px (36pt @3x)
→ JPEG encode (~5–15 KB)
→ Write to App Group container    →  UIImage(contentsOfFile: url.path)
  master_portrait.jpg                called inside view body at render time
```

**The image must be saved before the Live Activity starts.** The widget
extension reads the file at render time — if the file doesn't exist yet,
nothing is shown.

### 6.3 Image size limits (critical — official Apple constraint)

> **Apple documentation states:**
> "The system requires image assets for a Live Activity to use a resolution
> that's smaller or equal to the size of the presentation for a device.
> If you use an image asset that's larger than the size of the Live Activity
> presentation, the system **might fail to start the Live Activity**."
>
> — [Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)

The system **silently refuses** to render oversized images — no error, no
crash, just a blank space or a failed Live Activity start.

**Maximum image dimensions per presentation (from Apple HIG):**

| Presentation | Max size (points) | Max pixels @3x | Recommended JPEG |
|---|---|---|---|
| Lock Screen / banner (full width) | ~340 × 160 pt | 1020 × 480 px | ≤ 100 KB |
| Dynamic Island expanded (full) | ~371 × 84 pt | 1113 × 252 px | ≤ 60 KB |
| Dynamic Island expanded region (partial) | ~160 × 84 pt | 480 × 252 px | ≤ 30 KB |
| Dynamic Island compact leading/trailing | ~62 × 36 pt | 186 × 108 px | ≤ 10 KB |
| Dynamic Island minimal (attached) | ~45 × 36.67 pt | 135 × 110 px | ≤ 5 KB |

> For complete per-device specifications, see:
> [Human Interface Guidelines — Live Activities — Specifications](https://developer.apple.com/design/human-interface-guidelines/live-activities#Specifications)

**For a circular portrait avatar at 36 pt display size:**
- Max = **108 × 108 px @3x**
- Target JPEG size = **5–15 KB**
- `MasterPortraitStore` crops to a square and scales to exactly 108×108 px

Always **downscale and crop to a square** before saving. A full-resolution
photo (261 KB in testing) silently fails to render.

### 6.4 Implementation in this project

| File | Role |
|---|---|
| `MasterPortraitStore.swift` | Saves/loads the portrait via the App Group container. Crops to square and scales to 108×108 px before writing. |
| `AdventureLiveActivityView.swift` — `MasterPortraitView` | Reads the file with `UIImage(contentsOfFile:)` inside `body`. Renders as a 36 pt circle. |
| `AdventureActivityConfiguration.swift` | Uses `MasterPortraitView(size: 28)` in the expanded Dynamic Island trailing region. |
| `ContentView.swift` | `PhotosPicker` toolbar button — tap to pick, long-press to remove. Saves immediately via `MasterPortraitStore.save()`. |
| `Emoji Rangers.entitlements` | `com.apple.security.application-groups` set to `group.com.example.apple-samplecode.Emoji-RangersSXQJRCS9S9` |
| `EmojiRangersExtension.entitlements` | Same App Group — required so the widget extension can read the shared container |

### 6.5 App Group setup checklist

The entitlements file alone is **not sufficient**. You must also:

1. Select the **"Emoji Rangers"** target → **Signing & Capabilities** →
   **+ Capability** → **App Groups** → add
   `group.com.example.apple-samplecode.Emoji-RangersSXQJRCS9S9`
2. Select the **"EmojiRangerWidgetExtension"** target → same steps
3. Both targets must use the **same Apple Developer team**
4. Test on a **real device** — the Simulator may not enforce App Group
   sandboxing correctly

### 6.6 Usage flow

1. Open the app → tap **"Set Portrait"** in the top-right toolbar
2. Pick a photo — it is immediately scaled to 108×108 px and saved to the
   App Group container
3. Start a Live Activity by tapping **"Go on adventure!"**
4. The portrait appears as a circular avatar on the Lock Screen banner and
   in the expanded Dynamic Island
5. Long-press the portrait thumbnail in the toolbar to remove it

### 6.7 Common image display errors

| Symptom | Cause | Fix |
|---|---|---|
| Blank space where portrait should be | Image file too large (original photo resolution) | Re-pick the portrait after updating — `MasterPortraitStore` now scales to 108×108 px |
| Portrait shows in app but not in Live Activity | `UIImage(data:)` used instead of `UIImage(contentsOfFile:)`, or image saved after Live Activity started | Use `UIImage(contentsOfFile: url.path)` in widget view body; save portrait before starting activity |
| `containerURL` returns `nil` | App Groups capability not enabled in Xcode Signing & Capabilities | Add App Groups capability to both targets in Xcode |
| Portrait shows on first launch but disappears | App Group not provisioned on device (Simulator was masking the issue) | Ensure App Group is registered in Apple Developer portal and provisioning profiles are updated |

---

## 7. References

### Push Notifications
- [Apple Push Notifications Dashboard](https://icloud.developer.apple.com/dashboard/notifications)
- [Sending push notifications using command-line tools — Apple Developer](https://developer.apple.com/documentation/usernotifications/sending-push-notifications-using-command-line-tools)
- [Starting and updating Live Activities with ActivityKit push notifications — Apple Developer](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications)

### Live Activities — Core Documentation
- [Displaying live data with Live Activities — Apple Developer](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
  *(Contains the official 4KB data limit and image size constraint statements)*
- [Creating custom views for Live Activities — Apple Developer](https://developer.apple.com/documentation/activitykit/creating-custom-views-for-live-activities)
  *(Supplemental activity families, content margins, custom colors)*

### Live Activities — Design & Specifications
- [Human Interface Guidelines — Live Activities](https://developer.apple.com/design/human-interface-guidelines/live-activities)
- [Human Interface Guidelines — Live Activities — Specifications](https://developer.apple.com/design/human-interface-guidelines/live-activities#Specifications)
  *(Official per-device point and pixel dimensions for every presentation type)*

### WWDC Sessions
- [WWDC23 — Update Live Activities with push notifications](https://developer.apple.com/videos/play/wwdc2023/10185/)
- [WWDC23 — Design dynamic Live Activities](https://developer.apple.com/videos/play/wwdc2023/10194/)
- [WWDC24 — Broadcast updates to your Live Activities](https://developer.apple.com/videos/play/wwdc2024/10068/)

### Image Handling
- [Why Your Image Isn't Showing in a Live Activity — BleepingSwift](https://bleepingswift.com/blog/live-activity-image-not-showing)
  *(4KB limit, asset catalog requirements, image resolution constraints)*
- [Apple Developer Forums — Display Remote Image in a Live Activity](https://developer.apple.com/forums/thread/715170)
- [Apple Developer Forums — How to fetch an image in the Live Activity](https://developer.apple.com/forums/thread/716902)
