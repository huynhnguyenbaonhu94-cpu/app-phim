# Cinemora SwiftUI (prototype)

Native SwiftUI iOS app, kept alongside `mobile/` Expo app during the migration trial. It uses the existing public tRPC API at `https://cungcapicloud.id.vn`; it does not replace the existing website or backend.

## Stack

- SwiftUI, Swift concurrency, native `TabView` and `NavigationStack`
- iOS 26 Liquid Glass through `glassEffect` with an iOS 17+ material fallback
- AVPlayer for HLS, WKWebView for embed-only episodes
- XcodeGen project spec in `project.yml`

## Generate in Codemagic/macOS

```sh
brew install xcodegen
cd mobile-swiftui
xcodegen generate
open Cinemora.xcodeproj
```

The Ubuntu sandbox used for editing has no Xcode or Swift compiler, so the actual iOS compilation, simulator preview, signing, and IPA must be validated by Codemagic or Xcode on macOS.
