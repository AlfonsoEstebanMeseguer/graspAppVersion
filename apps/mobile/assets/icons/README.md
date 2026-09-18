# assets/icons

Set de iconos de la app. SVG, coherentes con la paleta de la Sección 5.1
(trazo `purple-700`, línea fina, remates redondeados), generados a partir de
`pictures/icons/icon-sketches.jpeg`.

## Convenciones

- `viewBox="0 0 24 24"`.
- Iconos de UI: **sin color propio**, para que el color lo ponga el tema. Los
  logotipos de terceros son la excepción.
- Nombre en kebab-case, con prefijo por familia: `provider-*`, `room-*`, `gift-*`.

## Inventario

Vacío por ahora: ningún icono de la app necesita todavía un SVG propio.

La marca de Grasp (el cerebro) **no** es un asset: se dibuja con `CustomPainter`
en `lib/core/ui/brand_mark.dart`, para poder animarla y escalarla sin pixelar.

## Pendiente

Los iconos de producto (sala, micrófono, regalo, VIP, mensaje, seguir, insignia,
racha, pánico) se generan cuando lleguen sus pantallas, no antes.

## Nota de marca

Ningún logotipo de terceros vive ya aquí: Grasp no ofrece acceso rápido con
proveedores sociales (`docs/decisions/0004-sin-login-social.md`). Si algún día se
reintroduce alguno, su logotipo estará sujeto a las guías de marca del proveedor
(tamaño, espacio de respeto y texto exacto del botón).
