using GLib;
using Gtk;

namespace GeditNemoPlugin
{
    interface IMatcher : Object {
        public abstract bool has_match (uint8 *text, size_t text_length, ref Range match);
    }

    struct Range {
        uint from;
        uint to;
    }

    class RegexSearch : Object, IMatcher {
        private Regex re;

        public RegexSearch (string pattern, bool ignore_case) {
            try {
                if (ignore_case)
                    re = new Regex (pattern, RegexCompileFlags.CASELESS);
                else
                    re = new Regex (pattern);
            }
            catch (RegexError err) {
                critical (err.message);
            }
        }

        public bool has_match (uint8 *text, size_t text_length, ref Range match) {
            MatchInfo info;

            // Avoid strdup-ing the whole buffer
            unowned string str = (string)text;

            // Pass the text length as str isn't null terminated
            try {
                if (!re.match_full (str, (ssize_t)text_length, 0, 0, out info))
                    return false;
            }
            catch (RegexError err) {
                critical (err.message);
                return false;
            }

            info.fetch_pos (0, out match.from, out match.to);

            return true;
        }
    }

    class BoyerMooreHorspool : Object, IMatcher {
        private string pattern;
        private int bad_char_shift[256];

        public bool ignore_case;

        public BoyerMooreHorspool (string pattern_, bool ignore_case_) {
            pattern = pattern_;
            ignore_case = ignore_case_;

            for (int i = 0; i < 256; i++)
                bad_char_shift[i] = pattern.length;

            for (int i = 0; i < pattern.length - 1; i++) {
                if (ignore_case) {
                    bad_char_shift[Posix.toupper(pattern[i])] = pattern.length - 1 - i;
                    bad_char_shift[Posix.tolower(pattern[i])] = pattern.length - 1 - i;
                }
                else {
                    bad_char_shift[pattern[i]] = pattern.length - 1 - i;
                }
            }
        }

        public bool has_match (uint8 *text, size_t text_length, ref Range match) {
            uint i = 0;

            if (text_length < pattern.length)
                return false;

            while (i <= text_length - pattern.length) {
                for (int j = pattern.length - 1; j >= 0; j--) {
                    // Check for a match backwards
                    if (ignore_case) {
                        if (Posix.tolower(text[i + j]) != Posix.tolower(pattern[j]))
                            break;
                    }
                    else {
                        if (text[i + j] != pattern[j])
                            break;
                    }
                    // The whole needle has been matched!
                    if (j == 0) {
                        match.from = i;
                        match.to = i + pattern.length;
                        return true;
                    }
                }

                // Jump ahead in the buffer
                i += bad_char_shift[text[i + pattern.length - 1]];
            }

            return false;
        }
    }

    class SearchJob {
        const int THREAD_WORKERS = 5;

        public signal void on_match_found (string path, uint line);
        public signal void on_search_finished ();

        // This queue holds all the file names to scan
        private AsyncQueue<string> scan_queue = new AsyncQueue<string>();

        // The list of (hard) workers
        private Thread<int> []thread_workers;

        // This signals the workers to stop crunching data
        private bool halt_workers = false;

        // Count how many workers are still working
        private int running_workers = 0;

        private IMatcher matcher;

        public string needle { get; private set; }
        public bool include_hidden { get; set; }
        public bool match_whole_word { get; set; }

        int worker () {
            while (true) {
                // Wait 0.5 seconds
                var tv = TimeVal ();
                tv.add (1000000 / 2);

                var path = scan_queue.timed_pop (ref tv);

                // Check for interruption
                lock (halt_workers) {
                    if (halt_workers)
                        break;
                }

                // If path is null then we're probably done
                if (path == null)
                    break;

                // Scan the file
                scan_file (path);
            }

            // We're done, check if we're the last worker active and signal it to the user
            lock (running_workers) {
                if (0 == (--running_workers)) {
                    // Run the completion callback in the main thread
                    Idle.add (() => { on_search_finished (); return false; });
                }
            }

            return 0;
        }

        public SearchJob (string needle_, bool regex_match, bool ignore_case) {
            needle = needle_;
            include_hidden = false;
            match_whole_word = false;

            if (regex_match)
                matcher = new RegexSearch (needle, ignore_case);
            else
                matcher = new BoyerMooreHorspool (needle, ignore_case);
        }

        public bool start () {
            thread_workers = new Thread<int>[THREAD_WORKERS];
            for (var i = 0; i < THREAD_WORKERS; i++)
                thread_workers[i] = new Thread<int> ("Worker", worker);

            running_workers = THREAD_WORKERS;

            return true;
        }

