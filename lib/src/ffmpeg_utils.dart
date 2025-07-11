// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:mime/mime.dart';
import 'package:video_compress/video_compress.dart';

import 'cl_media_tools_platform_interface.dart';

@immutable
class FFProbeInfo {
  const FFProbeInfo({
    this.frameCount = 0.0,
  });
  final double frameCount;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'frameCount': frameCount,
    };
  }

  factory FFProbeInfo.fromMap(Map<String, dynamic> map) {
    return FFProbeInfo(
      frameCount: (map['frameCount'] ?? 0.0) as double,
    );
  }

  String toJson() => json.encode(toMap());

  factory FFProbeInfo.fromJson(String source) =>
      FFProbeInfo.fromMap(json.decode(source) as Map<String, dynamic>);

  FFProbeInfo copyWith({
    double? frameCount,
  }) {
    return FFProbeInfo(
      frameCount: frameCount ?? this.frameCount,
    );
  }

  @override
  String toString() => 'FFProbeInfo(frameCount: $frameCount)';

  @override
  bool operator ==(covariant FFProbeInfo other) {
    if (identical(this, other)) return true;

    return other.frameCount == frameCount;
  }

  @override
  int get hashCode => frameCount.hashCode;
}

class FfmpegUtils {
  static String ffprobePath = "/usr/local/bin/ffprobe";

  /// FIXME: Keeping this script for debugging, with hard path. Remove ASAP
  static String ffmpegPath =
      '/Users/anandasarangaram/Work/tools/ffmpeg.sh'; //"/usr/local/bin/ffmpeg";

  static Future<FFProbeInfo> ffprobe(String path) async {
    final ffprobeInfo =
        await ClMediaInfoExtractorPlatform.instance.ffprobe(ffprobePath, path);

    double frameCount = 0.0;
    if (ffprobeInfo.keys.contains('ffprobeVideo') &&
        (ffprobeInfo['ffprobeVideo'] as Map<String, dynamic>)
            .containsKey('streams')) {
      final videoProbe =
          ffprobeInfo['ffprobeVideo']['streams'][0] as Map<String, dynamic>;

      final rFrameRate = videoProbe['r_frame_rate'] ?? 0;
      final duration = double.parse(videoProbe['duration'] as String? ?? "0.0");
      double fps = 0.0;
      if (rFrameRate != null) {
        final fpsSplit = rFrameRate.split('/');
        fps = double.parse(fpsSplit[0]) / double.parse(fpsSplit[1]);
      }
      frameCount = duration * fps;
    }

    return FFProbeInfo(frameCount: frameCount);
  }

  static Future<String> generatePreview(String mediaPath,
      {required String previewPath, int dimension = 256}) async {
    if (!File(mediaPath).existsSync()) {
      throw Exception("Media file not copied!");
    }
    if (Platform.isMacOS) {
      final ffProbeInfo = await FfmpegUtils.ffprobe(mediaPath);
      final tileSize = _computeTileSize(ffProbeInfo.frameCount);
      final frameFreq =
          (ffProbeInfo.frameCount / (tileSize * tileSize)).floor();

      final preview = await ClMediaInfoExtractorPlatform.instance
          .ffmpegGeneratePreview(ffmpegPath, mediaPath,
              previewPath: previewPath,
              frameFreq: frameFreq == 0 ? 1 : frameFreq,
              dimension: 256,
              tileSize: tileSize);
      return preview;
    } else {
      final mime = lookupMimeType(mediaPath);
      if (mime == null) {
        throw Exception("Failed to get mime");
      }
      if (mime.startsWith('video')) {
        final thumbnailFile = await VideoCompress.getFileThumbnail(mediaPath,
            quality: 50, // default(100)
            position: -1 // default(-1)
            );
        if (thumbnailFile.existsSync()) {
          thumbnailFile.copySync(previewPath);
          thumbnailFile.deleteSync();
        }
        return previewPath;
      } else if (mime.startsWith('image')) {
        final file = File(mediaPath);
        final bytes = await file.readAsBytes();

        final originalImage = img.decodeImage(bytes);
        if (originalImage == null) {
          throw Exception("Failed to decode image");
        }

        final resized = img.copyResize(
          originalImage,
          width: 256,
        );
        final resizedBytes = img.encodeJpg(resized, quality: 90);
        await File(previewPath).writeAsBytes(resizedBytes);
        return previewPath;
      }
    }
    throw Exception("Unsupported file");
  }

  static int _computeTileSize(double frameCount) {
    if (frameCount >= 16) {
      return 4;
    } else if (frameCount >= 9) {
      return 3;
    } else if (frameCount >= 4) {
      return 2;
    } else {
      return 1;
    }
  }
}
