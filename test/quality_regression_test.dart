import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twon_mobile/core/api.dart';
import 'package:twon_mobile/core/models.dart';
import 'package:twon_mobile/core/realtime.dart';
import 'package:twon_mobile/features/chat/chat_bloc.dart';
import 'package:twon_mobile/shared/forms.dart';
import 'social_experience_test.dart' show Harness;

class QualityRepository extends Mock implements AppRepository {}

void main() {
  testWidgets(
    'numeric initial values survive editing and optional fields can be blank',
    (tester) async {
      Json? submitted;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FeatureForm(
              title: 'Edit requirements',
              fields: const [
                FieldSpec(
                  'minimum',
                  'Minimum points',
                  kind: FieldKind.integer,
                  initial: 12,
                ),
                FieldSpec(
                  'extra',
                  'Extra amount',
                  kind: FieldKind.decimal,
                  required: false,
                ),
                FieldSpec(
                  'email',
                  'Contact email',
                  kind: FieldKind.email,
                  required: false,
                ),
              ],
              submit: (values) async {
                submitted = values;
                return values;
              },
            ),
          ),
        ),
      );
      expect(find.text('12'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(submitted?['minimum'], 12);
      expect(submitted?.containsKey('extra'), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('forms reject malformed email and non-finite amounts', (
    tester,
  ) async {
    var writes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeatureForm(
            title: 'Contact',
            fields: const [
              FieldSpec('email', 'Email', kind: FieldKind.email),
              FieldSpec('amount', 'Amount', kind: FieldKind.decimal),
            ],
            submit: (_) async {
              writes++;
            },
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField).at(0), 'a@');
    await tester.enterText(find.byType(TextFormField).at(1), 'NaN');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(find.text('Enter a valid email.'), findsOneWidget);
    expect(find.text('Enter a number.'), findsOneWidget);
  });

  test(
    'chat refresh does not reopen exhausted older-message history',
    () async {
      final harness = Harness();
      final realtime = RealtimeService(harness.api);
      final api = QualityRepository();
      var loads = 0;
      when(() => api.page(any(), query: any(named: 'query'))).thenAnswer((
        _,
      ) async {
        loads++;
        return ApiPage([
          Entity({'id': 'message-$loads', 'createdAt': '2026-10-08T00:00:00Z'}),
        ], loads == 2 ? null : 'cursor-$loads');
      });
      when(
        () => api.request(any(), method: any(named: 'method')),
      ).thenAnswer((_) async => null);
      final bloc = ChatBloc(api, realtime, 'conversation');
      await bloc.stream.firstWhere((s) => s.messages.length == 1 && !s.loading);
      bloc.add(ChatLoad(older: true));
      await bloc.stream.firstWhere((s) => s.messages.length == 2);
      expect(bloc.state.cursor, isNull);
      bloc.add(ChatLoad());
      await bloc.stream.firstWhere((s) => s.messages.length == 3);
      expect(bloc.state.cursor, isNull);
      bloc.add(ChatLoad(older: true));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(loads, 3);
      await bloc.close();
      await realtime.dispose();
      harness.api.dio.close();
      await harness.api.expired.close();
      await harness.api.tokensChanged.close();
    },
  );

  test(
    'closing chat during a pending send does not emit after closure',
    () async {
      final harness = Harness();
      final realtime = RealtimeService(harness.api);
      final api = QualityRepository();
      final send = Completer<dynamic>();
      when(
        () => api.page(any(), query: any(named: 'query')),
      ).thenAnswer((_) async => const ApiPage([], null));
      when(
        () => api.request(any(), method: any(named: 'method')),
      ).thenAnswer((_) async => null);
      when(
        () => api.request(
          any(),
          method: 'POST',
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) => send.future);
      final bloc = ChatBloc(api, realtime, 'conversation');
      await Future<void>.delayed(Duration.zero);
      bloc.add(ChatSend({'body': 'Hello'}));
      await bloc.stream.firstWhere((s) => s.sending);
      final closing = bloc.close();
      send.complete({'id': 'sent', 'createdAt': '2026-10-08T00:00:00Z'});
      await closing;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await realtime.dispose();
      harness.api.dio.close();
      await harness.api.expired.close();
      await harness.api.tokensChanged.close();
    },
  );
}
