import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:twon_mobile/core/api.dart';
import 'package:twon_mobile/core/models.dart';
import 'package:twon_mobile/features/chat/chat_media.dart';
import 'package:twon_mobile/features/chat/group_membership.dart';
import 'package:twon_mobile/shared/widgets.dart';
import 'direct_upload_test.dart' show Rig, reply, result, session;
import 'social_experience_test.dart' show Harness;

/// CHAT-3 on Mobile: private chat files (the server decides every access).
const owner = 'aaaaaaaaaaaaaaaaaaaaaaaa';
String ref(String category, String ext, [int n = 0]) =>
    '/api/v1/chat-media/$category/$owner/123e4567-e89b-42d3-a456-42661417400$n.$ext';

class LinkApi implements AppRepository {
  LinkApi({this.allowed, this.ttl = const Duration(minutes: 10)});
  final bool Function(String)? allowed;
  final Duration ttl;
  final calls = <List<String>>[];
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Object? body,
    Json? query,
    bool authenticated = true,
    dynamic cancel,
  }) async {
    expect((method, path), ('POST', 'chat-media/links'));
    final refs = ((body as Map)['refs'] as List).cast<String>();
    calls.add(refs);
    return {
      'links': [
        for (final r in refs)
          {
            'ref': r,
            'url': allowed?.call(r) == false
                ? null
                : '/api/v1/chat-media/open/T${calls.length}',
            'expiresAt': DateTime.now().add(ttl).toUtc().toIso8601String(),
          },
      ],
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.llfbandit.record/messages');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => messenger.setMockMethodCallHandler(channel, (_) async => null));
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('links', () {
    test('are batched and reused; public files need none', () async {
      final api = LinkApi();
      final links = ChatMediaLinks(api);
      final got = await Future.wait([
        links.link(ref('images', 'webp')),
        links.link(ref('images', 'webp', 1)),
        links.link(ref('images', 'webp')),
      ]);
      expect(api.calls, hasLength(1));
      expect(api.calls.single, hasLength(2));
      expect(got.first, startsWith('http'));
      expect(got.first, endsWith('/api/v1/chat-media/open/T1'));
      await links.link(ref('images', 'webp'));
      expect(api.calls, hasLength(1));
      await links.link(ref('images', 'webp'), refresh: true);
      expect(api.calls, hasLength(2));
      expect(
        await links.link('https://media.giphy.com/a.gif'),
        'https://media.giphy.com/a.gif',
      );
      expect(api.calls, hasLength(2));
    });
    test('near expiry are not reused; no access gives none', () async {
      final api = LinkApi(ttl: const Duration(seconds: 30));
      final links = ChatMediaLinks(api);
      await links.link(ref('images', 'webp'));
      await links.link(ref('images', 'webp'));
      expect(api.calls, hasLength(2));
      final denied = ChatMediaLinks(LinkApi(allowed: (_) => false));
      expect(await denied.link(ref('files', 'pdf')), isNull);
    });
  });

  test('kinds come from references too', () {
    expect(chatAttachmentKind(ref('images', 'webp')), 'image');
    expect(chatAttachmentKind(ref('audio', 'm4a')), 'audio');
    expect(chatAttachmentKind(ref('files', 'pdf')), 'file');
    expect(isPrivateChatMedia('https://x${ref('images', 'webp')}'), isFalse);
  });

  test('chat uploads carry the purpose in both flows', () async {
    final dir = Directory.systemTemp.createTempSync('twon-chat3-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final photo = '${dir.path}/a.jpg';
    File(photo).writeAsBytesSync(List.filled(10, 1));
    final direct = Rig([
      reply(201, session),
      reply(200, {'status': 'completed', 'result': result}),
    ]);
    await direct.api.upload(photo, endpoint: chatUploadEndpoint);
    expect((direct.apiCalls.first.data as Map)['purpose'], 'chat');
    final legacy = Rig([reply(404, null), reply(201, result)]);
    await legacy.api.upload(photo, endpoint: chatUploadEndpoint);
    expect(legacy.apiCalls.last.path, 'media/upload?purpose=chat');
    final other = Rig([
      reply(201, session),
      reply(200, {'status': 'completed', 'result': result}),
    ]);
    await other.api.upload(photo);
    expect((other.apiCalls.first.data as Map).containsKey('purpose'), isFalse);
  });

  testWidgets('a private photo is never loaded from its reference or cached on disk', (
    tester,
  ) async {
    final h = Harness(
      fixtures: {
        'conversations/c1': {'_id': 'c1', 'type': 'dm', 'participants': []},
        'conversations/c1/messages': [
          {
            '_id': 'm1',
            'senderId': {'_id': 'maya', 'fullName': 'Maya'},
            'body': '',
            'createdAt': '2026-11-01T00:00:00Z',
            'attachments': [
              {'url': ref('images', 'webp'), 'kind': 'image'},
              {'url': ref('files', 'pdf', 1), 'kind': 'file'},
            ],
          },
        ],
        'chat-media/links': {
          'links': [
            {
              'ref': ref('images', 'webp'),
              'url': '/api/v1/chat-media/open/T1',
              'expiresAt': '2099-01-01T00:00:00Z',
            },
          ],
        },
      },
    );
    await h.mount(tester);
    GoRouter.of(
      tester.element(find.text('What’s on your mind?')),
    ).go('/messages/c1');
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(PrivateChatImage), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(PrivateChatImage),
        matching: find.byType(BrandImage),
      ),
      findsNothing,
    );
    final asked = h.calls.where((r) => r.path == 'chat-media/links').toList();
    expect(asked, isNotEmpty);
    expect((asked.first.data as Map)['refs'], [ref('images', 'webp')]);
    // A document asks only when opened, and a refusal is told.
    await tester.tap(find.text('Open attachment'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('This file is unavailable.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
  });
}
