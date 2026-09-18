import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theming/grasp_palette.dart';
import '../../../../core/theming/app_theme.dart';
import '../../../../core/ui/grasp_buttons.dart';
import '../../../../domain/profile/profile.dart';
import '../../../auth/presentation/widgets/grasp_field.dart';
import '../../../onboarding/presentation/onboarding_feed_screen.dart';
import '../../application/profile_controller.dart';
import 'profile_bio_field.dart';

const List<(String slug, String label)> _genders = <(String, String)>[
  ('hombre', 'Hombre'),
  ('mujer', 'Mujer'),
  ('otro', 'Otro'),
];

/// Hoja de edición completa del perfil — abre desde el lápiz de
/// `ProfileHeader` en `08-profile.jpeg`.
///
/// Cubre exactamente los campos con backend real hoy
/// (`profile-update`): nombre, teléfono, fecha de nacimiento, género, país.
/// El avatar NO se edita aquí: lo escribe `profile-avatar-set` y se aplica al
/// instante, mientras que esta hoja acumula cambios y los guarda con un botón.
/// Mezclar los dos modelos produce bugs de «no se guardó lo que creía», así que
/// se remite a la hoja del avatar (decisión 0014). La contraseña tampoco está:
/// requiere un flujo de verificación propio, deferido — ver
/// `features/profile/README.md`. El acceso al feed
/// de onboarding reabre `OnboardingFeedScreen` en modo edición (mismo
/// `Navigator.push` que ya usaba la sección "Temas de interés").
class ProfileEditSheet extends ConsumerStatefulWidget {
  const ProfileEditSheet({super.key, required this.profile});

  final Profile profile;

  static Future<void> show(BuildContext context, Profile profile) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // Sin esto la hoja llega hasta el borde superior de la pantalla y el título se pinta DEBAJO
      // de la barra de estado — el reloj encima de «Editar perfil». No se veía hasta que la bio
      // hizo crecer el contenido lo bastante como para tocar el techo; con `isScrollControlled` la
      // altura la manda el contenido, así que el problema estaba latente desde antes.
      useSafeArea: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      builder: (BuildContext context) => ProfileEditSheet(profile: profile),
    );
  }

  @override
  ConsumerState<ProfileEditSheet> createState() => _ProfileEditSheetState();
}

class _ProfileEditSheetState extends ConsumerState<ProfileEditSheet> {
  late final TextEditingController _nameController =
      TextEditingController(text: widget.profile.displayName ?? '');
  late final TextEditingController _countryController =
      TextEditingController(text: widget.profile.country ?? '');
  late final TextEditingController _dateController = TextEditingController(
    text: widget.profile.birthDate == null ? '' : _formatDate(widget.profile.birthDate!),
  );
  late final TextEditingController _bioController =
      TextEditingController(text: widget.profile.bio ?? '');

  DateTime? _birthDate;
  String? _gender;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _birthDate = widget.profile.birthDate;
    _gender = widget.profile.gender;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _countryController.dispose();
    _dateController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await ref.read(profileControllerProvider.notifier).updateProfile(
            displayName: _nameController.text.trim().isEmpty ? null : _nameController.text.trim(),
            birthDate: _birthDate,
            gender: _gender,
            country: _countryController.text.trim().isEmpty ? null : _countryController.text.trim(),
          );
      // La bio va por su propio camino y **después**: `profile-update` no la acepta, se escribe
      // directa sobre `profiles` (ver `ProfileRepository.updateBio`). Va después a propósito — si
      // fallara, lo que ya se guardó del formulario sigue guardado, y quien reintente no vuelve a
      // mandar lo mismo.
      if ((_bioController.text.trim()) != (widget.profile.bio ?? '').trim()) {
        await ref
            .read(profileControllerProvider.notifier)
            .updateBio(_bioController.text);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Perfil actualizado.')));
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('No se pudo guardar. Inténtalo de nuevo.')),
        );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _openFeedEditor() {
    Navigator.of(context).pop();
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(builder: (BuildContext context) => const OnboardingFeedScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.gutter,
          right: AppSpacing.gutter,
          top: AppSpacing.lg,
          bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('Editar perfil', style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.lg),
              _PhotoRow(profile: widget.profile),
              const SizedBox(height: AppSpacing.md),
              GraspField(
                label: 'Nombre',
                controller: _nameController,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: AppSpacing.md),
              GraspDateField(
                label: 'Fecha de nacimiento',
                controller: _dateController,
                onChanged: (DateTime picked) => setState(() => _birthDate = picked),
              ),
              const SizedBox(height: AppSpacing.md),
              Text('Género', style: theme.textTheme.labelMedium?.copyWith(color: context.palette.textPrimary)),
              const SizedBox(height: AppSpacing.sm),
              GraspSegmented<String>(
                segments: <String, ({String label, IconData icon})>{
                  for (final (String slug, String label) in _genders)
                    slug: (label: label, icon: Icons.person_outline_rounded),
                },
                selected: _gender ?? _genders.first.$1,
                onChanged: (String value) => setState(() => _gender = value),
              ),
              const SizedBox(height: AppSpacing.md),
              // §6.4: la bio, con su contador de 160. El tope de verdad lo impone
              // `profiles_bio_length_chk` en la base; el contador solo evita escribir de más para
              // luego comerse un error.
              ProfileBioField(controller: _bioController),
              const SizedBox(height: AppSpacing.md),
              GraspField(
                label: 'País',
                controller: _countryController,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton.icon(
                onPressed: _openFeedEditor,
                icon: const Icon(Icons.tune_rounded),
                label: const Text('Revisar / editar mi feed'),
              ),
              const SizedBox(height: AppSpacing.lg),
              GraspPrimaryButton(
                label: 'Guardar',
                isLoading: _isSaving,
                onPressed: _isSaving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoRow extends StatelessWidget {
  const _PhotoRow({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String initial =
        (profile.displayName?.trim().isNotEmpty ?? false) ? profile.displayName![0].toUpperCase() : '?';

    return Row(
      children: <Widget>[
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: context.palette.outline, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(initial, style: theme.textTheme.titleLarge?.copyWith(color: context.palette.textPrimary)),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            'La foto y el avatar se cambian tocando la foto del perfil.',
            style: theme.textTheme.bodyMedium?.copyWith(color: context.palette.textMuted),
          ),
        ),
      ],
    );
  }
}