# ------- hard reset XRDP session for user 'ca' -------
USR="ca"

# stop anything running for ca
sudo loginctl terminate-user "$USR" 2>/dev/null || true
sudo pkill -u "$USR" -9 2>/dev/null || true

# backup & purge per-user GUI/session state
TS=$(date +%Y%m%d_%H%M%S)
sudo -u "$USR" bash -c '
set -e
BK=~/xrdp_profile_backup_'"$TS"'
mkdir -p "$BK"

# stash problematic files/dirs
for f in ~/.Xauthority ~/.ICEauthority ~/.xsession ~/.xsession-errors ~/.xsessions-errors ~/.xinitrc; do
  [ -e "$f" ] && mv "$f" "$BK"/ || true
done
for d in ~/.config/xfce4 ~/.config/autostart ~/.config/gnome ~/.cache ~/.dbus ~/.local/share; do
  [ -e "$d" ] && mv "$d" "$BK"/ || true
done

# clean .xsession that starts XFCE via dbus
cat > ~/.xsession <<EOF
export DESKTOP_SESSION=xfce
export XDG_CURRENT_DESKTOP=XFCE
exec dbus-launch startxfce4
EOF
chmod 644 ~/.xsession
'

# ensure correct ownership and safe perms (not group/world writable)
sudo chown -R "$USR:$USR" /home/"$USR"
sudo chmod go-w /home/"$USR"

# sanity: /tmp must be 1777
sudo chmod 1777 /tmp

# make sure the needed pkgs are present
sudo apt install -y xrdp xorgxrdp xfce4 dbus-x11 policykit-1

# restart rdp stack
sudo systemctl restart xrdp-sesman xrdp
# ------- end -------
