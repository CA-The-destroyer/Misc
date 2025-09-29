USR="rdpuser"

# 0) Stop any running session for safety
sudo loginctl terminate-user "$USR" 2>/dev/null || true
sudo pkill -u "$USR" -9 2>/dev/null || true

# 1) Minimal .xsession that cannot crash (xterm only)
sudo -u "$USR" bash -lc 'cat > ~/.xsession << "EOF"
#!/bin/sh
exec >"$HOME/.xrdp-session.log" 2>&1
exec xterm
EOF
chmod 0755 ~/.xsession
sed -i "s/\r$//" ~/.xsession 2>/dev/null || true
'

# 2) Make sure startwm.sh defers to user's .xsession
sudo tee /etc/xrdp/startwm.sh >/dev/null <<'EOS'
#!/bin/sh
# Prefer user's .xsession; if missing, fall back to xterm
if [ -r "$HOME/.xsession" ]; then
  exec /bin/sh "$HOME/.xsession"
fi
exec xterm
EOS
sudo chmod +x /etc/xrdp/startwm.sh

# 3) Perms sanity so nothing blocks startup
HOME_DIR="$(getent passwd "$USR" | cut -d: -f6)"
sudo chown -R "$USR:$USR" "$HOME_DIR"
sudo chmod 700 "$HOME_DIR"
sudo chmod 1777 /tmp
UID_CUR="$(id -u "$USR")"
sudo mkdir -p /run/user/"$UID_CUR"
sudo chown "$USR:$USR" /run/user/"$UID_CUR"
sudo chmod 700 /run/user/"$UID_CUR"

# 4) Restart XRDP
sudo systemctl restart xrdp-sesman xrdp
