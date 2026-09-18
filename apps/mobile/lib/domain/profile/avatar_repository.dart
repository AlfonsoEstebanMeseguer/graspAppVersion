import 'dart:typed_data';

import 'avatar_type.dart';

/// Contrato de escritura y lectura del avatar.
///
/// Está separado de `ProfileRepository` a propósito: el avatar no se escribe con `profile-update`
/// sino con `profile-avatar-set`, que es **la única dueña del invariante** «una foto o un dibujo,
/// nunca los dos» (decisión 0010). Mezclarlos en el mismo contrato invitaría a escribirlo por el
/// camino equivocado.
///
/// No existe ninguna operación para **quitar** el avatar: el backend exige exactamente uno de los
/// dos, y quitarse la foto se hace eligiendo un dibujo, que además encola la foto para borrarla de
/// R2. Ver la corrección al final de la decisión 0014.
abstract interface class AvatarRepository {
  /// Sube [imageBytes] (ya comprimidos) declarando [mimeType], y confirma la subida.
  ///
  /// Devuelve la clave de R2 que quedó escrita en `profiles.photo_path`. El [mimeType] tiene que ser
  /// el de los bytes **de verdad**: el backend los huele y devuelve 400 si no coinciden.
  Future<String> uploadPhoto(Uint8List imageBytes, String mimeType);

  /// Fija uno de los 8 avatares predeterminados. Borra la foto que hubiera (decisión 0010).
  Future<void> setPreset(AvatarType preset);

  /// URL firmada para ver la foto de [userId], o `null` si no tiene.
  ///
  /// **Caduca en 300 segundos** y cambia en cada llamada, así que quien la use tiene que cachearla
  /// por `photo_path` y no pedirla en cada `build` (`media-storage/SKILL.md`).
  Future<String?> photoUrl(String userId);

  /// Lo mismo para **varias personas de una vez**, sin las que no tengan foto.
  ///
  /// Existe porque la bandeja del §8 lo necesita y `messaging-inbox` **no manda la foto**: el
  /// contrato dice, con esas palabras, que *«se pide a `profile-photo-view-url`»*. Sin una versión
  /// por lotes, una bandeja de 100 conversaciones haría 100 peticiones para pintar 100 caras —
  /// justo lo que la función evita aceptando `user_ids` como array desde el primer día.
  ///
  /// Las URLs caducan igual (300 s) y cambian en cada llamada, así que quien las use las cachea.
  Future<Map<String, String>> photoUrls(List<String> userIds);
}
