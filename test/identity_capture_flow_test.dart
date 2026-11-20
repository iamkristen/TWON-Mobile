import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:twon_mobile/core/models.dart';
import 'package:twon_mobile/features/account/identity_verification.dart';
import 'package:twon_mobile/shared/widgets.dart';
import 'api_session_test.dart' show ApiAdapter;
import 'social_experience_test.dart' show Harness;

/// IV-E2E Mobile: identity capture through IV4 sessions with the camera only,
/// local previews only, server-driven steps and error codes, website handoff.

/// Records every pick; returns a fresh temporary JPEG (no platform channels in tests).
class RecordingCamera extends ImagePickerPlatform {
  RecordingCamera(this.dir);
  final Directory dir;
  final picks = <({ImageSource source, CameraDevice device})>[];
  final files = <File>[];
  @override
  Future<XFile?> getImageFromSource({required ImageSource source, ImagePickerOptions options = const ImagePickerOptions()}) async {
    picks.add((source: source, device: options.preferredCameraDevice));
    // A real (tiny) decodable image, so the local preview renders.
    final f = File('${dir.path}/shot${files.length}.jpg')..writeAsBytesSync(base64Decode(_pixel));
    files.add(f);
    return XFile(f.path);
  }
}

const _pixel = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

ResponseBody json(int status, Json body) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {Headers.contentTypeHeader: ['application/json']});
ResponseBody ok(Object? data, [int status = 200]) => json(status, {'success': true, 'data': data});
ResponseBody fail(int status, String code, String message) => json(status, {'success': false, 'error': {'code': code, 'message': message}});

const session = {
  'sessionId': '0123456789abcdef0123456789abcdef',
  'state': 'open',
  'documentType': 'passport',
  'steps': ['document_front', 'selfie', 'holding_document'],
  'received': [],
  'remaining': ['document_front', 'selfie', 'holding_document'],
  'expiresAt': '2026-11-20T12:00:00.000Z',
};

