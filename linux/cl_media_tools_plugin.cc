#include "include/cl_media_tools/cl_media_tools_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <sys/utsname.h>

#include <cstring>

#include "cl_media_tools_plugin_private.h"

#define CL_MEDIA_TOOLS_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), cl_media_tools_plugin_get_type(), \
                              ClMediaToolsPlugin))

struct _ClMediaToolsPlugin {
  GObject parent_instance;
};

G_DEFINE_TYPE(ClMediaToolsPlugin, cl_media_tools_plugin, g_object_get_type())

// Called when a method call is received from Flutter.
static void cl_media_tools_plugin_handle_method_call(
    ClMediaToolsPlugin* self,
    FlMethodCall* method_call) {
  g_autoptr(FlMethodResponse) response = nullptr;

  const gchar* method = fl_method_call_get_name(method_call);

  if (strcmp(method, "getPlatformVersion") == 0) {
    response = get_platform_version();
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

FlMethodResponse* get_platform_version() {
  struct utsname uname_data = {};
  uname(&uname_data);
  g_autofree gchar *version = g_strdup_printf("Linux %s", uname_data.version);
  g_autoptr(FlValue) result = fl_value_new_string(version);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static void cl_media_tools_plugin_dispose(GObject* object) {
  G_OBJECT_CLASS(cl_media_tools_plugin_parent_class)->dispose(object);
}

static void cl_media_tools_plugin_class_init(ClMediaToolsPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = cl_media_tools_plugin_dispose;
}

static void cl_media_tools_plugin_init(ClMediaToolsPlugin* self) {}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  ClMediaToolsPlugin* plugin = CL_MEDIA_TOOLS_PLUGIN(user_data);
  cl_media_tools_plugin_handle_method_call(plugin, method_call);
}

void cl_media_tools_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  ClMediaToolsPlugin* plugin = CL_MEDIA_TOOLS_PLUGIN(
      g_object_new(cl_media_tools_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "cl_media_tools",
                            FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);

  g_object_unref(plugin);
}
