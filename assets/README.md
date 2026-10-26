# Timbre MVD - App icon and splash

## Design

The Timbre MVD bus (brand board "Marca") lit on the night board: an amber
`#FFB21E` front-view city bus on ink `#0A1A3A`, with the bell and the LED
bar in its destination sign. The sign, windshield and corner lights are
see-through, so the unlit LEDs of the board (amber dots at 10 %) show
through them, and the lit bus blooms a little, like a real LED sign.
Nothing else: no text in the icon or in the splash.

The app draws the same icon in Flutter: `TimbreAppIcon(night: true)` on
the Info page.

**Amber is light, not paint.** It appears as LEDs on ink, never as flat
yellow and black blocks or stripes: in Uruguay that reads as football club
colors.

**Do not use official symbols** - no Escudo de Montevideo, no national flag
or Sol de Mayo, no STM / Intendencia branding, no bus company liveries or
logos. This is an unofficial app: Google Play's Misleading Claims policy and
Apple's guidelines treat government-looking icons as false affiliation.

## Files (all generated from the same vector, 1024 px unless noted)

| File | Use |
|---|---|
| `app_icon.png` | iOS (full-bleed square, iOS applies its own mask) |
| `app_icon_android.png` | Android < 8: rounded tile |
| `app_icon_background.png` | Android 8+ adaptive background: ink with unlit LEDs. The grid is 2/3 the pitch of the iOS one, because the launcher shows only the inner 72 of 108 dp |
| `app_icon_foreground.png` | Android 8+ adaptive foreground: the lit bus inside the 66 dp safe zone |
| `app_icon_monochrome.png` | Android 13+ themed icon: one color, sign and windshield cut out |
| `app_icon_ios_dark.png` | iOS 18 dark icon: the lit bus on transparent |
| `app_icon_ios_tinted.png` | iOS 18 tinted icon: the white bus on transparent, iOS tints it |
| `splash_icon.png` | 560 px: splash before Android 12 and iOS launch screen (140 dp/pt, bus 125 like Android 12) |
| `splash_icon_android12.png` | 1152 px: Android 12+ splash, bus inside the 768 px circle |

The status-bar icon for notifications is a vector drawable:
`android/app/src/main/res/drawable/ic_stat_timbre.xml` (white silhouette,
the sign and windshield are holes).

Colors: the splash is `#070F22`, the app background, day and night
(`flutter_native_splash.yaml`), so it opens into the app without a flash.
The Android window behind the app is the same color (`@color/noche` in
`values/styles.xml` and `values-night/styles.xml`): no white strip while
the keyboard opens or closes.

## Regenerate platform icons

```bash
dart run flutter_launcher_icons        # needs 0.14+ for the monochrome icon
dart run flutter_native_splash:create
```
