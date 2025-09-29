# -------- Fix "black screen" for user 'ca' on xrdp + XFCE --------
set -euo pipefail
USR="ca"
HOME_DIR="$(getent passwd "$USR" | cut -d: -f6)"
if [ -z "${HOME_DIR:-}" ] || [ ! -d "$HOME_DIR" ]; then
  echo "User $USR home not found. getent says: '$HOME_DIR'"; exit 1
fi

echo "Using HOME=$HOME_DIR"

# 1) Stop any running session for the user
sudo loginctl terminate-user "$USR" 2>/dev/null || true
sudo pkill -u "$USR" -9 2>/dev/null || true

# 2) Make sure required packages exist
sudo apt update
sudo apt install -y xrdp xorgxrdp xfce4 xfce4-goodies dbus-x11 policykit-1

# 3) Ensure Xorg is accessible (not strictly required, but helps on some builds)
echo "allowed_users=anybody" | sudo tee /etc/X11/Xwrapper.config >/dev/null || true

# 4) Disable GNOME Wayland globally so xrdp uses Xorg reliably
if [ -f /etc/gdm3/custom.conf ]; then
  sudo sed -i 's/^#\?WaylandEnable=.*/WaylandEnable=false/' /etc/gdm3/custom.conf
fi

# 5) Backup & purge per-user GUI/session state
TS="$(date +%Y%m%d_%H%M%S)"
sudo -u "$USR" bash -lc '
set -e
BK="$HOME/xrdp_profile_backup_'"$TS"'"
mkdir -p "$BK"

for f in ~/.Xauthority ~/.ICEauthority ~/.xsession ~/.xsession-errors ~/.xsessions-errors ~/.xinitrc ~/.Xresources ~/.profile ~/.bash_profile; do
  [ -e "$f" ] && cp -a "$f" "$BK"/ && rm -f "$f" || true
done
for d in ~/.config/xfce4 ~/.config/autostart ~/.config/gnome ~/.cache ~/.dbus ~/.local/share/xfce4-session ~/.config/pulse; do
  [ -e "$d" ] && mv "$d" "$BK"/ || true
done

# Write a clean, logged .xsession with DBus + XFCE (and fallbacks)
cat > ~/.xsession << "EOF"
#!/bin/sh
# Log everything from this session start
exec >"$HOME/.xrdp-session.log" 2>&1
set -x
umask 022

# Clean env that can confuse session startup
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

export DESKTOP_SESSION=xfce
export XDG_CURRENT_DESKTOP=XFCE
export GDMSESSION=xfce
export XDG_SESSION_TYPE=x11

# Ensure runtime dir exists with proper perms
UID_CUR="$(id -u)"
export XDG_RUNTIME_DIR="/run/user/${UID_CUR}"
[ -d "$XDG_RUNTIME_DIR" ] || mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# Start XFCE via dbus; fallback to xfce4-session; final fallback xterm
command -v startxfce4 >/dev/null 2>&1 && exec dbus-launch --exit-with-session startxfce4
command -v xfce4-session >/dev/null 2>&1 && exec dbus-launch --exit-with-session xfce4-session
exec xterm
EOF

chmod 0644 ~/.xsession

# Convert potential CRLF to LF (if edited from Windows)
sed -i "s/\r$//" ~/.xsession
'

# 6) Ownership & permissions
sudo chown -R "$USR:$USR" "$HOME_DIR"
sudo chmod 700 "$HOME_DIR"
sudo chmod go-w "$HOME_DIR"

# 7) Sanity: /tmp must be 1777
sudo chmod 1777 /tmp

# 8) Restart xrdp cleanly
sudo systemctl restart xrdp-sesman xrdp
sudo systemctl enable xrdp >/dev/null 2>&1 || true

echo "Done. Reconnect via RDP (Xorg) as $USR. If black screen persists, read $HOME_DIR/.xrdp-session.log"
# -------- end --------
