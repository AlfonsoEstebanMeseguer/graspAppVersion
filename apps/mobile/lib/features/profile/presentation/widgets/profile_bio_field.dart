import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theming/grasp_palette.dart';
import '../../../../core/theming/app_theme.dart';

/// `profiles.bio`, máximo 160 — §6.4.
const int kMaxBioLength = 160;

/// El campo de biografía de la hoja de edición, con su contador.
///
/// ## El contador NO es lo que impone el tope
///
/// Lo impone `profiles_bio_length_chk` **en la base** (1-160 sobre el texto recortado), y por eso
/// da igual por qué camino nazca la fila: PostgREST, una Edge Function futura o una importación
/// (invariante de `db-schema`, punto 4d — la validación vive en el camino de escritura, no en el de
/// edición). Este contador existe para que nadie escriba 300 caracteres y **luego** se coma un
/// error, no para ser la regla.
///
/// ## Cuenta puntos de código, no unidades UTF-16
///
/// Igual que el contador de mensajes de `RN-26`, y por el mismo motivo: `char_length` en Postgres
/// cuenta caracteres. Con `String.length`, 80 emojis contarían 160 y cortarían un texto que la base
/// acepta sin rechistar.
class ProfileBioField extends StatefulWidget {
  const ProfileBioField({super.key, required this.controller});

  static const Key fieldKey = Key('profile-bio-field');
  static const Key counterKey = Key('profile-bio-counter');

  static const String label = 'Sobre ti';
  static const String hint = 'Cuenta en dos líneas qué te trae por aquí.';

  final TextEditingController controller;

  @override
  State<ProfileBioField> createState() => _ProfileBioFieldState();
}

class _ProfileBioFieldState extends State<ProfileBioField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_repintar);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_repintar);
    super.dispose();
  }

  void _repintar() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int usados = widget.controller.text.runes.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          ProfileBioField.label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: context.palette.textPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          key: ProfileBioField.fieldKey,
          controller: widget.controller,
          maxLines: 3,
          minLines: 2,
          textInputAction: TextInputAction.newline,
          // El limitador va aquí y no en un `onChanged` que recorte: se **impide entrar**, no se
          // acepta y luego se corta a escondidas. `maxLength` de `TextField` contaría unidades
          // UTF-16, así que se cuenta a mano por puntos de código.
          inputFormatters: <TextInputFormatter>[_LimitePorPuntosDeCodigo()],
          decoration: InputDecoration(
            hintText: ProfileBioField.hint,
            // Sin `counterText`: el contador propio de abajo es el que cuenta bien.
            counterText: '',
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            key: ProfileBioField.counterKey,
            '$usados/$kMaxBioLength',
            style: theme.textTheme.labelSmall?.copyWith(
              color: usados >= kMaxBioLength
                  ? context.palette.brandStrong
                  : context.palette.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}

/// Corta por **puntos de código**, que es como cuenta `char_length` en Postgres.
class _LimitePorPuntosDeCodigo extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.runes.length <= kMaxBioLength) return newValue;
    // Se devuelve **lo anterior**, no un recorte del nuevo: recortar dejaría entrar la mitad de lo
    // pegado sin decir nada, y quien pega un texto largo tiene que ver que no cabe.
    return oldValue;
  }
}
