import 'cl_media_tools_platform_interface.dart';

Future<String?> getPlatformVersion() {
  return ClMediaInfoExtractorPlatform.instance.getPlatformVersion();
}
