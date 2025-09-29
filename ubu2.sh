# ------- XRDP/XFCE profile repair for user 'ca' -------
USR="ca"

# 0) sanity: not out of disk (black screens can be no-space)
df -h ~/"$USR"

# 1) stop any running session for the user
sudo loginctl terminate-user "$USR" 2>/dev/null || true
sudo pkill -u "$USR" -9 2>/dev/null || true

# 2) backup suspicious files/dirs, then reset clean session bits
TS=$(date +%Y%m%d_%H%M%S)
sudo -u "$USR" bash -c '
set -e
BK=~/xrdp_profile_backup_'"$TS"'
mkdir -p "$BK"

# backup files if present
for f in ~/.Xauthority ~/.ICEauthority ~/.xsession ~/.xsession-errors ~/.xinitrc ~/.Xresources ~/.xsessions-errors; do
  [ -e "$f" ] && cp -a "$f" "$BK"/ || true
done

# backup and clear problematic config dirs
for d in ~/.cache ~/.config/xfce4 ~/.config/autostart ~/.config/gnome ~/.config/gnome-session ~/.dbus; do
  [ -d "$d" ] && mv "$d" "$BK"/ || true
done

# write a clean xsession that guarantees DBus + XFCE
cat > ~/.xsession <<EOF
export DESKTOP_SESSION=xfce
export XDG_CURRENT_DESKTOP=XFCE
export GNOME_SHELL_SESSION_MODE=
exec dbus-launch startxfce4
EOF
chmod 644 ~/.xsession
'

# 3) make sure the user is unlocked and has a valid shell
sudo usermod -U "$USR" 2>/dev/null || true
sudo chsh -s /bin/bash "$USR"

# 4) ensure ownership of home is correct
sudo chown -R "$USR":"$USR" /home/"$USR"

# 5) (optional) copy a known-good XFCE profile from testuser if you want
# sudo -u "$USR" bash -c 'mkdir -p ~/.config && cp -a /home/testuser/.config/xfce4 ~/.config/ 2>/dev/null || true'

# 6) restart xrdp stack
sudo systemctl restart xrdp-sesman xrdp
# ------- end -------
