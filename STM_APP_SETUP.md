# STM Montevideo - Flutter App Setup Guide

A production-ready Flutter wrapper application for the Montevideo STM transit card website.

## Features

✅ Full WebView integration with STM website
✅ Quick access to Top-Up (Recarga) section
✅ Bottom navigation bar for easy navigation
✅ Floating Action Button for instant top-up access
✅ Loading indicator while pages load
✅ Android hardware back button support
✅ STM branding colors (Blue/White theme)
✅ Full-screen immersive experience
✅ Proper error handling and navigation delegation

---

## Quick Start

### Prerequisites

- Flutter SDK (3.0.0 or higher)
- Android Studio / Xcode
- Android device/emulator or iOS device/simulator

### Installation Steps

1. **Install dependencies:**
   ```bash
   flutter pub get
   ```

2. **Run on device:**
   ```bash
   # For Android
   flutter run

   # For iOS
   flutter run -d ios
   ```

3. **Build release APK (Android):**
   ```bash
   flutter build apk --release
   ```

4. **Build release IPA (iOS):**
   ```bash
   flutter build ios --release
   ```

---

## File Structure

```
stm_montevideo/
├── lib/
│   └── main.dart                 # Main application code
├── android/
│   └── app/src/main/
│       └── AndroidManifest.xml   # Android permissions
├── ios/
│   └── Runner/
│       └── Info.plist            # iOS permissions
└── pubspec.yaml                  # Dependencies
```

---

## Permissions Configuration

### Android Permissions (AndroidManifest.xml)

The following permissions are configured in `android/app/src/main/AndroidManifest.xml`:

```xml
<!-- REQUIRED: Internet access for WebView -->
<uses-permission android:name="android.permission.INTERNET" />

<!-- OPTIONAL: Check network connectivity -->
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

**Key Android Settings:**
- `android:usesCleartextTraffic="false"` - Ensures HTTPS-only connections
- `android:hardwareAccelerated="true"` - Enables hardware acceleration for smooth WebView performance

### iOS Permissions (Info.plist)

The following configurations are set in `ios/Runner/Info.plist`:

```xml
<!-- App Transport Security - Internet access -->
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <false/>
    <key>NSExceptionDomains</key>
    <dict>
        <key>stm.gub.uy</key>
        <dict>
            <key>NSIncludesSubdomains</key>
            <true/>
            <key>NSTemporaryExceptionAllowsInsecureHTTPLoads</key>
            <false/>
            <key>NSTemporaryExceptionMinimumTLSVersion</key>
            <string>TLSv1.2</string>
        </dict>
    </dict>
</dict>
```

**Key iOS Settings:**
- Allows secure HTTPS connections to `stm.gub.uy`
- Enforces minimum TLS 1.2 for security
- Includes camera/photo permissions for potential future QR code scanning

---

## Dependencies (pubspec.yaml)

```yaml
dependencies:
  flutter:
    sdk: flutter

  webview_flutter: ^4.4.2              # Core WebView functionality
  webview_flutter_android: ^3.12.1     # Android-specific WebView
  webview_flutter_wkwebview: ^3.9.4    # iOS WKWebView implementation
  url_launcher: ^6.2.1                 # External link handling
  cupertino_icons: ^1.0.6              # iOS-style icons
```

---

## App Features Explained

### 1. WebView Implementation
- Loads the STM website: `https://stm.gub.uy/app/mistm/cuenta/`
- JavaScript enabled for full website functionality
- Proper navigation handling and back button support

### 2. Navigation Options

**Bottom Navigation Bar:**
- **Inicio (Home):** Navigate to the main STM account page
- **Recarga (Top-Up):** Direct access to the recharge section (highlighted in blue)
- **Actualizar (Reload):** Refresh the current page

**Floating Action Button:**
- Quick access to the Top-Up page from anywhere in the app
- Positioned at the bottom-right for easy thumb access

### 3. User Experience
- Loading spinner with "Cargando STM..." text while pages load
- Clean white background during loading
- STM blue color scheme (#0066CC)
- Smooth transitions between pages

### 4. Android Back Button
- Pressing back navigates through browser history
- Only exits app when no more history available
- Prevents accidental app closure

---

## Customization

### Change Colors
Edit the color values in [main.dart](lib/main.dart):
```dart
primaryColor: const Color(0xFF0066CC), // STM Blue
```

### Modify URLs
Change the URLs in [main.dart](lib/main.dart):
```dart
static const String _baseUrl = 'https://stm.gub.uy/app/mistm/cuenta/';
static const String _topUpUrl = 'https://stm.gub.uy/app/mistm/cuenta/#/recarga';
```

### Hide/Show FAB
Remove or comment out the `floatingActionButton` section in [main.dart](lib/main.dart).

---

## Troubleshooting

### WebView not loading
- Check internet connection
- Verify permissions in AndroidManifest.xml and Info.plist
- Check if STM website is accessible in a browser

### Android build errors
```bash
flutter clean
flutter pub get
flutter build apk
```

### iOS build errors
- Ensure you have a valid Apple Developer account
- Check Xcode is properly installed
- Run `pod install` in the ios directory if needed

### Loading indicator stuck
- The website might be taking longer to load
- Check console for JavaScript errors
- Verify network connectivity

---

## Production Deployment

### Android (Google Play Store)
1. Update `applicationId` in `android/app/build.gradle`
2. Create a keystore for signing
3. Build signed APK/AAB:
   ```bash
   flutter build appbundle --release
   ```

### iOS (App Store)
1. Update bundle identifier in Xcode
2. Configure signing certificates
3. Build and archive in Xcode
4. Submit via App Store Connect

---

## Support & Maintenance

- **Flutter Version:** Keep Flutter updated for latest WebView improvements
- **Dependencies:** Run `flutter pub upgrade` periodically
- **Testing:** Test on both Android and iOS devices before release

---

## License

This is a wrapper application for the official STM Montevideo website.
All STM branding and content belongs to the Sistema de Transporte Metropolitano de Montevideo.

---

## Contact & Updates

For issues or improvements, refer to the Flutter documentation:
- [Flutter WebView Package](https://pub.dev/packages/webview_flutter)
- [Flutter Documentation](https://docs.flutter.dev)

---

**Ready to deploy!** 🚀

Simply run `flutter run` to test the app, or `flutter build apk` for a production Android build.
