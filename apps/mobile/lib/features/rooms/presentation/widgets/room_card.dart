import 'package:flutter/material.dart';

import '../../../../core/theming/app_theme.dart';
import '../../../../core/theming/grasp_palette.dart';
import '../../../../domain/rooms/room_summary.dart';
import '../../../messages/presentation/widgets/social_avatar.dart';

/// La tarjeta de sala del [ADR 0032 § 4](../../../../../../docs/decisions/0032-el-feed-de-salas-no-se-personaliza.md).
///
/// Layout: **izquierda** la foto de quien creó la sala, en grande · **centro** el título (texto
/// libre) y el chip del tema · **abajo a la derecha** la cadena de hasta 4 caras y la burbuja `+N`.
///
/// ## Lo que esta tarjeta NO pinta, y por qué
///
/// - **No hay botón «Entrar»**, aunque el boceto lo dibuje. La pantalla de sala es la Tarea 8: un
///   botón que no lleva a ninguna parte afirma que se puede entrar. Vuelve cuando haya destino.
/// - **No hay «N en la sala» en texto.** El ADR 0032 lo sustituyó por la cadena: es lo que espera
///   quien ve caras solapadas, y el número en texto duplicaría la misma información con otra regla
///   de conteo (el texto contaría al host; la cadena no).
/// - **No recalcula `overflow`.** Ver [RoomSummary.overflow].
class RoomCard extends StatelessWidget {
  const RoomCard({super.key, required this.room, this.categoryName, this.hostPhotoUrl, this.avatarUrls = const <String, String>{}});

  final RoomSummary room;

  /// El nombre del tema, resuelto contra el catálogo. Si falta —catálogo no cargado— **no se pinta
  /// el chip**: un chip vacío o con un uuid dentro es peor que ninguno.
  final String? categoryName;

  /// URL firmada de la foto del host, si tiene y se pudo firmar.
  final String? hostPhotoUrl;

  /// URLs firmadas de la cadena, por `user_id`. Quien no salga del mapa se pinta con el marcador
  /// neutro: `rooms-feed` manda `user_id` a secas y no dice quién tiene foto.
  final Map<String, String> avatarUrls;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.gutter,
        vertical: AppSpacing.sm,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: context.palette.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          // Sombra suave y difusa, nunca borde duro (lenguaje visual de `pictures/screens`).
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: context.palette.shadowSoft,
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // La foto del creador EN GRANDE: es la corrección del boceto que trae el ADR 0032.
            SocialAvatar(
              displayName: room.hostName ?? '',
              photoUrl: hostPhotoUrl,
              size: 64,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    room.title,
                    // Dos líneas y elipsis: el título son hasta 80 caracteres de texto libre, y a
                    // una línea la mayoría quedaría cortada. Dónde corta de verdad se mira en el
                    // emulador, no aquí: el test de widget corre a 800 px de ancho.
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: context.palette.textPrimary,
                    ),
                  ),
                  if (room.hostName != null && room.hostName!.trim().isNotEmpty) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      room.hostName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: context.palette.textSecondary,
                      ),
                    ),
                  ],
                  if (categoryName != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.sm),
                    _CategoryChip(name: categoryName!),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Align(
                    alignment: Alignment.centerRight,
                    child: RoomAvatarChain(
                      userIds: room.avatars,
                      overflow: room.overflow,
                      occupants: room.occupants,
                      urls: avatarUrls,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// El tema de la sala. **No es interactivo**: filtrar se hace con la fila de arriba, y un chip que
/// parece pulsable dentro de una tarjeta prometería una segunda forma de filtrar que no existe.
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: context.palette.containerSubtle,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: context.palette.textPrimary,
        ),
      ),
    );
  }
}

/// La cadena de caras solapadas y, si hace falta, la burbuja `+N`.
///
/// Va en un [Stack] de ancho **calculado**, no en un `Row` con márgenes negativos: así el solape es
/// exacto y la cadena mide lo que ocupa, que es lo que impide que empuje al resto de la tarjeta.
class RoomAvatarChain extends StatelessWidget {
  const RoomAvatarChain({
    super.key,
    required this.userIds,
    required this.overflow,
    required this.occupants,
    this.urls = const <String, String>{},
    this.size = 30,
  });

