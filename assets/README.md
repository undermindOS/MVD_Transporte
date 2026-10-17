# MVD Transporte - App Icon

## Design

White front-view bus on the app's brand blue (#0066CC). Nothing else.

**Do not use official symbols** — no Escudo de Montevideo, no national flag
or Sol de Mayo, no STM / Intendencia branding. This is an unofficial app:
Google Play's Misleading Claims policy and Apple's guidelines treat
government-looking icons as false affiliation. (The previous icon combined a
bus with the Montevideo coat of arms and was replaced for this reason.)

## Files

| File | Use |
|---|---|
| `app_icon.png` | Full icon, blue background: iOS and legacy Android launcher |
| `app_icon_foreground.png` | Transparent bus inside the 66% safe zone: Android adaptive foreground and splash screens |

Both are 1024×1024. The adaptive background color (#0066CC) is set in
`pubspec.yaml` (`flutter_launcher_icons`); splash colors are in
`flutter_native_splash.yaml`.

## Regenerate platform icons

```bash
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```
