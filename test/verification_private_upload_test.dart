import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:twon_mobile/shared/widgets.dart';
import 'social_experience_test.dart' show Harness;

const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
const _uid = '65f00000000000000000000a';
const docRef = 'verification/$_uid/11111111-1111-4111-8111-111111111111.webp';
const selfieRef = 'verification/$_uid/22222222-2222-4222-8222-222222222222.webp';

/// Returns a real temporary JPEG for any pick (no platform channels in tests).
class FakeImagePicker extends ImagePickerPlatform {
  FakeImagePicker(this.path);
  final String path;
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async => XFile(path);
}

void main() {
  late Directory dir;
  late File photo;

  late ImagePickerPlatform originalPicker;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('twon-verification-');
    photo = File('${dir.path}/id.jpg')..writeAsBytesSync([0xff, 0xd8, 0xff, 0xd9]);
    originalPicker = ImagePickerPlatform.instance;
    ImagePickerPlatform.instance = FakeImagePicker(photo.path);
    // The preview uses CachedNetworkImage, whose cache asks path_provider for a directory.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (_) async => dir.path);
  });
  tearDown(() {
    ImagePickerPlatform.instance = originalPicker;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    dir.deleteSync(recursive: true);
  });

  testWidgets(
    'verification uploads go to the private endpoint and submit stable references, not preview URLs',
    (tester) async {
      var uploads = 0;
      final h = Harness(
        fixtures: {
          'verification/status': {'status': 'none', 'request': null},
          'verification/submit': {'_id': 'req1', 'status': 'pending'},
        },
      );
      // Each private upload returns a stable ref and a short-lived signed preview URL.
      final adapter = h.api.dio.httpClientAdapter;
      h.api.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == 'verification/uploads') {
              h.calls.add(options);
              uploads += 1;
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 201,
                  data: {
                    'success': true,
                    'data': {
                      'ref': uploads == 1 ? docRef : selfieRef,
                      // Empty preview: CachedNetworkImage's cache cannot run in widget tests,
                      // and an empty URL proves the form never renders the ref as an image.
                      'url': '',
                      'expiresAt': '2026-10-11T08:00:00.000Z',
                    },
                  },
                ),
              );
            }
            handler.next(options);
          },
        ),
      );
      expect(adapter, isNotNull);
      await h.mount(tester);
      GoRouter.of(tester.element(find.text('What’s on your mind?'))).go('/verification');
      await tester.pumpAndSettle();
      expect(find.text('Submit verification'), findsOneWidget);

      for (var i = 0; i < 2; i++) {
        final add = find.text('Add attachment').at(i);
        await tester.ensureVisible(add);
        await tester.tap(add);
        await tester.pump(); // start the bottom-sheet animation
        await tester.pump(const Duration(milliseconds: 500)); // and finish it
        await tester.tap(find.text('Photo library'));
        // The upload reads the picked file with real I/O, which only completes outside fake async.
        // Its continuation runs in the fake-async zone, so alternate real time with pumps.
        for (var t = 0; t < 100 && uploads < i + 1; t++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(uploads, i + 1);
        // The preview is a network image that never resolves in tests, so pump
        // a bounded time instead of waiting for every animation to settle.
        await tester.pump(const Duration(milliseconds: 500));
      }
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      for (var t = 0; t < 100 && !h.calls.any((r) => r.path == 'verification/submit'); t++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 50));
      }

      final previews = tester.widgetList<BrandImage>(find.byType(BrandImage)).map((w) => w.url).toList();
      expect(previews, isNotEmpty);
      expect(previews, everyElement(isNot(anyOf(docRef, selfieRef))));
      final uploadCalls = h.calls.where((r) => r.path == 'verification/uploads').toList();
      expect(uploadCalls, hasLength(2));
      expect(h.calls.where((r) => r.path == 'media/upload'), isEmpty);
      final submit = h.calls.firstWhere((r) => r.path == 'verification/submit');
      final body = Map<String, dynamic>.from(submit.data as Map);
      expect(body['documentImage'], docRef);
      expect(body['selfieImage'], selfieRef);
      expect(body.toString(), isNot(contains('X-Amz-Signature')));
      await h.close(tester);
    },
  );
}
