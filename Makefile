all:
	valac --target-glib=2.32 -C gedit-nemo-plugin.vala --pkg gtk+-3.0 --pkg gedit --pkg PeasGtk-1.0 --pkg GtkSource-3.0 --pkg posix
	gcc -g -fPIC --shared -o libgedit-nemo-plugin.so gedit-nemo-plugin.c `pkg-config --cflags --libs gedit gtk+-3.0 gtksourceview-3.0 libpeas-gtk-1.0`
	cp libgedit-nemo-plugin.so gedit-nemo.plugin ~/.local/share/gedit/plugins/
