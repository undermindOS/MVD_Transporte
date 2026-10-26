# Adding App Icon to MVD Transporte

> **Outdated.** The app is Timbre MVD now, and its icon and splash are the
> night board (amber bus on ink), not blue and white. The current files,
> colors and commands are in [assets/README.md](assets/README.md).

## 📱 Easy Method: Using flutter_launcher_icons

This is the **recommended and easiest** way to add your icon to the app.

### Step 1: Package Already Configured

The `flutter_launcher_icons` package is already added to `pubspec.yaml`.

### Step 2: Configuration is Ready

The configuration is already set in `pubspec.yaml`:

```yaml
flutter_launcher_icons:
  android: true
  ios: true
  image_path: "assets/app_icon.png"
  adaptive_icon_background: "#0066CC"  # Blue color
  adaptive_icon_foreground: "assets/app_icon_foreground.png"
```

### Step 3: Create Your App Icon

**Design Requirements:**
- 🚌 **Minimalist bus icon** (simple silhouette)
- 🚫 **No official symbols** — no coat of arms, flag or STM/IM branding (unofficial app; store policies treat them as false affiliation)
- **Size:** 1024x1024 pixels (PNG format)
- **Colors:** Blue (#0066CC) and white
- **Style:** Clean, modern, professional

**Design Tools:**
1. **Figma/Canva** - Create custom icon
2. **Flaticon/Icons8** - Download and combine elements
3. **AI Tools** - Generate with DALL-E or Midjourney

**Design Elements:**
- Simple bus silhouette (front or side view)
- Clean lines, minimalist style
- Must be legible at 48x48px size

Save your final icon as `app_icon.png` in the `assets/` folder.

See detailed design guidelines in `assets/README.md`

### Step 4: Generate the Icons

Once you have `app_icon.png` in the `assets` folder, run:

```bash
# Make sure you're in the project directory
cd /Users/undermind/Documents/liberonvpn/MiSTM_pre_alpha_v0/stm_app

# Install dependencies
flutter pub get

# Generate app icons for Android and iOS
dart run flutter_launcher_icons

# Clean and rebuild
flutter clean
flutter pub get
flutter build apk --release
```

---

## 🛠️ Manual Method: Replace Icon Files Directly

If you prefer to do it manually:

### Android

Replace these icon files with your design (PNG format):

- `android/app/src/main/res/mipmap-mdpi/ic_launcher.png` (48x48 px)
- `android/app/src/main/res/mipmap-hdpi/ic_launcher.png` (72x72 px)
- `android/app/src/main/res/mipmap-xhdpi/ic_launcher.png` (96x96 px)
- `android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png` (144x144 px)
- `android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png` (192x192 px)

### iOS

Replace the icon sets in:
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/`

You'll need icons in these sizes:
- 20x20, 29x29, 40x40, 60x60, 76x76, 83.5x83.5 (all @1x, @2x, @3x variants)

---

## 🎨 Quick Placeholder Icon

For testing purposes, you can use a simple placeholder:

1. Find any bus icon PNG online (512x512+)
2. Name it `app_icon.png`
3. Place in `assets/` folder
4. Generate icons with commands above
5. Replace with final design later

---

## ✅ Verify Your Icon

After adding the icon:

1. Uninstall the old app from your device
2. Rebuild and reinstall:
   ```bash
   flutter clean
   flutter build apk --release
   flutter install
   ```

3. Check your app drawer - you should see your new icon with "MVD Transporte" as the app name

---

## 🔧 Troubleshooting

**Icon not updating?**
- Uninstall the app completely
- Run `flutter clean`
- Rebuild the APK
- Clear device cache if needed
- Restart your device

**Icon looks stretched?**
- Use a square image (1:1 aspect ratio)
- Minimum 512x512 pixels, recommended 1024x1024 pixels
- PNG format with transparent background works best

**Colors look wrong?**
- Verify you're using #0066CC for primary blue
- Ensure PNG has proper color profile (sRGB)
- Test on actual device, not just emulator

---

## 📚 Additional Resources

- **Icon Design:** `assets/README.md` (detailed guidelines)
- **flutter_launcher_icons:** https://pub.dev/packages/flutter_launcher_icons
- **Android Icon Guidelines:** https://developer.android.com/guide/practices/ui_guidelines/icon_design_launcher
- **iOS Icon Guidelines:** https://developer.apple.com/design/human-interface-guidelines/app-icons

---

**Legal Note:** This is an unofficial app. Design should be original and not
copy any official branding from government agencies or transport companies.
