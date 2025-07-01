// ignore_for_file: public_member_api_docs, sort_constructors_first

import 'dart:io';
import 'package:cl_basic_types/cl_basic_types.dart';

import 'package:crypto/crypto.dart' as crypto;
import 'package:exif/exif.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_video_info/flutter_video_info.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

class CLMediaFileUtils {
  static bool isURL(String text) {
    try {
      final uri = Uri.parse(text);
      // Check if the scheme is non-empty to ensure it's a valid URL
      return uri.scheme.isNotEmpty;
    } catch (e) {
      return false; // Parsing failed, not a valid URL
    }
  }

  static Future<CLMediaFile?> fromExifInfo(Map<String, dynamic> map) async {
    try {
      final exifmap = map['exiftool'][0];
      final createDateString = map['CreateDate'] as String?;
      final offsetString = map['OffsetTime'] as String?;

      return CLMediaFile(
        path: exifmap['SourceFile'] as String,
        md5: await checksum(File(exifmap['SourceFile'] as String)),
        fileSize: exifmap['FileSize'] as int,
        mimeType: exifmap['MIMEType'] as String,
        type: CLMediaType.fromMIMEType(exifmap['MIMEType'] as String),
        fileSuffix:
            ".${(exifmap['FileTypeExtension'] as String).toLowerCase()}",
        createDate: parseCreateDate(createDateString, offsetString),
        height: exifmap['ImageHeight'] as int,
        width: exifmap['ImageWidth'] as int,
        duration:
            exifmap['Duration'] != null ? exifmap['Duration'] as double : null,
      );
    } catch (e) {
      debugPrint("Error parsing exif info: $e");
      return null;
    }
  }

  static DateTime? parseCreateDate(
      String? createDateString, String? offsetString) {
    if (createDateString == "0000:00:00 00:00:00") {
      createDateString = null;
    }

    if (createDateString == null) return null;

    final dateTimeList = createDateString.split(' ');
    final dateString = dateTimeList[0].replaceAll(":", "-");
    final timeString = dateTimeList[1];

    final createDateStringCorrected = [dateString, timeString].join('T');

    final isoString = offsetString != null
        ? "$createDateStringCorrected$offsetString"
        : createDateStringCorrected; // no offset → local time

    final dateTime = DateTime.parse(isoString);
    return dateTime;
  }

  // fix_me: use filetype and implement specific md5 computation
  static Future<String> checksum(File file) async {
    try {
      final stream = file.openRead();
      final hash = await crypto.md5.bind(stream).first;

      // NOTE: You might not need to convert it to base64
      return hash.toString();
    } catch (exception) {
      throw Exception('unable to determine md5');
    }
  }

  static Future<CLMediaFile?> fromPath(
    String mediaPath, {
    String exiftoolPath = "/usr/local/bin/exiftool",
  }) async {
    // Not available on mobile
    /* final exifinfo = await ClMediaInfoExtractorPlatform.instance
        .getMediaInfo(exiftoolPath, mediaPath); */

    // Not providing createDate
    //final MediaInfo info = await VideoCompress.getMediaInfo(mediaPath);
    final mime = lookupMimeType(mediaPath);
    if (mime == null) {
      throw Exception("Failed to get mime");
    }
    if (mime.startsWith('video')) {
      final info = await FlutterVideoInfo().getVideoInfo(mediaPath);
      if (info == null) {
        throw Exception("Failed to get videoInfo");
      }
      final createDateString = info.date;
      final offsetString = null;
      var extension = extensionFromMime(mime);
      if (extension != null && !extension.startsWith('.')) {
        extension = ".$extension";
      }
      final videoInfo = <String, dynamic>{
        'path': info.path,
        'md5': await checksum(File(mediaPath)),
        'fileSize': info.filesize,
        'mimeType': info.mimetype,
        'fileSuffix': extension,
        'createDate': parseCreateDate(createDateString, offsetString)
            ?.millisecondsSinceEpoch,
        'height': info.height,
        'width': info.width,
        'duration': info.duration,
      };

      return CLMediaFile.fromMap(videoInfo);
    } else if (mime.startsWith('image')) {
      final fileBytes = File(mediaPath).readAsBytesSync();
      final exifInfo = await readExifFromBytes(fileBytes);
      final stat = await File(mediaPath).stat();
      /* for (final entry in exifInfo.entries) {
        print("${entry.key}: ${entry.value}");
      } */

      // FIXME! Why exif becomes empty?
      /* if (exifInfo.isEmpty) {
        throw Exception("No EXIF information found");
      } */

      if (exifInfo.containsKey('JPEGThumbnail')) {
        exifInfo.remove('JPEGThumbnail');
      }
      if (exifInfo.containsKey('TIFFThumbnail')) {
        exifInfo.remove('TIFFThumbnail');
      }
      final createDateString = exifInfo['EXIF DateTimeOriginal']?.printable;
      final offsetString = exifInfo['EXIF OffsetTimeOriginal']?.printable;

      var extension = extensionFromMime(mime);
      if (extension != null && !extension.startsWith('.')) {
        extension = ".$extension";
      }
      final imageInfo = <String, dynamic>{
        'path': mediaPath,
        'md5': await checksum(File(mediaPath)),
        'fileSize': stat.size,
        'mimeType': mime,
        'fileSuffix': extension,
        'createDate': parseCreateDate(createDateString, offsetString)
            ?.millisecondsSinceEpoch,
        'height': exifInfo['EXIF ExifImageLength']?.printable.toInt(),
        'width': exifInfo['EXIF ExifImageWidth']?.printable.toInt(),
        'duration': null,
      };

      return CLMediaFile.fromMap(imageInfo);
    }
    throw Exception("Unsupported file");
  }

