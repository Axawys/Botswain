#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  // Настройки рабочего стола (для отслеживания светлой/тёмной схемы).
  // Может быть nullptr, если схема GSettings недоступна (не-GNOME окружение).
  GSettings* interface_settings;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Читает системное предпочтение тёмной темы из org.gnome.desktop.interface.
static gboolean read_prefer_dark(GSettings* settings) {
  if (settings == nullptr) {
    return FALSE;
  }
  g_autofree gchar* scheme = g_settings_get_string(settings, "color-scheme");
  return g_strcmp0(scheme, "prefer-dark") == 0;
}

// Применяет системную схему к GTK: рамка окна (header bar) следует за темой.
// GTK3 не переключается в тёмную сам по себе — нужно явно выставить флаг.
static void apply_color_scheme(GSettings* settings) {
  gboolean dark = read_prefer_dark(settings);
  GtkSettings* gtk_settings = gtk_settings_get_default();
  if (gtk_settings != nullptr) {
    g_object_set(gtk_settings, "gtk-application-prefer-dark-theme", dark,
                 nullptr);
  }
}

// Живое обновление при переключении светлой/тёмной темы в системе.
static void color_scheme_changed_cb(GSettings* settings, gchar* key,
                                    gpointer user_data) {
  apply_color_scheme(settings);
}

// Создаёт GSettings для схемы рабочего стола, только если схема установлена,
// иначе возвращает nullptr (без падения на окружениях без GNOME-схем).
static GSettings* create_interface_settings() {
  GSettingsSchemaSource* source = g_settings_schema_source_get_default();
  if (source == nullptr) {
    return nullptr;
  }
  g_autoptr(GSettingsSchema) schema = g_settings_schema_source_lookup(
      source, "org.gnome.desktop.interface", TRUE);
  if (schema == nullptr ||
      !g_settings_schema_has_key(schema, "color-scheme")) {
    return nullptr;
  }
  return g_settings_new("org.gnome.desktop.interface");
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);

  // Подхватываем системную схему (светлая/тёмная) до создания виджетов, чтобы
  // рамка окна сразу отрисовалась в нужной теме, и следим за её изменением.
  self->interface_settings = create_interface_settings();
  if (self->interface_settings != nullptr) {
    apply_color_scheme(self->interface_settings);
    g_signal_connect(self->interface_settings, "changed::color-scheme",
                     G_CALLBACK(color_scheme_changed_cb), nullptr);
  }

  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "botswain");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "botswain");
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Фон под тему: тёмный в тёмной схеме, светлый в светлой — иначе при старте
  // и ресайзе мелькал бы чёрный прямоугольник поверх светлого UI.
  gboolean dark = read_prefer_dark(self->interface_settings);
  gdk_rgba_parse(&background_color, dark ? "#000000" : "#ffffff");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->interface_settings);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