        public void wait_for_completion () {
            lock (halt_workers) {
                halt_workers = true;
            }

            for (int i = 0; i < THREAD_WORKERS; i++)
                thread_workers[i].join();
        }

        bool is_binary (uint8 *buffer, size_t buffer_size) {
            return Posix.memchr (buffer, '\0', buffer_size) != null;
#if 0
            /* buffer[0] == 0xef && buffer[1] == 0xbb && buffer[2] == 0xbf */
            /* buffer[0] == 0xff && buffer[1] == 0xfe */
            /* buffer[0] == 0xfe && buffer[1] == 0xff */
            /* buffer[0] == 0xff && buffer[1] == 0xfe && buffer[2] == 0x00 && buffer[3] == 0x00 */
            /* buffer[0] == 0x00 && buffer[1] == 0x00 && buffer[2] == 0xfe && buffer[3] == 0xff */
#endif
        }

        public async void enqueue_dir (string path) {
            var queue = new Queue<string> ();
            var visited = new HashTable<string, int> (str_hash, str_equal);

            queue.push_tail (path);

            while (!queue.is_empty () && !halt_workers) {
                try {
                    var pew = queue.pop_head ();
                    Dir dir = Dir.open (pew);
                    string? name = null;

                    while ((name = dir.read_name()) != null && !halt_workers) {
                        if (name == "." || name == "..")
                            continue;

                        if (!include_hidden && name[0] == '.')
                            continue;

                        if (name == ".git" || name == ".svn" || name == ".hg" || name == ".bzr")
                            continue;

                        var subpath = Path.build_filename (pew, name);

                        if (FileUtils.test (subpath, FileTest.IS_SYMLINK)) {
                            var resolved_path = Posix.realpath (subpath);

                            if (resolved_path == null) {
                                critical ("Could not resolve %s", subpath);
                            }
                            else {
                                subpath = resolved_path;
                            }
                        }

                        if (visited.contains (subpath)) {
                            stdout.printf ("loop : %s\n", subpath);
                            continue;
                        }

                        if (FileUtils.test (subpath, FileTest.IS_REGULAR)) {
                            scan_queue.push (subpath);
                        }
                        else if (FileUtils.test (subpath, FileTest.IS_DIR)) {
                            visited.insert (subpath, 1);
                            queue.push_tail (subpath);
                        }
                    }
                }
                catch (FileError err) {
                    stderr.printf ("enqueue_dir failed : %s\n", err.message);
                }

                // Avoid locking up the ui
                Idle.add(enqueue_dir.callback);
                yield;
            }
        }

        struct Bookmark {
            uint line_number;
            size_t line_offset;
        }

        uint get_line (uint8 *buffer, size_t buffer_size, uint from, uint to, Bookmark bookmark) {
            // We take an advantage by knowing that all the calls to get_line are sequential, hence
            // we save the position of the last matched line and start from there
            var line_count = bookmark.line_number;
            var line_start = bookmark.line_offset;

            var ptr = buffer + line_start;

            while (true) {
                // Find the newline
                uint8 *nl = Posix.memchr (ptr, '\n', buffer_size - (ptr - buffer));

                // No more newlines, we're done
                if (nl == null)
                    return 0;

                // Skip the '\n'
                nl++;

                line_count++;

                size_t line_length = nl - ptr;

                // Check if the match is within this line
                if (from >= line_start && to < line_start + line_length) {
                    // Update the bookmark
                    bookmark.line_number = line_count;
                    bookmark.line_offset = line_start;

                    return line_count;
                }

                line_start += line_length;

                ptr = nl;
            }
        }

        bool isalnum (uint8 c) {
            return Posix.isalnum (c);
        }

