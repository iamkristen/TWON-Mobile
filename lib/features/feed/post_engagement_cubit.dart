import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/api.dart';
import '../../core/models.dart';

class PostEngagementState {
  const PostEngagementState({this.posts = const {}, this.busy = const {}});
  final Map<String, Entity> posts;
  final Set<String> busy;
}

/// Shared by feed, profile and detail cards; cleared when the signed-in user changes.
class PostEngagementCubit extends Cubit<PostEngagementState> {
  PostEngagementCubit(this.api) : super(const PostEngagementState());
  final AppRepository api;
  int _session = 0;
  int get session => _session;
  void reset() { _session++; emit(const PostEngagementState()); }

  Entity resolve(Entity source) {
    final saved = state.posts[source.id];
    if (saved == null) return source;
    final incomingTime = DateTime.tryParse(source.text('updatedAt'));
    final savedTime = DateTime.tryParse(saved.text('updatedAt'));
    if (incomingTime != null && savedTime != null && incomingTime.isAfter(savedTime)) return source;
    return Entity({...source.data, ...saved.data});
  }

  void accept(Entity post) {
    if (isClosed || post.id.isEmpty) return;
    final previous = state.posts[post.id];
    final oldTime = previous == null ? null : DateTime.tryParse(previous.text('updatedAt'));
    final newTime = DateTime.tryParse(post.text('updatedAt'));
    if (oldTime != null && newTime != null && newTime.isBefore(oldTime)) return;
    // Only engagement fields are cached; populated author/profile data stays intact.
    final patch = Entity({
      ...?previous?.data,
      '_id': post.id,
      for (final key in ['likes', 'likeCount', 'commentCount', 'shareCount', 'likePreview', 'updatedAt'])
        if (post.data.containsKey(key)) key: post.data[key],
    });
    emit(PostEngagementState(posts: {...state.posts, post.id: patch}, busy: state.busy));
  }

  void acceptCommentCount(String id, int count) {
    accept(Entity({'_id': id, 'commentCount': count}));
  }

  Future<void> recordShare(String id) async {
    final session = _session;
    final result = await api.request('posts/$id/share-event', method: 'POST');
    if (!isClosed && session == _session) accept(Entity(asJson(result)));
  }

  Future<void> refresh(String id) async {
    final session = _session;
    final post = Entity(asJson(await api.request('posts/$id')));
    if (!isClosed && session == _session) accept(post);
  }

  Future<void> toggleLike(Entity source, String userId, {bool onlyLike = false}) async {
    final post = resolve(source);
    if (state.busy.contains(post.id) || userId.isEmpty) return;
    final liked = post.strings('likes').contains(userId);
    if (onlyLike && liked) return;
    final session = _session;
    emit(PostEngagementState(posts: state.posts, busy: {...state.busy, post.id}));
    try {
      final result = Entity(asJson(await api.request('posts/${post.id}/like', method: liked ? 'DELETE' : 'POST')));
      if (!isClosed && session == _session) accept(result);
    } finally {
      if (!isClosed && session == _session) {
        emit(PostEngagementState(posts: state.posts, busy: {...state.busy}..remove(post.id)));
      }
    }
  }
}

class CommentsState {
  const CommentsState({this.items = const [], this.loading = false, this.busy = false, this.error});
  final List<Entity> items;
  final bool loading, busy;
  final String? error;
}

/// The API returns a complete comment snapshot. Serialize writes so an older
/// like/edit response cannot overwrite a newer reply or deletion.
class CommentsCubit extends Cubit<CommentsState> {
  CommentsCubit(this.api, this.postId, this.posts) : _session = posts.session, super(const CommentsState());
  final AppRepository api;
  final String postId;
  final PostEngagementCubit posts;
  final int _session;
  bool get active => !isClosed && posts.session == _session;
  int _generation = 0;

  Future<void> load() async {
    if (!active || state.busy || state.loading) return;
    final generation = ++_generation;
    emit(CommentsState(items: state.items, loading: true));
    try {
      final result = await api.request('posts/$postId/comments');
      if (active && generation == _generation) {
        emit(CommentsState(items: asRows(result).map(Entity.new).toList()));
        posts.acceptCommentCount(postId, state.items.length);
      }
    } catch (error) {
      if (active && generation == _generation) emit(CommentsState(items: state.items, error: error.toString()));
    }
  }

  Future<void> write(String path, {required String method, Json? body, bool creates = false}) async {
    if (!active) throw const AppFailure('Please reopen comments.');
    if (state.busy) throw const AppFailure('Please wait for the current comment action.');
    ++_generation;
    emit(CommentsState(items: state.items, busy: true));
    try {
      final result = await api.request(path, method: method, body: body);
      if (posts.session != _session) return;
      // A dismissed sheet must still update the cards behind it.
      if (creates) {
        posts.accept(Entity(asJson(result)));
      } else {
        posts.acceptCommentCount(postId, asRows(result).length);
      }
      if (isClosed) return;
      if (creates) {
        // Submission succeeded even if refreshing the list fails. Never resend it.
        emit(CommentsState(items: state.items));
        await load();
      } else {
        emit(CommentsState(items: asRows(result).map(Entity.new).toList()));
        try { await posts.refresh(postId); } catch (_) { /* Keep the confirmed comment snapshot. */ }
      }
    } catch (error) {
      if (active) emit(CommentsState(items: state.items, error: error.toString()));
      rethrow;
    }
  }

  Future<void> send(Json body) => write('posts/$postId/comments', method: 'POST', body: body, creates: true);
  Future<void> edit(String id, Json body) => write('posts/$postId/comments/$id', method: 'PATCH', body: body);
  Future<void> remove(String id) => write('posts/$postId/comments/$id', method: 'DELETE');
  Future<void> toggleLike(Entity comment, String userId) async {
    if (state.busy || userId.isEmpty) return;
    final latest = state.items.firstWhere((item) => item.id == comment.id, orElse: () => comment);
    await write('posts/$postId/comments/${comment.id}/like', method: latest.strings('likes').contains(userId) ? 'DELETE' : 'POST');
  }
}
