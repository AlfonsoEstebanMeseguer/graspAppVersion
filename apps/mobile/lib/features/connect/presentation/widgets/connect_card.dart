import 'package:flutter/material.dart';

import '../../../../core/theming/grasp_palette.dart';
import '../../../../core/theming/app_theme.dart';
import '../../../../domain/social/connect_candidate.dart';
import '../../../messages/presentation/widgets/activity_dot.dart';
import '../../../messages/presentation/widgets/social_avatar.dart';
import 'signal_chips.dart';

/// La tarjeta de usuario recomendado del §6.4.
///
/// Layout horizontal: **izquierda** foto + punto de actividad · **centro** nombre · edad · bio a 2
/// líneas con elipsis · chips no interactivos · **derecha** botón de chat y el `✕` en la esquina.
///
/// ## Los tres destinos del toque son tres, y son distintos (`RN-38`)
///
/// Tocar la tarjeta abre el perfil. Tocar el chat es **acción directa** y no abre el perfil. Tocar
/// el `✕` descarta y tampoco lo abre. Están separados con tres callbacks y tres tests, porque un
/// `InkWell` que envuelva a los botones se traga los tres en uno.
///
/// ## La frontera del Art. 9 RGPD pasa por aquí
///
/// Lo que esta tarjeta puede pintar son las **señales no sensibles** del
/// [ADR 0020](../../../../../docs/decisions/0020-conectar-no-muestra-datos-del-articulo-9.md):
/// perfil de oyente, tiempo escuchando y racha. Ni categorías, ni experiencias, ni el desglose del
/// scoring — el desglose diría *qué* eje coincidió, que es la categoría dicha de otra forma.
///
/// Hay un test que **enumera todo el texto que la tarjeta pinta** y lo compara con la lista
/// permitida: si alguien añade un campo, aparece ahí antes que en una pantalla.
class ConnectCard extends StatelessWidget {
  const ConnectCard({
    super.key,
    required this.candidate,
    this.photoUrl,
    this.messaged = false,
    this.onOpenProfile,
    this.onChat,
    this.onDismiss,
  });

  /// Para poder tocarlos en los tests sin depender del icono, que cambia con el diseño.
  static const Key chatButtonKey = Key('connect-card-chat');
  static const Key dismissButtonKey = Key('connect-card-dismiss');

  /// El texto del botón cuando ya se envió el primer mensaje (`RN-40`).
  static const String pendingLabel = 'Pendiente';

  final ConnectCandidate candidate;
  final String? photoUrl;

  /// `RN-40`: ya se le escribió. El botón pasa a `Pendiente` deshabilitado y **la tarjeta sigue en
  /// la lista** hasta el siguiente refresco — al contrario que el `✕`, que la quita al instante.
  final bool messaged;

  final VoidCallback? onOpenProfile;
  final VoidCallback? onChat;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.gutter,
        vertical: AppSpacing.sm,
      ),
      child: Material(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onOpenProfile,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: context.palette.containerSubtle),
            ),
            // El `✕` va SUPERPUESTO en la esquina —«en la esquina», §6.4— y no dentro de la fila.
            // Con él en la fila, la columna derecha necesitaba ~116 px de ancho y estrangulaba el
            // centro: la bio salía partida en líneas de dos palabras y los chips truncados. No lo
            // vio ningún test —`maxLines: 2` se cumplía igual— sino la pantalla del emulador.
            child: Stack(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.md,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Stack(
                        clipBehavior: Clip.none,
                        children: <Widget>[
                          SocialAvatar(
                            displayName: candidate.displayName,
                            presetAvatar: candidate.presetAvatar,
                            photoUrl: photoUrl,
                            size: 56,
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: ActivityDot(isActive: candidate.isActive),
                          ),
                        ],
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: _Center(candidate: candidate, theme: theme),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      // Ancho FIJO, y no es cosmético: `Row` da restricciones de ancho **infinito**
                      // a los hijos sin `flex`, y el botón del estado `Pendiente` las propaga a su
                      // `minimumSize` → «BoxConstraints forces an infinite width». Con el botón de
                      // icono no pasaba —tiene tamaño intrínseco—, así que ese fallo solo aparecía
                      // en la rama de RN-40.
                      _ChatAction(
                        messaged: messaged,
                        displayName: candidate.displayName,
                        onChat: onChat,
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: _DismissButton(
                    displayName: candidate.displayName,
                    onDismiss: onDismiss,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Center extends StatelessWidget {
  const _Center({required this.candidate, required this.theme});

  final ConnectCandidate candidate;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final String? bio = candidate.bio?.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Flexible(
              child: Text(
                candidate.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: context.palette.textPrimary,
                ),
              ),
            ),
            // La edad puede faltar: `profiles_private.birth_date` es opcional. Sin ella no se pinta
            // ni el separador, para que no quede un «Ana ·» colgando.
            if (candidate.age != null) ...<Widget>[
              const SizedBox(width: 6),
              Text(
                '${candidate.age}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: context.palette.textMuted,
                ),
              ),
            ],
          ],
        ),
        if (bio != null && bio.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            bio,
            // Las DOS líneas del §6.4.
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: context.palette.textSecondary,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        SignalChips(labels: signalLabelsFor(candidate)),
      ],
    );
  }
}

