# Two Play Store apps (required)

Google Play needs a **unique applicationId** for each listing.

| App | applicationId / package | Project folder |
|---|---|---|
| Customer (Sheetal Ice Cream) | `in.easycloud.sheetal_ice_creams` | `sheetal_icecream` |
| Partner (delivery boys) | `in.easycloud.sheetal_partner` | `sheetal_driver_app` |

Same company brand is fine. Same Firebase **project** (`sheetal-1430e`) is fine.
You must still register **two Android apps** inside that Firebase project (one per package).

## Partner app is already set to

```text
applicationId = in.easycloud.sheetal_partner
namespace     = in.easycloud.sheetal_partner
iOS bundle    = in.easycloud.sheetalPartner
```

## Firebase (Partner only)

1. Firebase Console → project `sheetal-1430e`
2. Add Android app → package name exactly: `in.easycloud.sheetal_partner`
3. Download `google-services.json` → put in `sheetal_driver_app/android/app/`
4. Copy the new `mobilesdk_app_id` into `lib/firebase_options.dart` (`android.appId`)
5. (Optional iOS) Add iOS app with bundle `in.easycloud.sheetalPartner`

## Play Console

Create **two** apps:

1. Sheetal Ice Cream → upload AAB from `sheetal_icecream`
2. Sheetal Partner → upload AAB from `sheetal_driver_app`

They can share one Google Play developer account, but must be separate listings.
