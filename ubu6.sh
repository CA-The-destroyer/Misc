# ----- Make rdpuser's XRDP session rock-solid (XFCE + Firefox + Terminal) -----
USR="rdpuser"
HOME_DIR="$(getent passwd "$USR" | cut -d: -f6)"

sudo apt update
sudo apt install -y xrdp xorgxrdp xfce4 xfce4-goodies xfce4-session xfce4-terminal \
                    firefox exo-utils xdg-utils dbus-x11 policykit-1 policykit-1-gnome \
                    gvfs gvfs-backends xterm

# Ensure xrdp owns RDP port and uses Xorg (avoid Wayland weirdness)
sudo systemctl disable --now gnome-remote-desktop 2>/dev/null || true
if [ -f /etc/gdm3/custom.conf ]; then
  sudo sed -i 's/^#\?WaylandEnable=.*/WaylandEnable=false/' /etc/gdm3/custom.conf
fi

# System defaults
sudo update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/bin/xfce4-terminal.wrapper 200
sudo update-alternatives --set x-terminal-emulator /usr/bin/xfce4-terminal.wrapper
sudo update-alternatives --install /usr/bin/x-www-browser x-www-browser /usr/bin/firefox 200

# Per-user session: guaranteed XFCE with dbus and logging
sudo -u "$USR" bash -lc '
mkdir -p ~/.config/xfce4 ~/.config/autostart ~/Desktop
cat > ~/.xsession << "EOF"
#!/bin/sh
# Log session for debugging
exec >"$HOME/.xrdp-session.log" 2>&1
unset SESSION_MANAGER DBUS_SESSION_BUS_ADDRESS
umask 022
export DESKTOP_SESSION=xfce
export XDG_CURRENT_DESKTOP=XFCE
export GDMSESSION=xfce
export XDG_SESSION_TYPE=x11
UID_CUR=`id -u`
export XDG_RUNTIME_DIR="/run/user/${UID_CUR}"
[ -d "$XDG_RUNTIME_DIR" ] || mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
# Start the desktop
if command -v startxfce4 >/dev/null 2>&1; then exec dbus-launch --exit-with-session startxfce4; fi
if command -v xfce4-session >/dev/null 2>&1; then exec dbus-launch --exit-with-session xfce4-session; fi
exec xterm
EOF
chmod 0644 ~/.xsession
sed -i "s/\r$//" ~/.xsession 2>/dev/null || true

# XFCE helper defaults (survive profile resets)
cat > ~/.config/xfce4/helpers.rc <<EOF
[Helpers]
TerminalEmulator=xfce4-terminal
WebBrowser=firefox
EOF

# Ensure a polkit agent exists (some apps need it)
cat > ~/.config/autostart/polkit-agent.desktop <<EOF
[Desktop Entry]
Type=Application
Name=PolicyKit Authentication Agent
Exec=/usr/lib/policykit-1-gnome/polkit-gnome-authentication-agent-1
OnlyShowIn=XFCE;
X-GNOME-Autostart-enabled=true
EOF

# Desktop launchers for easy access
cat > ~/Desktop/Terminal.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Terminal
Exec=xfce4-terminal
Icon=utilities-terminal
Terminal=false
Categories=System;Utility;
EOF
cat > ~/Desktop/Firefox.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Firefox Web Browser
Exec=firefox
Icon=firefox
Terminal=false
Categories=Network;WebBrowser;
EOF
chmod +x ~/Desktop/Terminal.desktop ~/Desktop/Firefox.desktop
'

# MIME/URL handler defaults (belt & suspenders)
sudo -u "$USR" bash -lc '
xdg-settings set default-web-browser firefox.desktop 2>/dev/null || true
xdg-mime default firefox.desktop text/html 2>/dev/null || true
xdg-mime default firefox.desktop x-scheme-handler/http 2>/dev/null || true
xdg-mime default firefox.desktop x-scheme-handler/https 2>/dev/null || true
'

# Permissions + /tmp sanity
sudo chown -R "$USR:$USR" "$HOME_DIR"
sudo chmod 700 "$HOME_DIR"
sudo chmod go-w "$HOME_DIR"
sudo chmod 1777 /tmp

# Restart XRDP stack
sudo systemctl enable --now xrdp
sudo systemctl restart xrdp-sesman xrdp

echo "Done. RDP to this host on :3389 as '$USR' (choose Xorg)."
# -------------------------------------------------------------------------------
