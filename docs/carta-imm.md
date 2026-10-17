# Carta a la Intendencia de Montevideo (borrador, no enviada)

**Para:** pci@imm.gub.uy — contacto indicado en las condiciones de uso de
https://api.montevideo.gub.uy/apidocs/publictransport
**Asunto:** Consulta sobre el uso de servicios de transporte en una app no oficial (MVD Transporte)

---

Estimados:

Les escribo como desarrollador de **MVD Transporte**, una aplicación móvil
gratuita y no oficial para usuarios del transporte público de Montevideo.
El código es público: https://github.com/undermindOS/MVD_Transporte

La app permite guardar paradas, ver los próximos ómnibus y recibir un aviso
cuando el ómnibus se acerca. Mi STM, Recarga y Cómo Ir se abren en sus
sitios oficiales, en el navegador del teléfono. La app indica claramente que
no es oficial y que los datos provienen de la Intendencia.

Hoy la app consulta, a pedido del usuario, los mismos servicios que usa la
versión web de Cómo Ir:

- `api.montevideo.gub.uy/transporteRest/siguientesParada/{parada}`
- `api.montevideo.gub.uy/transporteRest/lineas/{parada}`
- `geoserver.montevideo.gub.uy` (WFS `imm:v_uptu_paradas`) para buscar paradas cercanas

Frecuencia: una consulta cuando el usuario abre o actualiza una parada y, en
segundo plano, como máximo una cada 15 minutos por parada con alerta activa.

Quisiera hacer las cosas de la forma que ustedes prefieran, por eso les
consulto:

1. ¿Puede una app de terceros usar esos servicios, o prefieren que migremos
   a la API documentada de Transporte Público, con registro en el portal?
   Si es lo segundo, ¿hay algún límite de consultas que debamos respetar?
2. ¿Podemos usar los servicios `notificacion/mensajes` (novedades y desvíos)
   y `pci.montevideo.gub.uy/buses/control` (estado de los datos GPS)?
3. ¿Podemos mostrar la cartografía base de la Intendencia (la capa que usa
   Cómo Ir) en un mapa dentro de la app? ¿Con qué atribución?
4. ¿Qué texto de atribución prefieren para los datos?
5. ¿Existe o se planea un servicio para consultar el saldo de la tarjeta
   STM con autorización del usuario?

Con gusto ajusto la app a lo que indiquen. Quedo a disposición para una
reunión o para compartir más detalles técnicos.

Saludos cordiales,

[Nombre]
[Correo de contacto]
MVD Transporte — https://github.com/undermindOS/MVD_Transporte
