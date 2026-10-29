# Timbre MVD - Ícono de la app y pantalla de inicio

## Diseño

El ómnibus de Timbre MVD (la lámina «Marca» del diseño) encendido sobre el tablero
nocturno: un ómnibus urbano ámbar `#FFB21E` en vista frontal sobre tinta `#0A1A3A`,
con el timbre y la barra de LED en su cartel de destino. El cartel, el parabrisas y
las luces de las esquinas son transparentes, así que a través de ellos se ven los
LED apagados del tablero (puntos ámbar al 10 %), y el ómnibus encendido brilla un
poco, como un cartel de LED de verdad. Nada más: ni texto en el ícono ni en la
pantalla de inicio.

La app dibuja el mismo ícono en Flutter: `TimbreAppIcon` en la página Info
(`lib/ui/info_page.dart`).

**El ámbar es luz, no pintura.** Aparece como LED sobre tinta, nunca como bloques o
franjas planas amarillas y negras: en Uruguay eso se lee como los colores de un club
de fútbol.

**No uses símbolos oficiales** — nada de Escudo de Montevideo, ni bandera nacional
ni Sol de Mayo, ni marcas del STM / Intendencia, ni colores ni logos de las empresas
de ómnibus. Esta es una app no oficial: la política de Google Play sobre afirmaciones
engañosas (Misleading Claims) y las pautas de Apple consideran los íconos con
apariencia de gobierno como falsa afiliación.

## Archivos (todos salen del mismo vector; 1024 px salvo que se indique otra cosa)

| Archivo | Uso |
|---|---|
| `app_icon.png` | iOS (cuadrado a sangre; iOS aplica su propia máscara) |
| `app_icon_android.png` | Android < 8: baldosa redondeada |
| `app_icon_background.png` | Fondo del ícono adaptativo de Android 8+: tinta con LED apagados. La grilla tiene 2/3 del paso de la de iOS, porque el launcher muestra solo los 72 dp interiores de 108 |
| `app_icon_foreground.png` | Primer plano del ícono adaptativo de Android 8+: el ómnibus encendido dentro de la zona segura de 66 dp |
| `app_icon_monochrome.png` | Ícono temático de Android 13+: un solo color, con el cartel y el parabrisas recortados |
| `app_icon_ios_dark.png` | Ícono oscuro de iOS 18: el ómnibus encendido sobre transparente |
| `app_icon_ios_tinted.png` | Ícono teñido de iOS 18: el ómnibus blanco sobre transparente; iOS lo tiñe |
| `splash_icon.png` | 560 px: pantalla de inicio antes de Android 12 y launch screen de iOS (140 dp/pt, ómnibus de 125, como en Android 12) |
| `splash_icon_android12.png` | 1152 px: pantalla de inicio de Android 12+, el ómnibus dentro del círculo de 768 px |

El ícono de la barra de estado para las notificaciones es un vector drawable:
`android/app/src/main/res/drawable/ic_stat_timbre.xml` (silueta blanca; el cartel y
el parabrisas son huecos).

Colores: la pantalla de inicio es `#070F22`, el fondo de la app, de día y de noche
(`flutter_native_splash.yaml`), así la app abre sin un destello. La ventana de
Android detrás de la app es del mismo color (`@color/noche` en `values/styles.xml`,
`values-night/styles.xml` y sus variantes `-v31` para Android 12+): no aparece una
franja blanca mientras el teclado se abre o se cierra.

## Regenerar los íconos de cada plataforma

```bash
dart run flutter_launcher_icons        # hace falta la 0.14+ para el ícono monocromo
dart run flutter_native_splash:create
```

`flutter_native_splash:create` reescribe `values-v31/styles.xml` y
`values-night-v31/styles.xml`: después de correrlo, volvé a poner `@color/noche`
como `android:windowBackground`.
