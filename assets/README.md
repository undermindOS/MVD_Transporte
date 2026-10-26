# MVD Transporte - Ícono de la app

## Diseño

Ómnibus blanco en vista frontal sobre el azul de marca de la app (#0066CC). Nada más.

**No uses símbolos oficiales** — nada de Escudo de Montevideo, ni bandera nacional
ni Sol de Mayo, ni marcas del STM / Intendencia. Esta es una app no oficial:
la política de Google Play sobre afirmaciones engañosas (Misleading Claims) y las
pautas de Apple consideran los íconos con apariencia de gobierno como falsa
afiliación. (El ícono anterior combinaba un ómnibus con el escudo de Montevideo
y se reemplazó por este motivo.)

## Archivos

| Archivo | Uso |
|---|---|
| `app_icon.png` | Ícono completo, fondo azul: iOS y launcher legacy de Android |
| `app_icon_foreground.png` | Ómnibus con fondo transparente dentro de la zona segura del 66%: primer plano del ícono adaptativo de Android y pantallas de inicio (splash) |

Ambos son de 1024×1024. El color de fondo adaptativo (#0066CC) está definido en
`pubspec.yaml` (`flutter_launcher_icons`); los colores del splash están en
`flutter_native_splash.yaml`.

## Regenerar los íconos de cada plataforma

```bash
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```
