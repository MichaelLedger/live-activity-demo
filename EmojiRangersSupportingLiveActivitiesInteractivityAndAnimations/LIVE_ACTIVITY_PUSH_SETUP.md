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

---

## 3. Sending a Push-to-Start via `curl`

### Why the Apple Push Console doesn't work

The Apple Push Notification Console always sends to the app's main bundle ID
topic. Live Activity pushes require a **different topic**:

```
<bundle-id>.push-type.liveactivity
```

The console has no way to set a custom topic, so it always returns:

```json
{ "reason": "The device token doesn't match the specified topic." }
```

You must use `curl` (or a server-side APNs client) instead.

---

### 3.1 Payload structure

```json
{
  "aps": {
    "timestamp": 1740000000,
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
| `timestamp` | Yes | Unix epoch seconds — use `$(date +%s)` |
| `event` | Yes | `"start"` to start, `"update"` to update, `"end"` to end |
| `input-push-token` | Yes (iOS 18+) | `1` — tells APNs to issue a fresh push-to-start token in response |
| `attributes-type` | Yes | Exact Swift type name: `"AdventureAttributes"` |
| `attributes` | Yes | Static fields of `AdventureAttributes` — must include the full `EmojiRanger` object with all required fields |
| `content-state` | Yes | Dynamic fields of `AdventureAttributes.ContentState` — **camelCase keys** |

---

### 3.2 `curl` command

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

## 4. Common Errors

| Error | Cause | Fix |
|---|---|---|
| `The device token doesn't match the specified topic` | Sent to wrong token or wrong topic | Use push-to-start token + `.push-type.liveactivity` topic |
| APNs accepted but nothing happens | Wrong token (stale), snake_case keys, or incomplete `attributes` | Use latest token from log; use camelCase keys; include all `EmojiRanger` fields |
| `Entitlement not found` in Xcode | `com.apple.developer.activitykit.push-notification-authoring` is not a real key | Remove it — only `aps-environment` is needed |
| Live Activity starts but shows wrong data | `content-state` keys are snake_case | Switch encoder to default (camelCase) |

---

## 5. References

- [Sending push notifications using command-line tools — Apple Developer](https://developer.apple.com/documentation/usernotifications/sending-push-notifications-using-command-line-tools)
- [Starting and updating Live Activities with ActivityKit push notifications — Apple Developer](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications)
