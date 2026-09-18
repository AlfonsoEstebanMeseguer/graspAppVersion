import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/supabase/supabase_providers.dart';

/// A quién y de qué foto se pide la URL firmada.
///
/// Lleva `photoPath` **aunque el backend no lo acepte como parámetro** (y hace bien en no
/// aceptarlo: firmar una clave elegida por el cliente convertiría la función en una máquina de
/// firmar cualquier objeto del bucket). Está aquí como **clave de caché**: si la foto cambia,
/// cambia la clave, y la URL se vuelve a pedir sola.
typedef AvatarUrlRequest = ({String userId, String photoPath});

/// URL firmada para ver una foto de perfil, cacheada por `photoPath`.
///
/// POR QUÉ CACHEA, Y POR QUÉ POR AHÍ
///
/// `profile-photo-view-url` devuelve una URL **distinta cada vez** (la firma lleva la hora), y vive
/// 300 segundos. Sin caché, cada `build` pediría una firma nueva, y como la URL sería nueva,
/// `Image.network` volvería a descargar los bytes: una foto recién vista se bajaría otra vez por
/// repintar la pantalla. Cacheando por `photoPath`, la misma foto reutiliza la misma URL y por tanto
/// la misma entrada de `ImageCache` — y una foto nueva es una clave nueva, así que se refresca sola
/// sin que nadie tenga que acordarse de invalidar nada (`media-storage/SKILL.md`).
final AutoDisposeFutureProviderFamily<String?, AvatarUrlRequest>
avatarUrlProvider = FutureProvider.autoDispose
    .family<String?, AvatarUrlRequest>((Ref ref, AvatarUrlRequest request) {
      // Se mantiene viva mientras la foto sea la misma. Sin esto, `autoDispose` tiraría la URL en
      // cuanto la pantalla dejase de mirarla y la volvería a pedir al volver.
      ref.keepAlive();
      return ref.watch(avatarRepositoryProvider).photoUrl(request.userId);
    });
