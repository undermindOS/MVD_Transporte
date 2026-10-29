# Carta a la Intendencia de Montevideo (borrador, no enviada)

**Para:** pci@imm.gub.uy — contacto indicado en las condiciones de uso de
https://api.montevideo.gub.uy/apidocs/publictransport
**Asunto:** Consulta sobre el uso de servicios de transporte en una app no oficial (MVD Transporte)

---

Estimados:

Les escribo como desarrollador de **MVD Transporte**, una aplicación móvil
gratuita y no oficial para usuarios del transporte público de Montevideo.
El código es público: https://github.com/undermindOS/MVD_Transporte

La app permite guardar paradas, ver los próximos ómnibus, recibir un aviso
cuando el ómnibus se acerca y ver en un mapa dentro de la app los ómnibus con
GPS que vienen a las paradas guardadas. Mi STM, Recarga y Cómo Ir se abren en
sus sitios oficiales, en el navegador del teléfono. La app indica claramente que
no es oficial y que los datos provienen de la Intendencia.

Hoy la app consulta, a pedido del usuario, los mismos servicios que usa la
versión web de Cómo Ir:

- `api.montevideo.gub.uy/transporteRest/siguientesParada/{parada}`
- `api.montevideo.gub.uy/transporteRest/lineas/{parada}`
- `geoserver.montevideo.gub.uy` (WFS `imm:v_uptu_paradas`) para buscar paradas cercanas y ubicar
  en el mapa las paradas guardadas, pedidas por número

Frecuencia: una consulta cuando el usuario abre o actualiza una parada;
mientras Mis paradas o el mapa están a la vista, una consulta cada 30 s por
parada guardada, y, en segundo plano, como máximo una cada 15 minutos por parada
con alerta activa. Para el mapa, una consulta a geoserver por cada parada
guardada que todavía no tiene ubicación; después queda guardada en el teléfono.
Si no se encuentra, se vuelve a intentar como mucho cada 10 minutos.

Quisiera hacer las cosas de la forma que ustedes prefieran, por eso les
consulto:

1. ¿Puede una app de terceros usar esos servicios, o prefieren que migremos
   a la API documentada de Transporte Público, con registro en el portal?
   Si es lo segundo, ¿hay algún límite de consultas que debamos respetar?
2. ¿Podemos usar los servicios `notificacion/mensajes` (novedades y desvíos)
   y `pci.montevideo.gub.uy/buses/control` (estado de los datos GPS)?
3. Queremos mostrar en un mapa dentro de la app la posición de los ómnibus que
   devuelve `siguientesParada` (`coordinates`, con `real: true`) y la ubicación
   de las paradas de `imm:v_uptu_paradas`. El mapa base es de OpenStreetMap y
   viene dentro de la app: no usamos la cartografía de la Intendencia. ¿Hay
   algún inconveniente? ¿Con qué atribución prefieren que figure?
4. ¿Qué texto de atribución prefieren para los datos?
5. ¿Existe o se planea un servicio para consultar el saldo de la tarjeta
   STM con autorización del usuario?

Con gusto ajusto la app a lo que indiquen. Quedo a disposición para una
reunión o para compartir más detalles técnicos.

Saludos cordiales,

[Nombre]
[Correo de contacto]
MVD Transporte — https://github.com/undermindOS/MVD_Transporte
