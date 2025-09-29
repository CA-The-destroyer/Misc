# 4) Force an XFCE session (most reliable with xrdp)
sudo bash -c 'echo "startxfce4" > /home/'"$USR"'/.xsession'
sudo chown "$USR":"$USR" /home/"$USR"/.xsession
sudo chmod 0644 /home/"$USR"/.xsession

# 5) Make xrdp actually start XFCE (bypass Wayland/gnome quirks)
sudo sed -i 's/^test -r .*Xsession.*$/# disabled by setup/' /etc/xrdp/startwm.sh
sudo awk '1; END{print "startxfce4"}' /etc/xrdp/startwm.sh | sudo tee /etc/xrdp/startwm.sh >/dev/null
sudo chmod +x /etc/xrdp/startwm.sh

# 6) Kill any stuck sessions and stale auth files
sudo loginctl terminate-user "$USR" 2>/dev/null || true
sudo pkill -u "$USR" -9 2>/dev/null || true
sudo rm -f /home/"$USR"/.Xauthority /home/"$USR"/.Xwrapper /home/"$USR"/.ICEauthority 2>/dev/null || true
sudo chown -R "$USR":"$USR" /home/"$USR"

# 7) Make sure the account is usable and not locked
getent passwd "$USR" || echo "User $USR missing!"
sudo passwd -S "$USR"
# If you see 'L' (locked), unlock:
# sudo usermod -U "$USR"

# 8) Disable Wayland (GNOME displays) so xorg is used system-wide
if [ -f /etc/gdm3/custom.conf ]; then
  sudo sed -i 's/^#\?WaylandEnable=false/WaylandEnable=false/' /etc/gdm3/custom.conf
fi

# 9) Make sure hostname resolution works locally (xrdp sometimes cares)
HN=$(hostname)
grep -qE "127\.0\.1\.1\s+$HN" /etc/hosts || echo "127.0.1.1 $HN" | sudo tee -a /etc/hosts

# 10) Restart services clean
sudo systemctl restart xrdp-sesman xrdp
sudo systemctl enable xrdp
