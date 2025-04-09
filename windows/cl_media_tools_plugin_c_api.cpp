#include "include/cl_media_tools/cl_media_tools_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "cl_media_tools_plugin.h"

void ClMediaToolsPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  cl_media_tools::ClMediaToolsPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
