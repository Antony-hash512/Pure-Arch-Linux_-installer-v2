gnome:
    gsettings set org.gnome.desktop.input-sources xkb-options "['grp:alt_shift_toggle']"
    gsettings set org.gnome.desktop.wm.keybindings switch-input-source "['<Super>space']"

    gsettings reset org.gnome.desktop.input-sources xkb-options
    gsettings set org.gnome.desktop.wm.keybindings switch-input-source "['<Super>space', '<Alt>Shift_L']"


    reset:
        gsettings reset org.gnome.desktop.wm.keybindings switch-input-source
