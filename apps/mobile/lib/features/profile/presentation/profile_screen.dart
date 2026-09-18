import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theming/grasp_palette.dart';
import '../../../core/theming/app_theme.dart';
import '../../../core/ui/grasp_backdrop.dart';
import '../../../data/supabase/supabase_providers.dart';
import '../../../domain/profile/profile.dart';
import '../application/follows_controller.dart';
import '../application/profile_controller.dart';
import '../../settings/presentation/settings_screen.dart';
import 'follows_screen.dart';
import 'widgets/avatar_sheet.dart';
import 'widgets/privacy_section.dart';
import 'widgets/profile_tag_row.dart';
import 'widgets/avatar_viewer.dart';
import 'widgets/delete_account_sheet.dart';
import 'widgets/profile_badges_section.dart';
import 'widgets/profile_edit_sheet.dart';
import 'widgets/profile_header.dart';
import 'widgets/profile_metrics_row.dart';
import 'widgets/profile_section_card.dart';
import 'widgets/profile_xp_bar.dart';

/// Perfil propio — `08-profile.jpeg`.
///
/// Vive dentro del `StatefulShellRoute` de la barra inferior (ver
/// `core/router/app_router.dart`), así que no lleva su propio
/// `bottomNavigationBar`: lo pone `AppShellScreen`.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Profile> profileAsync = ref.watch(profileControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Ajustes',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => SettingsScreen.open(context),
          ),
          // Cerrar sesión vive aquí (y no en Inicio, como en el placeholder
          // del Bloque 1) porque Inicio ya es un destino real de la barra
          // inferior: no tiene sentido que cargue un botón de cuenta.
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
          ),
        ],
      ),
      body: GraspBackdrop(
        sceneHeightFactor: 0.18,
        sceneOpacity: 0.2,
        child: SafeArea(
          top: false,
          child: profileAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (Object error, StackTrace _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.gutter),
                child: Text(
                  'No se pudo cargar tu perfil. Desliza hacia abajo para reintentar.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
            data: (Profile profile) => RefreshIndicator(
              onRefresh: () => ref.refresh(profileControllerProvider.future),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  AppSpacing.md,
                  AppSpacing.gutter,
                  AppSpacing.xl,
                ),
                children: <Widget>[
                  ProfileHeader(
                    profile: profile,
                    birthDateMonthDay: formatBirthDateMonthDay(profile.birthDate),
                    onTapPhoto: () => AvatarSheet.show(
                      context,
                      selected: profile.presetAvatar,
                    ),
                    onTapAvatar: () => AvatarViewer.show(context, profile),
                    onTapEdit: () => ProfileEditSheet.show(context, profile),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  // §6.2: el tag, con copiar y cambiar. Va justo bajo la cabecera porque es parte
                  // de la identidad, no un ajuste.
                  ProfileTagRow(tag: profile.tag),
                  const SizedBox(height: AppSpacing.lg),
                  ProfileXpBar(level: profile.level, xp: profile.xp),
                  const SizedBox(height: AppSpacing.lg),
                  ProfileStatsGrid(
                    roomsJoinedCount: profile.roomsJoinedCount,
                    timeHelpingSeconds: profile.timeHelpingSeconds,
                    followersCount: profile.followersCount,
                    followingCount: profile.followingCount,
                    // `RN-50`: dejan de ser números inertes.
                    onTapFollowers: () =>
                        _abrirFollows(context, FollowsTab.followers),
                    onTapFollowing: () =>
                        _abrirFollows(context, FollowsTab.following),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ProfileSectionCard(
                    title: 'Insignias',
                    trailingLabel: 'Ver todas',
                    onTrailingTap: () => ProfileBadgesModal.show(context, profile.badges),
                    child: ProfileBadgesSummary(badges: profile.badges),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // `RN-32`/`RN-54`. A la vista y no dentro de la hoja de edición: un ajuste de
                  // privacidad que hay que buscar es tan inútil como uno que no existe.
                  const PrivacySection(),
                  const SizedBox(height: AppSpacing.md),
                  ProfileSectionCard(
                    title: 'Estadísticas',
                    trailingLabel: 'Ver todas',
                    onTrailingTap: () => _showComingSoon(context, 'Más estadísticas'),
                    child: _StreakRow(streakDays: profile.streakDays),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const _DeleteAccountEntry(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// `RN-50`: abre la lista que toque.
  ///
  /// `rootNavigator: true` para que la lista se apile **por encima de la barra inferior**, como la
  /// conversación: es un sitio del que se vuelve, no una quinta pestaña.
  void _abrirFollows(BuildContext context, FollowsTab tab) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => FollowsScreen(tab: tab),
      ),
    );
  }

  void _showComingSoon(BuildContext context, String subject) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$subject llega en un próximo bloque.')));
  }
}

/// "🔥 12 días consecutivos" — única métrica de la sección Estadísticas hoy
/// (Sección 4, punto 6 del encargo de Bloque 2: "de momento solo esa
/// métrica").
class _StreakRow extends StatelessWidget {
  const _StreakRow({required this.streakDays});

  final int streakDays;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$streakDays días consecutivos de racha',
      child: ExcludeSemantics(
        child: Row(
          children: <Widget>[
            const Text('🔥', style: TextStyle(fontSize: 20)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text('Días consecutivos', style: Theme.of(context).textTheme.bodyMedium),
            ),
            Text(
              '$streakDays días',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: context.palette.brandStrong),
            ),
          ],
        ),
      ),
    );
  }
}

/// Entrada al borrado de cuenta — hallazgo H-SV-02 de la auditoría de
/// 2026-08-15.
///
/// Deliberadamente **no** es un icono en el `AppBar` como "Cerrar sesión":
/// esa ubicación es apropiada para una acción reversible y de escape (salir
/// de una sesión atascada), pero un icono junto a otros dos en la cabecera
/// pondría a un tap de distancia una acción irreversible. Se pinta como un
/// enlace de texto discreto al final del scroll, fuera de las tarjetas que
/// replican `08-profile.jpeg` (Insignias, Estadísticas) para no dar a
/// entender que es contenido del boceto: es una entrada nueva, añadida sin
/// boceto propio (ver `DeleteAccountSheet`).
class _DeleteAccountEntry extends StatelessWidget {
  const _DeleteAccountEntry();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Semantics(
        button: true,
        label: 'Eliminar cuenta',
        child: TextButton.icon(
          onPressed: () => DeleteAccountSheet.show(context),
          icon: Icon(Icons.delete_outline_rounded, color: context.palette.error, size: 18),
          label: Text(
            'Eliminar cuenta',
            style: theme.textTheme.labelMedium?.copyWith(color: context.palette.error),
          ),
        ),
      ),
    );
  }
}