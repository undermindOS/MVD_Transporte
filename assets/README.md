# Timbre MVD - App icon and splash

## Design

The Timbre MVD bus (brand board "Marca"): white front-view city bus on the
flag blue #0038A8, with the bell and an amber LED bar in its destination
sign. Nothing else: no text in the icon or in the splash.

**Do not use official symbols** — no Escudo de Montevideo, no national flag
or Sol de Mayo, no STM / Intendencia branding, no bus company liveries or
logos. This is an unofficial app: Google Play's Misleading Claims policy and
Apple's guidelines treat government-looking icons as false affiliation.

## Files (all generated from the same vector, 1024 px unless noted)

| File | Use |
|---|---|
| `app_icon.png` | iOS (full-bleed square, iOS applies its own mask) |
| `app_icon_android.png` | Android < 8: rounded tile |
| `app_icon_foreground.png` | Android 8+ adaptive foreground, bus inside the 66 dp safe zone, over `#0038A8` |
| `app_icon_monochrome.png` | Android 13+ themed icon: one color, sign and windshield cut out |
| `app_icon_ios_dark.png` | iOS 18 dark and tinted icons: the bus on transparent |
| `splash_icon.png` | 560 px: splash before Android 12 and iOS launch screen (140 dp/pt, bus 125 like Android 12) |
| `splash_icon_android12.png` | 1152 px: Android 12+ splash, bus inside the 768 px circle |

The status-bar icon for notifications is a vector drawable:
`android/app/src/main/res/drawable/ic_stat_timbre.xml` (white silhouette,
the sign and windshield are holes).

Colors: icon background `#0038A8` in `pubspec.yaml`
(`flutter_launcher_icons`), splash `#0038A8` / night `#00266F` in
`flutter_native_splash.yaml`.

## Regenerate platform icons

```bash
dart run flutter_launcher_icons        # needs 0.14+ for the monochrome icon
dart run flutter_native_splash:create
```
