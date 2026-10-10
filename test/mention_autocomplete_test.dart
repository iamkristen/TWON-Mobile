import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twon_mobile/core/api.dart';
import 'package:twon_mobile/features/feed/post_composer_support.dart';
import 'api_session_test.dart' show MemoryStore, ApiAdapter;

void main() {
  test(
    'mention range ignores emails and replaces a complete handle around the cursor',
    () {
      expect(
        activeMention(
          'wolf@example.com',
          const TextSelection.collapsed(offset: 9),
        ),
        isNull,
      );
      expect(
        activeMention(
          '@wolf',
          const TextSelection(baseOffset: 0, extentOffset: 5),
        ),
        isNull,
      );
      final range = activeMention(
        'Hi @maya next',
        const TextSelection.collapsed(offset: 6),
      )!;
      expect(range.query, 'ma');
      expect(range.start, 3);
      expect(range.end, 8);
    },
  );
  testWidgets(
    'stale member searches cannot replace the newest suggestions or reopen a dismissed picker',
    (tester) async {
      final first = Completer<ResponseBody>();
      final api = DioRepository(
        baseUrl: 'https://test.invalid/api/v1',
        store: MemoryStore(),
      );
      ResponseBody result(String handle) => ResponseBody.fromString(
        jsonEncode({
          'success': true,
          'data': [
            {'id': handle, 'handle': handle, 'fullName': handle},
          ],
        }),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
      api.dio.httpClientAdapter = ApiAdapter(
        (r) async =>
            r.queryParameters['q'] == 'aa' ? first.future : result('ab'),
      );
      final cubit = MentionCubit(api);
      cubit.update(const MentionRange(0, 3, 'aa'));
      await tester.pump(const Duration(milliseconds: 250));
      cubit.update(const MentionRange(0, 3, 'ab'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      expect(cubit.state.items.single.text('handle'), 'ab');
      cubit.update(null);
      first.complete(result('aa'));
      await tester.pump();
      expect(cubit.state.range, isNull);
      expect(cubit.state.items, isEmpty);
      await cubit.close();
      api.dio.close(force: true);
      await api.expired.close();
      await api.tokensChanged.close();
    },
  );
}
