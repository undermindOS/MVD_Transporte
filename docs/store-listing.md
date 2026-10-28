# Ficha de la tienda (Google Play / App Store)

> Borrador. Corresponde a la app con Mi STM, Recarga, Cómo Ir y Avisos
> abiertos en el navegador del sistema (sin WebView propio): mantenerlo así,
> la política de Spam de Google Play prohíbe «a webview of a website without
> permission».
>
> Las respuestas de seguridad de los datos valen para una build con
> `MVD_PROXY_URL`, que hace todas sus consultas al servidor intermediario
> (`proxy/`). Las versiones de las tiendas se compilan así, después de
> desplegar el proxy y correr `proxy/scripts/smoke.js` contra él.
>
> Requisito de Google Play para apps no oficiales con información de gobierno:
> fuentes verificables en la descripción y aclarar que la app no es un
> organismo de gobierno
> ([ayuda de Play](https://support.google.com/googleplay/android-developer/answer/9514050)).

## Español (principal)

**Nombre (≤ 30):** Timbre MVD

**Descripción corta (≤ 80):**
Horarios en vivo de ómnibus de Montevideo y alertas en tus paradas. No oficial.

**Descripción completa:**

Timbre MVD te muestra cuándo llega tu ómnibus a las paradas que usás todos
los días y te avisa cuando se está acercando.

• Mis paradas: guardá tus paradas y mirá los próximos ómnibus de un vistazo.
• Paradas cercanas: encontrá las paradas a tu alrededor sin saber el número.
  Se buscan en tu teléfono: tu ubicación no sale de él.
• Buscar por calles: encontrá una parada por los nombres de sus calles.
• En vivo o por horario: los ómnibus con ubicación GPS se marcan distinto de
  los horarios teóricos, para que sepas qué tan confiable es cada tiempo.
• Accesibilidad: los ómnibus accesibles se marcan con una silla de ruedas.
• Comodidad: los ómnibus con aire acondicionado y los de cero emisiones
  (eléctricos) se marcan en cada arribo.
• Horarios: consultá el horario teórico de una parada para días hábiles,
  sábados o domingos.
• Novedades: desvíos y cambios de líneas publicados por la Intendencia.
• Alertas: recibí una notificación cuando el ómnibus está a pocos minutos.
• Estoy esperando: tocá un ómnibus y la app lo sigue mientras esperás, con la
  pantalla apagada, y te avisa cuando está por llegar.
• Rutas: guardá un trayecto con tus líneas preferidas.
• Accesos rápidos a Mi STM, Recarga y Cómo Ir, que se abren en los sitios
  oficiales desde tu navegador.

**Aplicación no oficial.** Timbre MVD no es una aplicación de la
Intendencia de Montevideo ni de ningún organismo de gobierno, y no está
afiliada al Sistema de Transporte Metropolitano (STM) ni a las empresas de
transporte.

**Fuentes de la información:**
• Tiempos de arribo, horarios, paradas y sus líneas, novedades y estado del
  GPS: servicios en línea de la Intendencia de Montevideo, los mismos que usa
  Cómo Ir — https://m.montevideo.gub.uy/comoir/
• Datos de los ómnibus (aire acondicionado, cero emisiones), lista de
  paradas y destinos de las líneas: API de transporte público de Montevideo
  API — https://api.montevideo.gub.uy
• Mi STM y recarga de tarjeta: sitio oficial — https://stm.gub.uy
• Información del transporte: https://montevideo.gub.uy

Los tiempos son estimados y pueden variar. Para información oficial consultá
siempre los canales de la Intendencia de Montevideo.

Privacidad: tus paradas se guardan solo en tu teléfono y tu ubicación no
sale de él. No hay cuentas, publicidad ni analíticas.
Política: https://github.com/undermindOS/MVD_Transporte/blob/main/docs/privacy-policy.md

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
- El ícono, el splash, el widget y las notificaciones están descritos en
  [docs/design/10-superficies.md](design/10-superficies.md).

## Política de privacidad (Play Console → Contenido de la app)

URL de la política: https://github.com/undermindOS/MVD_Transporte/blob/main/docs/privacy-policy.md

Es el mismo archivo que muestra la app: viene dentro de ella y se abre en
Info → «Política de privacidad», en la pantalla «Privacidad», también sin
conexión (`lib/ui/privacy_policy_page.dart`). Las líneas citadas (`>`) del
archivo son notas para quien lo mantiene: la app no las muestra, pero la URL
de GitHub sí. La URL muestra lo que está en `main`, así que el texto
publicado y el de la app coinciden cuando esta versión está fusionada en
`main`.

## Seguridad de los datos (Play Console) — borrador

Revisar contra la implementación final antes de enviar. Valen para una build
con `MVD_PROXY_URL` (ver la nota de arriba).

| Pregunta | Respuesta propuesta | Por qué |
|---|---|---|
| ¿Recopila o comparte datos? | No | Lo único que sale del teléfono son las consultas al servidor intermediario, que se procesan de forma efímera (fila de abajo) |
| Ubicación | No recopilada | «Paradas cercanas» elige las paradas en el teléfono, con el catálogo `/v1/catalog/stops`, que se descarga sin coordenadas (`NearbyStopsService.fetchNearby` en `lib/services/nearby_stops_service.dart`). `test/proxy_privacy_test.dart` verifica que ningún pedido lleva la posición. Una build sin `MVD_PROXY_URL` sí manda un área aproximada al WFS de la Intendencia: con esa build la respuesta pasa a ser «Ubicación aproximada, funcionalidad de la app» |
| Paradas y rutas guardadas | No recopilado | Quedan en el dispositivo (Hive) |
| Consultas al servidor intermediario (número de parada, IP) | No recopilado: procesamiento efímero | El proxy en Cloudflare (`proxy/`) reenvía las consultas de arribos, paradas, horarios, catálogo de paradas, novedades y estado del GPS, y no guarda la IP ni el número de parada. La IP solo es la clave del límite de pedidos por minuto (`IP_LIMITER` en `proxy/wrangler.jsonc`). Los logs de Workers están apagados (`wrangler.jsonc` no tiene bloque `observability`) y los únicos mensajes de error son textos fijos `<fuente>: <tipo>`, sin URL ni IP (`respond()` en `proxy/src/index.js`). Confirmar con Google antes de enviar: la [ayuda de Play](https://support.google.com/googleplay/android-developer/answer/10787469) dice que lo procesado de forma efímera no aparece en la sección pública, pero en un lugar pide declararlo igual en el formulario y en las preguntas frecuentes dice que no hace falta |
| Credenciales de Mi STM | No recopilado | Se ingresan en el sitio oficial, en el navegador del sistema |
| Biometría | No recopilado | La valida el sistema operativo; la app recibe solo sí/no |
| Cifrado en tránsito | Sí | Todas las solicitudes son HTTPS |
| Eliminación de datos | El usuario borra los datos de la app o la desinstala | No hay datos en servidores del desarrollador |

Detalle de la privacidad del proxy y de los logs: [docs/design/contrato-v1.md](design/contrato-v1.md)
y [proxy/README.md](../proxy/README.md).

## Permisos de servicio en primer plano (Play Console → Contenido de la app)

Obligatorio desde Android 14: declarar el tipo y adjuntar un video por función.

| Tipo | Función | Descripción propuesta |
|---|---|---|
| `dataSync` (`FOREGROUND_SERVICE_DATA_SYNC`) | «Estoy esperando» | El usuario toca un ómnibus y elige «Avisarme cuando llegue». Mientras espera, la app descarga cada 30 s el tiempo de arribo de esa parada desde el servidor de la app, que lo toma del servicio público de la Intendencia, y lo muestra en una notificación fija con el botón «Dejar de esperar». El servicio termina solo cuando el ómnibus está a los minutos elegidos (avisa), cuando el viaje ya pasó o a los 60 min. No arranca solo ni al reiniciar el teléfono. |

Video: tocar un ómnibus en «Mis paradas» → «Avisarme cuando llegue» → apagar
la pantalla → notificación fija que se actualiza → aviso de llegada.

Apple App Privacy: «Data Not Collected». En una build con `MVD_PROXY_URL` la
ubicación no sale del teléfono. Una build sin él manda un área aproximada a la
Intendencia: con esa build habría que declarar la ubicación aproximada (App
Functionality, no vinculada al usuario, sin tracking).
