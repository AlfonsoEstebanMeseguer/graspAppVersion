import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theming/grasp_palette.dart';
import '../../../../core/theming/app_theme.dart';

/// Campo de texto de la zona de autenticación: etiqueta encima, superficie
/// blanca con sombra difusa, radio de los bocetos.
class GraspField extends StatelessWidget {
  const GraspField({
    super.key,
    required this.label,
    required this.controller,
    this.hintText,
    this.keyboardType,
    this.textInputAction = TextInputAction.done,
    this.autofillHints,
    this.prefixIcon,
    this.enabled = true,
    this.autofocus = false,
    this.errorText,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final String? hintText;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final Iterable<String>? autofillHints;
  final IconData? prefixIcon;
  final bool enabled;
  final bool autofocus;
  final String? errorText;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.xs,
            bottom: AppSpacing.sm,
          ),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: context.palette.textPrimary,
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.field),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: context.palette.shadowSoft,
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            enabled: enabled,
            autofocus: autofocus,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            autofillHints: autofillHints,
            inputFormatters: inputFormatters,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            style: theme.textTheme.bodyLarge,
            decoration: InputDecoration(
              hintText: hintText,
              errorText: errorText,
              prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
            ),
          ),
        ),
      ],
    );
  }
}

/// Campo de contraseña con toggle de visibilidad (ojo).
class GraspPasswordField extends StatefulWidget {
  const GraspPasswordField({
    super.key,
    required this.label,
    required this.controller,
    this.hintText,
    this.enabled = true,
    this.autofocus = false,
    this.errorText,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction = TextInputAction.done,
  });

  final String label;
  final TextEditingController controller;
  final String? hintText;
  final bool enabled;
  final bool autofocus;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction textInputAction;

  @override
  State<GraspPasswordField> createState() => _GraspPasswordFieldState();
}

class _GraspPasswordFieldState extends State<GraspPasswordField> {
  bool _obscureText = true;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.xs,
            bottom: AppSpacing.sm,
          ),
          child: Text(
            widget.label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: context.palette.textPrimary,
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.field),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: context.palette.shadowSoft,
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: TextField(
            controller: widget.controller,
            enabled: widget.enabled,
            autofocus: widget.autofocus,
            obscureText: _obscureText,
            textInputAction: widget.textInputAction,
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
            style: theme.textTheme.bodyLarge,
            decoration: InputDecoration(
              hintText: widget.hintText,
              errorText: widget.errorText,
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                // El `tooltip` es también la etiqueta semántica del botón: sin
                // él, un lector de pantalla solo anuncia "botón". Cambia con el
                // estado para decir qué va a pasar, no en qué estado está.
                tooltip: _obscureText
                    ? 'Mostrar contraseña'
                    : 'Ocultar contraseña',
                icon: Icon(
                  _obscureText ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                  color: context.palette.brandStrong,
                ),
                onPressed: widget.enabled
                    ? () => setState(() => _obscureText = !_obscureText)
                    : null,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Campo de fecha con calendar picker y edición directa.
class GraspDateField extends StatefulWidget {
  const GraspDateField({
    super.key,
    required this.label,
    required this.controller,
    this.hintText = 'DD/MM/YYYY',
    this.enabled = true,
    this.errorText,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final String hintText;
  final bool enabled;
  final String? errorText;
  final ValueChanged<DateTime>? onChanged;

  @override
  State<GraspDateField> createState() => _GraspDateFieldState();
}

class _GraspDateFieldState extends State<GraspDateField> {
  DateTime? _selectedDate;

  /// Barrera de edad del Art. 8 RGPD: nadie puede registrarse (ni editar su
  /// fecha de nacimiento después) con menos de 13 años. El backend ya lo
  /// rechaza en `handle_new_user` (edad < 13 o > 120) — este límite existe
  /// para que la UI nunca deje construir esa petición, no como duplicado
  /// decorativo (hallazgo H-RV-01).
  DateTime get _maxBirthDate {
    final DateTime now = DateTime.now();
    return DateTime(now.year - 13, now.month, now.day);
  }

  DateTime get _minBirthDate {
    final DateTime now = DateTime.now();
    return DateTime(now.year - 120, now.month, now.day);
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime maxDate = _maxBirthDate;
    final DateTime minDate = _minBirthDate;
    final DateTime? initial = _selectedDate;
    final DateTime initialDate =
        (initial != null && !initial.isAfter(maxDate) && !initial.isBefore(minDate))
            ? initial
            : maxDate;

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: minDate,
      lastDate: maxDate,
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      widget.controller.text = _formatDate(picked);
      widget.onChanged?.call(picked);
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  DateTime? _parseDate(String text) {
    try {
      final List<String> parts = text.split('/');
      if (parts.length == 3) {
        return DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
      }
    } catch (_) {}
    return null;
  }

  void _onFieldChanged(String value) {
    final DateTime? parsed = _parseDate(value);
    if (parsed != null) {
      setState(() => _selectedDate = parsed);
      widget.onChanged?.call(parsed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.xs,
            bottom: AppSpacing.sm,
          ),
          child: Text(
            widget.label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: context.palette.textPrimary,
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.field),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: context.palette.shadowSoft,
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: TextField(
            controller: widget.controller,
            enabled: widget.enabled,
            keyboardType: TextInputType.number,
            onChanged: _onFieldChanged,
            style: theme.textTheme.bodyLarge,
            decoration: InputDecoration(
              hintText: widget.hintText,
              errorText: widget.errorText,
              prefixIcon: const Icon(Icons.calendar_today_rounded),
              suffixIcon: widget.enabled
                  ? IconButton(
                      tooltip: 'Elegir fecha en el calendario',
                      icon: Icon(
                        Icons.calendar_month_rounded,
                        color: context.palette.brandStrong,
                      ),
                      onPressed: () => _selectDate(context),
                    )
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}

/// Selector Email / Teléfono. Píldora segmentada, en la línea de los chips de
/// `03-feed-rooms.jpeg`.
class GraspSegmented<T> extends StatelessWidget {
  const GraspSegmented({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final Map<T, ({String label, IconData icon})> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: context.palette.containerSubtle,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        children: <Widget>[
          for (final MapEntry<T, ({String label, IconData icon})> entry
              in segments.entries)
            Expanded(
              child: Semantics(
                button: true,
                selected: entry.key == selected,
                label: entry.value.label,
                child: ExcludeSemantics(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onChanged(entry.key),
                    child: AnimatedContainer(
                      duration: GraspMotion.of(context).fast,
                      curve: Curves.easeOut,
                      height: 44,
                      decoration: BoxDecoration(
                        color: entry.key == selected
                            ? context.palette.surface
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        boxShadow: entry.key == selected
                            ? <BoxShadow>[
                                BoxShadow(
                                  color: context.palette.shadowSoft,
                                  blurRadius: 10,
                                  offset: Offset(0, 3),
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Icon(
                            entry.value.icon,
                            size: 18,
                            color: entry.key == selected
                                ? context.palette.brandStrong
                                : context.palette.textSecondary,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            entry.value.label,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: entry.key == selected
                                  ? context.palette.textPrimary
                                  : context.palette.textSecondary,
                              fontWeight: entry.key == selected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
