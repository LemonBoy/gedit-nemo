src=nemo-search-dialog.vala  \
		nemo-search-matcher.vala \
		nemo-results-tab.vala    \
		nemo-search-job.vala     \
		gedit-nemo-plugin.vala
src_c=$(src:.vala=.c)
clibs=`pkg-config --cflags --libs gedit gtk+-3.0 gtksourceview-3.0 libpeas-gtk-1.0`

all:
	valac --target-glib=2.32 -C $(src) --pkg gtk+-3.0 --pkg gedit --pkg PeasGtk-1.0 --pkg GtkSource-3.0 --pkg posix
	gcc -g -fPIC --shared -o libgedit-nemo-plugin.so $(src_c) $(clibs)
	cp libgedit-nemo-plugin.so gedit-nemo.plugin ~/.local/share/gedit/plugins/

clean:
	@rm -f libgedit-nemo-plugin.so
	@rm -f $(src_c)
