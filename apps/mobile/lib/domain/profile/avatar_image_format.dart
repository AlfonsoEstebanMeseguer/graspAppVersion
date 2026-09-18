/// Formatos de imagen que el backend acepta como foto de perfil.
///
/// **Este enum es un espejo, no la autoridad.** La autoridad es
/// `_shared/image-format.ts` en el backend, que es quien rechaza con un 400 lo que no encaje
/// (decisiones 0012 y 0013). Si divergen, gana el backend.
///
/// PNG no está, y es deliberado: ningún cliente lo produce y cada formato admitido es un
/// decodificador más que ejecutan los dispositivos de quien mire el perfil.
enum AvatarImageFormat {
  webp('image/webp'),
  jpeg('image/jpeg');

  const AvatarImageFormat(this.mimeType);

  /// Lo que se manda en `mime_type` a `profile-photo-upload-url`, y lo que se firma como
  /// `Content-Type` del `PUT`. Los dos tienen que ser el mismo o R2 rechaza la subida.
  final String mimeType;
}

/// Reconoce el formato **por los bytes**, no por lo que alguien diga que son.
///
/// POR QUÉ ESTO EXISTE EN EL CLIENTE
///
/// Es el espejo de `sniffFormat` del backend, y no es duplicación defensiva: es la única forma de
/// saber qué produjo de verdad el compresor. Los dos caminos de fallo son distintos y ninguno se
/// puede detectar preguntando:
///
/// - **En Android/iOS**, un dispositivo que no sabe codificar WebP lanza `UnsupportedError`.
/// - **En web NO lanza nada**: `canvas.toDataURL('image/webp', …)` devuelve **PNG en silencio** si
///   el navegador no sabe. Medido en Edge el 2026-08-13 (`docs/superpowers/specs/`): pedir
///   `image/avif` devuelve bytes PNG sin un solo error.
///
/// Sin esta comprobación, el cliente declararía `image/webp` mientras manda otra cosa — exactamente
/// la mentira que las decisiones 0012 y 0013 existen para impedir. La cazaría el backend con un 400,
/// pero el fallo sería del cliente y no se vería hasta ahí.
///
/// Devuelve `null` si no es ninguno de los dos admitidos (PNG incluido).
AvatarImageFormat? sniffImageFormat(List<int> bytes) {
  bool matches(List<int> prefix, int offset) {
    if (bytes.length < offset + prefix.length) return false;
    for (int i = 0; i < prefix.length; i++) {
      if (bytes[offset + i] != prefix[i]) return false;
    }
    return true;
  }

  // WebP es un contenedor RIFF: "RIFF" ....(tamaño).... "WEBP"
  const List<int> riff = <int>[0x52, 0x49, 0x46, 0x46];
  const List<int> webp = <int>[0x57, 0x45, 0x42, 0x50];
  if (matches(riff, 0) && matches(webp, 8)) return AvatarImageFormat.webp;

  const List<int> jpegSoi = <int>[0xFF, 0xD8, 0xFF];
  if (matches(jpegSoi, 0)) return AvatarImageFormat.jpeg;

  return null;
}
