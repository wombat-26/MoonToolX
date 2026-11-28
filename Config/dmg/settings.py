# dmgbuild-Einstellungen für das MoonToolX-DMG (aufgerufen von Tools/release.sh)
# Fenster 640 × 400 pt Inhalt mit Hintergrund, App links, Alias „Programme“ rechts, Pfeil dazwischen.
app = defines['app']
format = 'UDZO'
files = [app]
symlinks = {'Applications': '/Applications'}
icon = defines.get('volicon')
background = defines['background']

# Fenstergröße inkl. Titelleiste (32 pt) sowie Pfad- und Statusleiste (zusammen 55 pt), falls der Finder
# sie anzeigt: Der Inhaltsbereich bleibt so mindestens 400 pt hoch. Der Hintergrund ist 460 pt hoch.
window_rect = ((200, 140), (640, 487))
hide_extension = ['MoonToolX.app']
default_view = 'icon-view'
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
include_icon_view_settings = True
arrange_by = None
icon_size = 128
text_size = 13
icon_locations = {
    'MoonToolX.app': (170, 200),
    'Applications': (470, 200),
}
