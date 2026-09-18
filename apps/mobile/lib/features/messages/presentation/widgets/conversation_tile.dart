import 'package:flutter/material.dart';

import '../../../../core/theming/grasp_palette.dart';
import '../../../../core/theming/app_theme.dart';
import '../../../../domain/social/conversation_summary.dart';
import 'activity_dot.dart';
import 'social_avatar.dart';

/// Una fila de la pestaña **Contactos** (§8.2).
///
/// Boceto: `06-messaging-inbox.jpeg` — foto, nombre, último mensaje a 1 línea, hora a la derecha.
///
/// Va en un widget distinto de `RequestTile` y **no en uno solo con un booleano**. La diferencia no
/// es cosmética: esta fila pinta el punto de actividad y la de Solicitudes no puede (`RN-30`). Con
/// un único widget parametrizado, respetar la regla dependería de que cada sitio pasara el
/// booleano correcto; con dos, la fila de Solicitudes **no recibe el dato**.
class ConversationTile extends StatelessWidget {
  const ConversationTile({
    super.key,
    required this.conversation,
    this.photoUrl,
    this.onTap,
  });

  /// Lo que se enseña en lugar del texto de un mensaje borrado para todos (`RN-28`).
  ///
  /// El contenido real **no llega** —el backend manda `content: null` en cuanto hay lápida—, así
  /// que esto no oculta nada: es lo único que hay.
  static const String deletedMessage = 'Mensaje eliminado';

  /// El «Pendiente de aceptación» del §8.2, que deriva de `pending_acceptance` sin revelar el
  /// `status` (`RN-06`): vale igual para una solicitud mía sin responder que para una ignorada.
  static const String pendingLabel = 'Pendiente de aceptación';

  final ConversationSummary conversation;
  final String? photoUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool unread = conversation.unreadCount > 0;
    final FontWeight weight = unread ? FontWeight.w700 : FontWeight.w500;

    // `== true` y no `!= false`: `null` significa «esta lista no trae el dato», no «desconectado»,
    // y en ese caso no se pinta punto ninguno — ni siquiera gris.
    final bool? isActive = conversation.isActive;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.gutter,
          vertical: AppSpacing.sm + 2,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                SocialAvatar(
                  displayName: conversation.displayName,
                  presetAvatar: conversation.presetAvatar,
                  photoUrl: photoUrl,
                ),
                if (isActive != null)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: ActivityDot(isActive: isActive),
                  ),
              ],
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    conversation.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: weight,
                      color: context.palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _lastMessageLine(),
                    // A 1 línea, como pide el §8.2.
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: weight,
                      color: unread
                          ? context.palette.textPrimary
                          : context.palette.textMuted,
                    ),
                  ),
                  if (conversation.pendingAcceptance) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      pendingLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: context.palette.brand,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  formatInboxTimestamp(DateTime.now(), conversation.lastMessageAt),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: unread ? context.palette.brandStrong : context.palette.textMuted,
                    fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                // El número NO se pinta: `RN-31` lo hace un contador estrictamente local, y lo
                // único que la fila necesita decir es que hay algo sin leer.
                if (unread) const UnreadDot() else const SizedBox(height: 10),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _lastMessageLine() {
    final LastMessagePreview? last = conversation.lastMessage;
    if (last == null) return '';

    final String body = last.deletedForAll
        ? deletedMessage
        : (last.content ?? deletedMessage);
    // El «Tú: » del §8.2. Viaja como `from_me` y no como `sender_id`: la bandeja nunca ve quién
    // escribió, solo si fue uno mismo.
    return last.fromMe ? 'Tú: $body' : body;
  }
}

/// La hora de la derecha del §8.2.
///
/// Se distingue hoy / ayer / esta semana / más atrás porque «19:24» a secas en una conversación de
/// hace tres días se lee como de hoy. Los dos instantes van en hora **local**.
String formatInboxTimestamp(DateTime now, DateTime when) {
  final DateTime hoy = DateTime(now.year, now.month, now.day);
  final DateTime dia = DateTime(when.year, when.month, when.day);
  final int diferencia = hoy.difference(dia).inDays;

  if (diferencia <= 0) {
    return '${when.hour.toString().padLeft(2, '0')}:'
        '${when.minute.toString().padLeft(2, '0')}';
  }
  if (diferencia == 1) return 'Ayer';
  if (diferencia < 7) return _diaSemana(when.weekday);
  return '${when.day.toString().padLeft(2, '0')}/'
      '${when.month.toString().padLeft(2, '0')}';
}

String _diaSemana(int weekday) => switch (weekday) {
  DateTime.monday => 'Lun',
  DateTime.tuesday => 'Mar',
  DateTime.wednesday => 'Mié',
  DateTime.thursday => 'Jue',
  DateTime.friday => 'Vie',
  DateTime.saturday => 'Sáb',
  _ => 'Dom',
};
