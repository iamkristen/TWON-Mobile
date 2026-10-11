import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twon_mobile/app.dart';
import 'package:twon_mobile/core/api.dart';
import 'package:twon_mobile/core/models.dart';
import 'package:twon_mobile/features/feed/feed_pages.dart';
import 'package:twon_mobile/features/feed/post_composer_support.dart';
import 'package:twon_mobile/features/account/account_pages.dart';
import 'package:twon_mobile/shared/widgets.dart';
import 'api_session_test.dart' show MemoryStore, ApiAdapter;

const viewer = {
  'id': 'viewer',
  'fullName': 'Kristen Lama',
  'handle': 'kristen',
  'country': 'NP',
};
Json samplePost(int i) => {
  'id': 'post-$i',
  'body': i == 0
      ? 'There’s something special about finding your people, even when you’re miles from home.\n\nWhere is everyone spending their weekend? '
      : 'A little moment from the pack. Sharing good things and making new connections.',
  'authorId': {
    'id': 'aayush',
    'fullName': 'Aayush Shrestha',
    'handle': 'aayush',
  },
  'type': 'general',
  'visibility': 'public',
  'createdAt': DateTime.now()
      .subtract(Duration(minutes: 12 + i))
      .toIso8601String(),
  'likes': <String>[],
  'likeCount': 24,
  'commentCount': 8,
  'media': <String>[],
};

class Harness {
  final calls = <RequestOptions>[];
  final store = MemoryStore();
  late final DioRepository api;
  Harness({
    bool empty = false,
    bool likeFails = false,
    Json fixtures = const {},
    Map<String, String> nextCursors = const {},
  }) {
    store.value = {
      'accessToken': 'local-test',
      'refreshToken': 'local-test-refresh',
      'user': viewer,
    };
    api = DioRepository(baseUrl: 'https://test.invalid/api/v1', store: store);
    api.dio.httpClientAdapter = ApiAdapter((r) async {
      calls.add(r);
      Object? data = [];
      if (r.path == 'users/me') {
        data = viewer;
      } else if (r.path == 'posts' && r.method == 'GET') {
        data = empty ? [] : List.generate(12, samplePost);
      } else if (r.path.endsWith('/like')) {
        if (likeFails) {
          return ResponseBody.fromString(
            jsonEncode({
              'success': false,
              'error': {'message': 'Connection interrupted'},
            }),
            503,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          );
        }
        data = {
          ...samplePost(0),
          'authorId': 'aayush',
          'likes': ['viewer'],
          'likeCount': 25,
        };
      } else if (r.path == 'posts' && r.method == 'POST') {
        data = {'id': 'published', ...asJson(r.data)};
      }
      final fixtureKey =
          '${r.path}${r.queryParameters['cursor'] == null ? '' : ':${r.queryParameters['cursor']}'}';
      if (fixtures.containsKey(fixtureKey)) data = fixtures[fixtureKey];
      return ResponseBody.fromString(
        jsonEncode({
          'success': true,
          'data': data,
          'meta': {'nextCursor': nextCursors[fixtureKey]},
        }),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    });
  }
  Future<void> mount(
    WidgetTester tester, {
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('preview'),
        child: TwonApp(api: api, preferences: prefs),
      ),
    );
    await tester.pumpAndSettle();
    if (scale != 1) {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      await tester.pumpAndSettle();
    }
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    await api.expired.close();
    await api.tokensChanged.close();
  }
}

