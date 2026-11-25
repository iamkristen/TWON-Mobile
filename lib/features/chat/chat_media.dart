import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/api.dart';
import '../../core/env_config.dart';
import '../../core/models.dart';
import '../../shared/widgets.dart';
import '../auth/auth_cubit.dart';

/// CHAT-3: chat files are private. Messages carry references (paths without
/// any credential); the server exchanges them for short-lived links and
/// re-checks access every time one is opened.
const chatUploadEndpoint = 'media/upload?purpose=chat';
const _prefix = '/api/v1/chat-media/';
bool isPrivateChatMedia(String url) => url.startsWith(_prefix);

/// Links kept in memory only, for one account at a time. Requests made
/// together share one call.
class ChatMediaLinks {
  ChatMediaLinks(this.api);
  final AppRepository api;
  static final _instances = Expando<ChatMediaLinks>();
  static ChatMediaLinks of(BuildContext context) {
    final api = repository(context);
    return (_instances[api] ??= ChatMediaLinks(api))
      .._account(context.read<AuthCubit>().userId);
  }

  static const _batch = 60;
  static const _margin = Duration(minutes: 1);
  String? _user;
  final _cache = <String, (String, DateTime)>{};
  var _waiting = <String, List<Completer<String?>>>{};

  void _account(String? userId) {
    if (_user == userId) return;
    _user = userId;
    _cache.clear(); // another account: nothing carries over
  }

  /// A link, or null when the file is not available to this account.
  Future<String?> link(String ref, {bool refresh = false}) {
    if (!isPrivateChatMedia(ref)) return Future.value(ref);
    if (refresh) _cache.remove(ref);
    final cached = _cache[ref];
    if (cached != null && cached.$2.isAfter(DateTime.now())) {
      return Future.value(cached.$1);
    }
    final done = Completer<String?>();
    if (_waiting.isEmpty) scheduleMicrotask(_flush);
    (_waiting[ref] ??= []).add(done);
    return done.future;
  }

  Future<void> _flush() async {
    final batch = _waiting.entries.take(_batch).toList();
    _waiting = Map.fromEntries(_waiting.entries.skip(_batch));
    if (_waiting.isNotEmpty) scheduleMicrotask(_flush);
    final user = _user;
    try {
      final data = asJson(
        await api.request(
          'chat-media/links',
          method: 'POST',
          body: {'refs': [for (final e in batch) e.key]},
        ),
      );
      final links = {
        for (final row in (data['links'] as List? ?? const []).map(asJson))
          '${row['ref']}': row,
      };
      for (final entry in batch) {
        final path = links[entry.key]?['url'];
        final until = DateTime.tryParse('${links[entry.key]?['expiresAt']}');
        final url = path is String && path.startsWith(_prefix)
            ? '${Uri.parse(AppConfig.apiUrl).origin}$path'
            : null;
        if (url != null && until != null && user == _user) {
          _cache[entry.key] = (url, until.subtract(_margin));
        }
        for (final c in entry.value) {
          c.complete(url);
        }
      }
    } catch (error) {
      for (final entry in batch) {
        for (final c in entry.value) {
          c.completeError(error);
        }
      }
    }
  }
}

/// A private chat picture: held in memory only (never the disk image cache).
/// An expired link is renewed once; after that the photo is unavailable.
class PrivateChatImage extends StatefulWidget {
  const PrivateChatImage(this.source, {super.key, this.height = 170});
  final String source;
  final double height;
  @override
  State<PrivateChatImage> createState() => _PrivateChatImageState();
}

class _PrivateChatImageState extends State<PrivateChatImage> {
  String? url;
  bool loading = true, renewed = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(PrivateChatImage old) {
    super.didUpdateWidget(old);
    if (old.source == widget.source) return;
    url = null;
    loading = true;
    renewed = false;
    load();
  }

  Future<void> load({bool refresh = false}) async {
    final source = widget.source;
    String? next;
    try {
      next = await ChatMediaLinks.of(context).link(source, refresh: refresh);
    } catch (_) {
      next = null;
    }
    if (!mounted || source != widget.source) return;
    setState(() {
      url = next;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget box(Widget child) =>
        SizedBox(height: widget.height, child: Center(child: child));
    if (loading) return box(const CircularProgressIndicator());
    final unavailable = box(
      const Icon(
        Icons.broken_image_outlined,
        semanticLabel: 'Photo unavailable',
      ),
    );
    if (url == null) return unavailable;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.network(
        url!,
        key: ValueKey(url),
        height: widget.height,
        fit: BoxFit.cover,
        semanticLabel: 'Photo',
        errorBuilder: (_, _, _) {
          if (!renewed) {
            renewed = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) load(refresh: true);
            });
          }
          return unavailable;
        },
      ),
    );
  }
}