void main() {
  late Directory dir;
  late RecordingCamera camera;
  late ImagePickerPlatform original;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('twon-identity-');
    camera = RecordingCamera(dir);
    original = ImagePickerPlatform.instance;
    ImagePickerPlatform.instance = camera;
  });
  tearDown(() {
    ImagePickerPlatform.instance = original;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  /// The harness, with the identity routes answered by [respond] (null = default).
  Harness harness(Json status, ResponseBody? Function(RequestOptions o) respond) {
    final h = Harness(fixtures: {'verification/status': status});
    final base = h.api.dio.httpClientAdapter;
    h.api.dio.httpClientAdapter = ApiAdapter((o) async {
      final r = respond(o);
      if (r != null) {
        h.calls.add(o);
        return r;
      }
      return base.fetch(o, null, null);
    });
    return h;
  }

  Future<void> settleIo(WidgetTester tester, bool Function() until) async {
    for (var t = 0; t < 120 && !until(); t++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('camera-only capture through the capture session: local previews, server steps, submit, files removed', (tester) async {
    final uploads = <String>[];
    var submitted = false;
    final h = harness({'status': 'none', 'request': null}, (o) {
      if (o.path == 'verification/sessions' && o.method == 'POST') return ok(session, 201);
      if (o.path.startsWith('verification/sessions/${session['sessionId']}/evidence/')) {
        uploads.add(o.path.split('/').last);
        return ok({'received': uploads, 'remaining': []}, 201);
      }
      if (o.path == 'verification/sessions/${session['sessionId']}/submit') {
        submitted = true;
        return ok({'state': 'submitted'}, 201);
      }
      return null;
    });
    await h.mount(tester);
    GoRouter.of(tester.element(find.text('What’s on your mind?'))).go('/verification');
    await tester.pumpAndSettle();
    expect(find.text('Not verified'), findsWidgets);
    await tester.tap(find.text('Verify with this phone'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await settleIo(tester, () => find.text('Front of your document').evaluate().isNotEmpty);
    final start = h.calls.firstWhere((r) => r.path == 'verification/sessions');
    expect(start.data, {'documentType': 'passport'});

    for (final (kind, front) in const [('document_front', false), ('selfie', true), ('holding_document', true)]) {
      await tester.tap(find.textContaining(front ? 'Open front camera' : 'Open camera'));
      await settleIo(tester, () => find.byKey(Key('identity-preview-$kind')).evaluate().isNotEmpty);
      // The preview is the LOCAL file, never a network image.
      final preview = tester.widget<Image>(find.byKey(Key('identity-preview-$kind')));
      expect(preview.image, isA<FileImage>());
      await tester.tap(find.text('Use this photo'));
      await settleIo(tester, () => uploads.contains(kind));
      await tester.pump(const Duration(milliseconds: 200));
    }
    // Camera only, and the right camera for each step.
    expect(camera.picks.map((p) => p.source), everyElement(ImageSource.camera));
    expect(camera.picks.map((p) => p.device).toList(), [CameraDevice.rear, CameraDevice.front, CameraDevice.front]);
    expect(uploads, ['document_front', 'selfie', 'holding_document']);

    await tester.tap(find.text('Submit for review'));
    await settleIo(tester, () => submitted);
    await tester.pump(const Duration(milliseconds: 300));
    expect(submitted, isTrue);
    expect(camera.files.where((f) => f.existsSync()), isEmpty, reason: 'local previews are deleted after submitting');
    // Never the legacy endpoints, never a server image.
    expect(h.calls.where((r) => r.path == 'verification/uploads' || r.path == 'verification/submit' || r.path == 'media/upload'), isEmpty);
    expect(find.byType(BrandImage), findsNothing);
    await h.close(tester);
  });

  testWidgets('server refusals: a photo refused by the security check must be retaken; an expired session restarts', (tester) async {
    var attempt = 0;
    final h = harness({'status': 'none', 'request': null}, (o) {
      if (o.path.contains('/evidence/')) {
        attempt += 1;
        return attempt == 1
            ? fail(422, 'IDENTITY_EVIDENCE_REJECTED', 'This file was refused by the security check.')
            : fail(410, 'CAPTURE_SESSION_EXPIRED', 'This capture session has expired.');
      }
      return null;
    });
    await h.mount(tester);
    GoRouter.of(tester.element(find.text('What’s on your mind?'))).push('/verification/capture', extra: session);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open camera'));
    await settleIo(tester, () => find.byKey(const Key('identity-preview-document_front')).evaluate().isNotEmpty);
    await tester.tap(find.text('Use this photo'));
    await settleIo(tester, () => find.byKey(const Key('identity-capture-error')).evaluate().isNotEmpty);
    expect(find.textContaining('refused by the security check'), findsOneWidget);
    expect(find.byKey(const Key('identity-preview-document_front')), findsNothing, reason: 'a refused photo must be retaken');
    await tester.tap(find.text('Open camera'));
    await settleIo(tester, () => find.byKey(const Key('identity-preview-document_front')).evaluate().isNotEmpty);
    await tester.tap(find.text('Use this photo'));
    await settleIo(tester, () => find.text('Start again').evaluate().isNotEmpty);
    expect(find.text('Start again'), findsOneWidget);
    await h.close(tester);
  });

  testWidgets('website handoff: the QR deep link token is claimed once, then the capture opens; refusals are explained', (tester) async {
    var claims = 0;
    final h = harness({'status': 'none', 'request': null}, (o) {
      if (o.path == 'verification/pairing/claim') {
        claims += 1;
        final body = asJson(o.data);
        if (body['token'] == 'stolen-token-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa') {
          return fail(403, 'PAIRING_ACCOUNT_MISMATCH', 'This verification link belongs to another account.');
        }
        return ok({...session, 'pairingId': 'p1'}, 201);
      }
      return null;
    });
    await h.mount(tester);
    final router = GoRouter.of(tester.element(find.text('What’s on your mind?')));
    router.go('/identity/pair?t=good-token-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
    await settleIo(tester, () => find.text('Front of your document').evaluate().isNotEmpty);
    expect(asJson(h.calls.firstWhere((r) => r.path == 'verification/pairing/claim').data), {'token': 'good-token-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'});
    router.go('/pair?t=stolen-token-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
    await settleIo(tester, () => find.byKey(const Key('identity-pair-error')).evaluate().isNotEmpty);
    expect(find.textContaining('belongs to another account'), findsOneWidget);
    expect(claims, 2);
    router.go('/pair');
    await settleIo(tester, () => find.byKey(const Key('identity-pair-error')).evaluate().isNotEmpty);
    expect(claims, 2, reason: 'no token and no code: nothing is sent');
    await h.close(tester);
  });

  testWidgets('a rejected case shows the reason and the appeal, which is sent with the statement', (tester) async {
    Json? appeal;
    final h = harness({
      'status': 'rejected',
      'request': {'_id': '65f0000000000000000000aa', 'state': 'rejected', 'reasonCode': 'document_expired', 'appealableUntil': '2026-12-01T00:00:00.000Z'},
    }, (o) {
      if (o.path == 'verification/appeals') {
        appeal = asJson(o.data);
        return ok({'state': 'appealed'}, 201);
      }
      return null;
    });
    await h.mount(tester);
    GoRouter.of(tester.element(find.text('What’s on your mind?'))).go('/verification');
    await tester.pumpAndSettle();
    expect(find.text('The document has expired.'), findsOneWidget);
    await tester.tap(find.text('Appeal this decision'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('identity-appeal-statement')), 'My passport was renewed last week.');
    await tester.pump();
    await tester.tap(find.text('Send appeal'));
    await settleIo(tester, () => appeal != null);
    expect(appeal, {'requestId': '65f0000000000000000000aa', 'statement': 'My passport was renewed last week.'});
    await h.close(tester);
  });

  testWidgets('more evidence: the requested photos start a session without a body (steps come from the server)', (tester) async {
    Object? body = 'unset';
    final h = harness({
      'status': 'pending',
      'request': {'_id': 'c1', 'state': 'more_evidence_required', 'requestedKinds': ['document_back']},
    }, (o) {
      if (o.path == 'verification/sessions' && o.method == 'POST') {
        body = o.data;
        return ok({...session, 'steps': ['document_back'], 'remaining': ['document_back']}, 201);
      }
      return null;
    });
    await h.mount(tester);
    GoRouter.of(tester.element(find.text('What’s on your mind?'))).go('/verification');
    await tester.pumpAndSettle();
    expect(find.textContaining('Back of your document'), findsOneWidget);
    await tester.tap(find.text('Add the requested photos'));
    await settleIo(tester, () => find.text('Open camera').evaluate().isNotEmpty);
    expect(body, <String, dynamic>{});
    expect(find.text('Back of your document'), findsWidgets); // the step title and the checklist
    await h.close(tester);
  });

  test('every case state has member copy; unknown states count as under review; the badge is never inferred', () {
    for (final s in ['none', 'submitted', 'under_review', 'escalated', 'more_evidence_required', 'approved', 'rejected', 'appealed', 'suspended', 'revoked', 'expired', 'closed']) {
      expect(identityStateCopy(s).title, isNotEmpty, reason: s);
    }
    expect(identityStateCopy('some_future_state').title, 'Under review');
    expect(identityReasonCopy('holder_mismatch'), isNot(contains('holder_mismatch')));
    expect(identityReasonCopy(null), isNotEmpty);
    expect(identityStepCopy('selfie').front, isTrue);
    expect(identityStepCopy('document_front').front, isFalse);
  });
}
