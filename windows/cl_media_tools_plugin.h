#ifndef FLUTTER_PLUGIN_CL_MEDIA_TOOLS_PLUGIN_H_
#define FLUTTER_PLUGIN_CL_MEDIA_TOOLS_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace cl_media_tools {

class ClMediaToolsPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  ClMediaToolsPlugin();

  virtual ~ClMediaToolsPlugin();

  // Disallow copy and assign.
  ClMediaToolsPlugin(const ClMediaToolsPlugin&) = delete;
  ClMediaToolsPlugin& operator=(const ClMediaToolsPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace cl_media_tools

#endif  // FLUTTER_PLUGIN_CL_MEDIA_TOOLS_PLUGIN_H_