        void scan_file (string path) {
            var fd = Posix.open (path, Posix.O_RDONLY);
            if (fd < 0)
                return;

            Posix.Stat st;
            if (Posix.fstat (fd, out st) < 0) {
                Posix.close (fd);
                return;
            }

            if (Posix.S_ISFIFO (st.st_mode)) {
                Posix.close (fd);
                return;
            }

            var mmap_size = st.st_size;

            var buffer = (uint8 *)Posix.mmap (null, mmap_size, Posix.PROT_READ, Posix.MAP_SHARED, fd, 0);
            if (buffer == null) {
                Posix.close (fd);
                return;
            }

            // Skip binary files for obvious reasons
            if (is_binary (buffer, mmap_size)) {
                Posix.munmap (buffer, mmap_size);
                Posix.close (fd);
                return;
            }

            Range match = { 0, 0 };
            Bookmark bookmark = { 0, 0 };
            uint mmap_pos = 0;
            while (mmap_pos < mmap_size) {
                // Exit when there's no match
                lock (matcher) {
                    if (!matcher.has_match (buffer + mmap_pos, mmap_size - mmap_pos, ref match))
                        break;
                }

                // The match info is relative to the chunk scanned
                var match_from = mmap_pos + match.from;
                var match_to = mmap_pos + match.to;

                // Check if the match lies on a word boundary
                // This works both for regex and non-regex searches, even though in the former case
                // you should really use \b
                if (match_whole_word) {
                    bool before = true;
                    bool after = true;

                    // The match is on a word boundary if there are no consecutive alphanumeric
                    // characters right before or after the match
                    if (match_from > 0)
                        before = isalnum (buffer[match_from - 1]) != isalnum (buffer[match_from]);
                    if (match_to < mmap_size)
                        after = isalnum (buffer[match_to]) != isalnum  (buffer[match_to - 1]);

                    // Ignore the match
                    if (!before || !after) {
                        mmap_pos += match.to;
                        continue;
                    }
                }

                // Find out what line the match lies in
                var match_line = get_line (buffer, mmap_size, match_from, match_to, bookmark);

                // Notify that we got a match
                on_match_found(path, match_line);

                // Keep searching past the match
                mmap_pos += match.to;
            }

            Posix.munmap(buffer, mmap_size);
            Posix.close(fd);
        }
    }

    class SearchDialog : Gtk.Window {
        public signal void response (int response_id);

        public SearchDialog () {
        }

        private Button search_button;
        private MenuButton options_button;
        private HeaderBar header_bar;
        public Entry search_entry;
        private FileChooserButton folder_chooser;

        public void set_current_location (GLib.File path) {
            var p = path.get_path ();
            if (p == null)
                return;
            folder_chooser.set_current_folder (Path.get_dirname (p));
        }

        SimpleActionGroup build_action_group () {
            var action_group = new SimpleActionGroup ();

            var toggle_case_sensitive = new SimpleAction.stateful ("toggle-case-sensitive", null,
                    new Variant.boolean (false));
            var toggle_match_whole_word = new SimpleAction.stateful ("toggle-match-whole-word", null,
                    new Variant.boolean (false));
            var toggle_regexp_mode = new SimpleAction.stateful ("toggle-regexp-mode", null,
                    new Variant.boolean (false));

            action_group.add_action (toggle_case_sensitive);
            action_group.add_action (toggle_match_whole_word);
            action_group.add_action (toggle_regexp_mode);

            return action_group;
        }

        construct {
            var outer_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 5);
            box.set_border_width (5);

            // Header bar
            header_bar = new HeaderBar ();
            header_bar.set_title ("Find in files");
            header_bar.set_subtitle ("It just works™");

            outer_box.pack_start (header_bar);

            // Search button
            search_button = new Button.from_icon_name ("edit-find-symbolic", IconSize.BUTTON);
            search_button.set_valign (Align.CENTER);
            search_button.set_tooltip_text ("eww");
            search_button.set_sensitive (false);

            search_button.clicked.connect (() => {
                response (ResponseType.OK);
                destroy ();
            });

            header_bar.pack_end (search_button);

            // Close button
            var close_button = new Button.from_icon_name ("window-close-symbolic", IconSize.BUTTON);
            close_button.set_valign (Align.CENTER);
            close_button.set_tooltip_text ("eww");

            close_button.clicked.connect (() => {
                response (ResponseType.CLOSE);
                destroy ();
            });

            header_bar.pack_end (close_button);

            // Options button
            options_button = new MenuButton ();
            options_button.set_valign (Align.CENTER);
            options_button.set_tooltip_text ("eww");
            options_button.set_image (new Image.from_icon_name ("open-menu-symbolic",
                        IconSize.BUTTON));

            header_bar.pack_start (options_button);

            // Load the action group for the option menu
            var action_group = build_action_group ();
            insert_action_group ("opt", action_group);

            // Options menu
            var builder = new Builder.from_file ("menu.ui");
            var options_menu = (MenuModel)builder.get_object ("options_menu");
            options_button.set_menu_model (options_menu);

            // Search entry
            search_entry = new Entry ();
            search_entry.set_placeholder_text ("Enter your search terms here...");

            search_entry.activate.connect (() => {
                if (search_entry.text != "") {
                    response (ResponseType.OK);
                    destroy ();
                }
            });

            search_entry.changed.connect (() => {
                search_button.sensitive = (search_entry.text != "");
            });

            box.pack_start (search_entry);

