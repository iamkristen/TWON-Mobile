import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../../core/models.dart';
import '../../core/env_config.dart';
import '../../core/collection_cubit.dart';
import '../../shared/widgets.dart';
import '../../shared/forms.dart';
import '../auth/auth_cubit.dart';
import '../account/account_pages.dart';
import 'post_composer_support.dart';
import 'post_engagement_cubit.dart';
import 'post_type_badge.dart';
import 'comment_gif_picker.dart';
import 'feed_shimmer.dart';

const postTypes = ['general', 'housing', 'visa', 'fraud', 'scam', 'help'];

String postTypeLabel(String value) => postTypeDisplayLabel(value);
IconData postTypeIcon(String value) => switch (value) {
  'housing' => Icons.home_outlined,
  'visa' => Icons.badge_outlined,
  'fraud' => Icons.gpp_maybe_outlined,
  'scam' => Icons.report_outlined,
  'help' => Icons.volunteer_activism_outlined,
  _ => Icons.chat_bubble_outline_rounded,
};

class FeedPage extends StatelessWidget {
  const FeedPage({super.key, this.clanId});
  final String? clanId;
  @override
  Widget build(BuildContext c) => BlocProvider(
    create: (d) => CollectionCubit(
      repository(d),
      'posts',
      query: {if (clanId != null) 'clanId': clanId},
    )..load(),
    child: FeedTimeline(clanId: clanId),
  );
}

class FeedTimeline extends StatefulWidget {
  const FeedTimeline({super.key, this.clanId});
  final String? clanId;
  @override
  State<FeedTimeline> createState() => _FeedTimelineState();
}

