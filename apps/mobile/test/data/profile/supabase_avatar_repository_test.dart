import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/data/profile/photo_url_batches.dart';
import 'package:grasp_mobile/data/profile/supabase_avatar_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// LA COSTURA DONDE VIVÍA EL BUG, no la función pura que lo arregla.
///
/// `photo_url_batches_test.dart` prueba que `fetchPhotoUrlsInBatches` trocea. Lo que **no** prueba
/// —y es donde estaba el fallo— es que `SupabaseAvatarRepository.photoUrls` la **use**: volver a
/// escribir `return _photoUrlsBatch(ids)` restaura el bug entero con la función pura intacta y
/// todos sus casos en verde. Los dobles de las pantallas tampoco lo cubren, porque sustituyen la
/// clase completa: ese punto no lo miraba nadie por construcción.
///
/// Aquí el doble es **el transporte**, no el repositorio: un `MockClient` que se comporta como
/// `profile-photo-view-url` de verdad —incluido el **400 por encima de `MAX_USER_IDS`**— inyectado
/// en un `SupabaseClient` real. Sin ese 400 el caso pasaría igual sin trocear.
void main() {
  /// Peticiones vistas por el transporte, con el número de ids de cada una.
  late List<int> tamanos;
  late List<String> recibidos;

  MockClient transporte({int tope = photoUrlsBatchSize}) {
    tamanos = <int>[];
    recibidos = <String>[];

    return MockClient((http.Request request) async {
      final Map<String, dynamic> body =
          jsonDecode(request.body) as Map<String, dynamic>;
      final List<String> ids = (body['user_ids'] as List<dynamic>)
          .cast<String>();
      tamanos.add(ids.length);

      // Igual que `_shared/photo-view.ts`: por encima del tope es 400, NO una respuesta parcial.
      if (ids.length > tope) {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'error': 'too_many_ids',
            'message': 'Como mucho $tope ids por petición',
          }),
          400,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }

      recibidos.addAll(ids);
      return http.Response(
        jsonEncode(<String, dynamic>{
          'photos': <String, dynamic>{
            for (final String id in ids)
              id: <String, dynamic>{
                'url': 'https://r2.example/$id.webp',
                'expires_at': '2026-09-02T00:05:00Z',
              },
          },
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
  }

  /// Un `SupabaseClient` de verdad con el transporte pinchado: así la petición recorre el mismo
  /// `functions.invoke` que en producción, incluidos el `jsonEncode` del cuerpo y la traducción del
  /// error, en vez de un atajo que solo existe en el test.
  SupabaseClient clienteCon(MockClient mock) => SupabaseClient(
    'https://proyecto.supabase.co',
    'anon-key-de-mentira',
    httpClient: mock,
  );

  List<String> ids(int n) => <String>[for (int i = 0; i < n; i++) 'user-$i'];

  test('60 ids se piden en DOS llamadas, ninguna por encima de 50', () async {
    // ESTE ES EL CASO QUE MUERDE. Con `return _photoUrlsBatch(ids)` el transporte ve 60, devuelve
    // 400 y `photoUrls` lanza: 60 ids es el escenario de ~12 salas, que es tráfico normal.
    final MockClient mock = transporte();
    final SupabaseClient client = clienteCon(mock);
    addTearDown(client.dispose);

    final Map<String, String> urls = await SupabaseAvatarRepository(
      client,
    ).photoUrls(ids(60));

    expect(tamanos, <int>[50, 10]);
    expect(urls, hasLength(60));
    expect(urls['user-59'], 'https://r2.example/user-59.webp');
  });

  test('50 ids justos siguen siendo UNA sola llamada', () async {
    final MockClient mock = transporte();
    final SupabaseClient client = clienteCon(mock);
    addTearDown(client.dispose);

    await SupabaseAvatarRepository(client).photoUrls(ids(50));

    expect(tamanos, <int>[50]);
  });

  test('el peor caso del feed —500 ids— se sirve entero y sin repetir', () async {
    // `rooms_feed` termina en `limit 100` y cada sala aporta hasta 5 ids (host + 4 de la cadena).
    final MockClient mock = transporte();
    final SupabaseClient client = clienteCon(mock);
    addTearDown(client.dispose);

    final List<String> todos = ids(500);
    final Map<String, String> urls = await SupabaseAvatarRepository(
      client,
    ).photoUrls(todos);

    expect(tamanos, List<int>.filled(10, 50));
    expect(recibidos, todos);
    expect(urls.keys.toSet(), todos.toSet());
  });

  test('los duplicados se quitan ANTES de trocear', () async {
    // Deduplicar dejó de ser cosmético al trocear: 60 ids con 30 repetidos son 30 únicos y **una**
    // llamada, no dos.
    final MockClient mock = transporte();
    final SupabaseClient client = clienteCon(mock);
    addTearDown(client.dispose);

    await SupabaseAvatarRepository(client).photoUrls(<String>[
      ...ids(30),
      ...ids(30),
    ]);

    expect(tamanos, <int>[30]);
  });

  test('una lista vacía no llega al transporte', () async {
    final MockClient mock = transporte();
    final SupabaseClient client = clienteCon(mock);
    addTearDown(client.dispose);

    expect(
      await SupabaseAvatarRepository(client).photoUrls(const <String>[]),
      isEmpty,
    );
    expect(tamanos, isEmpty);
  });

  test('un 400 del endpoint sube como FunctionException — defecto CONOCIDO', () async {
    // El tope del doble baja a 10 para provocar el error **con el troceo puesto**: así se mira la
    // traducción del error sin depender de que el troceo esté roto.
    //
    // ⚠️ ESTE CASO FIJA UN FALLO, NO UN ACIERTO, Y ES DELIBERADO.
    //
    // Lo correcto sería un `AvatarException` con el texto ya en castellano — para eso existe
    // `_throwIfError`. Pero en `functions_client`, `invoke` **lanza** `FunctionException` en cuanto
    // la respuesta no es 2xx y nunca devuelve un `FunctionResponse` con status de error, así que
    // `_throwIfError` es código **inalcanzable** y la excepción cruda sube hasta arriba.
    //
    // No es un fallo de esta tarea ni se arregla aquí: está descrito con nombre y apellidos en el
    // comentario de cabecera de `data/social/social_error_mapper.dart`, que dice literalmente que
    // «esa es la forma del fallo que arrastra `SupabaseAvatarRepository`». Arreglarlo cambia el
    // texto de error de TODOS los flujos de avatar (subida, preset, bandeja, seguidores), y eso es
    // su propia tarea.
    //
    // Se deja escrito porque un fallo conocido sin test es un fallo que alguien «arregla» sin
    // saber que cambia, y porque este caso se pone rojo el día que se arregle de verdad — que es
    // exactamente cuando hay que venir a leerlo.
    final MockClient mock = transporte(tope: 10);
    final SupabaseClient client = clienteCon(mock);
    addTearDown(client.dispose);

    await expectLater(
      SupabaseAvatarRepository(client).photoUrls(ids(20)),
      throwsA(isA<FunctionException>()),
      reason:
          'Si esto pasa a ser AvatarException, el defecto se arregló: revisa el comentario.',
    );
  });
}
