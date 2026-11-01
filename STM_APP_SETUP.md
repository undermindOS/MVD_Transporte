# STM Montevideo - Guía de configuración de la app Flutter

Una aplicación Flutter lista para producción que funciona como contenedor (wrapper) del sitio web de la tarjeta de transporte STM de Montevideo.

## Funcionalidades

✅ Integración completa por WebView con el sitio web del STM
✅ Acceso rápido a la sección Recarga
✅ Barra de navegación inferior para moverte fácilmente
✅ Botón de acción flotante para acceder a la recarga al instante
✅ Indicador de carga mientras cargan las páginas
✅ Soporte para el botón físico de volver de Android
✅ Colores de marca del STM (tema azul/blanco)
✅ Experiencia inmersiva en pantalla completa
✅ Manejo de errores y delegación de navegación adecuados

---

## Inicio rápido

### Requisitos previos

- Flutter SDK (3.0.0 o superior)
- Android Studio / Xcode
- Dispositivo/emulador Android o dispositivo/simulador iOS

### Pasos de instalación

1. **Instalar las dependencias:**
   ```bash
   flutter pub get
   ```

2. **Ejecutar en el dispositivo:**
   ```bash
   # Para Android
   flutter run

   # Para iOS
   flutter run -d ios
   ```

3. **Compilar el APK de release (Android):**
   ```bash
   flutter build apk --release
   ```

4. **Compilar el IPA de release (iOS):**
   ```bash
   flutter build ios --release
   ```

---

## Estructura de archivos

```
stm_montevideo/
├── lib/
│   └── main.dart                 # Código principal de la aplicación
├── android/
│   └── app/src/main/
│       └── AndroidManifest.xml   # Permisos de Android
├── ios/
│   └── Runner/
│       └── Info.plist            # Permisos de iOS
└── pubspec.yaml                  # Dependencias
```

---

## Configuración de permisos

### Permisos de Android (AndroidManifest.xml)

Los siguientes permisos están configurados en `android/app/src/main/AndroidManifest.xml`:

```xml
<!-- REQUIRED: Internet access for WebView -->
<uses-permission android:name="android.permission.INTERNET" />

<!-- OPTIONAL: Check network connectivity -->
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

**Configuración clave de Android:**
- `android:usesCleartextTraffic="false"` - Garantiza conexiones solo por HTTPS
- `android:hardwareAccelerated="true"` - Activa la aceleración por hardware para que el WebView funcione con fluidez

### Permisos de iOS (Info.plist)

Las siguientes configuraciones están definidas en `ios/Runner/Info.plist`:

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

**Configuración clave de iOS:**
- Permite conexiones HTTPS seguras a `stm.gub.uy`
- Exige como mínimo TLS 1.2 por seguridad
- Incluye permisos de cámara/fotos para un posible escaneo de códigos QR en el futuro

---

## Dependencias (pubspec.yaml)

```yaml
dependencies:
  flutter:
    sdk: flutter

  webview_flutter: ^4.4.2              # Funcionalidad principal de WebView
  webview_flutter_android: ^3.12.1     # WebView específico de Android
  webview_flutter_wkwebview: ^3.9.4    # Implementación de WKWebView para iOS
  url_launcher: ^6.2.1                 # Manejo de enlaces externos
  cupertino_icons: ^1.0.6              # Íconos estilo iOS
```

---

## Explicación de las funcionalidades de la app

### 1. Implementación del WebView
- Carga el sitio web del STM: `https://stm.gub.uy/app/mistm/cuenta/`
- JavaScript habilitado para que el sitio funcione por completo
- Manejo adecuado de la navegación y soporte para el botón de volver

### 2. Opciones de navegación

**Barra de navegación inferior:**
- **Inicio:** Lleva a la página principal de la cuenta del STM
- **Recarga:** Acceso directo a la sección de recarga (resaltada en azul)
- **Actualizar:** Vuelve a cargar la página actual

**Botón de acción flotante:**
- Acceso rápido a la página de Recarga desde cualquier parte de la app
- Ubicado abajo a la derecha para alcanzarlo fácilmente con el pulgar

### 3. Experiencia de usuario
- Spinner de carga con el texto "Cargando STM..." mientras cargan las páginas
- Fondo blanco limpio durante la carga
- Esquema de colores azul STM (#0066CC)
- Transiciones suaves entre páginas

### 4. Botón de volver de Android
- Al tocar volver, se navega por el historial del navegador
- Solo sale de la app cuando no queda más historial
- Evita que la app se cierre por accidente

---

## Personalización

### Cambiar los colores
Editá los valores de color en [main.dart](lib/main.dart):
```dart
primaryColor: const Color(0xFF0066CC), // STM Blue
```

### Modificar las URLs
Cambiá las URLs en [main.dart](lib/main.dart):
```dart
static const String _baseUrl = 'https://stm.gub.uy/app/mistm/cuenta/';
static const String _topUpUrl = 'https://stm.gub.uy/app/mistm/cuenta/#/recarga';
```

### Ocultar/mostrar el FAB
Eliminá o comentá la sección `floatingActionButton` en [main.dart](lib/main.dart).

---

## Solución de problemas

### El WebView no carga
- Revisá la conexión a internet
- Verificá los permisos en AndroidManifest.xml e Info.plist
- Comprobá si el sitio web del STM abre en un navegador

### Errores de compilación en Android
```bash
flutter clean
flutter pub get
flutter build apk
```

### Errores de compilación en iOS
- Asegurate de tener una cuenta válida de Apple Developer
- Comprobá que Xcode esté bien instalado
- Ejecutá `pod install` en el directorio ios si hace falta

### El indicador de carga se queda trabado
- Puede que el sitio web esté tardando más en cargar
- Revisá la consola por errores de JavaScript
- Verificá la conectividad de red

---

## Despliegue en producción

### Android (Google Play Store)
1. Actualizá `applicationId` en `android/app/build.gradle`
2. Creá un keystore para la firma
3. Compilá el APK/AAB firmado:
   ```bash
   flutter build appbundle --release
   ```

### iOS (App Store)
1. Actualizá el bundle identifier en Xcode
2. Configurá los certificados de firma
3. Compilá y archivá en Xcode
4. Enviá la app a través de App Store Connect

---

## Soporte y mantenimiento

- **Versión de Flutter:** Mantené Flutter actualizado para tener las últimas mejoras del WebView
- **Dependencias:** Ejecutá `flutter pub upgrade` periódicamente
- **Pruebas:** Probá en dispositivos Android e iOS antes de publicar

---

## Licencia

Esta es una aplicación contenedora (wrapper) del sitio web oficial de STM Montevideo.
Toda la marca y el contenido del STM pertenecen al Sistema de Transporte Metropolitano de Montevideo.

---

## Contacto y actualizaciones

Para problemas o mejoras, consultá la documentación de Flutter:
- [Paquete WebView de Flutter](https://pub.dev/packages/webview_flutter)
- [Documentación de Flutter](https://docs.flutter.dev)

---

**¡Listo para desplegar!** 🚀

Simplemente ejecutá `flutter run` para probar la app, o `flutter build apk` para una compilación de producción para Android.
