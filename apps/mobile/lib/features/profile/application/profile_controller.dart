import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/supabase/supabase_providers.dart';
import '../../../domain/profile/profile.dart';
import '../../../domain/profile/profile_repository.dart';

/// Carga y edita el perfil del usuario autenticado.
class ProfileController extends AutoDisposeAsyncNotifier<Profile> {
  @override
  Future<Profile> build() => _repository.fetchOwn();

  ProfileRepository get _repository => ref.read(profileRepositoryProvider);

  /// Guarda los campos editados desde la hoja de edición
  /// (`widgets/profile_edit_sheet.dart`). Actualización optimista: la UI
  /// refleja el cambio al instante y se revierte solo si el backend lo
  /// rechaza — `profile-update` (validación server-side) es la última
  /// palabra.
  Future<void> updateProfile({
    String? displayName,
    DateTime? birthDate,
    String? gender,
    String? country,
  }) async {
    final Profile? previous = state.valueOrNull;
    if (previous == null) return;

    state = AsyncData<Profile>(
      previous.copyWith(
        displayName: displayName,
        age: birthDate == null ? null : _ageFrom(birthDate),
        gender: gender,
        country: country,
      ),
    );
    try {
      await _repository.updateProfile(
        displayName: displayName,
        birthDate: birthDate,
        gender: gender,
        country: country,
      );
    } on Object {
      state = AsyncData<Profile>(previous);
      rethrow;
    }
  }

  /// Guarda la biografía del §6.4 (`profiles.bio`, 1-160 por constraint de la base).
  ///
  /// Optimista con vuelta atrás, como [updateProfile]: se pinta antes de que el backend conteste
  /// para que el campo no parezca colgado, y si la escritura falla se restaura **lo que había** en
  /// vez de dejar en pantalla una bio que no se guardó.
  Future<void> updateBio(String? bio) async {
    final Profile? previous = state.valueOrNull;
    if (previous == null) return;

    final String recortada = (bio ?? '').trim();
    state = AsyncData<Profile>(
      recortada.isEmpty
          ? previous.copyWith(limpiarBio: true)
          : previous.copyWith(bio: recortada),
    );
    try {
      await _repository.updateBio(recortada.isEmpty ? null : recortada);
    } on Object {
      state = AsyncData<Profile>(previous);
      rethrow;
    }
  }

  /// `RN-32`/`RN-54`: ocultar el punto de actividad a los demás.
  Future<void> setHideActivityStatus(bool hidden) async {
    final Profile? previous = state.valueOrNull;
    if (previous == null) return;

    state = AsyncData<Profile>(previous.copyWith(hideActivityStatus: hidden));
    try {
      await _repository.setHideActivityStatus(hidden);
    } on Object {
      state = AsyncData<Profile>(previous);
      rethrow;
    }
  }

  /// Acuña un tag nuevo (`profile-tag-rotate`, §6.2).
  ///
  /// **NO es optimista, al revés que los de arriba, y la diferencia importa**: el tag nuevo lo
  /// elige el servidor y aquí no se puede adivinar. Pintar uno provisional enseñaría un
  /// identificador que no existe, y el tag es justo el dato que la gente copia y comparte. Se espera
  /// la respuesta y se pinta lo que devolvió.
  Future<TagRotation> rotateTag() async {
    final TagRotation rotation = await _repository.rotateTag();
    final Profile? previous = state.valueOrNull;
    if (previous != null) {
      state = AsyncData<Profile>(previous.copyWith(tag: rotation.tag));
    }
    return rotation;
  }

  int _ageFrom(DateTime birthDate) {
    final DateTime now = DateTime.now();
    int age = now.year - birthDate.year;
    final bool hasNotHadBirthdayYet =
        now.month < birthDate.month ||
        (now.month == birthDate.month && now.day < birthDate.day);
    if (hasNotHadBirthdayYet) age -= 1;
    return age;
  }
}

final AutoDisposeAsyncNotifierProvider<ProfileController, Profile>
profileControllerProvider =
    AsyncNotifierProvider.autoDispose<ProfileController, Profile>(
      ProfileController.new,
    );