import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theming/grasp_palette.dart';
import '../../../core/theming/app_theme.dart';
import '../../../domain/profile/profile_badge.dart';
import '../../../domain/social/follow_edge.dart';
import '../../../domain/social/public_profile.dart';
import '../../../domain/social/social_failure.dart';
import '../../messages/presentation/widgets/activity_dot.dart';
import '../../messages/presentation/widgets/social_avatar.dart';
import '../application/public_profile_controller.dart';
import 'widgets/profile_badge_icons.dart';
import 'widgets/profile_section_card.dart';

/// El perfil de **otra persona** — `RN-38` y §6.2.
///
/// Boceto: `08-profile.jpeg`, la misma derivación que las listas de follows (cabecera centrada,
/// tarjetas blancas de radio ~20).
///
/// ## Tres puertas, una sola pantalla
///
/// Se llega aquí desde la tarjeta de Conectar (`RN-38`), desde la ficha del tag (§6.2) y desde la
/// cabecera de la conversación. Las tres pasan **sólo un `userId`** y esta pantalla lo pide todo de
/// nuevo, en vez de recibir la ficha ya hecha desde donde se venga. Es deliberado y es lo que
/// resuelve el problema que tenía el paso 5: la tarjeta de Conectar traía la edad en la mano y las
/// otras dos no, así que una pantalla alimentada por su llamante enseñaría cosas distintas según
/// por dónde se entrara — y un perfil que a veces tiene edad y a veces no es peor que uno que no la
/// tenga nunca.
///
/// ## LO QUE ESTA PANTALLA NO PUEDE PINTAR
///
/// **Ni una categoría, ni una experiencia, ni la fecha de nacimiento, ni una marca de actividad**
/// ([ADR 0020](../../../../../docs/decisions/0020-conectar-no-muestra-datos-del-articulo-9.md)).
/// No basta con que la respuesta de hoy no las traiga: `lib/features/profile` entra en el escaneo
/// de `test/domain/social/no_articulo_9_test.dart` desde la Tarea 24, y el test de widget alimenta
/// esta pantalla con un fixture que **sí las trae** para comprobar que las ignora.
class PublicProfileScreen extends ConsumerWidget {
  const PublicProfileScreen({super.key, required this.userId});

  final String userId;

  /// Cómo se abre desde cualquiera de las tres puertas.
  ///
  /// `rootNavigator: true` por lo mismo que la conversación: se apila **por encima** de la barra
  /// inferior. Un perfil abierto no es una de las cuatro pestañas, es un sitio del que se vuelve.
  static void open(BuildContext context, String userId) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => PublicProfileScreen(userId: userId),
      ),
    );
  }

  static const Key followKey = Key('public-profile-follow');
  static const Key ageKey = Key('public-profile-age');
  static const Key bioKey = Key('public-profile-bio');
  static const Key badgeKey = Key('public-profile-badge');
  static const Key activityKey = Key('public-profile-activity');

  static const String followLabel = 'Seguir';
  static const String pendingLabel = 'Pendiente';
  static const String followingLabel = 'Siguiendo';

  /// El mismo texto para todas las causas por las que no hay ficha, y es deliberado: es el criterio
  /// de `RN-23` que ya sigue la búsqueda por tag. Dos textos distintos acabarían distinguiendo un
  /// bloqueo de una cuenta inexistente.
  static const String notFound = 'No se pudo abrir este perfil.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<PublicProfileView> vista = ref.watch(
      publicProfileControllerProvider(userId),
    );

    return Scaffold(
      backgroundColor: context.palette.canvas,
      appBar: AppBar(title: const Text('Perfil'), centerTitle: true),
      body: SafeArea(
        top: false,
        child: vista.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object error, StackTrace _) => const _Centrado(text: notFound),
          data: (PublicProfileView view) => _Contenido(view: view),
        ),
      ),
    );
  }
}

class _Contenido extends ConsumerWidget {
  const _Contenido({required this.view});