/// El `✕` de la decisión 8, en la esquina y discreto.
///
/// Con `Semantics` propio: es la **única** puerta de `connect_dismissals`, es **irreversible**
/// (`RN-48`) y no hay pantalla donde deshacerlo, así que quien navegue con lector de pantalla tiene
/// que saber qué está tocando **antes** de tocarlo.
class _DismissButton extends StatelessWidget {
  const _DismissButton({required this.displayName, required this.onDismiss});

  final String displayName;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'No mostrar más a $displayName',
      child: InkWell(
        key: ConnectCard.dismissButtonKey,
        onTap: onDismiss,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: EdgeInsets.all(10),
          child: Icon(
            Icons.close_rounded,
            size: 18,
            color: context.palette.textMuted,
          ),
        ),
      ),
    );
  }
}

class _ChatAction extends StatelessWidget {
  const _ChatAction({
    required this.messaged,
    required this.displayName,
    required this.onChat,
  });

  final bool messaged;
  final String displayName;
  final VoidCallback? onChat;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        // Deja sitio al `✕`, que va superpuesto en la esquina.
        const SizedBox(height: AppSpacing.lg),
        if (messaged)
          // RN-40: deshabilitado. `onPressed: null` y no un callback vacío — un botón que parece
          // pulsable y no hace nada es peor que uno que se ve apagado.
          FilledButton(
            key: ConnectCard.chatButtonKey,
            onPressed: null,
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              // **`minimumSize` es obligatorio aquí, y esta es la historia.**
              //
              // `filledButtonTheme` lo pone a `Size.fromHeight(56)`, y `Size.fromHeight` deja el
              // ancho en `double.infinity`. Dentro de un `Row` —que da restricciones de ancho
              // infinitas a los hijos sin `flex`— eso reventaba con «BoxConstraints forces an
              // infinite width», y se tapó metiendo el botón en un `SizedBox(width: 92)`.
              //
              // Ese parche cambió el fallo por otro más callado: la palabra no cabía y salía
              // «Pendie…». Ningún test lo veía (`find.text` compara el dato del `Text`, no los
              // glifos) y desde la app el estado era **inalcanzable** hasta la Tarea 22, porque el
              // botón de chat no llevaba a ninguna parte. Con un mínimo finito el botón se mide
              // por su contenido y no hace falta ancho fijo ninguno.
              minimumSize: const Size(0, 40),
            ),
            child: const Text(ConnectCard.pendingLabel, maxLines: 1),
          )
        else
          Semantics(
            button: true,
            label: 'Escribir a $displayName',
            child: IconButton.filled(
              key: ConnectCard.chatButtonKey,
              onPressed: onChat,
              icon: const Icon(Icons.chat_bubble_rounded, size: 18),
              style: IconButton.styleFrom(
                backgroundColor: context.palette.brand,
                foregroundColor: context.palette.onBrand,
              ),
            ),
          ),
      ],
    );
  }
}

/// Las señales del ADR 0020, ya formateadas y **sin las que no aportan**.
///
/// Un chip «0 h escuchando» ocuparía el sitio de una señal que sí dice algo, y de las tres solo el
/// perfil de oyente está siempre. Se exporta para poder probarlo aparte de la tarjeta.
List<String> signalLabelsFor(ConnectCandidate c) {
  final List<String> labels = <String>[];

  final String? profile = c.listenerProfile?.trim();
  if (profile != null && profile.isNotEmpty) labels.add(profile);

  if (c.timeHelpingSeconds > 0) {
    labels.add('${_formatTime(c.timeHelpingSeconds)} escuchando');
  }
  if (c.streakDays > 0) {
    labels.add(
      c.streakDays == 1 ? '1 día de racha' : '${c.streakDays} días de racha',
    );
  }

  return labels;
}

String _formatTime(int seconds) {
  if (seconds < 3600) return '${(seconds / 60).floor()} min';
  return '${(seconds / 3600).floor()} h';
}
