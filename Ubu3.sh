# ---------- XRDP instant-logout fix for user 'ca' ----------
USR="ca"
HOME_DIR="$(getent passwd "$USR" | cut -d: -f6)"

# 0) stop any running sessions
sudo loginctl terminate-user "$USR" 2>/dev/null || true
sudo pkill -u "$USR" -9 2>/dev/null || true

# 1) ensure required packages
sudo apt update
sudo apt install -y xrdp xorgxrdp xfce4 xfce4-goodies dbus-x11 policykit-1

# 2) restore a sane startwm.sh that respects ~/.xsession and falls back to XFCE
sudo tee /etc/xrdp/startwm.sh >/dev/null <<'EOS'
#!/bin/sh
# XRDP start script: prefer per-user .xsession, else start XFCE, else xterm

# 1) If the user has an .xsession, run it
if [ -r "$HOME/.xsession" ]; then
  exec /bin/sh "$HOME/.xsession"
fi

# 2) Minimal environment for desktop sessions
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XDG_SESSION_TYPE=x11
export DESKTOP_SESSION=xfce
export XDG_CURRENT_DESKTOP=XFCE
export GDMSESSION=xfce

# 3) Make sure runtime dir exists
UID_CUR=`id -u`
export XDG_RUNTIME_DIR="/run/user/${UID_CUR}"
[ -d "$XDG_RUNTIME_DIR" ] || mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# 4) Start XFCE via dbus; fall back to xfce4-session; final fallback xterm
if command -v startxfce4 >/dev/null 2>&1; then exec dbus-launch --exit-with-session startxfce4; fi
if command -v xfce4-session >/dev/null 2>&1; then exec dbus-launch --exit-with-session xfce4-session; fi
exec xterm
EOS
sudo chmod +x /etc/xrdp/startwm.sh

# 3) write a clean .xsession for 'ca' (logged, no bashisms)
sudo -u "$USR" /bin/sh -c 'cat > "$HOME/.xsession" << "EOF"
#!/bin/sh
# Log the session to troubleshoot instant exits
exec >"$HOME/.xrdp-session.log" 2>&1
set -e
umask 022
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export DESKTOP_SESSION=xfce
export XDG_CURRENT_DESKTOP=XFCE
export GDMSESSION=xfce
export XDG_SESSION_TYPE=x11
UID_CUR=`id -u`
export XDG_RUNTIME_DIR="/run/user/${UID_CUR}"
[ -d "$XDG_RUNTIME_DIR" ] || mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
# start desktop
if command -v startxfce4 >/dev/null 2>&1; then exec dbus-launch --exit-with-session startxfce4; fi
if command -v xfce4-session >/dev/null 2>&1; then exec dbus-launch --exit-with-session xfce4-session; fi
exec xterm
EOF
chmod 0644 "$HOME/.xsession"
sed -i "s/\r$//" "$HOME/.xsession" 2>/dev/null || true
'

# 4) guard your ~/.bashrc and ~/.profile from killing XRDP sessions
#    (common: custom lines like 'exit' or 'logout' for non-SSH shells)
for f in "$HOME_DIR/.bashrc" "$HOME_DIR/.profile"; do
  if [ -f "$f" ]; then
    sudo sed -i \
      -e 's/^\s*exit\s*$/# exit (disabled for XRDP)/' \
      -e 's/^\s*logout\s*$/# logout (disabled for XRDP)/' \
      "$f"
  fi
done

# 5) permissions sanity
sudo chown -R "$USR:$USR" "$HOME_DIR"
sudo chmod 700 "$HOME_DIR"
sudo chmod go-w "$HOME_DIR"
sudo rm -f "$HOME_DIR/.Xauthority" "$HOME_DIR/.ICEauthority" 2>/dev/null || true
sudo chmod 1777 /tmp

# 6) force GNOME to Xorg (Wayland can confuse xrdp)
if [ -f /etc/gdm3/custom.conf ]; then
  sudo sed -i 's/^#\?WaylandEnable=.*/WaylandEnable=false/' /etc/gdm3/custom.conf
fi

# 7) restart services
sudo systemctl restart xrdp-sesman xrdp
# ---------- end ----------
