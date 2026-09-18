import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/domain/social/blocked_user.dart';

void main() {
  test('BlockedUser.fromJson lee el perfil incrustado y la fecha', () {
    final BlockedUser bloqueado = BlockedUser.fromJson(<String, dynamic>{
      'created_at': '2026-08-20T10:00:00.000Z',
      'blocked': <String, dynamic>{
        'user_id': 'aaaaaaaa-0027-4000-8000-00000000000a',
        'display_name': 'Ana',
        'tag': 'ana#K7M2QX9F',
        'preset_avatar': null,
        'photo_path': null,
      },
    });

    expect(bloqueado.profile.userId, 'aaaaaaaa-0027-4000-8000-00000000000a');
    expect(bloqueado.profile.displayName, 'Ana');
    expect(bloqueado.profile.tag, 'ana#K7M2QX9F');
    expect(bloqueado.blockedAt.toUtc(), DateTime.utc(2026, 8, 20, 10));
  });
}
