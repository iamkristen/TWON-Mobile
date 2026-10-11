# TWON Mobile

Flutter Android/iOS community app using the existing TWON API, Dio, BLoC/Cubits, go_router, secure token storage and Socket.IO. Default appearance is the shared navy/rose dark theme. Forms, menus, lists and dialogs use Material 3; entry animations respect reduced motion.

## Local configuration

The central configuration is `lib/core/env_config.dart`. Public settings can be supplied with `--dart-define-from-file`; no server secrets belong in these files.

```sh
flutter pub get
flutter run --dart-define-from-file=config/env.android.local.json
# iOS simulator:
flutter run --dart-define-from-file=config/env.ios.local.json
```

Start TWON-backend on port 5001 and TWON-WebApp on port 3000. The default development host is `192.168.0.184`, reachable by physical devices on the same Wi-Fi. API, Socket.IO and website URLs all derive from this host. The iOS local-network permission and local HTTP exception are already configured; Android allows HTTP in debug only.

For a physical iPhone or Android phone, select **TWON: Physical device (local backend)** in VS Code, or run:

```sh
flutter run --dart-define-from-file=config/env.device.local.json
```

Allow TWON's Local Network permission on iPhone (Settings → Privacy & Security → Local Network). Fully stop and relaunch/rebuild the app after changing configuration; hot reload does not update compile-time settings. Existing simulator config files intentionally override the device host, so do not use those when launching a physical phone.

For another computer, edit `DEV_HOST` in `config/env.device.local.json`. Use the Mac's current LAN IP, since some Android devices cannot resolve `.local` names (for example `flutter run --dart-define=DEV_HOST=192.168.0.184`). Both devices must be on the same network, without client isolation, and the Mac must allow incoming backend connections. You can check connectivity from the phone's browser at `http://192.168.0.184:5001/api/v1/health`.

Android emulator config uses 10.0.2.2; iOS simulator config uses localhost. Explicit API_BASE_URL, SOCKET_URL and WEBSITE_URL still override derived values. For browser checkout on a physical phone, configure the website's NEXT_PUBLIC_API_URL to reach the same backend over the network too. Release builds still require an explicit HTTPS API_BASE_URL and HTTPS WEBSITE_URL.

## Website payments only

Browse products, choose size, manage quantities and persist the regional basket in the native app. `Pay on website` opens the system browser at `/merch/pay?currency=gbp|npr`. A pending order opens that same page with an `order` parameter. There are no native card fields, Stripe/Khalti SDKs, or native checkout/session creation calls.

The website requires sign-in with the same account. Login and two-step verification retain the payment destination. The website reads the account's saved basket and server prices. Stripe collects GBP; Khalti collects NPR. Both checkout creation and payment confirmation stay on the existing backend/web flow. On returning, the shop refreshes the stored basket and My orders refreshes its list. `Check payment` asks the backend to reconcile provider status; redirects alone never mark an order paid.

## Current screens

Authentication (signup, email verification, password recovery, authenticator/recovery code login); feed and clan posts (create/edit, photos, likes, comments/replies, reports, sharing); clans (join/invites, members, roles/titles, approvals/promotions, broadcasts); gatherings (publish/edit, RSVP, sharing, permission-gated management); messages (DM/groups/clan chat, reply, reactions, edit/delete/report, photos/files/voice, mute); profiles/member search; notifications; shop, saved basket, orders and lookbook; identity verification; support requests/history; settings, privacy, themes, password, two-step verification, sessions and deletion requests.

Writes use backend endpoints. Server permissions remain authoritative. Lists have refresh, loading/error/empty states and cursor pagination where supported. Mobile feeds request server-selected sponsored ads and record an impression after continuous visibility; desktop sidebar placements remain on the website.

## Validation and remaining release work

```sh
flutter analyze
flutter test
flutter build apk --debug
```

This is a development app, not an App Store/Play Store release. Device integration testing of all feature flows, production domains, application identifiers/signing, branded launcher icons, notification push delivery and associated-domain deep links still need completion. Native video/GIF selection, web link previews and the clan permission matrix editor are not yet at web parity. Default Android release signing is the generated debug configuration and must be replaced before distribution. Validation on 4 October 2026: Flutter analysis passed, all 31 mobile tests passed, Android debug APK built and iOS simulator app built. The website production build and all 68 web tests passed. No real payment was charged during tests; physical-device, live-payment and distribution-signing validation remain.


## Social feed and navigation redesign

The mobile feed has no category filters or standalone Post button. Its single “What’s on your mind?” prompt opens a dedicated New post screen. Photo and anonymous controls live inside that screen. Publishing stays backend-driven. Drafts are protected when leaving; cancelling the composer preserves the timeline. Likes patch the returned server post in place, keeping author details and the scroll position. Feed pagination uses a lazy sliver list, and refresh retains existing content while it loads.

Five animated bottom tabs (Home, Clans, Chat, Events, Gear) preserve each tab's state through go_router's indexed shell. The top action order is Search, Notifications, Settings; Pack Chat shows only its chat search action. The drawer groups community, shopping and account tools, with expandable shop and security/privacy submenus.

The website's light/dark navbar SVGs and feed, clan and gathering SVG illustrations are bundled unchanged from TWON-WebApp/public/images and rendered with flutter_svg. Navy/rose styling is retained, including light mode and reduced-motion support. Photo galleries support paging and pinch zoom.

Research references: https://www.facebook.com/help/170116376402147 (feed composer), https://api.flutter.dev/flutter/material/NavigationBar-class.html and https://m3.material.io/components/navigation-bar/overview (primary navigation).