class _FeedTimelineState extends State<FeedTimeline> {
  final scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    scroll.addListener(_nextPage);
  }

  void _nextPage() {
    if (scroll.hasClients && scroll.position.extentAfter < 500) {
      final cubit = context.read<CollectionCubit>();
      if (cubit.state.error == null) cubit.load(more: true);
    }
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  Future<void> compose({bool photos = false}) async {
    final uri = Uri(
      path: '/posts/new',
      queryParameters: {
        if (widget.clanId != null) 'clan': widget.clanId!,
        if (photos) 'photos': 'true',
      },
    );
    final published = await context.push<bool>(uri.toString());
    if (mounted && published == true) {
      await context.read<CollectionCubit>().load();
    }
  }

  @override
  Widget build(BuildContext c) => BlocConsumer<CollectionCubit, CollectionState>(
    listener: (_, state) {
      if (!state.loading && !state.loadingMore && state.error == null && state.cursor != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _nextPage(); });
      }
    },
    builder: (d, s) {
      final cubit = d.read<CollectionCubit>();
      return RefreshIndicator(
        onRefresh: () => cubit.load(),
        child: CustomScrollView(
          key: PageStorageKey('feed:${widget.clanId ?? 'home'}'),
          controller: scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FeedComposer(
                      onCompose: () => compose(),
                      onPhotos: () => compose(photos: true),
                    ),
                    const SizedBox(height: 12),
                    if (s.loading && s.items.isNotEmpty)
                      const LinearProgressIndicator(),
                  ],
                ),
              ),
            ),
            if (s.loading && s.items.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList.list(
                  children: const [FeedSkeleton(), FeedSkeleton()],
                ),
              )
            else if (s.items.isEmpty && s.error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: ErrorPanel(s.error!, retry: () => cubit.load()),
              )
            else if (s.items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: BrandEmptyState(
                  asset: 'empty-feed',
                  title: 'Every pack starts with a howl.',
                  message: 'Share a story or ask your first question.',
                  action: TextButton(
                    onPressed: () => compose(),
                    child: const Text('What’s on your mind?'),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList.builder(
                  itemCount: s.items.length,
                  itemBuilder: (d, index) => Column(
                    children: [
                      PostCard(
                        key: ValueKey(s.items[index].id),
                        post: s.items[index],
                        refresh: () => cubit.load(),
                        onChanged: cubit.replace,
                      ),
                      if (widget.clanId == null && index == 5)
                        const SponsoredSlot(),
                    ],
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverToBoxAdapter(
                child: Column(
                  children: [
                    if (s.error != null && s.items.isNotEmpty)
                      ErrorPanel(
                        s.error!,
                        retry: () => cubit.load(more: s.cursor != null),
                      ),
                    if (s.loadingMore)
                      const FeedSkeleton(),
                    if (s.cursor != null && !s.loadingMore && s.error == null)
                      TextButton(
                        onPressed: () => cubit.load(more: true),
                        child: const Text('More from your pack'),
                      ),
                    if (s.loaded && s.items.isNotEmpty && s.cursor == null)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              size: 18,
                              color: Theme.of(c).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            const Text('You’re all caught up.'),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class FeedComposer extends StatelessWidget {
  const FeedComposer({
    super.key,
    required this.onCompose,
    required this.onPhotos,
  });
  final Future<void> Function() onCompose, onPhotos;
  @override
  Widget build(BuildContext c) {
    final scheme = Theme.of(c).colorScheme;
    final user = c.watch<AuthCubit>().state.user ?? {};
    final placeholder = Theme.of(c).brightness == Brightness.dark
        ? const Color(0xFFA9B9D0)
        : const Color(0xFF52647E);
    final outline = Theme.of(c).brightness == Brightness.dark
        ? const Color(0xFF465572)
        : const Color(0xFFA0AEC3);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: outline.withValues(alpha: .75)),
      ),
      child: Row(
        children: [
          Semantics(
            label: 'Your profile',
            button: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () => c.push('/profile'),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: .65),
                    width: 1.5,
                  ),
                ),
                child: MemberAvatar(user, radius: 20),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Material(
              color: scheme.surfaceContainer.withValues(alpha: .55),
              borderRadius: BorderRadius.circular(28),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(28),
                      onTap: onCompose,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 18, 4, 18),
                        child: Text(
                          'What’s on your mind?',
                          style: TextStyle(
                            color: placeholder,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Add photos',
                    onPressed: onPhotos,
                    icon: Icon(
                      Icons.photo_library_outlined,
                      color: placeholder,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FeedSkeleton extends StatelessWidget {
  const FeedSkeleton({super.key});
  @override
  Widget build(BuildContext c) {
    final color = Theme.of(c).colorScheme.surfaceContainer;
    return Semantics(
      label: 'Loading posts',
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Theme.of(c).colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
        ),
        child: FeedShimmer(
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(backgroundColor: color),
                const SizedBox(width: 12),
                Container(width: 140, height: 14, color: color),
              ],
            ),
            const SizedBox(height: 24),
            Container(height: 12, color: color),
            const SizedBox(height: 10),
            Container(width: 180, height: 12, color: color),
            const SizedBox(height: 24),
            Container(
              height: 180,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}

class AnonymousWolfAvatar extends StatelessWidget {
  const AnonymousWolfAvatar({super.key, this.radius = 22});
  final double radius;
  @override
  Widget build(BuildContext context) => ClipOval(
    child: Image.asset(
      'assets/branding/anonymous-wolf.png',
      width: radius * 2,
      height: radius * 2,
      fit: BoxFit.cover,
      excludeFromSemantics: true,
    ),
  );
}

class PostCard extends StatefulWidget {
  const PostCard({
    super.key,
    required this.post,
    required this.refresh,
    this.onChanged,
  });
  final Entity post;
  final VoidCallback refresh;
  final void Function(Entity)? onChanged;
  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool expanded = false;
  Entity get post => context.read<PostEngagementCubit>().resolve(widget.post);
  bool get liking => context.read<PostEngagementCubit>().state.busy.contains(post.id);
  bool get liked => post.strings('likes').contains(context.read<AuthCubit>().userId);

  Future<void> like({bool onlyLike = false}) async {
    try {
      await context.read<PostEngagementCubit>().toggleLike(
        post, context.read<AuthCubit>().userId, onlyLike: onlyLike,
      );
      if (!mounted) return;
      widget.onChanged?.call(post);
      HapticFeedback.selectionClick();
    } catch (error) {
      if (mounted) notice(context, error.toString());
    }
  }

  Future<void> comments() async {
    final id = post.id;
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      enableDrag: true,
      isDismissible: true,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheet) => AnimatedPadding(
        duration: MediaQuery.disableAnimationsOf(sheet)
            ? Duration.zero : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheet).bottom),
        child: DraggableScrollableSheet(
          initialChildSize: .78,
          minChildSize: .3,
          maxChildSize: .95,
          expand: false,
          snap: true,
          snapSizes: const [.78],
          shouldCloseOnMinExtent: true,
          builder: (_, scrollController) => CommentsPane(id, scrollController: scrollController),
        ),
      ),
    );
  }

  Future<void> share() async {
    await showModalBottomSheet(
      context: context,
      useSafeArea: true,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.ios_share_rounded),
              title: const Text('Send to someone'),
              subtitle: const Text('Share a link to this post'),
              onTap: () async {
                Navigator.pop(sheet);
                final engagement = context.read<PostEngagementCubit>();
                final id = post.id;
                final result = await SharePlus.instance.share(
                  ShareParams(
                    text: '${AppConfig.websiteUrl}/feed?post=${post.id}',
                  ),
                );
                if (result.status == ShareResultStatus.success) {
                  try { await engagement.recordShare(id); } catch (_) {
                    if (mounted) notice(context, 'Shared, but the share count could not update.');
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.repeat_rounded),
              title: const Text('Share with your pack'),
              subtitle: const Text('Add a thought and repost'),
              onTap: () {
                Navigator.pop(sheet);
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (d) => SizedBox(
                    height: MediaQuery.sizeOf(d).height * .75,
                    child: FeatureForm(
                      title: 'Share with your pack',
                      fields: const [
                        FieldSpec(
                          'body',
                          'Add a thought',
                          kind: FieldKind.multiline,
                          required: false,
                        ),
                      ],
                      submit: (v) => repository(context).request(
                        'posts/${post.id}/share',
                        method: 'POST',
                        body: v,
                      ),
                      onSuccess: (_) {
                        context.read<PostEngagementCubit>().refresh(post.id).catchError((Object _) {});
                        Navigator.pop(d);
                        widget.refresh();
                      },
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> option(String value) async {
    if (value == 'report') {
      await showReport(context, 'post', post.id);
    } else if (value == 'edit') {
      await context.push('/posts/${post.id}/edit', extra: post.data);
      if (mounted) widget.refresh();
    } else if (value == 'delete') {
      if (!await confirm(
        context,
        'Delete post?',
        'This post and its comments will be removed.',
      )) {
        return;
      }
      if (!mounted) return;
      try {
        await repository(context).request('posts/${post.id}', method: 'DELETE');
        if (mounted) widget.refresh();
      } catch (error) {
        if (mounted) notice(context, error.toString());
      }
    }
  }

  @override
  Widget build(BuildContext c) {
    c.watch<PostEngagementCubit>();
    final scheme = Theme.of(c).colorScheme;
    final author = post.object('authorId');
    final anonymous = post.flag('isAnonymous');
    final own = entityId(post.data['authorId']) == c.read<AuthCubit>().userId;
    final body = post.text('body');
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 6, 0),
            child: Row(
              children: [
                anonymous
                    ? const AnonymousWolfAvatar(radius: 22)
                    : MemberAvatar(author, radius: 22),
                const SizedBox(width: 11),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: anonymous || author['handle'] == null
                        ? null
                        : () => c.push('/members/${author['handle']}'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          anonymous
                              ? 'Anonymous Wolf'
                              : author['fullName']?.toString() ?? 'Pack member',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                relativePostTime(post.text('createdAt')),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 5),
                              child: Text('·'),
                            ),
                            Icon(
                              post.text('visibility') == 'private'
                                  ? Icons.lock_outline_rounded
                                  : Icons.public_rounded,
                              size: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: PostTypeBadge(post.text('type', 'general')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Post options',
                  onSelected: option,
                  itemBuilder: (_) => [
                    if (own) ...[
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text('Edit post'),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete post'),
                      ),
                    ] else
                      const PopupMenuItem(
                        value: 'report',
                        child: Text('Report post'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SocialPostText(
                  text: expanded || body.length <= 280
                      ? body
                      : '${body.substring(0, 280).trimRight()}…',
                  mentions: post.rows('mentionDisplay'),
                  style: Theme.of(
                    c,
                  ).textTheme.bodyLarge?.copyWith(height: 1.5, fontSize: 15),
                ),
                if (body.length > 280)
                  TextButton(
                    onPressed: () => setState(() => expanded = !expanded),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(48, 40),
                    ),
                    child: Text(expanded ? 'Show less' : 'Read more'),
                  ),
                if (post.text('type') != 'general' &&
                    post.text('type').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '#${post.text('type')}',
                      style: TextStyle(
                        color: scheme.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (post.data['sharedPostId'] is Map)
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Shared with the pack',
                          style: Theme.of(c).textTheme.labelSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          asJson(
                                post.data['sharedPostId'],
                              )['body']?.toString() ??
                              'Shared post',
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (post.strings('media').isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: GestureDetector(
                onDoubleTap: () => like(onlyLike: true),
                child: PostMediaGallery(urls: post.strings('media')),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              children: [
                Expanded(
                  child: SocialAction(
                    label: '${post.number('likeCount')}',
                    semanticLabel: '${post.number('likeCount')} likes',
                    icon: liked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    selected: liked,
                    busy: liking,
                    onTap: like,
                  ),
                ),
                Expanded(
                  child: SocialAction(
                    label: '${post.number('commentCount')}',
                    semanticLabel: '${post.number('commentCount')} comments',
                    icon: Icons.chat_bubble_outline_rounded,
                    onTap: comments,
                  ),
                ),
                Expanded(
                  child: SocialAction(
                    label: '${post.number('shareCount')}',
                    semanticLabel: '${post.number('shareCount')} shares',
                    icon: Icons.ios_share_rounded,
                    onTap: share,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SocialAction extends StatelessWidget {
  const SocialAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.selected = false,
    this.busy = false,
    this.semanticLabel,
  });
  final String label;
  final String? semanticLabel;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected, busy;
  @override
  Widget build(BuildContext c) {
    final color = selected
        ? Theme.of(c).colorScheme.primary
        : Theme.of(c).colorScheme.onSurfaceVariant;
    final duration = MediaQuery.disableAnimationsOf(c)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    return Semantics(
      button: true,
      label: semanticLabel ?? label,
      selected: selected,
      child: Material(
        color: selected ? color.withValues(alpha: .09) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        animationDuration: duration,
        child: InkWell(
          onTap: busy ? null : onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                    ),
                  )
                else
                  AnimatedSwitcher(
                    duration: duration,
                    transitionBuilder: (child, animation) =>
                        ScaleTransition(scale: animation, child: child),
                    child: Icon(
                      icon,
                      key: ValueKey(selected),
                      size: 18,
                      color: color,
                    ),
                  ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String relativePostTime(String value) {
  final date = DateTime.tryParse(value);
  if (date == null) return '';
  final elapsed = DateTime.now().difference(date);
  if (elapsed.inMinutes < 1) return 'Just now';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes}m ago';
  if (elapsed.inDays < 1) return '${elapsed.inHours}h ago';
  if (elapsed.inDays < 7) return '${elapsed.inDays}d ago';
  return dateLabel(value);
}

class PostMediaGallery extends StatelessWidget {
  const PostMediaGallery({super.key, required this.urls});
  final List<String> urls;
  void open(BuildContext c, int index) => Navigator.of(c).push(
    MaterialPageRoute<void>(
      builder: (_) => _PhotoViewer(urls: urls, index: index),
    ),
  );
  @override
  Widget build(BuildContext c) {
    if (urls.length == 1) {
      return InkWell(
        onTap: () => open(c, 0),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: BrandImage(
            urls.first,
            height: double.infinity,
            width: double.infinity,
          ),
        ),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        childAspectRatio: 1.15,
      ),
      itemCount: urls.length.clamp(0, 4),
      itemBuilder: (d, index) => InkWell(
        onTap: () => open(c, index),
        child: Stack(
          fit: StackFit.expand,
          children: [
            BrandImage(urls[index], height: double.infinity),
            if (index == 3 && urls.length > 4)
              Container(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Text(
                  '+${urls.length - 4}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({required this.urls, required this.index});
  final List<String> urls;
  final int index;
  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late int index = widget.index;
  late final pages = PageController(initialPage: widget.index);
  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text('${index + 1} / ${widget.urls.length}'),
    ),
    body: PageView.builder(
      controller: pages,
      itemCount: widget.urls.length,
      onPageChanged: (v) => setState(() => index = v),
      itemBuilder: (_, i) => InteractiveViewer(
        minScale: 1,
        maxScale: 4,
        child: Center(
          child: BrandImage(
            widget.urls[i],
            height: MediaQuery.sizeOf(c).height * .8,
            width: double.infinity,
            fit: BoxFit.contain,
          ),
        ),
      ),
    ),
  );
}

class PostEditor extends StatefulWidget {
  const PostEditor({
    super.key,
    this.id,
    this.initial,
    this.clanId,
    this.startPhotos = false,
    this.startAnonymous = false,
  });
  final String? id, clanId;
  final Json? initial;
  final bool startPhotos, startAnonymous;
  @override
  State<PostEditor> createState() => PostEditorState();
}

class PostEditorState extends State<PostEditor> {
  late final body = SocialTextController(
    text: widget.initial?['body']?.toString() ?? '',
  );
  late String visibility =
          widget.initial?['visibility']?.toString() ?? 'public',
      type = widget.initial?['type']?.toString() ?? 'general';
  late bool anonymous =
      widget.initial?['isAnonymous'] == true || widget.startAnonymous;
  final photos = <String>[];
  bool uploading = false, saving = false, allowExit = false, prompting = false;
  String? error;
  double? uploadProgress;
  bool composerFocused = false;
  final bodyFocus = FocusNode();
  late final MentionCubit mentions;
  bool get changed =>
      body.text != (widget.initial?['body']?.toString() ?? '') ||
      photos.isNotEmpty ||
      anonymous != (widget.initial?['isAnonymous'] == true) ||
      visibility != (widget.initial?['visibility'] ?? 'public') ||
      type != (widget.initial?['type'] ?? 'general');
  @override
  void initState() {
    super.initState();
    mentions = MentionCubit(repository(context));
    body.addListener(_changed);
    if (widget.startPhotos) {
      WidgetsBinding.instance.addPostFrameCallback((_) => addPhotos());
    }
  }

  void _changed() {
    if (!mounted) return;
    mentions.update(
      body.value.composing.isValid && !body.value.composing.isCollapsed
          ? null
          : activeMention(body.text, body.selection),
    );
    setState(() {});
  }

  void insertSocialMarker(String marker) {
    if (saving || uploading) return;
    final selection = body.selection;
    final start = selection.isValid ? selection.start : body.text.length;
    final end = selection.isValid ? selection.end : body.text.length;
    final prefix = start > 0 && !RegExp(r'\s').hasMatch(body.text[start - 1])
        ? ' '
        : '';
    final value = '$prefix$marker';
    body.value = TextEditingValue(
      text: body.text.replaceRange(start, end, value),
      selection: TextSelection.collapsed(offset: start + value.length),
    );
    bodyFocus.requestFocus();
  }

  void pickMention(Entity member) {
    final range = activeMention(body.text, body.selection);
    if (range == null || saving || uploading) return;
    final suffix =
        range.end < body.text.length &&
            RegExp(r'\s').hasMatch(body.text[range.end])
        ? ''
        : ' ';
    final replacement = '@${member.text('handle')}$suffix';
    body.value = TextEditingValue(
      text: body.text.replaceRange(range.start, range.end, replacement),
      selection: TextSelection.collapsed(
        offset: range.start + replacement.length + (suffix.isEmpty ? 1 : 0),
      ),
    );
    bodyFocus.requestFocus();
  }

  @override
  void dispose() {
    mentions.close();
    bodyFocus.dispose();
    body.dispose();
    super.dispose();
  }

  Future<void> addPhotos() async {
    if (uploading || saving) return;
    FocusScope.of(context).unfocus();
    try {
      final selected = await ImagePicker().pickMultiImage(
        maxWidth: 1800,
        imageQuality: 85,
        limit: 5,
      );
      if (!mounted || selected.isEmpty) return;
      if (photos.length + selected.length > 5) {
        throw const AppFailure('Choose up to five photos.');
      }
      setState(() {
        uploading = true;
        error = null;
      });
      final api = repository(context);
      for (final photo in selected) {
        final result = await api.upload(
          photo.path,
          progress: (sent, total) {
            if (mounted) {
              setState(() => uploadProgress = total > 0 ? sent / total : null);
            }
          },
        );
        if (!mounted) return;
        setState(() => photos.add(result['url'] as String));
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          uploading = false;
          uploadProgress = null;
        });
      }
    }
  }

  Future<bool> canLeave() async {
    if (allowExit || !changed && !saving && !uploading) return true;
    if (prompting || saving || uploading) return false;
    prompting = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Leave this post?'),
        content: const Text('Your unfinished post will be discarded.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Keep writing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    prompting = false;
    if (discard != true || !mounted) return false;
    setState(() => allowExit = true);
    await WidgetsBinding.instance.endOfFrame;
    return mounted;
  }

  Future<void> exit() async {
    if (await canLeave() && mounted) context.pop();
  }

  Future<void> publish() async {
    if (saving || uploading || body.text.trim().isEmpty) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await repository(context).request(
        widget.id == null ? 'posts' : 'posts/${widget.id}',
        method: widget.id == null ? 'POST' : 'PATCH',
        body: {
          'body': body.text.trim(),
          'type': type,
          'visibility': visibility,
          'isAnonymous': anonymous,
          if (widget.id == null) ...{
            'media': photos,
            if (widget.clanId != null) 'clanId': widget.clanId,
          },
        },
      );
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      setState(() => allowExit = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) context.pop(true);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> choosePostType() async {
    if (saving || uploading) return;
    FocusScope.of(context).unfocus();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final selected = await showDialog<String>(
      context: context,
      barrierLabel: 'Close post types',
      barrierColor: Colors.black.withValues(alpha: .3),
      animationStyle: AnimationStyle(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 180),
        reverseDuration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 140),
      ),
      builder: (dialog) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Post type',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close post types',
                            onPressed: () => Navigator.pop(dialog),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final value in postTypes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: ListTile(
                          key: ValueKey('post-type-$value'),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          selected: type == value,
                          selectedTileColor: Theme.of(
                            dialog,
                          ).colorScheme.primary.withValues(alpha: .12),
                          leading: Icon(postTypeIcon(value)),
                          title: Text(postTypeLabel(value)),
                          trailing: type == value
                              ? const Icon(Icons.check_rounded, size: 20)
                              : null,
                          onTap: () => Navigator.pop(dialog, value),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (selected != null && mounted) {
      HapticFeedback.selectionClick();
      setState(() => type = selected);
    }
  }

  @override
  Widget build(BuildContext c) {
    final user = c.watch<AuthCubit>().state.user ?? {};
    final scheme = Theme.of(c).colorScheme;
    // Match the web login's nepal-auth-field outline in each theme.
    final dark = Theme.of(c).brightness == Brightness.dark;
    final authOutline = Color(dark ? 0xFF465572 : 0xFFA0AEC3);
    final authFieldFill = Color(dark ? 0xFF111D36 : 0xFFFFFFFF);
    final composerPhotos = widget.id == null
        ? photos
        : (widget.initial?['media'] as List? ?? [])
              .whereType<String>()
              .toList();
    return PopScope(
      canPop: allowExit || !changed && !saving && !uploading,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) exit();
      },
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 20, 6),
            child: Row(
              children: [
                BackButton(onPressed: saving || uploading ? null : exit),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    widget.id == null ? 'New post' : 'Edit post',
                    style: Theme.of(c).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    key: const ValueKey('post-profile-card'),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          scheme.surface,
                          Color.alphaBlend(
                            scheme.primary.withValues(alpha: .045),
                            scheme.surface,
                          ),
                        ],
                      ),
                      border: Border.all(color: authOutline),
                    ),
                    child: CustomPaint(
                      painter: ProfileCometPattern(
                        color: scheme.onSurfaceVariant.withValues(
                          alpha: Theme.of(c).brightness == Brightness.dark
                              ? .15
                              : .13,
                        ),
                        accent: const Color(0xFFEF646E).withValues(alpha: .38),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: scheme.primary.withValues(
                                        alpha: .65,
                                      ),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: anonymous
                                      ? const AnonymousWolfAvatar(radius: 23)
                                      : MemberAvatar(user, radius: 23),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    anonymous
                                        ? 'Anonymous Wolf'
                                        : '${user['fullName'] ?? 'Pack member'}',
                                    style: Theme.of(c).textTheme.titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -.25,
                                        ),
                                  ),
                                ),
                                if (!anonymous &&
                                    user['isIdentityVerified'] == true)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: Tooltip(
                                      message: 'Identity verified',
                                      child: Icon(
                                        Icons.verified_rounded,
                                        size: 20,
                                        color: scheme.primary,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                PopupMenuButton<String>(
                                  tooltip:
                                      'Visibility: ${visibility == 'public' ? 'Public' : 'Private'}',
                                  enabled: !saving && !uploading,
                                  initialValue: visibility,
                                  style: IconButton.styleFrom(
                                    minimumSize: const Size(48, 48),
                                    backgroundColor: scheme.surfaceContainer
                                        .withValues(alpha: .7),
                                    foregroundColor: scheme.onSurfaceVariant,
                                    side: BorderSide(
                                      color: scheme.outlineVariant.withValues(
                                        alpha: .65,
                                      ),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  icon: Icon(
                                    visibility == 'public'
                                        ? Icons.public_rounded
                                        : Icons.lock_outline_rounded,
                                    size: 21,
                                  ),
                                  onSelected: (v) {
                                    HapticFeedback.selectionClick();
                                    setState(() => visibility = v);
                                  },
                                  itemBuilder: (_) => [
                                    for (final value in ['public', 'private'])
                                      PopupMenuItem(
                                        value: value,
                                        child: Row(
                                          children: [
                                            Icon(
                                              value == 'public'
                                                  ? Icons.public_rounded
                                                  : Icons.lock_outline_rounded,
                                              size: 20,
                                            ),
                                            const SizedBox(width: 12),
                                            Text(
                                              value == 'public'
                                                  ? 'Public'
                                                  : 'Private',
                                            ),
                                            const Spacer(),
                                            if (visibility == value)
                                              const Icon(
                                                Icons.check_rounded,
                                                size: 18,
                                              ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton(
                                    key: const ValueKey('choose-post-type'),
                                    onPressed: saving || uploading
                                        ? null
                                        : choosePostType,
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: authFieldFill,
                                      foregroundColor: scheme.onSurface,
                                      side: BorderSide(color: authOutline),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        AnimatedSwitcher(
                                          duration:
                                              MediaQuery.disableAnimationsOf(c)
                                              ? Duration.zero
                                              : const Duration(
                                                  milliseconds: 160,
                                                ),
                                          child: Icon(
                                            postTypeIcon(type),
                                            key: ValueKey(type),
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            postTypeLabel(type),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        const Icon(
                                          Icons.keyboard_arrow_down_rounded,
                                          size: 20,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Focus(
                    onFocusChange: (focused) {
                      if (!focused) mentions.update(null);
                      setState(() => composerFocused = focused);
                    },
                    child: AnimatedContainer(
                      key: const ValueKey('status-composer'),
                      duration: MediaQuery.disableAnimationsOf(c)
                          ? Duration.zero
                          : const Duration(milliseconds: 160),
                      decoration: BoxDecoration(
                        color: scheme.surface.withValues(alpha: .55),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: composerFocused
                              ? scheme.primary.withValues(alpha: .65)
                              : scheme.outlineVariant.withValues(alpha: .55),
                          width: 1.3,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: body,
                            focusNode: bodyFocus,
                            autofocus: !widget.startPhotos,
                            enabled: !saving,
                            minLines: composerPhotos.isEmpty ? 5 : 3,
                            maxLines: null,
                            maxLength: 20000,
                            textCapitalization: TextCapitalization.sentences,
                            style: const TextStyle(fontSize: 20, height: 1.5),
                            decoration: InputDecoration(
                              hintText: anonymous ? 'Speak freely, ghost wolf…' : 'What’s on your mind?',
                              counterText: body.text.length >= 19000
                                  ? '${body.text.length}/20000'
                                  : '',
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              contentPadding: const EdgeInsets.all(20),
                              hintStyle: TextStyle(
                                color: scheme.onSurfaceVariant.withValues(
                                  alpha: .65,
                                ),
                                fontSize: 22,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                IconButton(
                                  tooltip: 'Add hashtag',
                                  onPressed: saving || uploading
                                      ? null
                                      : () => insertSocialMarker('#'),
                                  icon: const Icon(Icons.tag_rounded, size: 21),
                                ),
                                IconButton(
                                  tooltip: 'Mention a member',
                                  onPressed: saving || uploading
                                      ? null
                                      : () => insertSocialMarker('@'),
                                  icon: const Icon(
                                    Icons.alternate_email_rounded,
                                    size: 21,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          MentionSuggestions(
                            cubit: mentions,
                            onPick: pickMention,
                          ),
                          if (composerPhotos.isNotEmpty)
                            ComposerPhotoStrip(
                              urls: composerPhotos,
                              busy: uploading || saving,
                              onRemove: widget.id == null
                                  ? (index) =>
                                        setState(() => photos.removeAt(index))
                                  : null,
                            ),
                          if (uploading)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                              child: Column(
                                children: [
                                  LinearProgressIndicator(
                                    value: uploadProgress,
                                  ),
                                  const SizedBox(height: 8),
                                  const Text('Preparing your photos…'),
                                ],
                              ),
                            ),
                          if (widget.id != null && composerPhotos.isNotEmpty)
                            const Padding(
                              padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
                              child: Text(
                                'Existing media stays with your post.',
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Material(
                    color: scheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: scheme.outlineVariant.withValues(alpha: .55),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        if (widget.id == null)
                          ListTile(
                            leading: const Icon(
                              Icons.photo_library_outlined,
                              color: Color(0xff69c6af),
                            ),
                            title: const Text('Add photos'),
                            subtitle: const Text('Up to 5 photos'),
                            trailing: const Icon(Icons.add_rounded),
                            onTap: uploading || saving ? null : addPhotos,
                          ),
                        if (widget.id == null)
                          Divider(
                            height: 1,
                            indent: 16,
                            endIndent: 16,
                            color: scheme.outlineVariant.withValues(alpha: .45),
                          ),
                        SwitchListTile.adaptive(
                          secondary: const Icon(
                            Icons.masks_outlined,
                            color: Color(0xffc7b1ff),
                          ),
                          title: Text(anonymous ? 'Incognito Mode' : 'Public Identity'),
                          subtitle: Text(anonymous ? 'Posting as Anonymous Wolf' : 'Post with your name and profile photo'),
                          value: anonymous,
                          onChanged: saving
                              ? null
                              : (v) => setState(() => anonymous = v),
                        ),
                      ],
                    ),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        error!,
                        style: TextStyle(color: scheme.error),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: saving || uploading || body.text.trim().isEmpty
                      ? null
                      : publish,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (saving) ...[
                        const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Flexible(
                        child: Text(
                          saving
                              ? 'Sharing…'
                              : widget.id == null
                              ? 'Share with the pack'
                              : 'Save changes',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PostDetailPage extends StatelessWidget {
  const PostDetailPage(this.id, {super.key});
  final String id;
  @override
  Widget build(BuildContext c) => Column(
    children: [
      Expanded(
        flex: 3,
        child: DetailView(
          path: 'posts/$id',
          builder: (d, p, r) => PostCard(post: p, refresh: r),
        ),
      ),
      Expanded(flex: 4, child: CommentsPane(id)),
    ],
  );
}

class CommentsPane extends StatefulWidget {
  const CommentsPane(this.id, {super.key, this.scrollController});
  final String id;
  final ScrollController? scrollController;
  @override
  State<CommentsPane> createState() => _CommentsPaneState();
}

class _CommentsPaneState extends State<CommentsPane> {
  late final CommentsCubit commentsCubit;
  List<Entity> get _comments => commentsCubit.state.items;
  bool get _loading => commentsCubit.state.loading;
  String? get _error => commentsCubit.state.error;

  String? replyToCommentId;
  String? replyToCommentAuthor;
  final controller = TextEditingController();
  final mutation = MutationCubit();
  final composerFocus = FocusNode();
  final expandedReplies = <String>{};
  String? attachmentUrl;
  bool uploadingAttachment = false;
  final attachmentMenu = MenuController();
  bool attachmentMenuOpen = false;
  late final MentionCubit _mentionCubit;

  @override
  void initState() {
    super.initState();
    commentsCubit = CommentsCubit(repository(context), widget.id, context.read<PostEngagementCubit>());
    _mentionCubit = MentionCubit(repository(context));
    controller.addListener(_onTextChanged);
    composerFocus.addListener(_updateComposerFocus);
    _loadComments();
  }

  void _onTextChanged() {
    final range = activeMention(controller.text, controller.selection);
    _mentionCubit.update(range);
  }

  void _updateComposerFocus() {
    if (mounted) setState(() {});
  }

  Future<void> _loadComments() => commentsCubit.load();

  String _threadId(Entity comment) {
    final byId = {for (final c in _comments) c.id: c};
    final seen = <String>{comment.id};
    var current = comment;
    while (true) {
      final parent = byId[current.text('parentCommentId')];
      if (parent == null || !seen.add(parent.id)) return current.id;
      current = parent;
    }
  }

  Future<void> _likeComment(Entity row) async {
    try {
      await commentsCubit.toggleLike(row, context.read<AuthCubit>().userId);
    } catch (error) {
      if (mounted) notice(context, error.toString());
    }
  }

  Future<void> sendComment() async {
    if (uploadingAttachment || mutation.state.busy || commentsCubit.state.busy ||
        (controller.text.trim().isEmpty && attachmentUrl == null)) return;
    final parent = replyToCommentId;
    final root = parent == null ? null : _comments.where((r) => r.id == parent).firstOrNull;
    await mutation.run(() => commentsCubit.send({
      'text': controller.text.trim(),
      if (attachmentUrl != null) 'attachmentUrl': attachmentUrl,
      if (parent != null) 'parentCommentId': parent,
    }));
    if (!mounted) return;
    if (mutation.state.success) {
      controller.clear();
      setState(() {
        if (root != null) expandedReplies.add(_threadId(root));
        replyToCommentId = null;
        replyToCommentAuthor = null;
        attachmentUrl = null;
      });
    } else {
      notice(context, mutation.state.error ?? 'Could not send comment.');
    }
  }

  Future<void> commentAction(
    BuildContext c,
    Entity row,
    String action,
  ) async {
    if (action == 'edit') {
      await showModalBottomSheet<void>(
        context: c,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (sheet) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheet).bottom,
          ),
          child: SizedBox(
            height: 400,
            child: FeatureForm(
              title: 'Edit reply',
              fields: [
                FieldSpec(
                  'text',
                  'Reply',
                  initial: row.text('text'),
                  required: row.text('attachmentUrl').isEmpty,
                  kind: FieldKind.multiline,
                  maxLength: 2000,
                ),
              ],
              submit: (v) => commentsCubit.edit(row.id, v),
              onSuccess: (_) {
                Navigator.pop(sheet);
              },
            ),
          ),
        ),
      );
    } else {
      if (!await confirm(c, 'Delete comment', 'Remove this reply?') ||
          !c.mounted) {
        return;
      }
      try {
        await commentsCubit.remove(row.id);
      } catch (error) {
        if (c.mounted) notice(c, error.toString());
      }
    }
  }

  Future<void> pickCommentGif() async {
    if (uploadingAttachment || mutation.state.busy) return;
    composerFocus.unfocus();
    final url = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheet) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheet).bottom),
        child: SizedBox(height: MediaQuery.sizeOf(sheet).height * .65, child: const CommentGifPicker()),
      ),
    );
    if (!mounted || url == null) return;
    setState(() => attachmentUrl = url);
  }

  Future<void> pickCommentPicture() async {
    if (uploadingAttachment || mutation.state.busy) return;
    setState(() => uploadingAttachment = true);
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'gif'],
      );
      if (files.isEmpty || files.first.path == null || !mounted) return;
      final path = files.first.path!;
      if (await File(path).length() > 10 * 1024 * 1024) {
        throw const AppFailure('Choose a picture or GIF under 10 MB.');
      }
      if (!mounted) return;
      final uploaded = await repository(context).upload(path);
      if (mounted) setState(() => attachmentUrl = uploaded['url'] as String);
    } catch (error) {
      if (mounted) notice(context, error.toString());
    } finally {
      if (mounted) setState(() => uploadingAttachment = false);
    }
  }

  @override
  void dispose() {
    controller.removeListener(_onTextChanged);
    controller.dispose();
    composerFocus.removeListener(_updateComposerFocus);
    composerFocus.dispose();
    commentsCubit.close();
    _mentionCubit.close();
    mutation.close();
    super.dispose();
  }

  void _beginReply(Entity row) {
    if (mutation.state.busy) return;
    setState(() {
      replyToCommentId = row.id;
      replyToCommentAuthor = row.object('authorId')['fullName']?.toString() ?? 'Pack member';
    });
    composerFocus.requestFocus();
  }

  Widget _commentRow(BuildContext c, Entity row, int depth) {
    final me = c.read<AuthCubit>().userId;
    final author = row.object('authorId');
    final own = entityId(row.data['authorId']) == me;
    final liked = row.strings('likes').contains(me);
    final muted = Theme.of(c).colorScheme.onSurfaceVariant;
    return Padding(
      padding: EdgeInsets.only(left: depth == 0 ? 0 : 36, bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MemberAvatar(author, radius: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(author['fullName']?.toString() ?? 'Pack member',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    Text(relativePostTime(row.text('createdAt')),
                      style: TextStyle(fontSize: 11, color: muted)),
                  ],
                ),
                if (row.text('text').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: SocialPostText(text: row.text('text'), mentions: row.rows('mentionDisplay')),
                  ),
                if (row.text('attachmentUrl').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: GestureDetector(
                      onTap: () => showDialog<void>(
                        context: c,
                        builder: (dialog) => Dialog(
                          child: Stack(children: [
                            InteractiveViewer(child: BrandImage(row.text('attachmentUrl'), height: 320, fit: BoxFit.contain)),
                            Positioned(right: 4, top: 4, child: IconButton(
                              tooltip: 'Close picture', onPressed: () => Navigator.pop(dialog), icon: const Icon(Icons.close))),
                          ]),
                        ),
                      ),
                      child: BrandImage(row.text('attachmentUrl'), height: 150, fit: BoxFit.contain),
                    ),
                  ),
                Row(children: [
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: muted, padding: EdgeInsets.zero),
                    onPressed: mutation.state.busy ? null : () => _beginReply(row),
                    child: const Text('Reply', style: TextStyle(fontSize: 12)),
                  ),
                  if (own) PopupMenuButton<String>(
                    tooltip: 'Comment options',
                    enabled: !commentsCubit.state.busy,
                    icon: Icon(Icons.more_horiz, size: 18, color: muted),
                    onSelected: (action) => commentAction(c, row, action),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ]),
              ],
            ),
          ),
          Column(children: [
            IconButton(
              tooltip: liked ? 'Unlike comment' : 'Like comment',
              onPressed: commentsCubit.state.busy ? null : () => _likeComment(row),
              icon: Icon(liked ? Icons.favorite : Icons.favorite_border, size: 18,
                color: liked ? Theme.of(c).colorScheme.primary : muted),
            ),
            if (row.number('likeCount') > 0)
              Text('${row.number('likeCount')}', style: TextStyle(fontSize: 11, color: muted)),
          ]),
        ],
      ),
    );
  }

  List<Widget> _threadWidgets(BuildContext c, Entity root) {
    final replies = _comments.where((row) => row.id != root.id && _threadId(row) == root.id).toList();
    final expanded = expandedReplies.contains(root.id);
    return [
      _commentRow(c, root, 0),
      for (final row in expanded ? replies : replies.take(1)) _commentRow(c, row, 1),
      if (replies.length > 1)
        Padding(
          padding: const EdgeInsets.only(left: 46, bottom: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() {
                if (expanded) { expandedReplies.remove(root.id); } else { expandedReplies.add(root.id); }
              }),
              child: Text(expanded ? 'Show fewer replies' : 'Show all replies (${replies.length})',
                style: TextStyle(fontSize: 12, color: Theme.of(c).colorScheme.onSurfaceVariant)),
            ),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext c) => BlocBuilder<CommentsCubit, CommentsState>(
    bloc: commentsCubit,
    builder: (c, state) => Column(
    children: [
      Expanded(
          child: ListView(
            controller: widget.scrollController,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(16),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (_loading && _comments.isEmpty)
                const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
              if (_error != null) ErrorPanel(_error!, retry: () => _loadComments()),
              if (!_loading && _error == null && _comments.isEmpty)
                const Padding(padding: EdgeInsets.all(24), child: Text('Be the first to comment.', textAlign: TextAlign.center)),
              for (final root in _comments.where((row) => _threadId(row) == row.id))
                ..._threadWidgets(c, root),
            ],
          ),
      ),
      if (replyToCommentId != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
          child: Container(
            padding: const EdgeInsets.only(
              left: 12,
              right: 4,
              top: 4,
              bottom: 4,
            ),
            decoration: BoxDecoration(
              color: Theme.of(
                c,
              ).colorScheme.primaryContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Theme.of(c).colorScheme.primary.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.reply_rounded,
                  size: 16,
                  color: Theme.of(c).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Replying to $replyToCommentAuthor',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(c).colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Cancel reply',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  iconSize: 16,
                  color: Theme.of(c).colorScheme.onSurfaceVariant,
                  onPressed: () => setState(() {
                    replyToCommentId = null;
                    replyToCommentAuthor = null;
                  }),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
        ),
      MentionSuggestions(
        cubit: _mentionCubit,
        onPick: (member) {
          final range = activeMention(
            controller.text,
            controller.selection,
          );
          if (range == null) return;
          final suffix = range.end < controller.text.length &&
                  RegExp(r'\s')
                      .hasMatch(controller.text[range.end])
              ? ''
              : ' ';
          final replacement = '@${member.text('handle')}$suffix';
          final newText = controller.text.replaceRange(
            range.start,
            range.end,
            replacement,
          );
          controller.value = TextEditingValue(
            text: newText,
            selection: TextSelection.collapsed(
              offset: range.start +
                  replacement.length +
                  (suffix.isEmpty ? 1 : 0),
            ),
          );
          composerFocus.requestFocus();
        },
      ),
      BlocProvider.value(
        value: mutation,
        child: BlocBuilder<MutationCubit, MutationState>(
          builder: (d, s) => SafeArea(
            top: false,
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              decoration: BoxDecoration(
                color: Theme.of(c).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: composerFocus.hasFocus
                      ? Theme.of(c).colorScheme.primary.withValues(alpha: 0.7)
                      : Theme.of(
                          c,
                        ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                  width: composerFocus.hasFocus ? 1.5 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: composerFocus.hasFocus ? 0.04 : 0.02,
                    ),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (attachmentUrl != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Theme.of(c)
                                        .colorScheme
                                        .outlineVariant
                                        .withValues(alpha: 0.6),
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: BrandImage(
                                  attachmentUrl!,
                                  width: 72,
                                  height: 52,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            Positioned(
                              top: -6,
                              right: -6,
                              child: Material(
                                color: Colors.black.withValues(alpha: 0.75),
                                shape: const CircleBorder(),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: s.busy
                                      ? null
                                      : () => setState(
                                            () => attachmentUrl = null,
                                          ),
                                  child: const Tooltip(
                                    message: 'Remove attachment',
                                    child: Padding(
                                      padding: EdgeInsets.all(4),
                                      child: Icon(
                                        Icons.close_rounded,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 3,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        TextFieldTapRegion(
                          child: MenuAnchor(
                            controller: attachmentMenu,
                            onOpen: () { if (mounted) setState(() => attachmentMenuOpen = true); },
                            onClose: () { if (mounted) setState(() => attachmentMenuOpen = false); },
                            style: MenuStyle(
                              shape: WidgetStatePropertyAll(RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              )),
                            ),
                            menuChildren: [
                              MenuItemButton(
                                leadingIcon: const Icon(Icons.image_outlined, size: 20),
                                onPressed: s.busy || uploadingAttachment ? null : pickCommentPicture,
                                child: const Text('Picture'),
                              ),
                              MenuItemButton(
                                leadingIcon: const Icon(Icons.gif_box_outlined, size: 20),
                                onPressed: s.busy || uploadingAttachment ? null : pickCommentGif,
                                child: const Text('GIF'),
                              ),
                            ],
                            builder: (context, menu, child) => IconButton(
                              tooltip: attachmentMenuOpen ? 'Close attachments' : 'Add picture or GIF',
                              onPressed: s.busy || uploadingAttachment ? null : () {
                                if (menu.isOpen) { menu.close(); } else { menu.open(); }
                              },
                              color: attachmentMenuOpen
                                  ? Theme.of(c).colorScheme.primary
                                  : Theme.of(c).colorScheme.onSurfaceVariant,
                              icon: uploadingAttachment
                                  ? const SizedBox(width: 18, height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2))
                                  : AnimatedRotation(
                                      turns: attachmentMenuOpen ? .125 : 0,
                                      duration: MediaQuery.disableAnimationsOf(c)
                                          ? Duration.zero : const Duration(milliseconds: 200),
                                      curve: Curves.easeOutCubic,
                                      child: const Icon(Icons.add_rounded, size: 24),
                                    ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: controller,
                            focusNode: composerFocus,
                            enabled: !s.busy,
                            onTapOutside: (_) => composerFocus.unfocus(),
                            minLines: 1,
                            maxLines: 4,
                            maxLength: 2000,
                            style: const TextStyle(fontSize: 14, height: 1.3),
                            decoration: InputDecoration(
                              hintText: replyToCommentId != null
                                  ? 'Write a reply…'
                                  : 'Add a comment…',
                              hintStyle: TextStyle(
                                fontSize: 14,
                                color: Theme.of(c).colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.55),
                              ),
                              counterText: '',
                              filled: false,
                              isDense: true,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 10,
                              ),
                            ),
                          ),
                        ),
                        TextFieldTapRegion(
                          child: ValueListenableBuilder<TextEditingValue>(
                            valueListenable: controller,
                            builder: (context, value, _) {
                              final hasContent =
                                  value.text.trim().isNotEmpty ||
                                  attachmentUrl != null;
                              return IconButton.filled(
                                tooltip: 'Send reply',
                                style: IconButton.styleFrom(
                                  backgroundColor: hasContent
                                      ? Theme.of(c).colorScheme.primary
                                      : Theme.of(c)
                                            .colorScheme
                                            .surfaceContainerHighest
                                            .withValues(alpha: 0.4),
                                  foregroundColor: hasContent
                                      ? Theme.of(c).colorScheme.onPrimary
                                      : Theme.of(c).colorScheme.onSurfaceVariant
                                            .withValues(alpha: 0.35),
                                  minimumSize: const Size(36, 36),
                                  padding: EdgeInsets.zero,
                                  shape: const CircleBorder(),
                                ),
                                onPressed: (s.busy || uploadingAttachment)
                                    ? null
                                    : () {
                                        if (controller.text.trim().isEmpty &&
                                            attachmentUrl == null) {
                                          return;
                                        }
                                        sendComment();
                                      },
                                icon: s.busy
                                    ? SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Theme.of(
                                            c,
                                          ).colorScheme.onPrimary,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.arrow_upward_rounded,
                                        size: 18,
                                      ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
    ),
  );
}

class SponsoredSlot extends StatefulWidget {
  const SponsoredSlot({super.key});
  @override
  State<SponsoredSlot> createState() => _SponsoredSlotState();
}

class _SponsoredSlotState extends State<SponsoredSlot> {
  Json? ad;
  Timer? timer;
  bool tracked = false;
  bool visible = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ad == null) {
      repository(context)
          .request('ads/delivery', query: {'placement': 'feed'})
          .then((v) {
            if (mounted && asRows(v).isNotEmpty) {
              setState(() => ad = asRows(v).first);
            }
          })
          .catchError((_) {
            return;
          });
    }
  }

  Future<void> track(String event) async {
    try {
      await repository(context).request(
        'ads/track',
        method: 'POST',
        body: {
          'creativeId': entityId(ad),
          'placement': 'feed',
          'deliveryToken': ad?['deliveryToken'],
          'event': event,
        },
      );
      if (event == 'impression') tracked = true;
    } catch (_) {
      /* Never block the feed on ad tracking. */
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    if (ad == null) return const SizedBox.shrink();
    return VisibilityDetector(
      key: ValueKey('ad:${ad!['deliveryToken']}'),
      onVisibilityChanged: (info) {
        visible = info.visibleFraction >= .5;
        timer?.cancel();
        if (visible && !tracked) {
          timer = Timer(const Duration(seconds: 1), () {
            if (mounted && visible && !tracked) track('impression');
          });
        }
      },
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sponsored · ${ad!['advertiserName']}'),
              const SizedBox(height: 10),
              BrandImage(
                ad!['imageUrl']?.toString() ?? '',
                width: double.infinity,
              ),
              Text(
                ad!['headline']?.toString() ?? '',
                style: Theme.of(c).textTheme.titleLarge,
              ),
              Text(ad!['body']?.toString() ?? ''),
              ActionButton(
                label: ad!['cta']?.toString() ?? 'Learn more',
                action: () async {
                  await track('click');
                  await openUrl(ad!['destinationUrl']?.toString() ?? '');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
