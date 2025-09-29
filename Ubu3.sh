sudo -u ca bash -c 'mkdir -p ~/.config && cp -a /home/testuser/.config/xfce4 ~/.config/'
sudo systemctl restart xrdp-sesman xrdp
