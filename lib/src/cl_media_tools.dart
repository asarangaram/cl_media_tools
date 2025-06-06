// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:exif/exif.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_video_info/flutter_video_info.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

enum CLMediaType {
  collection,
  text,
  image,
  video,
  audio,
  file,
  uri,
  unknown;

  static CLMediaType fromMIMEType(String mimiType) {
    for (final type in CLMediaType.values) {
      if (mimiType.startsWith(type.name)) {
        return type;
      }
    }
    return CLMediaType.file;
  }
}

extension ExtIntOnString on String? {
  int? toInt() {
    if (this == null) return null;
    return int.parse(this!);
  }
}

abstract class CLMediaContent {
  const CLMediaContent();

  static bool isURL(String text) {
    try {
      final uri = Uri.parse(text);
      // Check if the scheme is non-empty to ensure it's a valid URL
      return uri.scheme.isNotEmpty;
    } catch (e) {
      return false; // Parsing failed, not a valid URL
    }
  }

  String get identity;
}

@immutable
class CLMediaText extends CLMediaContent {
  final String text;
  final CLMediaType type;
  const CLMediaText(this.text) : type = CLMediaType.text;

  @override
  String get identity => text;
}

@immutable
class CLMediaURI extends CLMediaContent {
  final Uri uri;
  final CLMediaType type;
  const CLMediaURI(this.uri) : type = CLMediaType.uri;
  @override
  String get identity => uri.toString();

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

  static String getFileName(http.Response response) {
    String? filename;

    // Check if we get file name
    if (response.headers.containsKey('content-disposition')) {
      final contentDispositionHeader = response.headers['content-disposition'];
      final match = RegExp('filename=(?:"([^"]+)"|(.*))')
          .firstMatch(contentDispositionHeader!);

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

  Future<String?> download({required Directory downloadDir}) async {
    String? filename;
    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) return null;
      filename = secureFilename(
        p.join(
          downloadDir.path,
          getFileName(response),
        ),
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

  Future<bool> get isSupportedFile async {
    final type = CLMediaType.fromMIMEType(await getMimeType(uri));
    return [
      CLMediaType.image,
      CLMediaType.video,
    ].contains(type);
  }

  Future<CLMediaFile?> toMediaFile({
    required Directory downloadDirectory,
  }) async {
    if (await isSupportedFile) {
      final path = await download(downloadDir: downloadDirectory);
      if (path != null) {
        return CLMediaFile.fromPath(path);
      }
    }
    return null;
  }
}

@immutable
class CLMediaUnknown extends CLMediaContent {
  final String path;
  final CLMediaType type;
  const CLMediaUnknown(this.path) : type = CLMediaType.unknown;

  @override
  String get identity => path;
}

@immutable
class CLMediaFile extends CLMediaContent {
  final String path;
  final String md5;
  final int fileSize;
  final String mimeType;
  final CLMediaType type;
  final String fileSuffix;
  final DateTime? createDate;
  final int? height;
  final int? width;
  final double? duration;
  const CLMediaFile({
    required this.path,
    required this.md5,
    required this.fileSize,
    required this.mimeType,
    required this.type,
    required this.fileSuffix,
    this.createDate,
    this.height,
    this.width,
    this.duration,
  });

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

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'path': path,
      'md5': md5,
      'fileSize': fileSize,
      'mimeType': mimeType,
      'type': type.name,
      'fileSuffix': fileSuffix,
      'createDate': createDate?.millisecondsSinceEpoch,
      'height': height,
      'width': width,
      'duration': duration,
    };
  }

  factory CLMediaFile.fromMap(Map<String, dynamic> map) {
    return CLMediaFile(
      path: (map['path'] ?? '') as String,
      md5: (map['md5'] ?? '') as String,
      fileSize: (map['fileSize'] ?? 0) as int,
      mimeType: (map['mimeType'] ?? '') as String,
      type: CLMediaType.values.firstWhere(
        (e) => (map['mimeType'] as String).startsWith(e.name),
        orElse: () => throw ArgumentError('Invalid MediaType: ${map['name']}'),
      ),
      fileSuffix: (map['fileSuffix'] ?? '') as String,
      createDate: map['createDate'] != null
          ? DateTime.fromMillisecondsSinceEpoch((map['createDate'] ?? 0) as int)
          : null,
      height: map['height'] != null ? map['height'] as int : null,
      width: map['width'] != null ? map['width'] as int : null,
      duration: map['duration'] != null ? map['duration'] as double : null,
    );
  }

  String toJson() => json.encode(toMap());

  factory CLMediaFile.fromJson(String source) =>
      CLMediaFile.fromMap(json.decode(source) as Map<String, dynamic>);

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

  CLMediaFile copyWith({
    String? path,
    String? md5,
    int? fileSize,
    String? mimeType,
    CLMediaType? type,
    String? fileSuffix,
    ValueGetter<DateTime?>? createDate,
    ValueGetter<int?>? height,
    ValueGetter<int?>? width,
    ValueGetter<double?>? duration,
  }) {
    return CLMediaFile(
      path: path ?? this.path,
      md5: md5 ?? this.md5,
      fileSize: fileSize ?? this.fileSize,
      mimeType: mimeType ?? this.mimeType,
      type: type ?? this.type,
      fileSuffix: fileSuffix ?? this.fileSuffix,
      createDate: createDate != null ? createDate.call() : this.createDate,
      height: height != null ? height.call() : this.height,
      width: width != null ? width.call() : this.width,
      duration: duration != null ? duration.call() : this.duration,
    );
  }

  @override
  String toString() {
    return 'CLMediaFile(path: $path, md5: $md5, fileSize: $fileSize, mimeType: $mimeType, type: $type, fileSuffix: $fileSuffix, createDate: $createDate, height: $height, width: $width, duration: $duration)';
  }

  @override
  bool operator ==(covariant CLMediaFile other) {
    if (identical(this, other)) return true;

    return other.path == path &&
        other.md5 == md5 &&
        other.fileSize == fileSize &&
        other.mimeType == mimeType &&
        other.type == type &&
        other.fileSuffix == fileSuffix &&
        other.createDate == createDate &&
        other.height == height &&
        other.width == width &&
        other.duration == duration;
  }

  @override
  int get hashCode {
    return path.hashCode ^
        md5.hashCode ^
        fileSize.hashCode ^
        mimeType.hashCode ^
        type.hashCode ^
        fileSuffix.hashCode ^
        createDate.hashCode ^
        height.hashCode ^
        width.hashCode ^
        duration.hashCode;
  }

  void deleteFile() {
    final file = File(path);
    if (file.existsSync()) {
      file.deleteSync();
    }
  }

  @override
  String get identity => path;
}
