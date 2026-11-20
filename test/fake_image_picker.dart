import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

/// Returns a real temporary file for any pick (no platform channels in tests).
/// Shared by tests (formerly in verification_private_upload_test.dart).
class FakeImagePicker extends ImagePickerPlatform {
  FakeImagePicker(this.path);
  final String path;
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async => XFile(path);
}
