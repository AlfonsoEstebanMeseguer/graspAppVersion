import 'package:flutter/material.dart';

import '../../../../core/theming/grasp_palette.dart';
import '../../../../core/theming/app_theme.dart';
import '../../../../domain/social/conversation_summary.dart';
import 'conversation_tile.dart';
import 'social_avatar.dart';

/// Una fila de la pestaña **Solicitudes** (§8.3).
///
/// ## AQUÍ VIVE `RN-30`, Y VIVE EN LO QUE ESTA CLASE **NO** TIENE
///
/// El §8.3 dice: *«Foto de perfil (**sin** punto de actividad, `RN-30`)»*. Esta fila no recibe
/// `isActive` **por ningún camino**: ni parámetro, ni lectura de
/// [ConversationSummary.isActive]. No es que se acuerde de no pintarlo — es que **no tiene el dato
/// con el que pintarlo**.
///
/// Es la misma idea que sostiene el resto de la Fase 4: `conversations` no tiene `grant` para que
/// `status` no pueda salir, y `PublicSendBlockedReason` no tiene variante para el bloqueo para que
/// no pueda serializarse. Lo que no está no se filtra por descuido.
///
/// (El backend además **omite la clave** `is_active` en la lista `requests`, así que hay dos capas.
/// Ésta es la que sigue en pie si la otra cambiara.)
class RequestTile extends StatelessWidget {
  const RequestTile({
    super.key,
    required this.request,
    this.photoUrl,
    this.onTap,
  });

  final ConversationSummary request;
  final String? photoUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.gutter,
          vertical: AppSpacing.sm + 2,
        ),
        child: Row(
          children: <Widget>[
            // Sin `Stack` y sin `ActivityDot`: ver el bloque de arriba.
            SocialAvatar(
              displayName: request.displayName,
              presetAvatar: request.presetAvatar,
              photoUrl: photoUrl,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    request.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      // Una solicitud siempre destaca: es algo que espera una decisión. No depende
                      // de `unread_count`, que en una solicitud puede venir a cero.
                      fontWeight: FontWeight.w700,
                      color: context.palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _mensaje(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: context.palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              formatInboxTimestamp(DateTime.now(), request.lastMessageAt),
              style: theme.textTheme.labelSmall?.copyWith(
                color: context.palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _mensaje() {
    final LastMessagePreview? last = request.lastMessage;
    if (last == null) return '';
    return last.deletedForAll
        ? ConversationTile.deletedMessage
        : (last.content ?? ConversationTile.deletedMessage);
    // Sin prefijo «Tú: »: una solicitud RECIBIDA la abrió la otra persona por definición, así que
    // el último mensaje visible no puede ser propio hasta que se acepte — y al aceptarla deja de
    // ser una solicitud.
  }
}
