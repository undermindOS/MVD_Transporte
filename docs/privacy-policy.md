# Política de privacidad — MVD Transporte

> Borrador. Revisarlo con un asesor legal y actualizar la fecha antes de
> publicarlo. Las tiendas piden una URL pública (por ejemplo GitHub Pages) y
> Google Play también un enlace dentro de la app. Revisar con el asesor el
> uso de Cloudflare (servidores fuera de Uruguay) según la Ley N° 18.331.

**Última actualización:** [fecha]

MVD Transporte es una aplicación no oficial, desarrollada por undermindOS /
Liberon.tech. No es una aplicación de la Intendencia de Montevideo ni de
ningún organismo de gobierno.

## Resumen

- No tenés que crear una cuenta.
- No usamos publicidad, analíticas ni rastreo.
- Lo que guardás en la app queda en tu teléfono. Nuestro servidor
  intermediario solo reenvía consultas de horarios y no guarda datos
  personales.

## Qué datos usa la app

**Paradas, rutas y preferencias.** Los números de parada, rutas y líneas
que guardás, y la configuración del bloqueo biométrico, se almacenan solo en
tu dispositivo. Se borran al eliminar los datos de la app o desinstalarla.

**Tiempos de arribo, horarios y paradas.** La app los pide a un servidor
intermediario de MVD Transporte, alojado en Cloudflare, que a su vez consulta
los servicios públicos de la Intendencia (`api.montevideo.gub.uy`) y agrega
datos públicos del ómnibus, como si tiene aire acondicionado o es de cero
emisiones. Ese servidor recibe el número de parada y datos técnicos de la
conexión, como tu dirección IP. Usa la IP solo para limitar la cantidad de
consultas por minuto y evitar abusos; no la guarda ni la asocia con otros
datos, y a la Intendencia no le llega tu IP sino la del servidor. Cloudflare
actúa como proveedor de alojamiento.

**Novedades y estado de los datos GPS.** La app consulta directamente los
servicios públicos de la Intendencia (`api.montevideo.gub.uy`,
`pci.montevideo.gub.uy`). Esas solicitudes llegan a la Intendencia, que las
trata según sus propias políticas; incluyen datos técnicos como tu dirección
IP.

**Ubicación.** Solo si usás «Paradas cercanas»: la app obtiene tu ubicación
en ese momento y envía un área aproximada al servicio público de mapas de la
Intendencia para encontrar paradas. No guardamos tu ubicación ni la
recibimos. Podés negar el permiso; el resto de la app sigue funcionando.

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
zhongnanhaii@yahoo.com. También podés dirigirte a la Unidad Reguladora y de
Control de Datos Personales (URCDP).

## Menores

La app no está dirigida especialmente a menores y no recopila datos que
permitan identificarlos.

## Cambios

Si cambia el tratamiento de datos, actualizaremos esta política y la fecha
de arriba antes de publicar la nueva versión.
