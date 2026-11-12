import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:twon_mobile/shared/widgets.dart';
import 'social_experience_test.dart' show Harness;
import 'verification_private_upload_test.dart' show FakeImagePicker;

const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
const _uid = '65f00000000000000000000a';
const lookRef = 'lookbook/$_uid/33333333-3333-4333-8333-333333333333.webp';

/// F-33: Pack Look photos are uploaded privately; only the reference is submitted.
void main() {
  late Directory dir;
  late File photo;
  late ImagePickerPlatform originalPicker;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('twon-lookbook-');
    photo = File('${dir.path}/look.jpg')..writeAsBytesSync([0xff, 0xd8, 0xff, 0xd9]);
    originalPicker = ImagePickerPlatform.instance;
    ImagePickerPlatform.instance = FakeImagePicker(photo.path);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (_) async => dir.path);
  });
  tearDown(() {
    ImagePickerPlatform.instance = originalPicker;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    dir.deleteSync(recursive: true);
  });

  testWidgets('Pack Look photos go to the private endpoint and submit imageRef, never a public URL', (tester) async {
    var uploads = 0;
    final h = Harness(fixtures: {'lookbook': {'_id': 'look1', 'status': 'pending'}});
    h.api.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path == 'lookbook/uploads') {
            h.calls.add(options);
            uploads += 1;
            return handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 201,
                data: {
                  'success': true,
                  // Empty preview url: the form must never render the ref as an image.
                  'data': {'imageRef': lookRef, 'url': '', 'expiresAt': '2026-10-18T08:00:00.000Z'},
                },
              ),
            );
          }
          handler.next(options);
        },
      ),
    );
    await h.mount(tester);
    GoRouter.of(tester.element(find.text('What’s on your mind?'))).push('/lookbook/new');
    await tester.pumpAndSettle();
    expect(find.text('Share your pack style'), findsOneWidget);

    final add = find.text('Add attachment').first;
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Photo library'));
    for (var t = 0; t < 100 && uploads < 1; t++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(uploads, 1);
    await tester.pump(const Duration(milliseconds: 500));

    await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Night run');
    await tester.enterText(find.widgetWithText(TextFormField, 'Caption'), 'Lakeside, Pokhara');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    for (var t = 0; t < 100 && !h.calls.any((r) => r.path == 'lookbook' && r.method == 'POST'); t++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 50));
    }

    final previews = tester.widgetList<BrandImage>(find.byType(BrandImage)).map((w) => w.url).toList();
    expect(previews, everyElement(isNot(lookRef)));
    expect(h.calls.where((r) => r.path == 'media/upload'), isEmpty);
    final submit = h.calls.firstWhere((r) => r.path == 'lookbook' && r.method == 'POST');
    final body = Map<String, dynamic>.from(submit.data as Map);
    expect(body['imageRef'], lookRef);
    expect(body.containsKey('imageUrl'), isFalse);
    expect(body['title'], 'Night run');
    await h.close(tester);
  });
}
