# ---------- Create a pristine XRDP user + desktop ----------
set -e

# Settings (change if you like)
RDP_USER="rdpuser"

# 1) Install XRDP + XFCE and essentials
sudo apt update
sudo apt install -y xrdp xorgxrdp xfce4 xfce4-goodies dbus-x11 policykit-1 policykit-1-gnome \
                    gvfs gvfs-backends xfce4-session xfce4-terminal

# 2) Disable GNOME's built-in RDP & force Xorg (avoid fights with xrdp)
sudo systemctl disable --now gnome-remote-desktop 2>/dev/null || true
if [ -f /etc/gdm3/custom.conf ]; then
  sudo sed -i 's/^#\?WaylandEnable=.*/WaylandEnable=false/' /etc/gdm3/custom.conf
fi

# 3) Create the user if missing, with a random strong password
if ! id "$RDP_USER" >/dev/null 2>&1; then
  sudo adduser --disabled-password --gecos "" "$RDP_USER"
  RDP_PASS="$(tr -dc 'A-Za-z0-9!@#$%*' </dev/urandom | head -c 20)"
  echo "${RDP_USER}:${RDP_PASS}" | sudo chpasswd
  echo "----------------------------------------------------------------"
  echo " RDP user created:  ${RDP_USER}"
  echo " Temporary password: ${RDP_PASS}"
  echo " (Change it after first login with:  passwd ${RDP_USER})"
  echo "----------------------------------------------------------------"
else
  echo "User ${RDP_USER} already exists; leaving password unchanged."
fi

# Allow xrdp to read its certs
sudo usermod -aG ssl-cert "$RDP_USER"

# (Optional) give sudo rights — uncomment next two lines if desired
# echo "${RDP_USER} ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/90-${RDP_USER}-nopasswd >/dev/null
# sudo chmod 440 /etc/sudoers.d/90-${RDP_USER}-nopasswd

# 4) Write a clean .xsession for XFCE under dbus and a polkit agent
sudo -u "$RDP_USER" /bin/sh -c '
mkdir -p "$HOME/.config/autostart"
cat > "$HOME/.xsession" << "EOF"
#!/bin/sh
# Minimal, logged session start for XRDP + XFCE
exec >"$HOME/.xrdp-session.log" 2>&1
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
umask 022

export DESKTOP_SESSION=xfce
export XDG_CURRENT_DESKTOP=XFCE
export GDMSESSION=xfce
export XDG_SESSION_TYPE=x11

# XDG runtime dir is required by dbus/polkit
UID_CUR=`id -u`
export XDG_RUNTIME_DIR="/run/user/${UID_CUR}"
[ -d "$XDG_RUNTIME_DIR" ] || mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# Start the desktop (with fallbacks)
if command -v startxfce4 >/dev/null 2>&1; then exec dbus-launch --exit-with-session startxfce4; fi
if command -v xfce4-session >/dev/null 2>&1; then exec dbus-launch --exit-with-session xfce4-session; fi
exec xterm
EOF
chmod 0644 "$HOME/.xsession"

# Autostart a PolicyKit auth agent (some apps need it)
cat > "$HOME/.config/autostart/polkit-agent.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=PolicyKit Authentication Agent
Exec=/usr/lib/policykit-1-gnome/polkit-gnome-authentication-agent-1
OnlyShowIn=XFCE;
X-GNOME-Autostart-enabled=true
EOF
'

# 5) Permissions sanity and /tmp
HOME_DIR="$(getent passwd "$RDP_USER" | cut -d: -f6)"
sudo chown -R "$RDP_USER:$RDP_USER" "$HOME_DIR"
sudo chmod 700 "$HOME_DIR"
sudo chmod go-w "$HOME_DIR"
sudo chmod 1777 /tmp

# 6) Ensure xrdp is enabled and listening
sudo systemctl enable --now xrdp
sudo systemctl restart xrdp-sesman xrdp

# 7) Open firewall if UFW is active
if sudo ufw status | grep -q "Status: active"; then
  sudo ufw allow 3389/tcp
fi

echo "----------------------------------------------------------------"
echo "XRDP is ready."
echo "Connect using Microsoft Remote Desktop / mstsc to: <this-host>:3389"
echo "User: ${RDP_USER}"
echo "Session type: Xorg"
echo "If you changed nothing else, you should land in XFCE."
echo "If apps won't launch, check: ${HOME_DIR}/.xrdp-session.log"
echo "----------------------------------------------------------------"
# ---------- end ----------
