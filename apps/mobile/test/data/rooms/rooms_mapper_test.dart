import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/data/rooms/rooms_mapper.dart';
import 'package:grasp_mobile/domain/rooms/room_summary.dart';

/// El mapeo vive fuera del repositorio precisamente para poder probarse aquí: sin
/// `SupabaseClient`, sin sesión y sin red (mismo patrón que `profile_mapper_test.dart`).
///
/// Los cuerpos de este fichero están copiados de la forma exacta que devuelve
/// `apps/backend/supabase/functions/rooms-feed/index.ts`, en `camelCase` — que es donde se rompería
/// si alguien cambiara el contrato de un lado solo.
void main() {
  group('RoomSummary.fromJson — los siete campos del contrato', () {
    test('copia todos los campos que manda rooms-feed', () {
      final RoomSummary room = RoomSummary.fromJson(<String, dynamic>{
        'id': 'aaaa-1111',
        'title': 'Hablemos de ansiedad',
        'categoryId': 'cat-1',
        'hostId': 'host-1',
        'hostName': 'Ana',
        'hostPhotoPath': 'avatars/host-1/foto.webp',
        'occupants': 12,
        'avatars': <String>['u1', 'u2', 'u3', 'u4'],
        'overflow': 7,
      });

      expect(room.id, 'aaaa-1111');
      expect(room.title, 'Hablemos de ansiedad');
      expect(room.categoryId, 'cat-1');
      expect(room.hostId, 'host-1');
      expect(room.hostName, 'Ana');
      expect(room.hostPhotoPath, 'avatars/host-1/foto.webp');
      expect(room.occupants, 12);
      expect(room.avatars, <String>['u1', 'u2', 'u3', 'u4']);
      expect(room.overflow, 7);
    });

    test('el overflow se COPIA, no se deriva de occupants ni de la cadena', () {
      // Con 12 dentro y 4 en la cadena hay tres números defendibles —12, 11 y 7— y solo uno lo
      // decidió `pickCardAvatars`. Este caso fija que el mapper no calcula ninguno.
      final RoomSummary room = RoomSummary.fromJson(<String, dynamic>{
        'id': 'r1',
        'occupants': 12,
        'avatars': <String>['u1', 'u2', 'u3', 'u4'],
        'overflow': 7,
      });

      expect(room.overflow, 7);
      expect(room.overflow, isNot(room.occupants));
      expect(room.overflow, isNot(room.occupants - room.avatars.length));
    });

    test('los dos campos que pueden faltar de verdad llegan a null', () {
      // `profiles.display_name` es opcional y `photo_path` también: un host puede tener un avatar
      // predeterminado, que NO vive en R2.
      final RoomSummary room = RoomSummary.fromJson(<String, dynamic>{
        'id': 'r1',
        'title': 'Sin host con nombre',
        'categoryId': 'cat-1',
        'hostId': 'host-1',
        'hostName': null,
        'hostPhotoPath': null,
        'occupants': 1,
        'avatars': <String>[],
        'overflow': 0,
      });

      expect(room.hostName, isNull);
      expect(room.hostPhotoPath, isNull);
      expect(room.avatars, isEmpty);
      expect(room.overflow, 0);
    });

    test('una fila incompleta cae a valores neutros, no a null ni a excepción', () {
      final RoomSummary room = RoomSummary.fromJson(<String, dynamic>{'id': 'r1'});

      expect(room.title, '');
      expect(room.occupants, 0);
      expect(room.overflow, 0);
      expect(room.avatars, isEmpty);
    });

    test('un elemento no-String de la cadena se descarta sin tumbar la sala', () {
      final RoomSummary room = RoomSummary.fromJson(<String, dynamic>{
        'id': 'r1',
        'avatars': <Object?>['u1', 42, null, 'u2'],
      });

      expect(room.avatars, <String>['u1', 'u2']);
    });
  });

  group('mapRoomsFeed', () {
    test('mapea la lista conservando el orden que mandó el backend', () {
      final List<RoomSummary> rooms = mapRoomsFeed(<String, dynamic>{
        'rooms': <Object?>[
          <String, dynamic>{'id': 'r1', 'title': 'Primera'},
          <String, dynamic>{'id': 'r2', 'title': 'Segunda'},
        ],
      });

      // El orden es el de `rooms_feed` (actividad reciente, ADR 0032 § 3).
      expect(rooms.map((RoomSummary r) => r.title), <String>['Primera', 'Segunda']);
    });

    test('sin la clave `rooms` devuelve lista vacía, no una excepción', () {
      expect(mapRoomsFeed(const <String, dynamic>{}), isEmpty);
      expect(mapRoomsFeed(<String, dynamic>{'rooms': 'nope'}), isEmpty);
    });

    test('una fila que no es un mapa se salta; las demás se mapean', () {
      final List<RoomSummary> rooms = mapRoomsFeed(<String, dynamic>{
        'rooms': <Object?>[
          'basura',
          <String, dynamic>{'id': 'r2', 'title': 'Buena'},
        ],
      });

      expect(rooms, hasLength(1));
      expect(rooms.single.title, 'Buena');
    });
  });

  group('mapRoomCategories — la degradación contra la v9 de producción', () {
    test('mapea id y nombre', () {
      final List<RoomCategory> categories = mapRoomCategories(<String, dynamic>{
        'categories': <Object?>[
          <String, dynamic>{
            'id': 'cat-1',
            'slug': 'ansiedad-estres',
            'name': 'Ansiedad y estrés cotidiano',
          },
        ],
      });

      expect(categories.single.id, 'cat-1');
      expect(categories.single.name, 'Ansiedad y estrés cotidiano');
    });

    test('SIN `id` —la v9 viva en producción— devuelve lista vacía', () {
      // ESTE ES EL CAMINO QUE VA A OCURRIR DE VERDAD hasta que se redespliegue
      // `onboarding-catalogs`: la función responde 200 con un catálogo perfectamente válido para el
      // onboarding y sin `id`. No es un error que se pueda atrapar con un `try`, y por eso no basta
      // con probar que un `throw` deja la pantalla sin chips.
      //
      // Vacío es lo correcto: una categoría sin identificador no puede filtrar nada, y quedársela
      // pintaría un chip que al pulsarlo pediría el feed con `null`.
      final List<RoomCategory> categories = mapRoomCategories(<String, dynamic>{
        'categories': <Object?>[
          <String, dynamic>{'slug': 'ansiedad-estres', 'name': 'Ansiedad'},
          <String, dynamic>{'slug': 'duelo', 'name': 'Duelo'},
        ],
      });

      expect(categories, isEmpty);
    });

    test('descarta solo las que no sirven, no el catálogo entero', () {
      final List<RoomCategory> categories = mapRoomCategories(<String, dynamic>{
        'categories': <Object?>[
          <String, dynamic>{'slug': 'sin-id', 'name': 'Sin id'},
          <String, dynamic>{'id': 'cat-2', 'name': 'Con id'},
          <String, dynamic>{'id': 'cat-3'},
          <String, dynamic>{'id': 42, 'name': 'Id que no es texto'},
          'basura',
        ],
      });

      expect(categories.map((RoomCategory c) => c.name), <String>['Con id']);
    });

    test('sin la clave `categories` devuelve lista vacía', () {
      expect(mapRoomCategories(const <String, dynamic>{}), isEmpty);
    });
  });
}
