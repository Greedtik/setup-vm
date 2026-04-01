  #!/bin/bash

# 0. Check Root
if [ "$EUID" -ne 0 ]; then
  echo "Error: Please run as root or use sudo"
  exit 1
fi

echo "=========================================="
echo "    Universal VM Provisioning Script      "
echo "=========================================="

# 1. Interactive Input (Read from /dev/tty to support curl | bash)
read -p "[?] Allow SSH Password Authentication? (y/n): " ssh_pass_choice < /dev/tty

# 2. Identify OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    OS_FAMILY=$ID_LIKE
else
    echo "Error: Cannot identify OS"
    exit 1
fi

echo -e "\n[*] Running on: $PRETTY_NAME"

# 3. Command Setup based on Distro
if [[ "$OS" == "ubuntu" || "$OS" == "debian" || "$OS_FAMILY" == *"debian"* ]]; then
    PKG_MGR="apt-get"
    $PKG_MGR update > /dev/null 2>&1
    PKG_UPGRADE="apt-get upgrade -y"
    PKG_INSTALL="apt-get install -y"
    PKGS_TOOLS="htop vim curl wget jq net-tools tar unzip qemu-guest-agent systemd-timesyncd"
    FW_DISABLE="systemctl disable --now ufw"
elif [[ "$OS" == "centos" || "$OS" == "rocky" || "$OS" == "almalinux" || "$OS" == "rhel" || "$OS_FAMILY" == *"rhel"* ]]; then
    PKG_MGR="dnf"
    PKG_UPGRADE="dnf upgrade -y"
    PKG_INSTALL="dnf install -y"
    $PKG_INSTALL epel-release > /dev/null 2>&1
    PKGS_TOOLS="htop vim curl wget jq net-tools tar unzip qemu-guest-agent chrony"
    FW_DISABLE="systemctl disable --now firewalld"
fi

# 4. Execute Update, Install Tools & QEMU Agent
echo "[*] Updating system and installing tools..."
$PKG_UPGRADE > /dev/null 2>&1
$PKG_INSTALL $PKGS_TOOLS > /dev/null 2>&1
$FW_DISABLE > /dev/null 2>&1 || true
systemctl enable --now qemu-guest-agent > /dev/null 2>&1
echo "[+] Tools and QEMU Guest Agent installed/enabled"
echo "[+] Firewall disabled"

# 5. Timezone and Sync
timedatectl set-timezone Asia/Bangkok
if command -v systemctl | grep -q "systemd-timesyncd"; then
    systemctl enable --now systemd-timesyncd > /dev/null 2>&1
else
    systemctl enable --now chronyd > /dev/null 2>&1
fi
echo "[+] Timezone set to Asia/Bangkok"

# 6. SSH Configuration
SSH_CONF="/etc/ssh/sshd_config"
cp $SSH_CONF "${SSH_CONF}.bak"
if [[ "$ssh_pass_choice" == "n" || "$ssh_pass_choice" == "N" ]]; then
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' $SSH_CONF
    echo "[+] SSH Password Authentication: DISABLED"
else
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' $SSH_CONF
    echo "[+] SSH Password Authentication: ENABLED"
fi

# Restart SSH Service
if systemctl list-unit-files | grep -q "^sshd.service"; then
    systemctl restart sshd > /dev/null 2>&1
else
    systemctl restart ssh > /dev/null 2>&1
fi

echo -e "\n[ SUCCESS ] VM Setup completed! Enjoy your system."
