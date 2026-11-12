import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:twon_mobile/core/api.dart';
import 'package:twon_mobile/features/account/account_pages.dart';
import 'package:twon_mobile/features/feed/post_composer_support.dart';
import 'api_session_test.dart' show MemoryStore, ApiAdapter;

void main() {
  test('whole hashtag tokens exclude URL fragments and trailing punctuation', () {
    final tokens = socialTokens
        .allMatches(
          'Hi @maya #TWON, #Himalayas! word#no ##bad https://example.com/#fragment',
        )
        .map((m) => m.group(0))
        .toList();
    expect(tokens, [
      '@maya',
      '#TWON',
      '#Himalayas',
      'https://example.com/#fragment',
    ]);
  });
  testWidgets(
    'hashtag recognizer opens the existing search route with its visible query',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final router = GoRouter(
        initialLocation: '/feed',
        routes: [
          GoRoute(
            path: '/feed',
            builder: (_, _) => const Scaffold(
              body: SocialPostText(text: '#TWON, #Himalayas!'),
            ),
          ),
          GoRoute(
            path: '/search',
            builder: (_, state) => Scaffold(
              body: Text('Searching ${state.uri.queryParameters['q']}'),
            ),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.tapOnText(find.textRange.ofSubstring('#TWON'));
      await tester.pumpAndSettle();
      expect(find.text('Searching #TWON'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(SocialPostText), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    },
  );
  testWidgets(
    'hashtag search keeps the term visible and reuses paginated posts API',
    (tester) async {
      final api = DioRepository(
        baseUrl: 'https://test.invalid/api/v1',
        store: MemoryStore(),
      );
      final requests = <RequestOptions>[];
      api.dio.httpClientAdapter = ApiAdapter((request) async {
        requests.add(request);
        return ResponseBody.fromString(
          jsonEncode({
            'success': true,
            'data': [],
            'meta': {'nextCursor': null},
          }),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        );
      });
      await tester.pumpWidget(
        RepositoryProvider<AppRepository>.value(
          value: api,
          child: const MaterialApp(
            home: Scaffold(body: SearchPage(initialQuery: '#Himalayas')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '#Himalayas',
      );
      expect(requests.single.path, 'posts');
      expect(requests.single.queryParameters['hashtag'], '#Himalayas');
      expect(find.text('No visible posts with this hashtag.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      api.dio.close(force: true);
      await api.expired.close();
      await api.tokensChanged.close();
    },
  );
}
