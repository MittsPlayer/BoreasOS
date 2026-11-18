#!/usr/bin/env bash
# BoreasOS - gera a ISO live (XFCE) a partir do perfil "releng" do archiso.
# Rode como root num Arch Linux (ou container archlinux --privileged).
set -euo pipefail

HERE="$(pwd)"
PROFILE="$HERE/boreasos-profile"
WORK="${WORK:-/tmp/boreas-work}"
OUT="$HERE/out"
RELENG="${RELENG:-/usr/share/archiso/configs/releng}"

for f in boreasos-icon.png wallpaper.png; do
  [ -f "$HERE/$f" ] || { echo "ERRO: falta o arquivo $f na raiz do repositorio"; exit 1; }
done

echo "==> Instalando archiso"
pacman -Syu --noconfirm --needed archiso

echo "==> Copiando perfil base (releng)"
rm -rf "$PROFILE" "$WORK"
cp -r "$RELENG" "$PROFILE"
cd "$PROFILE"

add_line() { # arquivo linha
  touch "$1"
  if [ -s "$1" ] && [ -n "$(tail -c1 "$1")" ]; then echo >> "$1"; fi
  echo "$2" >> "$1"
}

echo "==> Branding (profiledef + menus de boot)"
sed -i 's|^iso_name=.*|iso_name="boreasos"|' profiledef.sh
sed -i 's|^iso_label=.*|iso_label="BOREAS_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"|' profiledef.sh
sed -i 's|^iso_publisher=.*|iso_publisher="BoreasOS"|' profiledef.sh
sed -i 's|^iso_application=.*|iso_application="BoreasOS Live"|' profiledef.sh
{ grep -rl 'Arch Linux' grub syslinux efiboot 2>/dev/null || true; } | xargs -r sed -i 's/Arch Linux/BoreasOS/g'

echo "==> Pacotes"
add_line packages.x86_64 ""
cat >> packages.x86_64 <<'EOF'
xorg-server
xf86-input-libinput
mesa
xfce4
xfce4-goodies
xfce4-terminal
xfce4-whiskermenu-plugin
xfce4-pulseaudio-plugin
xfce4-notifyd
xfce4-taskmanager
xfce4-screenshooter
xfce4-power-manager
thunar
thunar-archive-plugin
file-roller
gvfs
udisks2
ntfs-3g
mousepad
galculator
ristretto
parole
gst-plugins-good
gst-libav
gparted
firefox
firefox-i18n-pt-br
lightdm
lightdm-gtk-greeter
networkmanager
network-manager-applet
pipewire
pipewire-alsa
pipewire-pulse
wireplumber
pavucontrol
polkit
sudo
git
nano
htop
fastfetch
xdg-user-dirs
librsvg
papirus-icon-theme
noto-fonts
noto-fonts-emoji
ttf-dejavu
ttf-liberation
EOF

echo "==> Identidade do sistema"
mkdir -p airootfs/usr/share/boreasos airootfs/etc
cat > airootfs/usr/share/boreasos/os-release <<'EOF'
NAME="BoreasOS"
PRETTY_NAME="BoreasOS"
ID=boreasos
ID_LIKE=arch
BUILD_ID=rolling
ANSI_COLOR="38;2;120;190;255"
LOGO=boreasos
EOF
echo "boreasos" > airootfs/etc/hostname
echo "Bem-vindo ao BoreasOS (baseado em Arch Linux)." > airootfs/etc/motd

echo "==> Idioma, teclado e fuso (pt-BR)"
printf 'pt_BR.UTF-8 UTF-8\nen_US.UTF-8 UTF-8\n' > airootfs/etc/locale.gen
echo "LANG=pt_BR.UTF-8" > airootfs/etc/locale.conf
echo "KEYMAP=br-abnt2" > airootfs/etc/vconsole.conf
ln -sf /usr/share/zoneinfo/America/Sao_Paulo airootfs/etc/localtime
mkdir -p airootfs/etc/X11/xorg.conf.d
cat > airootfs/etc/X11/xorg.conf.d/00-keyboard.conf <<'EOF'
Section "InputClass"
    Identifier "boreas-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "br,us"
    Option "XkbVariant" "abnt2,"
    Option "XkbOptions" "grp:alt_shift_toggle"
