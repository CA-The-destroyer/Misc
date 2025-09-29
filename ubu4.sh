# --- XRDP "apps won't launch" repair (XFCE) ---
USR="ca"    # change if needed
sudo apt update
sudo apt install -y xrdp xorgxrdp xfce4 xfce4-goodies dbus-x11 policykit-1 \
                    xfce4-session xfce4-terminal x11-apps gvfs gvfs-backends

# Ensure /tmp perms are correct (bad perms break many apps)
sudo chmod 1777 /tmp

# Disable Wayland so Xorg is used consistently
if [ -f /etc/gdm3/custom.conf ]; then
  sudo sed -i 's/^#\?WaylandEnable=.*/WaylandEnable=false/' /etc/gdm3/custom.conf
fi

# Write a clean .xsession that guarantees DBus + XFCE (logged)
sudo -u "$USR" /bin/sh -c 'cat > "$HOME/.xsession" << "EOF"
#!/bin/sh
exec >"$HOME/.xrdp-session.log" 2>&1
# minimal, robust env
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
umask 022
export DESKTOP_SESSION=xfce
export XDG_CURRENT_DESKTOP=XFCE
export GDMSESSION=xfce
export XDG_SESSION_TYPE=x11
# PATH sanity (in case shell dotfiles broke it)
[ -r /etc/environment ] && . /etc/environment
case ":$PATH:" in
  *:/usr/local/sbin:*) ;; *) PATH="$PATH:/usr/local/sbin";;
esac
case ":$PATH:" in
  *:/usr/sbin:*) ;; *) PATH="$PATH:/usr/sbin";;
esac
export PATH

# XDG runtime dir required for dbus/polkit
UID_CUR=`id -u`
export XDG_RUNTIME_DIR="/run/user/${UID_CUR}"
[ -d "$XDG_RUNTIME_DIR" ] || mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# Start XFCE under dbus; fallback to xfce4-session; final fallback xterm
if command -v startxfce4 >/dev/null 2>&1; then exec dbus-launch --exit-with-session startxfce4; fi
if command -v xfce4-session >/dev/null 2>&1; then exec dbus-launch --exit-with-session xfce4-session; fi
exec xterm
EOF
chmod 0644 "$HOME/.xsession"
sed -i "s/\r$//" "$HOME/.xsession" 2>/dev/null || true
'

# Ensure a polkit auth agent is present in the session (needed for apps that request elevation)
sudo -u "$USR" /bin/sh -c '
mkdir -p "$HOME/.config/autostart"
cat > "$HOME/.config/autostart/polkit-agent.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=PolicyKit Authentication Agent
Exec=/usr/lib/policykit-1-gnome/polkit-gnome-authentication-agent-1
OnlyShowIn=XFCE;
X-GNOME-Autostart-enabled=true
EOF
'

# Restore sane permissions
HOME_DIR="$(getent passwd "$USR" | cut -d: -f6)"
sudo chown -R "$USR:$USR" "$HOME_DIR"
sudo chmod 700 "$HOME_DIR"
sudo chmod go-w "$HOME_DIR"

# Restart XRDP
sudo systemctl restart xrdp-sesman xrdp
# --- end ---
