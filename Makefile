src=fif-plugin.vala  \
		fif-result-tab.vala \
		fif-dialog.vala \
		fif-job.vala \
		fif-matcher.vala
src_c=$(src:.vala=.c)
clibs=`pkg-config --cflags --libs gedit gtk+-3.0 gtksourceview-3.0 libpeas-gtk-1.0 gmodule-export-2.0`

all:
	glib-compile-resources resources.xml --target resources.c --sourcedir=. --generate-source
	valac --gresources=resources.xml --target-glib=2.38 -C $(src) --pkg gtk+-3.0 --pkg gedit --pkg PeasGtk-1.0 --pkg GtkSource-3.0 --pkg posix
	gcc -g -fPIC --shared -o libgedit-findinfiles-plugin.so resources.c $(src_c) $(clibs)
	cp libgedit-findinfiles-plugin.so findinfiles.plugin ~/.local/share/gedit/plugins/

clean:
	@rm -f libgedit-findinfiles-plugin.so resources.c $(src_c)