EndSection
EOF
cat > airootfs/etc/systemd/system/boreas-locale.service <<'EOF'
[Unit]
Description=Prepara o BoreasOS (locales e identidade)
Before=display-manager.service

[Service]
Type=oneshot
ExecStart=/usr/bin/locale-gen
ExecStart=/usr/bin/cp /usr/share/boreasos/os-release /usr/lib/os-release

[Install]
WantedBy=multi-user.target
EOF

echo "==> Usuario live + autologin + sem senha para admin"
add_line airootfs/etc/passwd  'liveuser:x:1000:1000:BoreasOS Live:/home/liveuser:/bin/bash'
add_line airootfs/etc/shadow  'liveuser::14871::::::'
add_line airootfs/etc/group   'liveuser:x:1000:'
add_line airootfs/etc/group   'autologin:x:1001:liveuser'
add_line airootfs/etc/gshadow 'liveuser:!!::'
add_line airootfs/etc/gshadow 'autologin:!!::liveuser'
mkdir -p airootfs/home/liveuser airootfs/etc/sudoers.d airootfs/etc/lightdm/lightdm.conf.d airootfs/etc/polkit-1/rules.d
echo 'liveuser ALL=(ALL:ALL) NOPASSWD: ALL' > airootfs/etc/sudoers.d/boreas
cat > airootfs/etc/polkit-1/rules.d/49-boreas-live.rules <<'EOF'
polkit.addRule(function(action, subject) {
    if (subject.user == "liveuser") {
        return polkit.Result.YES;
    }
});
EOF
cat > airootfs/etc/lightdm/lightdm.conf.d/50-boreas.conf <<'EOF'
[Seat:*]
autologin-user=liveuser
autologin-session=xfce
user-session=xfce
EOF

echo "==> Rede (NetworkManager)"
mkdir -p airootfs/etc/NetworkManager/conf.d
printf '[main]\ndns=systemd-resolved\n' > airootfs/etc/NetworkManager/conf.d/10-dns.conf

echo "==> Visual: logo, papel de parede, tema e icones"
mkdir -p airootfs/usr/share/backgrounds airootfs/usr/local/bin airootfs/etc/xdg/autostart
cp "$HERE/wallpaper.png" airootfs/usr/share/backgrounds/boreas.png
mkdir -p airootfs/usr/share/pixmaps airootfs/usr/share/icons/hicolor/256x256/apps
cp "$HERE/boreasos-icon.png" airootfs/usr/share/pixmaps/boreasos.png
cp "$HERE/boreasos-icon.png" airootfs/usr/share/icons/hicolor/256x256/apps/boreasos.png
cat > airootfs/usr/local/bin/boreas-wallpaper <<'EOF'
#!/bin/sh
img=/usr/share/backgrounds/boreas.png
props=""
for i in 1 2 3 4 5 6 7 8 9 10; do
  props=$(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep 'last-image$')
  [ -n "$props" ] && break
  sleep 1
done
for p in $props; do
  xfconf-query -c xfce4-desktop -p "$p" -s "$img"
done
EOF
cat > airootfs/etc/xdg/autostart/boreas-wallpaper.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=BoreasOS Wallpaper
Exec=/usr/local/bin/boreas-wallpaper
OnlyShowIn=XFCE;
NoDisplay=true
EOF
XCFG=airootfs/home/liveuser/.config/xfce4
mkdir -p "$XCFG/xfconf/xfce-perchannel-xml" "$XCFG/panel"
cat > "$XCFG/xfconf/xfce-perchannel-xml/xsettings.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="Adwaita-dark"/>
    <property name="IconThemeName" type="string" value="Papirus-Dark"/>
  </property>
  <property name="Gtk" type="empty">
    <property name="FontName" type="string" value="Noto Sans 10"/>
  </property>
</channel>
EOF

printf 'button-icon=boreasos\nshow-button-title=false\n' > "$XCFG/panel/whiskermenu-1.rc"

