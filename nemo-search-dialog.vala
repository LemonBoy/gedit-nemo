namespace GeditNemoPlugin {
    class FindDialog : Gtk.Dialog {
        public Gtk.Entry search_entry;
        public Gtk.FileChooserButton sel_folder;
        public Gtk.CheckButton case_sensitive;
        public Gtk.CheckButton match_whole_word;
        public Gtk.CheckButton regex_mode;
        public Gtk.Widget search_button;

        public FindDialog (File? root) {
            build_layout ();
            setup_signals ();

            try {
                if (root != null)
                    sel_folder.set_current_folder_file (root);
            }
            catch (Error err) {
                warning (err.message);
            }
        }

        private void build_layout () {
            this.title = "Find in Files";
            this.border_width = 5;
            this.set_size_request (450, -1);

            // Use a grid to compose the layout instead of many hboxes
            var grid = new Gtk.Grid ();

            grid.set_column_spacing (12);
            grid.set_row_spacing (12);

            var search_label = new Gtk.Label.with_mnemonic ("F_ind");
            search_label.xalign = 1;
            search_label.yalign = 0.5f;
            search_entry = new Gtk.Entry ();
            search_entry.set_hexpand (true);
            // Pressing enter activates the search button
            search_entry.set_activates_default (true);
            search_label.set_mnemonic_widget (search_entry);

            var folder_label = new Gtk.Label.with_mnemonic ("_In");
            folder_label.xalign = 1;
            folder_label.yalign = 0.5f;
            sel_folder = new Gtk.FileChooserButton ("Select a _folder", Gtk.FileChooserAction.SELECT_FOLDER);
            sel_folder.set_hexpand (true);
            folder_label.set_mnemonic_widget (sel_folder);

            grid.attach (search_label, 0, 0, 1, 1);
            grid.attach_next_to (search_entry, search_label, Gtk.PositionType.RIGHT, 1, 1);
            grid.attach (folder_label, 0, 1, 1, 1);
            grid.attach_next_to (sel_folder, folder_label, Gtk.PositionType.RIGHT, 1, 1);

            // The checkboxes toggle the options
            // The option labels have been worded to match the ones in the search & replace dialog
            case_sensitive = new Gtk.CheckButton.with_mnemonic ("_Match case");
            match_whole_word = new Gtk.CheckButton.with_mnemonic ("Match _entire word only");
            regex_mode = new Gtk.CheckButton.with_mnemonic ("Re_gular expression");

            var checkbox_grid = new Gtk.Grid ();

            checkbox_grid.set_row_spacing (4);
            checkbox_grid.set_column_spacing (12);

            checkbox_grid.attach (case_sensitive, 0, 0, 1, 1);
            checkbox_grid.attach (match_whole_word, 0, 1, 1, 1);
            checkbox_grid.attach (regex_mode, 0, 2, 1, 1);

            grid.attach (checkbox_grid, 1, 2, 2, 1);

            var hbox = get_content_area () as Gtk.Box;
            hbox.pack_start (grid);

            if (Gtk.Settings.get_default ().gtk_dialogs_use_header) {
                var header_bar = new Gtk.HeaderBar ();

                header_bar.set_title ("Find in Files");
                header_bar.set_show_close_button (true);

                this.set_titlebar (header_bar);
            }
            else {
                add_button ("_Close", Gtk.ResponseType.CLOSE);
            }

            search_button = add_button ("_Find", Gtk.ResponseType.OK);

            set_default_response (Gtk.ResponseType.OK);
            set_response_sensitive (Gtk.ResponseType.OK, false);
        }

        private void setup_signals () {
            search_entry.changed.connect (() => {
                search_button.sensitive = (search_entry.text != "");
            });
        }
    }
}
