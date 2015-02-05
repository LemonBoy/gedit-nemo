using GLib;

namespace GeditNemoPlugin
{
    public class Window : Gedit.WindowActivatable, Peas.ExtensionBase {
        public Window () {
            GLib.Object ();
        }

        public Gedit.Window window {
            owned get; construct;
        }

        File? get_file_browser_root () {
            var bus = window.get_message_bus ();

            if (bus.is_registered ("/plugins/filebrowser", "get_root")) {
                var msg = Object.new (bus.lookup ("/plugins/filebrowser", "get_root"),
                                      "method", "get_root",
                                      "object_path", "/plugins/filebrowser");

                bus.send_message_sync (msg as Gedit.Message);

                Value val = Value (typeof (Object));
                msg.get_property ("location", ref val);

                return val.dup_object () as File;
            }

            return null;
        }

        void dialog_run () {
            var active_doc = window.get_active_document ();

            // Use the filebrowser root as starting folder, if possible.
            var root = get_file_browser_root ();

            // If that's not possible try to use the current document folder.
            if (root == null) {
                var location = active_doc.get_file ().get_location ();
                if (location != null)
                    root = location.get_parent ();
            }

            // Fall back to the user's root if none of the methods were successfully
            if (root == null)
                root = File.new_for_path (Environment.get_home_dir ());

            var dialog = new FindDialog (root);

            dialog.set_transient_for (window);
            dialog.set_destroy_with_parent (true);

            // Grab the selection and use it as search query
            Gtk.TextIter start, end;
            if (active_doc.get_selection_bounds (out start, out end)) {
                var selection = active_doc.get_text (start, end, true);

                dialog.search_entry.text = Gtk.SourceUtils.escape_search_text (selection);
            }

            dialog.response.connect ((response_id) => {
                switch (response_id) {
                    case Gtk.ResponseType.CLOSE:
                        dialog.destroy ();
                        break;

                    case Gtk.ResponseType.OK:
                        var search_text = dialog.search_entry.text;
                        var search_path = dialog.sel_folder.get_filename ();

                        // Make sure there's no other search with the same parameters
                        var panel = (Gtk.Stack)window.get_bottom_panel ();
                        var child = panel.get_child_by_name ("find-in-files");
                        if (child != null)
                            child.destroy ();

                        // Setup the job parameters
                        var cancellable = new Cancellable ();
                        var job = new FindJob (cancellable);

                        job.ignore_case = !dialog.case_sensitive.active;
                        job.match_whole_word = dialog.match_whole_word.active;

                        try {
                            job.prepare (dialog.search_entry.text, dialog.regex_mode.active);
                            job.execute.begin (search_path);
                        }
                        catch (Error err) {
                            warning (err.message);
                            dialog.destroy ();
                            return;
                        }

                        // Prepare the tab to hold the results
                        var result_tab = new ResultTab.for_job (job, search_path, window);

                        panel.add_titled (result_tab, "find-in-files", "\"%s\"".printf(search_text));

                        result_tab.show_all ();

                        // Make the panel visible
                        panel.set_visible (true);

                        // Focus the new search tab
                        panel.set_visible_child_name ("find-in-files");

                        result_tab.toggle_stop_button (true);
                        result_tab.grab_focus ();

                        dialog.destroy ();
                        break;
                }
            });

            dialog.show_all ();
        }

        public void activate () {
            var act = new SimpleAction ("find-in-files", null);
            window.add_action (act);
            act.activate.connect (dialog_run);
       }

        public void deactivate () {
        }

        public void update_state () {
        }
    }

    public class App : GLib.Object, Gedit.AppActivatable {
        private Gedit.MenuExtension? menu_ext = null;

        public App () {
            GLib.Object ();
        }

        public Gedit.App app {
            owned get; construct;
        }

        public void activate () {
            menu_ext = extend_menu ("search-section");

            var item = new GLib.MenuItem ("Find in Files...", "win.find-in-files");
            menu_ext.append_menu_item (item);

            app.add_accelerator ("<Shift><Ctrl>f", "win.find-in-files", null);
        }

        public void deactivate () {
            menu_ext.remove_items ();

            app.remove_accelerator ("win.find-in-files", null);
        }
    }
}

[ModuleInit]
public void peas_register_types (TypeModule module)
{
    var objmodule = module as Peas.ObjectModule;

    objmodule.register_extension_type (typeof (Gedit.WindowActivatable),
                                       typeof (GeditNemoPlugin.Window));
    objmodule.register_extension_type (typeof (Gedit.AppActivatable),
                                       typeof (GeditNemoPlugin.App));
}