echo "==> Painel: menu iniciar, atalhos, bandeja, relogio e botao liga/desliga"
cat > "$XCFG/xfconf/xfce-perchannel-xml/xfce4-panel.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-panel" version="1.0">
  <property name="configver" type="int" value="2"/>
  <property name="panels" type="array">
    <value type="int" value="1"/>
    <property name="dark-mode" type="bool" value="true"/>
    <property name="panel-1" type="empty">
      <property name="position" type="string" value="p=10;x=0;y=0"/>
      <property name="length" type="uint" value="100"/>
      <property name="position-locked" type="bool" value="true"/>
      <property name="icon-size" type="uint" value="0"/>
      <property name="size" type="uint" value="36"/>
      <property name="plugin-ids" type="array">
        <value type="int" value="1"/>
        <value type="int" value="2"/>
        <value type="int" value="3"/>
        <value type="int" value="4"/>
        <value type="int" value="5"/>
        <value type="int" value="6"/>
        <value type="int" value="7"/>
        <value type="int" value="8"/>
        <value type="int" value="9"/>
        <value type="int" value="10"/>
        <value type="int" value="11"/>
      </property>
    </property>
  </property>
  <property name="plugins" type="empty">
    <property name="plugin-1" type="string" value="whiskermenu"/>
    <property name="plugin-2" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="firefox.desktop"/>
        <value type="string" value="thunar.desktop"/>
        <value type="string" value="xfce4-terminal.desktop"/>
        <value type="string" value="org.xfce.mousepad.desktop"/>
        <value type="string" value="galculator.desktop"/>
      </property>
    </property>
    <property name="plugin-3" type="string" value="separator">
      <property name="expand" type="bool" value="false"/>
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-4" type="string" value="tasklist">
      <property name="grouping" type="uint" value="1"/>
    </property>
    <property name="plugin-5" type="string" value="separator">
      <property name="expand" type="bool" value="true"/>
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-6" type="string" value="systray"/>
    <property name="plugin-7" type="string" value="pulseaudio"/>
    <property name="plugin-8" type="string" value="power-manager-plugin"/>
    <property name="plugin-9" type="string" value="notification-plugin"/>
    <property name="plugin-10" type="string" value="clock"/>
    <property name="plugin-11" type="string" value="actions"/>
  </property>
</channel>
EOF

echo "==> Servicos (NetworkManager, LightDM, locale)"
find airootfs/etc/systemd/system \( -name 'systemd-networkd*' -o -name 'iwd.service' \) -delete 2>/dev/null || true
mkdir -p airootfs/etc/systemd/system/multi-user.target.wants
ln -sf /usr/lib/systemd/system/NetworkManager.service airootfs/etc/systemd/system/multi-user.target.wants/NetworkManager.service
ln -sf /etc/systemd/system/boreas-locale.service airootfs/etc/systemd/system/multi-user.target.wants/boreas-locale.service
ln -sf /usr/lib/systemd/system/lightdm.service airootfs/etc/systemd/system/display-manager.service
ln -sf /usr/lib/systemd/system/graphical.target airootfs/etc/systemd/system/default.target

echo "==> Permissoes"
cat >> profiledef.sh <<'EOF'
file_permissions+=(
  ["/home/liveuser"]="1000:1000:750"
  ["/home/liveuser/.config"]="1000:1000:755"
  ["/home/liveuser/.config/xfce4"]="1000:1000:755"
  ["/home/liveuser/.config/xfce4/xfconf"]="1000:1000:755"
  ["/home/liveuser/.config/xfce4/xfconf/xfce-perchannel-xml"]="1000:1000:755"
  ["/home/liveuser/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"]="1000:1000:644"
  ["/home/liveuser/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml"]="1000:1000:644"
  ["/home/liveuser/.config/xfce4/panel"]="1000:1000:755"
  ["/home/liveuser/.config/xfce4/panel/whiskermenu-1.rc"]="1000:1000:644"
  ["/etc/sudoers.d/boreas"]="0:0:440"
  ["/usr/local/bin/boreas-wallpaper"]="0:0:755"
)
EOF

echo "==> Gerando a ISO"
mkdir -p "$OUT"
mkarchiso -v -w "$WORK" -o "$OUT" "$PROFILE"
echo "==> Pronto: $(ls "$OUT"/*.iso)"
