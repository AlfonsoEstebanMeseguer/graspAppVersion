#!/usr/bin/env node
//
// Genera los ocho avatares PNG (512×512, RGBA) a partir de los SVG de este directorio y
// los copia a apps/mobile/assets/avatars/.
//
//   cd assets/avatars && npm install && node build-pngs.js
//
// POR QUÉ ESTE SCRIPT EXISTE Y LOS SEIS ANTERIORES NO
// Hubo seis intentos (`convert-avatars.js`, `convert-avatars-node.js`,
// `convert-avatars.py`, `convert-with-resvg.js`, `create-png-placeholders.js`,
// `generate-pngs.js`) y ninguno funcionaba:
//
//   · `generate-pngs.js` escribía la cabecera PNG a mano y declaraba el chunk IHDR con
//     longitud 17 donde la especificación exige 13. Los ficheros parecían PNG y ningún
//     decodificador serio los aceptaba.
//   · `create-png-placeholders.js` ignoraba el parámetro `color` de Jimp, así que los
//     ocho avatares salían idénticos.
//   · `convert-with-resvg.js` usa `render()`, que no existe en @resvg/resvg-js v2 (la
//     API es la clase `Resvg`). Convertía 0 de 8 ficheros **y aun así imprimía
//     "✓ All avatars exported"**, copiando los PNG viejos por encima.
//   · El resto dependía de puppeteer, cairosvg o svg2png, que no están instalados.
//
// El resultado fue que durante todo el sprint los ocho avatares eran el mismo fichero
// corrupto, y no se vio porque `AvatarSelector` envuelve cada `Image.asset` en un
// `errorBuilder` que sustituye la imagen rota por un icono gris: ocho iconos idénticos
// se dieron por "ocho avatares renderizados".
//
// De ahí las dos reglas de este script:
//   1. Un fallo de conversión **aborta con código distinto de cero**. Nunca se informa de
//      éxito parcial como si fuera éxito.
//   2. Cada PNG se vuelve a leer y se comprueba antes de darlo por bueno.

const fs = require('fs');
const path = require('path');
const sharp = require('sharp');

const SIZE = 512;
const SRC_DIR = __dirname;
const OUT_DIR = path.resolve(__dirname, '../../apps/mobile/assets/avatars');

/** Comprueba que el buffer sea un PNG con un IHDR bien formado del tamaño esperado. */
function assertValidPng(buffer, label) {
  const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  if (!buffer.subarray(0, 8).equals(signature)) {
    throw new Error(`${label}: no empieza por la firma PNG`);
  }
  // Bytes 8-11: longitud del primer chunk. La especificación exige exactamente 13 para IHDR.
  const ihdrLength = buffer.readUInt32BE(8);
  if (ihdrLength !== 13) {
    throw new Error(`${label}: IHDR declara ${ihdrLength} bytes, la especificación exige 13`);
  }
  if (buffer.subarray(12, 16).toString('ascii') !== 'IHDR') {
    throw new Error(`${label}: el primer chunk no es IHDR`);
  }
  const width = buffer.readUInt32BE(16);
  const height = buffer.readUInt32BE(20);
  if (width !== SIZE || height !== SIZE) {
    throw new Error(`${label}: ${width}×${height}, se esperaba ${SIZE}×${SIZE}`);
  }
}

async function main() {
  const svgs = fs.readdirSync(SRC_DIR).filter((f) => f.endsWith('.svg')).sort();

  if (svgs.length === 0) {
    throw new Error(`No hay ningún .svg en ${SRC_DIR}`);
  }

  fs.mkdirSync(OUT_DIR, { recursive: true });

  const digests = new Map();

  for (const svg of svgs) {
    const name = path.basename(svg, '.svg');
    const srcPath = path.join(SRC_DIR, svg);
    const outPath = path.join(SRC_DIR, `${name}.png`);

    // `density` alto antes de rasterizar: sin él, sharp rasteriza el SVG a su tamaño
    // nominal y luego lo escala, y los bordes salen borrosos.
    const png = await sharp(srcPath, { density: 384 })
      .resize(SIZE, SIZE, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } })
      .png()
      .toBuffer();

    assertValidPng(png, name);

    fs.writeFileSync(outPath, png);
    fs.copyFileSync(outPath, path.join(OUT_DIR, `${name}.png`));

    const digest = require('crypto').createHash('md5').update(png).digest('hex');
    if (digests.has(digest)) {
      throw new Error(
        `${name}.png es byte a byte idéntico a ${digests.get(digest)}.png. ` +
        `Es el fallo del sprint de avatares repitiéndose: revisa los SVG de origen.`,
      );
    }
    digests.set(digest, name);

    console.log(`  ${name}.png  ${String(png.length).padStart(6)} bytes  ${digest.slice(0, 8)}`);
  }

  console.log(`\n${svgs.length} avatares generados en assets/avatars/ y copiados a`);
  console.log(path.relative(process.cwd(), OUT_DIR));
}

main().catch((err) => {
  console.error(`\nERROR: ${err.message}`);
  console.error('No se ha generado nada utilizable. Corrige el fallo y vuelve a ejecutar.');
  process.exit(1);
});
