# Avatares predeterminados — fuentes

Los ocho avatares de `apps/mobile/assets/avatars/*.png` **no se dibujan a mano**: los emite
`gen.py` como SVG a partir de una base común, y de ahí se rasterizan a PNG de 512×512.

## Por qué hay un generador y no ocho ficheros sueltos

Porque lo que los hace parecer una familia es que el cuerpo, los ojos, la boca, los pies y los
destellos sean **exactamente los mismos** en los ocho. Con ocho ficheros independientes, cualquier
retoque hay que repetirlo ocho veces y a la tercera dejan de coincidir. Aquí un cambio en la base
se aplica a todos por construcción.

Lo que varía por avatar está en la tabla `AVATARS` al final de `gen.py`: color de cuerpo, de fondo,
de pie, expresión de ojos y boca, postura de brazos y accesorio.

**El color pesa más que el accesorio.** A 96 px —el tamaño al que se pinta en el perfil— el detalle
del accesorio se empasta y lo único que distingue un avatar de otro de un vistazo es la pareja
cuerpo/fondo. Por eso ninguna pareja se repite; si añades uno nuevo, elige una que no exista.

## Regenerar

```bash
python design/avatars/gen.py        # escribe los .svg junto al script
```

Y para rasterizar (en Windows, con Edge; cualquier navegador headless vale):

```bash
msedge --headless=new --disable-gpu --hide-scrollbars \
  --screenshot=coding-user.png --window-size=512,512 file:///<ruta>/coding-user.svg
```

Los PNG resultantes van a `apps/mobile/assets/avatars/` con **el mismo nombre**: los ficheros son el
contrato con `AvatarType.assetPath`, y `avatar_assets_test.dart` comprueba que los ocho decodifican
y que no hay dos con bytes idénticos.

## Lo que NO hay que tocar

Los **slugs** (`gym`, `reader`, `music`, `coding`, `animal`, `normal_1`, `normal_2`, `normal_3`) son
un contrato con la base de datos: el `check` `profiles_preset_avatar_valid` de la migración
`20260813090000` solo acepta esos ocho. Cambiar un nombre de fichero es cosmético; cambiar un slug
rompe el `UPDATE` en el backend.
