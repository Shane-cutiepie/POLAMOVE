import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Uploads driver documents to Cloudinary.
///
/// Firebase Cloud Storage requires a billing-enabled plan, which this project
/// does not have. Cloudinary's free tier covers this app's volume (three
/// photos per driver, a few hundred KB each) with no payment method required.
///
/// Uses an unsigned upload preset: the app has no server component, so
/// requests cannot be signed without embedding an API secret in the client.
/// Format and folder restrictions are configured on the preset itself — the
/// client never passes a `folder` field.
class CloudinaryService {
  static const String _cloudName = 'iqbekf86';
  static const String _uploadPreset = 'polamove_documents';
  static final Uri _endpoint =
      Uri.parse('https://api.cloudinary.com/v1_1/$_cloudName/image/upload');

  static const Duration _timeout = Duration(seconds: 30);

  /// Uploads [file] and returns its secure HTTPS URL.
  ///
  /// [publicIdHint] is a label like `'license'`, not the literal Cloudinary
  /// `public_id` — every driver's license photo would otherwise collide on
  /// the same id and overwrite the last driver's upload. A timestamp is
  /// appended so the hint stays searchable in the media library while every
  /// upload keeps its own asset.
  ///
  /// Throws [CloudinaryException] on failure — the caller decides what to do.
  static Future<String> uploadDocument(File file, {String? publicIdHint}) async {
    final request = http.MultipartRequest('POST', _endpoint)
      ..fields['upload_preset'] = _uploadPreset
      ..files.add(await http.MultipartFile.fromPath('file', file.path));

    if (publicIdHint != null) {
      request.fields['public_id'] =
          '${publicIdHint}_${DateTime.now().millisecondsSinceEpoch}';
    }

    http.StreamedResponse streamed;
    try {
      streamed = await request.send().timeout(_timeout);
    } on TimeoutException {
      throw CloudinaryException(
          'Upload timed out. Check your connection and try again.');
    } on SocketException {
      throw CloudinaryException(
          'No internet connection. Please check your network.');
    } catch (_) {
      throw CloudinaryException('Could not upload the document. Please try again.');
    }

    if (streamed.statusCode != 200) {
      throw CloudinaryException('The document upload was rejected. Please try again.');
    }

    final body = await streamed.stream.bytesToString();
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final url = json['secure_url'] as String?;
      if (url == null || url.isEmpty) throw const FormatException('missing secure_url');
      return url;
    } catch (_) {
      throw CloudinaryException('Received an unexpected response. Please try again.');
    }
  }
}

class CloudinaryException implements Exception {
  final String message;
  CloudinaryException(this.message);
  @override
  String toString() => message;
}
