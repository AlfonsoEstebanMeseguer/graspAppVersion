import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/data/profile/photo_url_batches.dart';

/// Un `profile-photo-view-url` de mentira que **se comporta como el de verdad**: por encima de
/// `MAX_USER_IDS` (50) devuelve 400, no una respuesta parcial.
///
/// Ese detalle es el test entero. Un doble que aceptara cualquier tamaño convertiría este fichero
/// en decoración: pasaría igual sin trocear, que es exactamente el estado del que venimos.
class _FakeEndpoint {
  final List<int> batchSizes = <int>[];
  final List<String> received = <String>[];

  Future<Map<String, String>> call(List<String> batch) async {
    batchSizes.add(batch.length);
    if (batch.length > photoUrlsBatchSize) {
      throw Exception('400 too_many_ids: ${batch.length} > $photoUrlsBatchSize');
    }
    received.addAll(batch);
    return <String, String>{
      for (final String id in batch)
        if (id.endsWith('-con-foto')) id: 'https://r2/$id.jpg',
    };
  }
}

List<String> _ids(int n, {bool conFoto = true}) => <String>[
  for (int i = 0; i < n; i++) 'u$i${conFoto ? '-con-foto' : ''}',
];

void main() {
  group('fetchPhotoUrlsInBatches', () {
    test('una lista vacía no llama al endpoint', () async {
      final _FakeEndpoint endpoint = _FakeEndpoint();
      expect(
        await fetchPhotoUrlsInBatches(const <String>[], endpoint.call),
        isEmpty,
      );
      expect(endpoint.batchSizes, isEmpty);
    });

    test('por debajo del tope va en UNA sola petición', () async {
      final _FakeEndpoint endpoint = _FakeEndpoint();
      await fetchPhotoUrlsInBatches(_ids(12), endpoint.call);
      expect(endpoint.batchSizes, <int>[12]);
    });

    test('justo en el tope sigue siendo una sola petición', () async {
      // El off-by-one que convertiría el arreglo en dos peticiones para nada, o —peor— en un 400
      // por mandar 51.
      final _FakeEndpoint endpoint = _FakeEndpoint();
      await fetchPhotoUrlsInBatches(_ids(50), endpoint.call);
      expect(endpoint.batchSizes, <int>[50]);
    });

    test('POR ENCIMA DEL TOPE trocea, y ninguna tanda pasa de 50', () async {
      // SIN EL TROCEO ESTE CASO EXPLOTA: el doble devuelve 400 por encima de 50, igual que
      // `_shared/photo-view.ts`. Es el caso que faltaba — los anteriores usaban 12 ids, justo por
      // debajo del tope, y por eso el agujero sobrevivió a una tanda entera de tests en verde.
      final _FakeEndpoint endpoint = _FakeEndpoint();
      final Map<String, String> urls = await fetchPhotoUrlsInBatches(
        _ids(51),
        endpoint.call,
      );

      expect(endpoint.batchSizes, <int>[50, 1]);
      expect(urls, hasLength(51));
    });

    test('el peor caso real —100 salas × 5 ids— se sirve entero', () async {
      // `rooms_feed` termina en `limit 100` y cada sala aporta hasta 5 ids (host + 4 de la cadena).
      final _FakeEndpoint endpoint = _FakeEndpoint();
      final List<String> ids = _ids(500);
      final Map<String, String> urls = await fetchPhotoUrlsInBatches(
        ids,
        endpoint.call,
      );

      expect(endpoint.batchSizes, List<int>.filled(10, 50));
      // NADIE SE PIERDE Y NADIE SE REPITE: trocear mal es fácil de escribir de forma que el
      // resultado siga «pareciendo» bien porque el mapa tiene entradas.
      expect(endpoint.received, ids);
      expect(urls.keys.toSet(), ids.toSet());
    });

    test('quien no tiene foto no sale del mapa, tanda a tanda', () async {
      final _FakeEndpoint endpoint = _FakeEndpoint();
      final Map<String, String> urls = await fetchPhotoUrlsInBatches(
        <String>[..._ids(60), 'nadie'],
        endpoint.call,
      );

      expect(urls, hasLength(60));
      expect(urls.containsKey('nadie'), isFalse);
    });

    test('si una tanda falla, falla la llamada entera', () async {
      // Media pantalla de fotos es un resultado que el llamante no puede distinguir de «esa gente
      // no tiene foto». Se prefiere el error, que sí se puede tratar.
      int llamadas = 0;
      Future<Map<String, String>> fallaLaSegunda(List<String> batch) async {
        llamadas++;
        if (llamadas == 2) throw Exception('503');
        return const <String, String>{};
      }

      await expectLater(
        fetchPhotoUrlsInBatches(_ids(120), fallaLaSegunda),
        throwsA(isA<Exception>()),
      );
      // Y no sigue pidiendo tandas después del fallo.
      expect(llamadas, 2);
    });
  });
}