  final PublicProfileView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final PublicProfile p = view.profile;
    final String? bio = p.bio?.trim();
    final int? edad = p.age;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.lg,
        AppSpacing.gutter,
        AppSpacing.xl,
      ),
      children: <Widget>[
        // ── Cabecera: cara, nombre, edad y tag ────────────────────────────────
        Center(
          child: Stack(
            children: <Widget>[
              SocialAvatar(
                displayName: p.displayName,
                presetAvatar: p.presetAvatar,
                photoUrl: view.photoUrl,
                size: 96,
              ),
              // `RN-30`: el punto va **sobre** la foto, como en la cabecera de la conversación.
              // `isActive == null` significa «no se pudo saber», y entonces no se pinta nada: un
              // punto gris afirmaría que está desconectado.
              if (view.isActive != null)
                Positioned(
                  right: 2,
                  bottom: 6,
                  child: ActivityDot(
                    key: PublicProfileScreen.activityKey,
                    isActive: view.isActive!,
                    size: 18,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          p.displayName,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            color: context.palette.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        // La edad **se omite entera** cuando no se sabe. Ni un cero, ni un guion: «edad
        // desconocida» y «cero años» no son lo mismo, y la vista devuelve NULL justo para no
        // confundirlos.
        if (edad != null) ...<Widget>[
          const SizedBox(height: 2),
          Text(
            '$edad años',
            key: PublicProfileScreen.ageKey,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: context.palette.textMuted,
              // `labelSmall`/`bodyMedium` de Material 3 vienen en `w500`; sin esto el texto de
              // apoyo se pinta más grueso que la etiqueta a la que acompaña.
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
        if (p.tag != null && p.tag!.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          // Sin botón de copiar, y no es un olvido: `ProfileTagRow` ofrece copiar y **rotar**, y
          // rotar el tag de otra persona no existe. El tag ajeno se enseña porque es la única
          // forma de encontrar a alguien (`RN-11`), no para operarlo.
          Center(
            child: Text(
              p.tag!,
              style: theme.textTheme.labelLarge?.copyWith(
                color: context.palette.brandStrong,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],

        const SizedBox(height: AppSpacing.lg),
        _BotonSeguir(view: view),

        // ── Bio ───────────────────────────────────────────────────────────────
        if (bio != null && bio.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.lg),
          ProfileSectionCard(
            key: PublicProfileScreen.bioKey,
            title: 'Sobre mí',
            child: Text(
              bio,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: context.palette.textPrimary,
              ),
            ),
          ),
        ],

        // ── Nivel e insignia destacada — LAS DOS SOLO AQUÍ (decisión 1) ────────
        const SizedBox(height: AppSpacing.lg),
        ProfileSectionCard(
          title: 'Progreso',
          child: Row(
            children: <Widget>[
              _Dato(valor: '${p.level}', etiqueta: 'Nivel'),
              const SizedBox(width: AppSpacing.lg),
              _Dato(valor: '${p.streakDays}', etiqueta: 'Días de racha'),
              const SizedBox(width: AppSpacing.lg),
              _Dato(
                valor: '${p.timeHelpingSeconds ~/ 3600} h',
                etiqueta: 'Escuchando',
              ),
            ],
          ),
        ),

        if (p.featuredBadge != null) ...<Widget>[
          const SizedBox(height: AppSpacing.lg),
          ProfileSectionCard(
            key: PublicProfileScreen.badgeKey,
            title: 'Insignia destacada',
            child: _Insignia(badge: p.featuredBadge!),
          ),
        ],

        // ── Follows ───────────────────────────────────────────────────────────
        const SizedBox(height: AppSpacing.lg),
        ProfileSectionCard(
          title: 'Comunidad',
          child: Row(
            children: <Widget>[
              _Dato(valor: '${p.followersCount}', etiqueta: 'Seguidores'),
              const SizedBox(width: AppSpacing.lg),
              _Dato(valor: '${p.followingCount}', etiqueta: 'Seguidos'),
            ],
          ),
        ),
      ],
    );
  }
}

/// Los tres botones del §6.2: `Seguir` · `Pendiente` (deshabilitado) · `Siguiendo`.
///
/// `Siguiendo` **no ofrece dejar de seguir desde aquí**, y no es una omisión: `RN-53` pone esa
/// acción en la lista de Seguidos, donde se ve a quién se le está haciendo. Un botón que cambia de
/// significado al pulsarlo —de «te sigo» a «deja de seguirme»— invita a deshacer sin querer lo que
/// se acaba de conseguir.
class _BotonSeguir extends ConsumerWidget {
  const _BotonSeguir({required this.view});

  final PublicProfileView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (String etiqueta, bool activo) = switch (view.followState) {
      FollowState.none => (PublicProfileScreen.followLabel, true),
      FollowState.pending => (PublicProfileScreen.pendingLabel, false),
      FollowState.following => (PublicProfileScreen.followingLabel, false),
    };

    final bool pulsable = activo && !view.followInFlight;

    return FilledButton(
      key: PublicProfileScreen.followKey,
      onPressed: pulsable ? () => _seguir(context, ref) : null,
      style: FilledButton.styleFrom(
        backgroundColor: activo ? context.palette.brandStrong : context.palette.containerSubtle,
        foregroundColor: activo
            ? context.palette.onBrand
            : context.palette.brandStrong,
        // Finito: el tema pone `Size.fromHeight(56)`, que deja el ancho en `double.infinity`. Aquí
        // no está dentro de un `Row`, así que no reventaría — pero se fija igual para que mover
        // este botón a una fila no rompa la pantalla entera más adelante.
        minimumSize: const Size(0, 48),
      ),
      child: Text(etiqueta),
    );
  }

  Future<void> _seguir(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(publicProfileControllerProvider(view.profile.userId).notifier)
          .follow();
    } on Object catch (error) {
      if (!context.mounted) return;
      final String texto = error is SocialFailure
          ? error.message
          : 'No se pudo enviar la solicitud. Inténtalo de nuevo.';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(texto)));
    }
  }
}

class _Insignia extends StatelessWidget {
  const _Insignia({required this.badge});

  final ProfileBadge badge;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? descripcion = badge.description;

    return Row(
      children: <Widget>[
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: context.palette.containerSubtle,
            shape: BoxShape.circle,
          ),
          child: Icon(
            badgeIconFor(badge.icon),
            color: context.palette.brandStrong,
            size: 24,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                badge.name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: context.palette.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (descripcion != null && descripcion.isNotEmpty)
                Text(
                  descripcion,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: context.palette.textMuted,
                    // `labelSmall` viene en `w500`: sin esto la descripción se pinta más gruesa
                    // que el nombre de la insignia al que acompaña.
                    fontWeight: FontWeight.w400,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato({required this.valor, required this.etiqueta});

  final String valor;
  final String etiqueta;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            valor,
            style: theme.textTheme.titleMedium?.copyWith(
              color: context.palette.brandStrong,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            etiqueta,
            style: theme.textTheme.labelSmall?.copyWith(
              color: context.palette.textMuted,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _Centrado extends StatelessWidget {
  const _Centrado({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.gutter,
      vertical: AppSpacing.xxl,
    ),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: context.palette.textMuted),
    ),
  );
}
