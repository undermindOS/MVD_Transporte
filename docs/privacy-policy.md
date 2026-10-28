# Política de privacidad — Timbre MVD

> Borrador. Revisarlo con un asesor legal y actualizar la fecha antes de
> publicarlo. Las tiendas piden una URL pública (por ejemplo GitHub Pages) y
> Google Play también un enlace dentro de la app. Revisar con el asesor el
> uso de Cloudflare (servidores fuera de Uruguay) según la Ley N° 18.331.
>
> Esta política da por hecho que las versiones de las tiendas se compilan
> con `MVD_PROXY_URL`, o sea, que usan el servidor intermediario (`proxy/`).
> Si se publica una versión sin él, revisá los párrafos que dicen «sin el
> servidor intermediario» y la sección de seguridad de los datos de
> `docs/store-listing.md`.

**Última actualización:** 27 de octubre de 2026

Timbre MVD es una aplicación no oficial, desarrollada por Liberon Tech,
de Khrestenkov & Co. No es una aplicación de la Intendencia de Montevideo ni de
ningún organismo de gobierno.

## Resumen

- No tenés que crear una cuenta.
- No usamos publicidad, analíticas ni rastreo.
- Lo que guardás en la app queda en tu teléfono. Las consultas de la app
  pasan por nuestro servidor intermediario, que pide los datos a la
  Intendencia y no guarda datos personales.
- Tu ubicación no sale del teléfono: las paradas cercanas se buscan en el
  dispositivo.

## Qué datos usa la app

Las versiones de la app que se publican en las tiendas hacen todas sus
consultas a través de nuestro servidor intermediario. Las versiones de
prueba compiladas sin ese servidor consultan directamente a la Intendencia;
donde eso cambia algo, se aclara en el párrafo correspondiente.

**Paradas, rutas y preferencias.** Los números de parada, rutas y líneas
que guardás, y la configuración del bloqueo biométrico, se almacenan solo en
tu dispositivo. Se borran al eliminar los datos de la app o desinstalarla.

**Tiempos de arribo, horarios y paradas.** La app los pide a un servidor
intermediario de Timbre MVD, alojado en Cloudflare, que a su vez consulta
los servicios públicos de la Intendencia (`api.montevideo.gub.uy`,
`geoserver.montevideo.gub.uy`) y agrega datos públicos del ómnibus, como si
tiene aire acondicionado o es de cero emisiones. Ese servidor recibe el
número de parada y datos técnicos de la conexión, como tu dirección IP. Usa
la IP solo para limitar la cantidad de consultas por minuto y evitar abusos;
no la guarda ni la asocia con otros datos, y a la Intendencia no le llega tu
IP sino la del servidor. El servidor no lleva un registro de las consultas:
lo único que anota son avisos de error fijos, como «transporteRest: HTTP
500», sin la dirección que pidió la app, sin números de parada y sin tu IP.
Cloudflare actúa como proveedor de alojamiento. Sin el servidor
intermediario, la app consulta directamente `api.montevideo.gub.uy`, y a la
Intendencia le llegan el número de parada y tu IP.

**Novedades y estado de los datos GPS.** También pasan por nuestro servidor
intermediario, que los pide a los servicios públicos de la Intendencia
(`api.montevideo.gub.uy`, `pci.montevideo.gub.uy`). Son consultas iguales
para todos, sin ningún dato tuyo; el servidor no guarda datos personales ni
registra las consultas ni tu IP, y a la Intendencia le llega la IP del
servidor, no la tuya. Sin el servidor intermediario, la app consulta esos
servicios directamente: las solicitudes llegan a la Intendencia, que las
trata según sus propias políticas, e incluyen datos técnicos como tu
dirección IP.

**Ubicación.** Solo si usás «Paradas cercanas»: la app obtiene tu ubicación
en ese momento y busca en el teléfono las paradas que están a menos de
400 m. Para eso usa la lista de todas las paradas de Montevideo, que
descarga de nuestro servidor intermediario sin mandar tu posición: es la
misma para todos, queda guardada en el teléfono y se actualiza como mucho
una vez por día (si llega sin las líneas de cada parada, se vuelve a pedir a
los 15 minutos). Tu ubicación no sale del dispositivo: no la
recibimos nosotros ni la Intendencia. Sin el servidor intermediario, la app
envía al servicio público de mapas de la Intendencia
(`geoserver.montevideo.gub.uy`) un área de unos 950 m de lado alrededor de
tu posición redondeada a tres decimales (unos 110 m), nunca la posición
exacta, y elige las paradas cercanas en el teléfono. No guardamos tu
ubicación. Podés negar el permiso; el resto de la app sigue funcionando.

**Mi STM, Recarga y Cómo Ir.** Se abren en el navegador de tu teléfono,
en los sitios oficiales. Tu usuario, contraseña, ID Uruguay o datos de pago
los ingresás directamente en esos sitios: la app no tiene acceso a ellos.

**Notificaciones.** Las alertas de ómnibus se generan en tu teléfono. No
usamos servicios de notificaciones remotas.

**Biometría.** La huella o Face ID las valida el sistema operativo; la app
solo recibe si la verificación fue correcta o no.

## Tus derechos

De acuerdo con la Ley N° 18.331 de Protección de Datos Personales, tenés
derecho de acceso, rectificación, actualización, inclusión y supresión. Como
no conservamos datos personales en servidores propios, podés ejercerlos
directamente borrando los datos de la app. Para consultas escribinos a
daniil@khrestenkov.com. También podés dirigirte a la Unidad Reguladora y de
Control de Datos Personales (URCDP).

## Menores

La app no está dirigida especialmente a menores y no recopila datos que
permitan identificarlos.

## Cambios

Si cambia el tratamiento de datos, actualizaremos esta política y la fecha
de arriba antes de publicar la nueva versión.
