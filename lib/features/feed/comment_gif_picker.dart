import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/api.dart';
import '../../core/models.dart';
import '../../shared/widgets.dart';

class _GifState {
  const _GifState({this.items = const [], this.loading = false, this.error});
  final List<Json> items;
  final bool loading;
  final String? error;
}

class _GifCubit extends Cubit<_GifState> {
  _GifCubit(this.api) : super(const _GifState());
  final AppRepository api;
  Timer? _timer;
  int _request = 0;
  String _query = '';

  void search(String value, {bool immediate = false}) {
    _query = value.trim();
    _timer?.cancel();
    final request = ++_request;
    emit(const _GifState(loading: true));
    if (immediate) {
      _load(_query, request);
    } else {
      _timer = Timer(const Duration(milliseconds: 300), () => _load(_query, request));
    }
  }

  void retry() => search(_query, immediate: true);

  Future<void> _load(String query, int request) async {
    try {
      final result = await api.request(query.isEmpty ? 'media/gif/trending' : 'media/gif/search',
        query: query.isEmpty ? null : {'q': query});
      if (!isClosed && request == _request) {
        emit(_GifState(items: asRows(result).where((gif) =>
          Uri.tryParse(gif['url']?.toString() ?? '')?.scheme == 'https').toList()));
      }
    } catch (_) {
      if (!isClosed && request == _request) {
        emit(const _GifState(error: 'GIFs are unavailable right now. Please try again.'));
      }
    }
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    _request++;
    return super.close();
  }
}

class CommentGifPicker extends StatefulWidget {
  const CommentGifPicker({super.key});
  @override
  State<CommentGifPicker> createState() => _CommentGifPickerState();
}

class _CommentGifPickerState extends State<CommentGifPicker> {
  late final _GifCubit cubit;
  @override
  void initState() {
    super.initState();
    cubit = _GifCubit(context.read<AppRepository>())..search('', immediate: true);
  }
  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => Column(children: [
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
      child: Row(children: [
        const Expanded(child: Text('Choose a GIF', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
        IconButton(tooltip: 'Close GIF picker', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
      ]),
    ),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        onChanged: cubit.search,
        textInputAction: TextInputAction.search,
        onSubmitted: (query) { cubit.search(query, immediate: true); FocusScope.of(context).unfocus(); },
        onTapOutside: (_) => FocusScope.of(context).unfocus(),
        decoration: const InputDecoration(hintText: 'Search GIFs', prefixIcon: Icon(Icons.search)),
      ),
    ),
    Expanded(child: BlocBuilder<_GifCubit, _GifState>(
      bloc: cubit,
      builder: (context, state) {
        if (state.loading) return const Center(child: CircularProgressIndicator());
        if (state.error != null) return Center(child: ErrorPanel(state.error!, retry: cubit.retry));
        if (state.items.isEmpty) return const Center(child: Text('No GIFs found. Try another search.'));
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 1.35),
          itemCount: state.items.length,
          itemBuilder: (context, index) {
            final gif = state.items[index];
            final url = gif['url'].toString();
            return Semantics(
              button: true,
              label: gif['title']?.toString() ?? 'Select GIF',
              child: InkWell(
                onTap: () => Navigator.pop(context, url),
                borderRadius: BorderRadius.circular(12),
                child: ClipRRect(borderRadius: BorderRadius.circular(12),
                  child: BrandImage(gif['previewUrl']?.toString() ?? url, fit: BoxFit.cover)),
              ),
            );
          },
        );
      },
    )),
  ]);
}
