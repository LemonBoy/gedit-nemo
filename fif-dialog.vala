/*
* Copyright (C) 2015 The Lemon Mank
*
* This program is free software; you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation; either version 2, or (at your option)
* any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with this program; if not, write to the Free Software
* Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
*/

namespace GeditFindInFilesPlugin {
    [GtkTemplate (ui = "/org/gnome/gedit/ui/dialog.ui")]
    class FindDialog : Gtk.Dialog {
        public Gtk.Entry search_entry;
        public Gtk.FileChooserButton sel_folder;
        [GtkChild]
        public Gtk.CheckButton match_case_checkbutton;
        [GtkChild]
        public Gtk.CheckButton entire_word_checkbutton;
        [GtkChild]
        public Gtk.CheckButton regex_checkbutton;
        [GtkChild]
        public Gtk.Widget find_button;
        [GtkChild]
        Gtk.Grid grid;
        [GtkChild]
        Gtk.Label search_label;
        [GtkChild]
        Gtk.Label folder_label;

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
            search_entry = new Gtk.Entry ();
            search_entry.set_size_request (300, -1);
            search_entry.set_hexpand (true);
            search_entry.set_activates_default (true);
            grid.attach_next_to (search_entry, search_label, Gtk.PositionType.RIGHT, 1, 1);

            sel_folder = new Gtk.FileChooserButton ("Select a _folder", Gtk.FileChooserAction.SELECT_FOLDER);
            sel_folder.set_hexpand (true);
            grid.attach_next_to (sel_folder, folder_label, Gtk.PositionType.RIGHT, 1, 1);

            search_label.set_mnemonic_widget (search_entry);
            folder_label.set_mnemonic_widget (sel_folder);

            set_default_response (Gtk.ResponseType.OK);
            set_response_sensitive (Gtk.ResponseType.OK, false);

            if (Gtk.Settings.get_default ().gtk_dialogs_use_header) {
                var header_bar = new Gtk.HeaderBar ();

                header_bar.set_title ("Find in Files");
                header_bar.set_show_close_button (true);

                this.set_titlebar (header_bar);
            }
            else {
                add_button ("_Close", Gtk.ResponseType.CLOSE);
            }
        }

        private void setup_signals () {
            search_entry.changed.connect (() => {
                find_button.sensitive = (search_entry.text != "");
            });
        }
    }
}