  static Future<String> getMimeType(Uri uri) async {
    try {
      final response = await http.head(uri);

      if (response.headers.containsKey('content-type')) {
        return response.headers['content-type']!;
      }
    } catch (e) {
      /** */
    }
    return 'application/octet-stream'; // Default MIME type
  }

  static Future<bool> isSupportedUri(CLMediaURI uri) async {
    final type = CLMediaType.fromMIMEType(await getMimeType(uri.uri));
    return [CLMediaType.image, CLMediaType.video].contains(type);
  }

  static String getFileName(http.Response response) {
    String? filename;

    // Check if we get file name
    if (response.headers.containsKey('content-disposition')) {
      final contentDispositionHeader = response.headers['content-disposition'];
      final match = RegExp(
        'filename=(?:"([^"]+)"|(.*))',
      ).firstMatch(contentDispositionHeader!);

      filename = match?[1] ?? match?[2];
    }
    filename = filename ?? '${DateTime.now().millisecondsSinceEpoch}_tmp';
    if (p.extension(filename).isEmpty) {
      // If no extension found, add extension if possible
      // Parse the Content-Type header to determine the file extension
      final mediaType = MediaType.parse(response.headers['content-type'] ?? '');

      final fileExtension = mediaType.subtype;
      filename = '$filename.$fileExtension';
    }
    return filename;
  }

  static String secureFilename(String fullPath) {
    // Check if the file already exists
    if (!File(fullPath).existsSync()) {
      return fullPath; // If file doesn't exist, return original full path
    }

    final directory = Directory(p.dirname(fullPath));
    final fileName = p.basenameWithoutExtension(fullPath);
    final extension = p.extension(fullPath);

    var index = 1;
    String newFileName;
    do {
      newFileName = '$fileName-$index$extension';
      index++;
    } while (File('${directory.path}/$newFileName').existsSync());

    return '${directory.path}/$newFileName';
  }

  static Future<String?> download(CLMediaURI uri,
      {required Directory downloadDir}) async {
    String? filename;
    try {
      final response = await http.get(uri.uri);
      if (response.statusCode != 200) return null;
      filename = secureFilename(
        p.join(downloadDir.path, getFileName(response)),
      );

      File(filename)
        ..createSync(recursive: true)
        ..writeAsBytesSync(response.bodyBytes);
      return filename;
    } catch (e) {
      if (filename != null) {
        final file = File(filename);
        if (file.existsSync()) {
          file.deleteSync();
        }
      }
      return null;
    }
  }

  static Future<CLMediaFile?> uriToMediaFile(
    CLMediaURI uri, {
    required Directory downloadDirectory,
  }) async {
    if (await CLMediaFileUtils.isSupportedUri(uri)) {
      final path =
          await CLMediaFileUtils.download(uri, downloadDir: downloadDirectory);
      if (path != null) {
        return CLMediaFileUtils.fromPath(path);
      }
    }
    return null;
  }
}
