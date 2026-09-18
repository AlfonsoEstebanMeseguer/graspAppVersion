import 'package:flutter/foundation.dart';

/// Una sala activa tal y como la sirve `rooms-feed`, y **exactamente** con los campos que esa
/// función devuelve ([apps/backend/supabase/functions/rooms-feed/index.ts]).
///
/// ## Lo que este tipo NO hace
///
/// No deriva nada. En particular **no calcula [overflow]**: lo decide el backend, con la regla del
/// [ADR 0032 § 4](../../../../../docs/decisions/0032-el-feed-de-salas-no-se-personaliza.md) —el host
/// no cuenta, el escenario va primero, caben cuatro—, y recalcularlo aquí sería una segunda fuente
/// de verdad para el mismo número. Si la cadena pintase `occupants - avatars.length` diría algo
/// distinto de lo que decidió `pickCardAvatars`, porque el host está en `occupants` y no en la
/// cadena.
@immutable
class RoomSummary {
  const RoomSummary({
    required this.id,
    required this.title,
    required this.categoryId,
    required this.hostId,
    required this.occupants,
    this.hostName,
    this.hostPhotoPath,
    this.avatars = const <String>[],
    this.overflow = 0,
  });

  final String id;

  /// Texto libre de quien creó la sala (3 a 80 caracteres, validado en `room-actions`).
  final String title;

  /// El tema, del catálogo cerrado `categories`. Es un uuid: para pintar su nombre hace falta el
  /// catálogo, que viaja aparte (ver `RoomCategory`).
  final String categoryId;

  final String hostId;

  /// Puede faltar: `profiles.display_name` es opcional.
  final String? hostName;

  /// **Clave de R2, no una URL.** No se pinta directamente: se cambia por una URL firmada en
  /// `profile-photo-view-url`, que además no acepta la clave como parámetro —firmar una clave
  /// elegida por el cliente convertiría esa función en una máquina de firmar cualquier objeto del
  /// bucket—. Aquí sirve para dos cosas: saber si el host **tiene** foto (y no pedir una firma
  /// inútil) y como clave de caché, porque una foto nueva es una clave nueva.
  final String? hostPhotoPath;

  /// Gente dentro, **incluido el host**.
  final int occupants;

  /// Hasta 4 `user_id` para la cadena de caras, ya ordenados y **sin el host**.
  final List<String> avatars;

  /// Los que **no caben** en la cadena, nunca el total. Ver la nota de arriba.
  final int overflow;

  /// Mapea una fila de la respuesta de `rooms-feed`.
  factory RoomSummary.fromJson(Map<String, dynamic> json) => RoomSummary(
    id: json['id'] as String,
    title: (json['title'] as String?) ?? '',
    categoryId: (json['categoryId'] as String?) ?? '',
    hostId: (json['hostId'] as String?) ?? '',
    hostName: json['hostName'] as String?,
    hostPhotoPath: json['hostPhotoPath'] as String?,
    occupants: (json['occupants'] as num?)?.toInt() ?? 0,
    avatars: <String>[
      for (final Object? id in (json['avatars'] as List<Object?>? ?? const <Object?>[]))
        if (id is String) id,
    ],
    overflow: (json['overflow'] as num?)?.toInt() ?? 0,
  );
}

/// Un tema del catálogo `categories`, con su `id` porque es lo que `rooms-feed` acepta como filtro.
///
/// El `slug` no viaja: `rooms-feed` filtra por uuid (`p_category uuid`) y un segundo identificador
/// que nadie usa solo invita a mandar el equivocado.
@immutable
class RoomCategory {
  const RoomCategory({required this.id, required this.name});

  final String id;
  final String name;
}