New regression tests cover filter removal, backend publishing, anonymous posting, tab/scroll preservation, settings position and drawer access, backend likes and failure states, draft protection, and narrow screens with 180% text scaling. Preview screenshots use test fixtures and do not add posts to your database.

## Minimal interface update

The feed starts directly with the composer. Its tagline, subtitle, section label and refresh button are removed; pull-to-refresh remains. Shared headings and forms no longer add generic instructions. Navy surfaces, rose accents, menus, sheets, dialogs and selection states use one palette in both appearance modes. Settings use a grouped list and the drawer keeps compact community, shop and account navigation.

The website wording appears where useful: Clan Territory, Pack Gatherings, Pack Chat, Your Signals, Pack support, and “Every pack starts with a howl.” Profiles combine the original website wolf SVG with a mountain cover, an overlapping avatar, verification icon, backend statistics and compact actions. Uploaded cover images remain supported. Member search, notification actor links, clan member links and profile posts now use the registered mobile profile routes.

Gathering filters live beside search in a dismissible sheet with apply/reset and removable active filters. Dismissing the sheet leaves the applied filters unchanged. Publishing remains gated by backend clan permissions. Chat search reads paginated conversations and matches names, handles and the latest message; it also provides the new conversation flow.

Messages support swipe right to reply, alongside the existing long-press reply/reaction menu. The swipe returns the message to its position and exposes an accessible Reply action. List entrances, bottom-tab motion and tactile selection feedback are subtle; added visual animations respect reduced-motion settings. Photos retain swipe paging and pinch zoom. No purchases were moved into the app.

New checks cover chat search across pages, filtering and cancellation, profile navigation and statistics, member search navigation, swipe thresholds, pull-to-refresh, and gathering/profile layouts on 320-point screens with 180% text scaling. Screenshots in the supplied outputs are rendered from test fixtures, not live user data.

## Focused post composer

The feed composer contains only the “What’s on your mind?” prompt. New post and Edit post omit the main app bar and drawer, using a small back control and screen title. Visibility is shown as a globe or lock icon, with accessible Public/Private menu choices. The adjacent post-type dropdown opens all six server-supported types in a centered, dismissible dialog over a blurred background. Selected type and visibility are sent through the existing post API. Photo uploads, anonymous sharing, draft-discard protection and publishing remain available.

Regression coverage verifies the simplified entry, absence of the main app bar, backend type/visibility values, all type options, centered blur dialog, cancellation without losing the draft, reduced motion and large text layouts. Preview screenshots use sample data.

The New post identity area now uses a rose-outlined profile card and avatar ring. Visibility has a separate outlined icon control, and post type is a full-width tinted, bordered button with a category icon and dropdown chevron. Category icon changes animate unless reduced motion is enabled. The writing area has its own rounded surface and focus border; photo and anonymous options share a compact outlined panel. Existing 25 tests continue to verify publishing, privacy, drafts and large-text layouts.

Selected photos and upload progress now appear inside the same bordered composer as the status text. Images use a compact, fixed-height horizontal preview strip with individual removal buttons. Existing images are also shown inside the composer when editing a post.

## Hashtags and mentions

Photo previews stay inside the status card in one horizontal row (132 points tall), including when five images are selected. They no longer grow into a grid. The composer has # and @ controls; hashtags highlight inline, including Nepali combining characters. Hashtags remain part of the saved status text; there is no hashtag discovery/search endpoint in this version.

Typing @ followed by a name/handle requests real suggestions from the existing member search API. Search is debounced and canceled when the query changes or the picker closes. Picking a member inserts @handle at the cursor, preserving surrounding text. Existing backend mention display data renders clickable member names in posts and comments. Public, non-anonymous post mentions use backend notifications with the recipient’s preferences and block relationships enforced. Anonymous/private post creation and editing suppress mention notifications to avoid revealing the author or a post the recipient cannot access; email addresses are not interpreted as mentions.

Validation: 31 mobile tests passed, Flutter analysis passed, backend type checking/build passed, and the backend suite passed 133 tests with 103 integration tests skipped by their existing environment flags. Nine targeted backend tests cover mention parsing, duplicate notifications, blocks and post privacy. The native tests include stale-search cancellation, inline insertion, profile links, Nepali hashtag handling and five-photo scrolling/removal. Physical-device photo picking and live notification delivery still need device testing.

## Messaging gestures and quality fixes — 8 October 2026

Messages now open a blurred action menu on long press or double tap, with seven quick reactions and seven extra choices. Reactions are grouped by emoji with counts and your own selection highlighted; selecting your current reaction removes it through TWON's DELETE endpoint. Selecting another replaces your reaction through TWON's POST endpoint. Errors leave existing reactions intact. Swipe right or choose Reply to focus the composer; reply IDs are sent to the existing TWON messages API. Copy, own-message editing/deletion, and reporting remain available. Deleted messages ignore reply and reaction gestures.

The composer sharing button wraps on narrow screens and at large text sizes. Shared forms accept blank optional email/numeric fields and reject malformed email/non-finite numbers. Chat history remains exhausted after a refresh, pending sends are safe when leaving the screen, and reaction patches preserve the sender's display details.

Tests cover menu gestures, expanded emoji choices, reaction counts/removal, own-message actions, deleted-message restrictions, reply requests, draft preservation, narrow-screen layouts, form validation and chat lifecycle/history. Native microphone operations are mocked in widget tests; live camera/microphone, multi-device messaging, payments and production rollout remain unverified.

Final validation: Flutter analysis reports no issues; all 59 mobile tests pass; the Android debug APK builds successfully. This debug build uses local development service URLs unless overridden with environment defines.
