import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'api.dart';
import 'models.dart';

class CollectionState {
  const CollectionState({
    this.items = const [],
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.cursor,
    this.loaded = false,
    this.pages = 0,
  });
  final List<Entity> items;
  final bool loading, loadingMore, loaded;
  final String? error, cursor;

  /// Pages loaded since the last full (re)load (Task 12: bounded auto-loading).
  final int pages;
}

class CollectionCubit extends Cubit<CollectionState> {
  CollectionCubit(this.repository, this.path, {this.query = const {}})
    : super(const CollectionState());

  /// Pages loaded automatically while scrolling; beyond this, more needs a tap,
  /// so an endless scroll never loads unlimited pages and images (Task 12).
  static const autoLoadPages = 8;

  bool get canAutoLoad =>
      state.cursor != null &&
      state.error == null &&
      !state.loading &&
      !state.loadingMore &&
      state.pages < autoLoadPages;
  final AppRepository repository;
  final String path;
  Json query;
  CancelToken? _cancel;
  int _request = 0;
  /// [cached]: an initial load may reuse a fresh public response (Task 13);
  /// refreshes and later pages always go to the server.
  Future<void> load({Json? filters, bool more = false, bool cached = false}) async {
    if (more && (state.loadingMore || state.loading || state.cursor == null)) {
      return;
    }
    final request = ++_request;
    _cancel?.cancel();
    _cancel = CancelToken();
    if (filters != null) query = filters;
    final old = state;
    emit(
      CollectionState(
        items: filters == null ? old.items : const [],
        loading: !more,
        loadingMore: more,
        cursor: old.cursor,
        loaded: old.loaded,
        pages: old.pages,
      ),
    );
    try {
      final pageQuery = {...query, 'limit': 20, if (more) 'cursor': old.cursor};
      final repo = repository;
      final page = cached && !more && repo is DioRepository
          ? await repo.page(path, query: pageQuery, cancel: _cancel, cached: true)
          : await repository.page(path, query: pageQuery, cancel: _cancel);
      if (isClosed || request != _request) return;
      final rows = more ? [...old.items, ...page.items] : page.items;
      final unique = <String, Entity>{for (final row in rows) row.id: row};
      emit(
        CollectionState(
          items: unique.values.toList(),
          cursor: page.cursor,
          loaded: true,
          pages: more ? old.pages + 1 : 1,
        ),
      );
    } catch (error) {
      if (isClosed || request != _request) return;
      emit(
        CollectionState(
          items: filters == null ? old.items : const [],
          cursor: more ? old.cursor : null,
          error: error.toString(),
          loaded: old.loaded,
          pages: old.pages,
        ),
      );
    }
  }

  void replace(Entity item) {
    emit(
      CollectionState(
        items: state.items
            .map((row) => row.id == item.id ? item : row)
            .toList(),
        cursor: state.cursor,
        loaded: state.loaded,
        error: state.error,
        loading: state.loading,
        loadingMore: state.loadingMore,
        pages: state.pages,
      ),
    );
  }

  @override
  Future<void> close() {
    _cancel?.cancel();
    return super.close();
  }
}

class MutationState {
  const MutationState({
    this.busy = false,
    this.error,
    this.result,
    this.success = false,
  });
  final bool busy, success;
  final String? error;
  final dynamic result;
}

class MutationCubit extends Cubit<MutationState> {
  MutationCubit() : super(const MutationState());
  Future<dynamic> run(Future<dynamic> Function() action) async {
    if (state.busy) return null;
    emit(const MutationState(busy: true));
    try {
      final value = await action();
      if (!isClosed) emit(MutationState(success: true, result: value));
      return value;
    } catch (error) {
      if (!isClosed) emit(MutationState(error: error.toString()));
      return null;
    }
  }
}

class DetailState {
  const DetailState({this.item, this.loading = false, this.error});
  final Entity? item;
  final bool loading;
  final String? error;
}

class DetailCubit extends Cubit<DetailState> {
  DetailCubit(this.repository, this.path) : super(const DetailState());
  final AppRepository repository;
  final String path;
  CancelToken? _cancel;
  /// [cached]: the initial load may reuse a fresh public response (Task 13).
  Future<void> load({bool cached = false}) async {
    _cancel?.cancel();
    final token = _cancel = CancelToken();
    emit(DetailState(item: state.item, loading: true));
    try {
      final repo = repository;
      final result = asJson(
        cached && repo is DioRepository
            ? await repo.request(path, cancel: token, cached: true)
            : await repository.request(path, cancel: token),
      );
      if (!isClosed && !token.isCancelled) {
        emit(DetailState(item: Entity(result)));
      }
    } catch (error) {
      if (!isClosed && !token.isCancelled) {
        emit(DetailState(item: state.item, error: error.toString()));
      }
    }
  }

  @override
  Future<void> close() {
    _cancel?.cancel();
    return super.close();
  }
}
