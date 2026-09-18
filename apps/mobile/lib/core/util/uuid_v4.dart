import 'dart:math';

/// Genera un UUID v4 en el formato canónico `8-4-4-4-12` en minúsculas.
///
/// ## Por qué escrito a mano y no `package:uuid`
///
/// El proyecto no tiene esa dependencia, ni transitivamente (`pubspec.lock` no la trae), y esto son
/// veinte líneas contra una dependencia entera. Lo que sí importa es el **origen de la
/// aleatoriedad**: `Random.secure()` y no `Random()`.
///
/// No es paranoia criptográfica: la clave de idempotencia de `messaging-send` es la que decide si
/// un envío es nuevo o un reintento, sobre el índice único
/// `direct_messages (sender_id, idempotency_key)`. `Random()` sin semilla se inicializa desde el
/// reloj, así que dos instalaciones que arranquen a la vez pueden generar la misma secuencia; una
/// colisión ahí no es un fallo visible, es un **mensaje que desaparece** porque el backend lo toma
/// por un reintento y devuelve un 200 con el mensaje anterior.
///
/// El backend valida el formato con `isUuid` (`_shared/validation.ts`), así que los bits de versión
/// y de variante tienen que ir puestos: sin ellos la cadena sigue teniendo la pinta correcta pero
/// no es un UUID, y ahí la regex sí lo dejaría pasar — de modo que esto se pone por corrección, no
/// porque nadie lo compruebe.
String newUuidV4() {
  final Random random = Random.secure();
  final List<int> bytes = List<int>.generate(
    16,
    (int _) => random.nextInt(256),
    growable: false,
  );

  // Versión 4 en el nibble alto del byte 6, y variante RFC 4122 (10xx) en el byte 8.
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  final String hex = bytes
      .map((int b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