Future<void> capture(WidgetTester tester, String name) async {
  final output = const String.fromEnvironment('PREVIEW_DIR');
  if (output.isEmpty) return;
  final fontDirectory = const String.fromEnvironment('PREVIEW_FONTS');
  if (fontDirectory.isNotEmpty) {
    await tester.runAsync(() async {
      final loader = FontLoader('Roboto');
      for (final file in ['Roboto-Regular.ttf', 'Roboto-Bold.ttf']) {
        loader.addFont(
          Future.value(
            ByteData.sublistView(
              await File('$fontDirectory/$file').readAsBytes(),
            ),
          ),
        );
      }
      await loader.load();
      final icons = FontLoader('MaterialIcons');
      icons.addFont(
        Future.value(
          ByteData.sublistView(
            await File(
              '$fontDirectory/MaterialIcons-Regular.otf',
            ).readAsBytes(),
          ),
        ),
      );
      await icons.load();
    });
    await tester.pumpAndSettle();
  }
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('preview')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final directory =
        '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts';
    for (final entry in {
      'Roboto': ['Roboto-Regular.ttf', 'Roboto-Bold.ttf'],
      'MaterialIcons': ['MaterialIcons-Regular.otf'],
    }.entries) {
      final loader = FontLoader(entry.key);
      for (final file in entry.value) {
        loader.addFont(
          Future.value(
            ByteData.sublistView(await File('$directory/$file').readAsBytes()),
          ),
        );
      }
      await loader.load();
    }
  });

  testWidgets(
    'feed has no filters or Post button; composer publishes to the backend',
    (tester) async {
      final h = Harness();
      await h.mount(tester);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.text('Post'), findsNothing);
      expect(find.text('Your pack, your people.'), findsNothing);
      expect(find.byTooltip('Refresh feed'), findsNothing);
      expect(find.text('FROM YOUR COMMUNITY'), findsNothing);
      expect(find.text('What’s on your mind?'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(FeedComposer),
          matching: find.byType(MemberAvatar),
        ),
        findsOneWidget,
      );
      expect(find.text('Photo'), findsNothing);
      expect(find.text('Anonymous'), findsNothing);
      expect(
        h.calls
            .firstWhere((r) => r.path == 'posts')
            .queryParameters
            .containsKey('type'),
        isFalse,
      );
      await capture(tester, 'TWON-social-feed');
      await tester.tap(find.text('What’s on your mind?'));
      await tester.pumpAndSettle();
      expect(find.byType(PostEditor), findsOneWidget);
      await tester.enterText(
        find.byType(TextField).first,
        'A real backend-connected thought.',
      );
      await tester.pump();
      await tester.tap(find.text('Share with the pack'));
      await tester.pumpAndSettle();
      final write = h.calls.firstWhere(
        (r) => r.path == 'posts' && r.method == 'POST',
      );
      expect(asJson(write.data)['body'], 'A real backend-connected thought.');
      expect(asJson(write.data)['type'], 'general');
      expect(find.byType(FeedTimeline), findsOneWidget);
      await h.close(tester);
    },
  );
  testWidgets(
    'tab switching preserves feed position and the top Settings follows Notifications',
    (tester) async {
      final h = Harness();
      await h.mount(tester);
      final settings = tester.getCenter(find.byTooltip('Settings'));
      final notifications = tester.getCenter(find.byTooltip('Notifications'));
      expect(settings.dx, greaterThan(notifications.dx));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -650));
      await tester.pumpAndSettle();
      final scrollable = find
          .descendant(
            of: find.byType(FeedTimeline),
            matching: find.byType(Scrollable),
          )
          .first;
      final offset = tester.state<ScrollableState>(scrollable).position.pixels;
      await tester.tap(find.byKey(const ValueKey('tab-/clans')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tab-/feed')));
      await tester.pumpAndSettle();
      expect(tester.state<ScrollableState>(scrollable).position.pixels, offset);
      expect(
        h.calls.where((r) => r.path == 'posts' && r.method == 'GET').length,
        1,
      );
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Notifications & privacy'), findsOneWidget);
      await h.close(tester);
    },
  );
  testWidgets(
    'like uses the backend and patches one card without reloading the timeline',
    (tester) async {
      final h = Harness();
      await h.mount(tester);
      await tester.ensureVisible(find.byTooltip('Like').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Like').first);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Liked'), findsOneWidget);
      expect(find.text('25'), findsOneWidget);
      expect(find.text('Pack member'), findsNothing);
      expect(
        h.calls.where((r) => r.path == 'posts' && r.method == 'GET').length,
        1,
      );
      expect(
        h.calls
            .where((r) => r.path == 'posts/post-0/like' && r.method == 'POST')
            .length,
        1,
      );
      await h.close(tester);
    },
  );
  testWidgets(
    'failed like keeps the previous state and offers an understandable error',
    (tester) async {
      final h = Harness(likeFails: true);
      await h.mount(tester);
      await tester.ensureVisible(find.byTooltip('Like').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Like').first);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Liked'), findsNothing);
      expect(find.text('24'), findsWidgets);
      expect(find.text('Connection interrupted'), findsOneWidget);
      await h.close(tester);
    },
  );
  testWidgets('drawer exposes Settings and shop submenus with SVG branding', (
    tester,
  ) async {
    final h = Harness();
    await h.mount(tester);
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await capture(tester, 'TWON-social-drawer');
    await tester.scrollUntilVisible(
      find.text('Settings & privacy'),
      250,
      scrollable: find
          .descendant(
            of: find.byType(TwonDrawer),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Settings & privacy'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('All settings'));
    await tester.tap(find.text('All settings'));
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsOneWidget);
    await h.close(tester);
  });
  testWidgets(
    'empty feed uses the web illustration and stays usable at large text size',
    (tester) async {
      final h = Harness(empty: true);
      await h.mount(tester, width: 320, scale: 1.8);
      expect(find.text('Every pack starts with a howl.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Appearance'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await h.close(tester);
    },
  );
  testWidgets(
    'anonymous sharing remains available inside the new post screen',
    (tester) async {
      final h = Harness();
      await h.mount(tester);
      await tester.tap(find.text('What’s on your mind?'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Share anonymously'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share anonymously'));
      await tester.pumpAndSettle();
      expect(find.text('Anonymous pack member'), findsOneWidget);
      await tester.enterText(
        find.byType(TextField).first,
        'A question without my name.',
      );
      await tester.pump();
      await capture(tester, 'TWON-social-composer');
      await tester.tap(find.text('Share with the pack'));
      await tester.pumpAndSettle();
      expect(
        asJson(
          h.calls
              .firstWhere((r) => r.path == 'posts' && r.method == 'POST')
              .data,
        )['isAnonymous'],
        isTrue,
      );
      await h.close(tester);
    },
  );
  testWidgets(
    'leaving a draft asks before discarding and does not reload the feed',
    (tester) async {
      final h = Harness();
      await h.mount(tester);
      await tester.tap(find.text('What’s on your mind?'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).first,
        'Keep this thought until I decide.',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Leave this post?'), findsOneWidget);
      await tester.tap(find.text('Keep writing'));
      await tester.pumpAndSettle();
      expect(find.text('Keep this thought until I decide.'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.byType(FeedTimeline), findsOneWidget);
      expect(
        h.calls.where((r) => r.path == 'posts' && r.method == 'GET').length,
        1,
      );
      expect(h.calls.where((r) => r.method == 'POST'), isEmpty);
      await h.close(tester);
    },
  );
  testWidgets('drawer and feed fit on a narrow phone with large text', (
    tester,
  ) async {
    final h = Harness();
    await h.mount(tester, width: 320, scale: 1.8);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Close menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('What’s on your mind?'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await h.close(tester);
  });
  testWidgets(
    'gathering filters apply backend parameters and cancel without changing results',
    (tester) async {
      final h = Harness(
        fixtures: {
          'clans/me': {
            'membership': {'canHostEvents': true},
          },
          'events': [
            {
              'id': 'walk',
              'title': 'A walk with the pack',
              'date': '2026-10-15',
              'time': '10:00',
              'location': 'London',
              'attendeeCount': 12,
            },
          ],
        },
      );
      await h.mount(tester);
      await tester.tap(find.byKey(const ValueKey('tab-/events')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Publish gathering'), findsOneWidget);
      expect(
        tester.getCenter(find.byTooltip('Filter gatherings')).dy,
        closeTo(tester.getCenter(find.byType(TextField)).dy, 2),
      );
      await capture(tester, 'TWON-clean-gatherings');
      await tester.tap(find.byTooltip('Filter gatherings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upcoming'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Past').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Outdoors');
      await tester.tap(find.text('Show gatherings'));
      await tester.pumpAndSettle();
      final query = h.calls
          .lastWhere((r) => r.path == 'events')
          .queryParameters;
      expect(query['period'], 'past');
      expect(query['category'], 'Outdoors');
      await tester.tap(find.byTooltip('Filter gatherings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(12, 120));
      await tester.pumpAndSettle();
      expect(find.text('Outdoors'), findsOneWidget);
      await h.close(tester);
    },
  );

  testWidgets(
    'chat search finds later pages and retains the new conversation flow',
    (tester) async {
      final h = Harness(
        fixtures: {
          'conversations': [
            {
              'id': 'first',
              'name': 'London pack',
              'participants': <Json>[],
              'lastMessage': {'text': 'See you at the gathering.'},
            },
          ],
          'conversations:next': [
            {
              'id': 'second',
              'name': 'Mountain wolves',
              'participants': <Json>[],
              'lastMessage': {'text': 'The trail is calling.'},
            },
          ],
        },
        nextCursors: {'conversations': 'next'},
      );
      await h.mount(tester);
      await tester.tap(find.byKey(const ValueKey('tab-/messages')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Search chats'), findsOneWidget);
      expect(find.byTooltip('Notifications'), findsNothing);
      expect(find.byTooltip('New conversation'), findsNothing);
      await capture(tester, 'TWON-clean-chat');
      await tester.tap(find.byTooltip('Search chats'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'mountain');
      await tester.pumpAndSettle();
      expect(find.text('Mountain wolves'), findsOneWidget);
      expect(find.text('London pack'), findsNothing);
      expect(
        h.calls.any(
          (r) =>
              r.path == 'conversations' &&
              r.queryParameters['cursor'] == 'next',
        ),
        isTrue,
      );
      await tester.tap(find.text('New conversation'));
      await tester.pumpAndSettle();
      expect(find.text('Search members'), findsOneWidget);
      await h.close(tester);
    },
  );

  testWidgets(
    'profile has wolf identity, real stats and a working posts route on a narrow phone',
    (tester) async {
      final h = Harness(
        fixtures: {
          'users/me': {
            ...viewer,
            'bio': 'Finding my pack, one trail at a time.',
            'stats': {
              'followerCount': 128,
              'followingCount': 84,
              'packPoints': 320,
            },
            'isIdentityVerified': true,
          },
        },
      );
      await h.mount(tester);
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kristen Lama'));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileIdentity), findsOneWidget);
      expect(find.byType(WolfLandscape), findsOneWidget);
      expect(find.text('128'), findsOneWidget);
      await capture(tester, 'TWON-clean-profile');
      tester.view.physicalSize = const Size(320, 844);
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('My posts'),
        250,
        scrollable: find
            .descendant(
              of: find.byType(ProfilePage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(find.text('My posts'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('My posts'));
      await tester.pumpAndSettle();
      expect(h.calls.any((r) => r.path == 'posts/author/viewer'), isTrue);
      expect(tester.takeException(), isNull);
      await h.close(tester);
    },
  );

  testWidgets(
    'swipe reply has a threshold, never dismisses a message, and supports reduced motion',
    (tester) async {
      var replies = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: Center(
                child: SwipeReply(
                  onReply: () => replies++,
                  child: const SizedBox(
                    width: 220,
                    height: 80,
                    child: Text('Message stays here'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.drag(find.text('Message stays here'), const Offset(25, 0));
      await tester.pumpAndSettle();
      expect(replies, 0);
      await tester.drag(find.text('Message stays here'), const Offset(100, 0));
      await tester.pumpAndSettle();
      expect(replies, 1);
      expect(find.text('Message stays here'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('feed refresh remains available as a pull gesture', (
    tester,
  ) async {
    final h = Harness();
    await h.mount(tester);
    final before = h.calls.where((r) => r.path == 'posts').length;
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 350));
    await tester.pumpAndSettle();
    expect(h.calls.where((r) => r.path == 'posts').length, before + 1);
    await h.close(tester);
  });
  testWidgets('member search opens the real profile route', (tester) async {
    final h = Harness(
      fixtures: {
        'users/search': [
          {'id': 'aayush', 'fullName': 'Aayush Shrestha', 'handle': 'aayush'},
        ],
        'users/aayush': {
          'id': 'aayush',
          'fullName': 'Aayush Shrestha',
          'handle': 'aayush',
        },
      },
    );
    await h.mount(tester);
    await tester.tap(find.byTooltip('Find members'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'aayush');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aayush Shrestha'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileIdentity), findsOneWidget);
    expect(h.calls.any((r) => r.path == 'users/aayush'), isTrue);
    expect(find.text('Follow'), findsOneWidget);
    await h.close(tester);
  });

  testWidgets(
    'gatherings keep search and filters usable for non-hosts at large text sizes',
    (tester) async {
      final h = Harness();
      await h.mount(tester, width: 320, scale: 1.8);
      await tester.tap(find.byKey(const ValueKey('tab-/events')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Publish gathering'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Filter gatherings'));
      await tester.pumpAndSettle();
      expect(find.text('Show gatherings'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await h.close(tester);
    },
  );
  testWidgets(
    'new post has no app bar and sends the selected visibility and centered post type',
    (tester) async {
      final h = Harness();
      await h.mount(tester);
      await tester.tap(find.text('What’s on your mind?'));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsNothing);
      expect(find.text('New post'), findsOneWidget);
      expect(find.text('Public'), findsNothing);
      expect(find.text('Add a topic'), findsNothing);
      await tester.enterText(
        find.byType(TextField).first,
        'Looking for a room in London.',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Visibility: Public'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Private'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Visibility: Private'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('choose-post-type')));
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsOneWidget);
      final dialog = find.byType(Dialog);
      expect(tester.getCenter(dialog).dx, closeTo(195, 1));
      expect(tester.getCenter(dialog).dy, closeTo(422, 1));
      for (final type in postTypes) {
        expect(find.byKey(ValueKey('post-type-$type')), findsOneWidget);
      }
      await capture(tester, 'TWON-post-type-picker');
      await tester.tap(find.byKey(const ValueKey('post-type-housing')));
      await tester.pumpAndSettle();
      expect(find.text('Housing'), findsOneWidget);
      await capture(tester, 'TWON-new-post');
      await tester.tap(find.text('Share with the pack'));
      await tester.pumpAndSettle();
      final payload = asJson(
        h.calls.firstWhere((r) => r.path == 'posts' && r.method == 'POST').data,
      );
      expect(payload['type'], 'housing');
      expect(payload['visibility'], 'private');
      expect(payload['body'], 'Looking for a room in London.');
      await h.close(tester);
    },
  );

  testWidgets(
    'post type picker fits large text, closes without changing the draft, and leaves all options reachable',
    (tester) async {
      final h = Harness();
      await h.mount(tester, width: 320, scale: 1.8);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      await tester.tap(find.text('What’s on your mind?'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Keep my draft.');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('choose-post-type')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const ValueKey('post-type-help')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Close post types'));
      await tester.pumpAndSettle();
      expect(find.text('General'), findsOneWidget);
      expect(find.text('Keep my draft.'), findsOneWidget);
      tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
      await h.close(tester);
    },
  );
  testWidgets(
    'member autocomplete inserts a real handle without losing surrounding status or hashtags',
    (tester) async {
      final h = Harness(
        fixtures: {
          'users/search': [
            {
              'id': 'maya',
              'fullName': 'Maya Gurung',
              'handle': 'maya',
              'avatar': '',
            },
          ],
        },
      );
      await h.mount(tester);
      await tester.tap(find.text('What’s on your mind?'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Hello @ma #nepal');
      final editor = tester.state<PostEditorState>(find.byType(PostEditor));
      editor.body.selection = TextSelection.collapsed(
        offset: editor.body.text.indexOf(' #nepal'),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(
        h.calls.lastWhere((r) => r.path == 'users/search').queryParameters['q'],
        'ma',
      );
      expect(find.byKey(const ValueKey('mention-maya')), findsOneWidget);
      await capture(tester, 'TWON-mention-composer');
      await tester.ensureVisible(find.byKey(const ValueKey('mention-maya')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mention-maya')));
      await tester.pumpAndSettle();
      expect(editor.body.text, 'Hello @maya #nepal');
      expect(find.byKey(const ValueKey('mention-suggestions')), findsNothing);
      await tester.tap(find.text('Share with the pack'));
      await tester.pumpAndSettle();
      final write = h.calls.firstWhere(
        (r) => r.path == 'posts' && r.method == 'POST',
      );
      expect(asJson(write.data)['body'], 'Hello @maya #nepal');
      await h.close(tester);
    },
  );

  testWidgets(
    'five composer photos stay in one scrollable row and removing one preserves the draft',
    (tester) async {
      final h = Harness();
      await h.mount(tester, width: 320, scale: 1.8);
      await tester.tap(find.text('What’s on your mind?'));
      await tester.pumpAndSettle();
      final editor = tester.state<PostEditorState>(find.byType(PostEditor));
      editor.photos.addAll(List.filled(5, ''));
      editor.body.text = 'Keep this status with my photos.';
      await tester.pumpAndSettle();
      final strip = find.byKey(const ValueKey('composer-photo-strip'));
      await tester.ensureVisible(strip);
      await tester.pumpAndSettle();
      expect(tester.getSize(strip).height, 132);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('status-composer')),
          matching: find.byType(ComposerPhotoStrip),
        ),
        findsOneWidget,
      );
      await tester.drag(strip, const Offset(-900, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('remove-composer-photo-4')));
      await tester.pumpAndSettle();
      expect(editor.photos.length, 4);
      expect(editor.body.text, 'Keep this status with my photos.');
      expect(tester.getSize(strip).height, 132);
      expect(tester.takeException(), isNull);
      await h.close(tester);
    },
  );

  testWidgets(
    'resolved post mentions open profiles and hashtags remain in the displayed status',
    (tester) async {
      final h = Harness(
        fixtures: {
          'posts': [
            {
              ...samplePost(0),
              'body': '@maya',
              'mentionDisplay': [
                {'handle': 'maya', 'fullName': 'Maya Gurung'},
              ],
            },
          ],
          'users/maya': {
            'id': 'maya',
            'handle': 'maya',
            'fullName': 'Maya Gurung',
          },
        },
      );
      await h.mount(tester);
      await tester.tap(find.text('Maya Gurung', findRichText: true));
      await tester.pumpAndSettle();
      expect(h.calls.any((r) => r.path == 'users/maya'), isTrue);
      expect(find.byType(ProfileIdentity), findsOneWidget);
      await h.close(tester);
    },
  );

  testWidgets(
    'hashtag and mention controls insert at the cursor and hashtags support Nepali text',
    (tester) async {
      final h = Harness();
      await h.mount(tester);
      await tester.tap(find.text('What’s on your mind?'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Pack');
      await tester.tap(find.byTooltip('Add hashtag'));
      await tester.pumpAndSettle();
      final editor = tester.state<PostEditorState>(find.byType(PostEditor));
      expect(editor.body.text, 'Pack #');
      await tester.enterText(find.byType(TextField).first, 'Pack #नेपाल');
      expect(socialTokens.firstMatch(editor.body.text)?.group(0), '#नेपाल');
      await tester.tap(find.byTooltip('Mention a member'));
      await tester.pumpAndSettle();
      expect(editor.body.text, 'Pack #नेपाल @');
      expect(find.text('Type a name or handle'), findsOneWidget);
      await h.close(tester);
    },
  );
}
