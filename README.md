# Live Activity Practice

## Issues

### 1. APPLICATION_EXTENSION_API_ONLY
```
Showing All Messages
Application extensions and any libraries they link to must be built with the `APPLICATION_EXTENSION_API_ONLY` build setting set to YES.
```

Resolution:

Manually add `APPLICATION_EXTENSION_API_ONLY = YES;` to the build settings of the extension target.

```
        678085AF2F504CB40072A475 /* Debug */ = {
            isa = XCBuildConfiguration;
            buildSettings = {
                APPLICATION_EXTENSION_API_ONLY = YES;
                ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
                ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
                ASSETCATALOG_COMPILER_WIDGET_BACKGROUND_COLOR_NAME = WidgetBackground;
                CLANG_ANALYZER_NONNULL = YES;
                CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
                CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
                CLANG_ENABLE_MODULES = YES;
                CLANG_ENABLE_OBJC_ARC = YES;
                CLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
                CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
                CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
                CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
                CODE_SIGN_IDENTITY = "Apple Development";
                "CODE_SIGN_IDENTITY[sdk=iphoneos*]" = "iPhone Developer";
                CODE_SIGN_STYLE = Automatic;
                CURRENT_PROJECT_VERSION = 1;
                DEBUG_INFORMATION_FORMAT = dwarf;
                DEVELOPMENT_TEAM = XXX;
                ENABLE_USER_SCRIPT_SANDBOXING = YES;
                GCC_C_LANGUAGE_STANDARD = gnu17;
                GCC_PREPROCESSOR_DEFINITIONS = (
                    "DEBUG=1",
                    "$(inherited)",
                );
                GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
                GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
                GENERATE_INFOPLIST_FILE = YES;
                INFOPLIST_FILE = PromoActivityWidgetExtension/Info.plist;
                INFOPLIST_KEY_CFBundleDisplayName = PromoActivityWidgetExtension;
                INFOPLIST_KEY_NSHumanReadableCopyright = "Copyright © 2026 XXX. All rights reserved.";
                IPHONEOS_DEPLOYMENT_TARGET = 18.0;
                LD_RUNPATH_SEARCH_PATHS = (
                    "$(inherited)",
                    "@executable_path/Frameworks",
                    "@executable_path/../../Frameworks",
                );
                LOCALIZATION_PREFERS_STRING_CATALOGS = YES;
                MARKETING_VERSION = 1.0;
                MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
                MTL_FAST_MATH = YES;
                PRODUCT_BUNDLE_IDENTIFIER = com.xxx.xxx.PromoActivityWidgetExtension;
                PRODUCT_NAME = "$(TARGET_NAME)";
                SKIP_INSTALL = YES;
                STRING_CATALOG_GENERATE_SYMBOLS = YES;
                SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
                SWIFT_APPROACHABLE_CONCURRENCY = YES;
                SWIFT_EMIT_LOC_STRINGS = YES;
                SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES;
                SWIFT_VERSION = 5.0;
                TARGETED_DEVICE_FAMILY = "1,2";
            };
            name = Debug;
        };
```

### 2. Request activity fails: ActivityKit.ActivityAuthorizationError.unsupportedTarget

```
    // MARK: - Generic Request

    private func request(
        attributes: FreePrintsPromoAttributes,
        state: FreePrintsPromoAttributes.ContentState,
        promoType: PromoType,
        endTime: Date,
        errorPrefix: String
    ) {
        let content = ActivityContent(state: state, staleDate: endTime)
        do {
            // pushType: .token enables push-to-update AND push-to-start token delivery
            let activity = try Activity.request(
                attributes: attributes,
                content: content,
                //pushType: .token
                pushType: nil
            )
            activeActivities[promoType.rawValue] = activity.id
            activityStates[promoType.rawValue] = activity.activityState
            observeActivity(activity)
            errorMessage = nil
        } catch {
            errorMessage = "\(errorPrefix): \(error.localizedDescription)"
        }
    }
```

```
(lldb) po error
ActivityKit.ActivityAuthorizationError.unsupportedTarget
```

Resolution:

Verify `Info.plist` Entry: Adding the capability via the Xcode interface should automatically add the NSSupportsLiveActivities property to your app's Info.plist file (or the app's plist equivalent in modern Xcode projects). Manually verify this entry exists in the main app target's configuration.

```
<key>NSSupportsLiveActivities</key>
<true/>
``` 

### 3. payload's content-state is in-completed causing live activity cannot be triggered via push

our ContentState is incomplete
This is the main blocker.

Your Swift type:
```
public struct ContentState: Codable, Hashable {
    var promoTitle: String
    var promoSubtitle: String
    var discount: String
    var endTime: String
    var promoType: PromoType
    var progress: Double          // ❌ REQUIRED
    var currentStep: String       // ❌ REQUIRED
    var itemCount: Int
    var isExpired: Bool = false
}
```

But your push payload does NOT include:
```
"progress"
"currentStep"
```

Result
➡️ JSONDecoder fails

➡️ ActivityKit drops the start silently

➡️ No Live Activity appears

➡️ No logs

➡️ APNs still says 200 OK

Resolution:

```
Device Token: 8088aae94b3e802f14cba34b1fb2461244edf590c9082a28fe1c96119dbe1486c39960c07130cb0bc6cb4afe767ad50b1e92beaba03fcd80c989d3f4bfa15ce99b94344396c37b5a1ff520ee0eb596fa

{"aps":{"timestamp":1772177039,"event":"start","input-push-token":1,"attributes-type":"FreePrintsPromoAttributes","attributes":{"promoId":"abc","productType":"4x6 Prints"},"content-state":{"promoTitle":"promo title here","promoSubtitle":"promo sub title here","discount":"50% discount","endTime":"2026-02-27 17:30:00","promoType":"freePrints","progress":0,"currentStep":"","itemCount":20,"isExpired":false},"alert":{"title":"FreePrints promo begun","body":"Start to prints now!"}}}
```

### 4. How to debug widget process in Xcode?

Xcode -> Debug -> Attach to process -> Likely Targets -> <LiveActivityWidgetName>
