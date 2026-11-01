# Agregar el ícono de la app en MVD Transporte

> **Desactualizado.** La app ahora es Timbre MVD, y su ícono y su pantalla de inicio
> son el tablero nocturno (el ómnibus ámbar sobre tinta), no azul y blanco. Los archivos,
> colores y comandos actuales están en [assets/README.md](assets/README.md).

## 📱 Método fácil: con flutter_launcher_icons

Esta es la forma **recomendada y más fácil** de agregar tu ícono a la app.

### Paso 1: El paquete ya está configurado

El paquete `flutter_launcher_icons` ya está agregado en `pubspec.yaml`.

### Paso 2: La configuración está lista

La configuración ya está definida en `pubspec.yaml`:

```yaml
flutter_launcher_icons:
  android: true
  ios: true
  image_path: "assets/app_icon.png"
  adaptive_icon_background: "#0066CC"  # Color azul
  adaptive_icon_foreground: "assets/app_icon_foreground.png"
```

### Paso 3: Crear el ícono de tu app

**Requisitos de diseño:**
- 🚌 **Ícono minimalista de ómnibus** (silueta simple)
- 🚫 **Sin símbolos oficiales** — nada de escudo, bandera ni marcas del STM/IM (app no oficial; las políticas de las tiendas los consideran una falsa afiliación)
- **Tamaño:** 1024x1024 píxeles (formato PNG)
- **Colores:** Azul (#0066CC) y blanco
- **Estilo:** Limpio, moderno, profesional

**Herramientas de diseño:**
1. **Figma/Canva** - Creá un ícono personalizado
2. **Flaticon/Icons8** - Descargá y combiná elementos
3. **Herramientas de IA** - Generalo con DALL-E o Midjourney

**Elementos de diseño:**
- Silueta simple de ómnibus (vista frontal o lateral)
- Líneas limpias, estilo minimalista
- Tiene que ser legible en un tamaño de 48x48px

Guardá tu ícono final como `app_icon.png` en la carpeta `assets/`.

Mirá las pautas de diseño detalladas en `assets/README.md`

### Paso 4: Generar los íconos

Cuando tengas `app_icon.png` en la carpeta `assets`, ejecutá:

```bash
# Asegurate de estar en el directorio del proyecto
cd /Users/undermind/Documents/liberonvpn/MiSTM_pre_alpha_v0/stm_app

# Instalar las dependencias
flutter pub get

# Generar los íconos de la app para Android e iOS
dart run flutter_launcher_icons

# Limpiar y recompilar
flutter clean
flutter pub get
flutter build apk --release
```

---

## 🛠️ Método manual: reemplazar los archivos del ícono directamente

Si preferís hacerlo a mano:

### Android

Reemplazá estos archivos de ícono con tu diseño (formato PNG):

- `android/app/src/main/res/mipmap-mdpi/ic_launcher.png` (48x48 px)
- `android/app/src/main/res/mipmap-hdpi/ic_launcher.png` (72x72 px)
- `android/app/src/main/res/mipmap-xhdpi/ic_launcher.png` (96x96 px)
- `android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png` (144x144 px)
- `android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png` (192x192 px)

### iOS

Reemplazá los conjuntos de íconos en:
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/`

Vas a necesitar íconos en estos tamaños:
- 20x20, 29x29, 40x40, 60x60, 76x76, 83.5x83.5 (todas las variantes @1x, @2x, @3x)

---

## 🎨 Ícono provisorio rápido

Para hacer pruebas, podés usar un ícono provisorio simple:

1. Buscá en internet cualquier ícono de ómnibus en PNG (512x512+)
2. Nombralo `app_icon.png`
3. Ponelo en la carpeta `assets/`
4. Generá los íconos con los comandos de arriba
5. Más adelante reemplazalo por el diseño final

---

## ✅ Verificar tu ícono

Después de agregar el ícono:

1. Desinstalá la app vieja de tu dispositivo
2. Recompilá y reinstalá:
   ```bash
   flutter clean
   flutter build apk --release
   flutter install
   ```

3. Revisá el cajón de aplicaciones - deberías ver tu ícono nuevo con "MVD Transporte" como nombre de la app

---

## 🔧 Solución de problemas

**¿El ícono no se actualiza?**
- Desinstalá la app por completo
- Ejecutá `flutter clean`
- Recompilá el APK
- Borrá la caché del dispositivo si hace falta
- Reiniciá tu dispositivo

**¿El ícono se ve estirado?**
- Usá una imagen cuadrada (relación de aspecto 1:1)
- Mínimo 512x512 píxeles, recomendado 1024x1024 píxeles
- Lo que mejor funciona es un PNG con fondo transparente

**¿Los colores se ven mal?**
- Verificá que estés usando #0066CC para el azul principal
- Asegurate de que el PNG tenga el perfil de color correcto (sRGB)
- Probalo en un dispositivo real, no solo en el emulador

---

## 📚 Recursos adicionales

- **Diseño del ícono:** `assets/README.md` (pautas detalladas)
- **flutter_launcher_icons:** https://pub.dev/packages/flutter_launcher_icons
- **Pautas de íconos de Android:** https://developer.android.com/guide/practices/ui_guidelines/icon_design_launcher
- **Pautas de íconos de iOS:** https://developer.apple.com/design/human-interface-guidelines/app-icons

---

**Nota legal:** Esta es una app no oficial. El diseño tiene que ser original y no
copiar ninguna marca oficial de organismos de gobierno ni de empresas de transporte.
