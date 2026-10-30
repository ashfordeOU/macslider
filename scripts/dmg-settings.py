# dmgbuild settings for Monorail's installer window.
# Used by scripts/package.sh:  dmgbuild -s scripts/dmg-settings.py -D app=… -D background=… "Monorail" out.dmg
import os

application = defines.get("app", "dist/Monorail.app")  # noqa: F821 (provided by dmgbuild)
appname = os.path.basename(application)

format = "UDZO"
filesystem = "HFS+"
size = None
files = [application]
symlinks = {"Applications": "/Applications"}
icon = defines.get("volume_icon")  # noqa: F821
background = defines.get("background")  # noqa: F821

# A clean icon view: no toolbar, sidebar or status bar.
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
default_view = "icon-view"
window_rect = ((200, 140), (660, 420))
icon_size = 128
text_size = 13
arrange_by = None
label_pos = "bottom"
icon_locations = {
    appname: (170, 200),
    "Applications": (490, 200),
}
