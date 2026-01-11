gnome:
    gsettings set org.gnome.desktop.input-sources xkb-options "['grp:alt_shift_toggle']"
    gsettings set org.gnome.desktop.wm.keybindings switch-input-source "['<Super>space']"

    gsettings reset org.gnome.desktop.input-sources xkb-options
    gsettings set org.gnome.desktop.wm.keybindings switch-input-source "['<Super>space', '<Alt>Shift_L']"
    
    echo "QT_QPA_PLATFORMTHEME=qt5ct" >> /etc/environment

    reset:
        gsettings reset org.gnome.desktop.wm.keybindings switch-input-source
