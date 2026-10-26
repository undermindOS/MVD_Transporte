# Ficha de la tienda (Google Play / App Store)

> Borrador. Corresponde a la app con Mi STM, Recarga, Cómo Ir y Avisos
> abiertos en el navegador del sistema (sin WebView propio): mantenerlo así,
> la política de Spam de Google Play prohíbe «a webview of a website without
> permission».
>
> Requisito de Google Play para apps no oficiales con información de gobierno:
> fuentes verificables en la descripción y aclarar que la app no es un
> organismo de gobierno
> ([ayuda de Play](https://support.google.com/googleplay/android-developer/answer/9514050)).

## Español (principal)

**Nombre (≤ 30):** MVD Transporte

**Descripción corta (≤ 80):**
Horarios en vivo de ómnibus de Montevideo y alertas en tus paradas. No oficial.

**Descripción completa:**

MVD Transporte te muestra cuándo llega tu ómnibus a las paradas que usás todos
los días y te avisa cuando se está acercando.

• Mis paradas: guardá tus paradas y mirá los próximos ómnibus de un vistazo.
• Paradas cercanas: encontrá las paradas a tu alrededor sin saber el número.
• En vivo o por horario: los ómnibus con ubicación GPS se marcan distinto de
  los horarios teóricos, para que sepas qué tan confiable es cada tiempo.
• Accesibilidad: los ómnibus accesibles se marcan con ♿.
• Horarios: consultá el horario teórico de una parada para días hábiles,
  sábados o domingos.
• Novedades: desvíos y cambios de líneas publicados por la Intendencia.
• Alertas: recibí una notificación cuando el ómnibus está a pocos minutos.
• Estoy esperando: tocá un ómnibus y la app lo sigue mientras esperás, con la
  pantalla apagada, y te avisa cuando está por llegar.
• Rutas: guardá un trayecto con tus líneas preferidas.
• Accesos rápidos a Mi STM, Recarga y Cómo Ir, que se abren en los sitios
  oficiales desde tu navegador.

**Aplicación no oficial.** MVD Transporte no es una aplicación de la
Intendencia de Montevideo ni de ningún organismo de gobierno, y no está
afiliada al Sistema de Transporte Metropolitano (STM) ni a las empresas de
transporte.

**Fuentes de la información:**
• Tiempos de arribo, horarios, paradas y novedades: servicios en línea de la
  Intendencia de Montevideo, los mismos que usa Cómo Ir —
  https://m.montevideo.gub.uy/comoir/
• Mi STM y recarga de tarjeta: sitio oficial — https://stm.gub.uy
• Información del transporte: https://montevideo.gub.uy

Los tiempos son estimados y pueden variar. Para información oficial consultá
siempre los canales de la Intendencia de Montevideo.

Privacidad: tus paradas se guardan solo en tu teléfono. No hay cuentas,
publicidad ni analíticas. Política: <URL de docs/privacy-policy.md publicada>

## English

**Short description:**
Live Montevideo bus arrivals and alerts for your stops. Unofficial app.

**Full description:** translate the Spanish text above; keep the
"unofficial app" paragraph and the source links unchanged.

## Gráficos

- Ícono: `assets/app_icon.png` (el ómnibus encendido en ámbar sobre el
  tablero oscuro, sin escudo ni símbolos oficiales). Para Play (512 px):
  el mismo archivo reducido.
- Capturas: solo pantallas propias de la app (Mis paradas, Rutas, alertas).
  No usar capturas de stm.gub.uy ni logos del STM o la Intendencia.

## Seguridad de los datos (Play Console) — borrador

Revisar contra la implementación final antes de enviar.

| Pregunta | Respuesta propuesta | Por qué |
|---|---|---|
| ¿Recopila o comparte datos? | Ubicación aproximada, para «Paradas cercanas» | Esa función envía un área alrededor del usuario al servicio público de la Intendencia (WFS) para obtener paradas; no se envía al desarrollador |
| Paradas y rutas guardadas | No recopilado | Quedan en el dispositivo (Hive) |
| Credenciales de Mi STM | No recopilado | Se ingresan en el sitio oficial, en el navegador del sistema |
| Biometría | No recopilado | La valida el sistema operativo; la app recibe solo sí/no |
| Cifrado en tránsito | Sí | Todas las solicitudes son HTTPS |
| Eliminación de datos | El usuario borra los datos de la app o la desinstala | No hay datos en servidores del desarrollador |

## Permisos de servicio en primer plano (Play Console → Contenido de la app)

Obligatorio desde Android 14: declarar el tipo y adjuntar un video por función.

| Tipo | Función | Descripción propuesta |
|---|---|---|
| `dataSync` (`FOREGROUND_SERVICE_DATA_SYNC`) | «Estoy esperando» | El usuario toca un ómnibus y elige «Avisarme cuando llegue». Mientras espera, la app descarga cada 30 s el tiempo de arribo de esa parada desde el servicio público de la Intendencia y lo muestra en una notificación fija con el botón «Dejar de esperar». El servicio termina solo cuando el ómnibus está a los minutos elegidos (avisa), cuando el viaje ya pasó o a los 60 min. No arranca solo ni al reiniciar el teléfono. |

Video: tocar un ómnibus en «Mis paradas» → «Avisarme cuando llegue» → apagar
la pantalla → notificación fija que se actualiza → aviso de llegada.

Apple App Privacy: «Data Not Collected», salvo la ubicación aproximada de
«Paradas cercanas» (App Functionality, no vinculada al usuario, sin tracking).
