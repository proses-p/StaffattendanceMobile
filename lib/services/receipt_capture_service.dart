import 'package:image_picker/image_picker.dart';

class ReceiptCaptureService {
  ReceiptCaptureService({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  Future<XFile?> captureFromCamera() {
    return _picker.pickImage(source: ImageSource.camera, imageQuality: 88);
  }
}
