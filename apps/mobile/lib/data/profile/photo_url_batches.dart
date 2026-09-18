/// Tope de `user_ids` que acepta `profile-photo-view-url` **por petición**.
///
/// Es el `MAX_USER_IDS` de `apps/backend/supabase/functions/_shared/photo-view.ts`, y por encima de
/// él la función devuelve **400**, no una respuesta parcial. Está escrito aquí porque hasta ahora no
/// lo conocía nadie en el cliente: `photoUrls` mandaba la lista entera y el tope solo existía en el
/// backend.
///
/// **Cómo se alcanza en la práctica** (lo que hizo que esto se escribiera): `rooms_feed` termina en
/// `limit 100` y cada sala aporta hasta 5 ids —el host más los 4 de la cadena—, así que la lista de
/// salas cruza los 50 **a partir de ~11 salas**. La bandeja y las listas de seguidores tienen el
/// mismo techo y lo alcanzan más tarde.
const int photoUrlsBatchSize = 50;

/// Trocea [userIds] en tandas de como mucho [photoUrlsBatchSize] y une lo que devuelva [fetchBatch].
///
/// ## Por qué esto vive en la capa de datos y no en cada llamante
///
/// El tope es **propiedad del endpoint**, no del feed de salas ni de la bandeja. Si lo respetara
/// cada llamante, el siguiente que pida fotos volvería a mandar la lista entera — y el fallo es
/// especialmente traicionero porque el 400 se traga arriba y la pantalla se queda **sin ninguna
/// foto**, no con las que cupieran: no hay hueco roto, no hay log, solo caras grises.
///
/// **Secuencial y no en paralelo**: son dos o tres peticiones en el peor caso realista, y lanzarlas
/// a la vez solo añade presión sobre un endpoint que firma contra R2 en cada una.
///
/// Si una tanda falla, **falla la llamada entera**. Devolver media pantalla de fotos sería un
/// resultado que el llamante no puede distinguir de «esa gente no tiene foto», y ese es exactamente
/// el tipo de mentira silenciosa que este fichero existe para quitar.
Future<Map<String, String>> fetchPhotoUrlsInBatches(
  List<String> userIds,
  Future<Map<String, String>> Function(List<String> batch) fetchBatch,
) async {
  if (userIds.isEmpty) return const <String, String>{};

  final Map<String, String> merged = <String, String>{};
  for (int start = 0; start < userIds.length; start += photoUrlsBatchSize) {
    final int end = start + photoUrlsBatchSize < userIds.length
        ? start + photoUrlsBatchSize
        : userIds.length;
    merged.addAll(await fetchBatch(userIds.sublist(start, end)));
  }
  return merged;
}
