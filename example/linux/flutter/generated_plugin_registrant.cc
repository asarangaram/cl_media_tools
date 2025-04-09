//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <cl_media_tools/cl_media_tools_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) cl_media_tools_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "ClMediaToolsPlugin");
  cl_media_tools_plugin_register_with_registrar(cl_media_tools_registrar);
}