  /// Los que **caben**, ya elegidos y ordenados por el backend. Se pintan todos y solo estos: ni se
  /// rellena hasta cuatro ni se recorta.
  final List<String> userIds;

  /// Los que **no** caben. Cero significa que no hay burbuja.
  final int overflow;

  /// Gente dentro **en total, el host incluido**. No se pinta —el ADR 0032 cambió el «18 en la
  /// sala» del boceto por la cadena, y eso es una decisión **visual**— pero sí se anuncia: quien no
  /// ve las caras se quedaría sin saber cuánta gente hay, y ni `avatars.length` ni el `+N` dan ese
  /// número (el primero corta en cuatro, y ninguno de los dos cuenta al host).
  final int occupants;

  final Map<String, String> urls;
  final double size;

  /// Cuánto se solapa cada cara sobre la anterior.
  static const double _overlap = 9;

  @override
  Widget build(BuildContext context) {
    final int bubbles = userIds.length + (overflow > 0 ? 1 : 0);
    if (bubbles == 0) return const SizedBox.shrink();

    final double step = size - _overlap;

    return Semantics(
      // El número REAL de gente en la sala, no cuántas caras se ven. La versión anterior decía
      // «4 personas más, y 8 que no caben»: «más» respecto a nada, y sin contar al host.
      label: occupantsLabel(occupants),
      child: SizedBox(
        height: size,
        width: step * (bubbles - 1) + size,
        child: Stack(
          children: <Widget>[
            for (int i = 0; i < userIds.length; i++)
              Positioned(
                left: step * i,
                child: _Ring(
                  size: size,
                  child: RoomAvatar(photoUrl: urls[userIds[i]], size: size),
                ),
              ),
            if (overflow > 0)
              Positioned(
                left: step * userIds.length,
                child: _Ring(
                  size: size,
                  child: _OverflowBubble(count: overflow, size: size),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Cuánta gente hay dentro, dicho para un lector de pantalla.
///
/// Se exporta para poder afirmar sobre el texto exacto sin depender del árbol de widgets.
String occupantsLabel(int occupants) =>
    occupants == 1 ? '1 persona en la sala' : '$occupants personas en la sala';

/// Una cara de la cadena.
///
/// Es un tipo propio y público para que los tests puedan contar **cuántas** se pintan sin depender
/// de con qué se rellene cada una.
///
/// No pinta inicial: `rooms-feed` manda solo `user_id` de la cadena —ni nombre ni foto— así que no
/// hay letra que poner. El marcador neutro es honesto; una letra inventada, no.
class RoomAvatar extends StatelessWidget {
  const RoomAvatar({super.key, this.photoUrl, this.size = 30});

  final String? photoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final String? url = photoUrl;

    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: url == null
            ? _Placeholder(size: size)
            : Image.network(
                url,
                fit: BoxFit.cover,
                // Una firma caducada o R2 caído no pueden dejar un hueco roto en la lista.
                errorBuilder: (BuildContext context, Object _, StackTrace? _) =>
                    _Placeholder(size: size),
              ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.palette.containerSubtle,
      child: Icon(
        Icons.person_rounded,
        size: size * 0.6,
        color: context.palette.iconSoft,
      ),
    );
  }
}

/// La burbuja `+N`. **N son los que no caben**, no el total (ADR 0032 § 4).
class _OverflowBubble extends StatelessWidget {
  const _OverflowBubble({required this.count, required this.size});

  final int count;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.palette.containerSubtle,
        shape: BoxShape.circle,
      ),
      child: Text(
        '+$count',
        maxLines: 1,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: context.palette.textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.36,
        ),
      ),
    );
  }
}

/// El aro del color de la tarjeta que hace legible el solape.
///
/// `surface` y no blanco: la tarjeta es blanca en claro y `night700` en oscuro, y un aro blanco en
/// oscuro dibujaría cuatro anillos luminosos alrededor de las caras.
class _Ring extends StatelessWidget {
  const _Ring({required this.size, required this.child});

  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: context.palette.surface, width: 1.5),
      ),
      child: ClipOval(child: child),
    );
  }
}
