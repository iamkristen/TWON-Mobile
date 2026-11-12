import 'package:flutter_test/flutter_test.dart';
import 'package:twon_mobile/core/models.dart';
import 'package:twon_mobile/features/account/settings_pages.dart';

/// SEC-020/SEC-021: deletion sends credentials; devices are revoked by stable session id.
void main() {
  test(
    'deletion body carries the password, and the code only when entered',
    () {
      expect(deletionRequestBody({'currentPassword': 'Passw0rd!'}), {
        'currentPassword': 'Passw0rd!',
      });
      expect(
        deletionRequestBody({
          'currentPassword': 'Passw0rd!',
          'token': ' 123456 ',
        }),
        {'currentPassword': 'Passw0rd!', 'token': '123456'},
      );
      expect(
        deletionRequestBody({'currentPassword': 'Passw0rd!', 'token': ''}),
        {'currentPassword': 'Passw0rd!'},
      );
    },
  );

  test(
    'revokes by the stable id, falling back to the jti from older servers',
    () {
      final id = 'a' * 24;
      expect(
        sessionRevokePath(Entity({'id': id, 'jti': 'j1'})),
        'auth/sessions/$id',
      );
      expect(sessionRevokePath(Entity({'jti': 'j1'})), 'auth/sessions/j1');
    },
  );
}
