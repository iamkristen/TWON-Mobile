import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twon_mobile/core/api.dart';
import 'package:twon_mobile/core/models.dart';
import 'package:twon_mobile/features/feed/post_engagement_cubit.dart';

class EngagementApi implements AppRepository {
  EngagementApi(this.respond);
  final Future<dynamic> Function(String, String, Object?) respond;
  @override
  Future<dynamic> request(String path, {String method = 'GET', Object? body,
    Json? query, bool authenticated = true, CancelToken? cancel}) => respond(path, method, body);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('initial comments load completes and updates the shared count', () async {
    final api = EngagementApi((path, method, body) async => [{'_id': 'comment', 'text': 'Hello'}]);
    final posts = PostEngagementCubit(api);
    final comments = CommentsCubit(api, 'post', posts);
    await comments.load();
    expect(comments.state.items.single.text('text'), 'Hello');
    expect(comments.state.loading, isFalse);
    expect(posts.resolve(Entity({'_id': 'post'})).number('commentCount'), 1);
    await comments.close();
    await posts.close();
  });

  test('duplicate taps make one request and preserve populated author data', () async {
    final response = Completer<dynamic>();
    var calls = 0;
    final api = EngagementApi((path, method, body) { calls++; return response.future; });
    final posts = PostEngagementCubit(api);
    final source = Entity({'_id': 'post', 'authorId': {'_id': 'author', 'fullName': 'Alex'}, 'likes': []});
    final first = posts.toggleLike(source, 'viewer');
    await posts.toggleLike(source, 'viewer');
    expect(calls, 1);
    response.complete({'_id': 'post', 'authorId': 'author', 'likes': ['viewer'], 'likeCount': 1});
    await first;
    expect(posts.resolve(source).object('authorId')['fullName'], 'Alex');
    expect(posts.resolve(source).number('likeCount'), 1);
    expect(posts.state.busy, isEmpty);
    await posts.close();
  });

  test('an old account response cannot repopulate the engagement cache', () async {
    final response = Completer<dynamic>();
    final posts = PostEngagementCubit(EngagementApi((path, method, body) => response.future));
    final pending = posts.toggleLike(Entity({'_id': 'post', 'likes': []}), 'old-user');
    posts.reset();
    response.complete({'_id': 'post', 'likes': ['old-user'], 'likeCount': 1});
    await pending;
    expect(posts.state.posts, isEmpty);
    expect(posts.state.busy, isEmpty);
    await posts.close();
  });

  test('a stale list response cannot overwrite a confirmed comment mutation', () async {
    final oldList = Completer<dynamic>();
    final api = EngagementApi((path, method, body) async {
      if (method == 'DELETE') return <Json>[];
      if (path.endsWith('/comments')) return oldList.future;
      return {'_id': 'post', 'commentCount': 0};
    });
    final posts = PostEngagementCubit(api);
    final comments = CommentsCubit(api, 'post', posts);
    final loading = comments.load();
    await comments.remove('comment');
    oldList.complete([{'_id': 'comment', 'text': 'Deleted'}]);
    await loading;
    expect(comments.state.items, isEmpty);
    expect(comments.state.loading, isFalse);
    await comments.close();
    await posts.close();
  });

  test('failed sends release busy state and expose the failure for retry', () async {
    final posts = PostEngagementCubit(EngagementApi((path, method, body) async => throw const AppFailure('Offline')));
    final comments = CommentsCubit(posts.api, 'post', posts);
    await expectLater(comments.send({'text': 'Keep draft'}), throwsA(isA<AppFailure>()));
    expect(comments.state.busy, isFalse);
    expect(comments.state.error, 'Offline');
    await comments.close();
    await posts.close();
  });
}