            // Folder chooser
            folder_chooser = new FileChooserButton ("...", FileChooserAction.SELECT_FOLDER);

            box.pack_start (folder_chooser);

            outer_box.pack_start (box);
            add (outer_box);

            outer_box.show_all ();

            set_size_request (300, 100);
        }
    }

    class ResultTab {
        private SearchJob job;
        private ListStore results_model;
        private Button stop_button;

        ~ResultTab () {
            job.wait_for_completion ();
        }

        public ResultTab.for_job (Stack panel, SearchJob job_) {
            results_model = new ListStore (2, typeof(string), typeof(string));
            job = job_;

            // Connect to the job signals
            job.on_match_found.connect((path, line) => {
                Idle.add (() => {
                    TreeIter iter;

                    results_model.append (out iter);
                    results_model.set (iter, 0, path, 1, line.to_string ());

                    return false;
                });
            });

            job.on_search_finished.connect (() => {
                stop_button.set_visible (false);
                job.wait_for_completion ();
            });

            // Create the ui to hold the results
            var list = new TreeView.with_model (results_model);
            list.insert_column_with_attributes (-1, "File", new CellRendererText (), "text", 0);
            list.insert_column_with_attributes (-1, "At", new CellRendererText (), "text", 1);

            // Stub the sort function for a more responsive UI under heavy loads
            results_model.set_sort_func (0, (a,b,c) => { return 0; });
            results_model.set_sort_func (1, (a,b,c) => { return 0; });

            list.row_activated.connect ((path, column) => {
                TreeIter iter;

                if (!results_model.get_iter (out iter, path))
                    return;

                Value puth;
                Value line;
                results_model.get_value (iter, 0, out puth);
                results_model.get_value (iter, 1, out line);

                stdout.printf ("%s:%s\n", (string)puth, (string)line);
            });

            // The stop button is showed in the bottom-left corner of the TreeView
            stop_button = new Button.from_icon_name ("process-stop-symbolic", IconSize.BUTTON);
            stop_button.set_tooltip_text ("Stop the search");
            stop_button.set_visible (false);
            stop_button.set_valign (Align.END);
            stop_button.set_halign (Align.END);
            stop_button.set_margin_bottom (4);
            stop_button.set_margin_end (4);

            stop_button.clicked.connect (() => {
                job.wait_for_completion ();
                stop_button.set_visible (false);
            });

            var scroll = new ScrolledWindow (null, null);
            scroll.set_policy (PolicyType.AUTOMATIC, PolicyType.AUTOMATIC);
            scroll.add (list);

            // Create the overlay containing the stop button
            var overlay = new Overlay ();
            overlay.add_overlay (stop_button);
            overlay.add (scroll);
            overlay.show_all ();

            // Create a tab in the bottom panel
            panel.add_titled (overlay, "r", "\"%s\"".printf (job.needle));
        }

        public void set_stop_sensitive () {
            stop_button.set_visible (true);
        }
    }

    public class Window : Gedit.WindowActivatable, Peas.ExtensionBase {
        public Window () {
            GLib.Object ();
        }

        public Gedit.Window window {
            owned get; construct;
        }

        ResultTab tab;

        public void activate () {
            print ("Window: activated\n");

            var act = new SimpleAction ("search-in-files", null);
            window.add_action (act);

            var d = new SearchDialog ();
            d.set_transient_for (window);
            d.response.connect ((response_id) => {
                switch (response_id) {
                    case ResponseType.CLOSE:
                        stdout.printf ("close\n");
                        break;

                    case ResponseType.OK:
                        var job = new SearchJob (d.search_entry.text, false, false);

                        var bottom_panel = window.get_bottom_panel () as Stack;
                        tab = new ResultTab.for_job (bottom_panel, job);

                        job.enqueue_dir.begin ("/usr/include", (obj, res) => { });
                        job.start ();

                        tab.set_stop_sensitive ();
                    break;
                }
            });

            d.show_all ();
        }

        public void deactivate () {
            print ("Window: deactivated\n");
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
            assert (menu_ext != null);

            var search_entry = new GLib.MenuItem ("Search in files", "win.search-in-files");
            menu_ext.append_menu_item (search_entry);
        }

        public void deactivate () {
            menu_ext.remove_items ();
        }
    }
}

[ModuleInit]
public void peas_register_types (TypeModule module)
{
    var objmodule = module as Peas.ObjectModule;

    objmodule.register_extension_type (typeof (Gedit.WindowActivatable), typeof (GeditNemoPlugin.Window));
    objmodule.register_extension_type (typeof (Gedit.AppActivatable), typeof (GeditNemoPlugin.App));
}
