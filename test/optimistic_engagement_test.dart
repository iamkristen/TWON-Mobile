import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twon_mobile/core/api.dart';
import 'package:twon_mobile/core/collection_cubit.dart';
import 'package:twon_mobile/core/models.dart';
import 'package:twon_mobile/features/account/account_pages.dart';
import 'package:twon_mobile/features/feed/post_engagement_cubit.dart';

/// Tasks 11/12: optimistic likes, comment likes and follows; bounded paging.
class FakeApi implements AppRepository {
  FakeApi(this.respond);
  final Future<dynamic> Function(String path, String method) respond;
  final calls = <String>[];
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Object? body,
    Json? query,
    bool authenticated = true,
    CancelToken? cancel,
  }) {
    calls.add('$method $path');
    return respond(path, method);
  }

  @override
  Future<ApiPage> page(String path, {Json? query, CancelToken? cancel}) async {
    calls.add('PAGE $path ${query?['cursor'] ?? ''}');
    final n = calls.where((c) => c.startsWith('PAGE')).length;
    return ApiPage([
      Entity({'_id': 'p$n'}),
    ], 'cursor$n');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final source = Entity({'_id': 'post', 'likes': <String>[], 'likeCount': 5});

  test('a like shows at once and the server response reconciles it', () async {
    final response = Completer<dynamic>();
    final posts = PostEngagementCubit(FakeApi((_, _) => response.future));
    final pending = posts.toggleLike(source, 'me');
    expect(posts.resolve(source).strings('likes'), ['me']);
    expect(posts.resolve(source).number('likeCount'), 6);
    response.complete({
      '_id': 'post',
      'likes': ['me'],
      'likeCount': 9,
    });
    await pending;
    expect(posts.resolve(source).number('likeCount'), 9);
    await posts.close();
  });

  test(
    'a refused like rolls back; an uncertain one re-reads the post',
    () async {
      var attempt = 0;
      final api = FakeApi((path, method) async {
        if (method == 'GET') {
          return {
            '_id': 'post',
            'likes': ['me'],
            'likeCount': 6,
          };
        }
        attempt++;
        throw attempt == 1
            ? const AppFailure('Post not found', status: 404)
            : const AppFailure('Cannot reach TWON');
      });
      final posts = PostEngagementCubit(api);
      await expectLater(
        posts.toggleLike(source, 'me'),
        throwsA(isA<AppFailure>()),
      );
      expect(posts.resolve(source).strings('likes'), isEmpty);
      expect(posts.resolve(source).number('likeCount'), 5);
      await expectLater(
        posts.toggleLike(source, 'me'),
        throwsA(isA<AppFailure>()),
      );
      expect(api.calls.last, 'GET posts/post');
      expect(posts.resolve(source).strings('likes'), [
        'me',
      ]); // the server did apply it
      expect(posts.state.busy, isEmpty);
      await posts.close();
    },
  );

  test(
    'a comment like shows at once, rolls back when refused, and does not re-read the post',
    () async {
      final response = Completer<dynamic>();
      final api = FakeApi((path, method) {
        if (path.endsWith('/comments')) {
          return Future.value([
            {'_id': 'c1', 'text': 'hi', 'likes': <String>[], 'likeCount': 0},
          ]);
        }
        return response.future;
      });
      final posts = PostEngagementCubit(api);
      final comments = CommentsCubit(api, 'post', posts);
      await comments.load();
      final pending = comments.toggleLike(comments.state.items.single, 'me');
      expect(comments.state.items.single.number('likeCount'), 1);
      response.completeError(const AppFailure('Forbidden', status: 403));
      await expectLater(pending, throwsA(isA<AppFailure>()));
      expect(comments.state.items.single.number('likeCount'), 0);
      expect(api.calls.where((c) => c == 'GET posts/post'), isEmpty);
      await comments.close();
      await posts.close();
    },
  );

  test('scrolling loads a bounded number of pages automatically', () async {
    final cubit = CollectionCubit(FakeApi((_, _) async => null), 'posts');
    await cubit.load();
    while (cubit.canAutoLoad) {
      await cubit.load(more: true);
    }
    expect(cubit.state.pages, CollectionCubit.autoLoadPages);
    expect(cubit.state.cursor, isNotNull); // more exists: a tap loads it
    await cubit.load(more: true);
    expect(cubit.state.pages, CollectionCubit.autoLoadPages + 1);
    await cubit.load(); // a refresh starts counting again
    expect(cubit.state.pages, 1);
    await cubit.close();
  });

  testWidgets('follow flips at once and treats "already following" as done', (
    tester,
  ) async {
    final response = Completer<dynamic>();
    var changed = 0;
    final api = FakeApi((_, _) => response.future);
    await tester.pumpWidget(
      RepositoryProvider<AppRepository>.value(
        value: api,
        child: MaterialApp(
          home: Scaffold(
            body: FollowButton(
              userId: 'u2',
              following: false,
              onChanged: () => changed++,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Follow'));
    await tester.pump();
    expect(find.text('Unfollow'), findsOneWidget); // optimistic
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    response.completeError(
      const AppFailure('Already following this user', status: 409),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unfollow'), findsOneWidget);
    expect(changed, 1);
    expect(api.calls, ['POST users/u2/follow']);
  });
}
