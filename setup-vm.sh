#!/bin/bash

# 0. Check Root
if [ "$EUID" -ne 0 ]; then
  echo "Error: Please run as root or use sudo"
  exit 1
fi

echo "=========================================="
echo "    Universal VM Provisioning Script      "
echo "=========================================="

# 1. Interactive Input
read -p "[?] Allow SSH Password Authentication? (y/n): " ssh_pass_choice < /dev/tty

# กำหนดตัวแปรสำหรับระบบ Progress
TOTAL_STEPS=6
CURRENT_STEP=0

show_progress() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    echo -e "\n=========================================="
    echo -e "Step ${CURRENT_STEP}/${TOTAL_STEPS}: $1"
    echo -e "=========================================="
}

# ฟังก์ชันแสดง Sub-progress (กำลังทำงาน)
print_sub() {
    local pct=$1
    local msg=$2
    # เพิ่ม \e[K ต่อท้าย
    printf "\r    -> [%3d%%] %-45s\e[K" "$pct" "$msg"
}

# ฟังก์ชันแสดงผลลัพธ์เมื่อทำงานเสร็จ (พิมพ์ทับแล้วขึ้นบรรทัดใหม่)
print_success() {
    local msg=$1
    # เพิ่ม \e[K ต่อท้าย ก่อนขึ้นบรรทัดใหม่ (\n)
    printf "\r    [+] %-50s\e[K\n" "$msg"
}


# ---------------------------------------------------------
# Step 1: ตรวจสอบ OS และเตรียมตัวแปร
# ---------------------------------------------------------
show_progress "Detecting OS and Setting up Variables"

print_sub 33 "Reading /etc/os-release..."
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    OS_FAMILY=$ID_LIKE
    print_success "Identified OS: $PRETTY_NAME"
else
    echo -e "\nError: Cannot identify OS"
    exit 1
fi

print_sub 66 "Setting up package manager variables..."
if [[ "$OS" == "ubuntu" || "$OS" == "debian" || "$OS_FAMILY" == *"debian"* ]]; then
    PKG_UPDATE="DEBIAN_FRONTEND=noninteractive apt-get update"
    PKG_UPGRADE="DEBIAN_FRONTEND=noninteractive apt-get upgrade -y"
    PKG_CLEAN="DEBIAN_FRONTEND=noninteractive apt-get autoremove -y"
    PKG_INSTALL="DEBIAN_FRONTEND=noninteractive apt-get install -y"
    TOOLS=(htop vim curl wget jq net-tools tar unzip qemu-guest-agent systemd-timesyncd)
    FW_STOP="systemctl stop ufw"
    FW_DISABLE="systemctl disable ufw"
    TIME_SVC="systemd-timesyncd"
elif [[ "$OS" == "centos" || "$OS" == "rocky" || "$OS" == "almalinux" || "$OS" == "rhel" || "$OS_FAMILY" == *"rhel"* ]]; then
    PKG_UPDATE="dnf makecache"
    PKG_UPGRADE="dnf upgrade -y"
    PKG_CLEAN="dnf autoremove -y"
    PKG_INSTALL="dnf install -y"
    TOOLS=(epel-release htop vim curl wget jq net-tools tar unzip qemu-guest-agent chrony)
    FW_STOP="systemctl stop firewalld"
    FW_DISABLE="systemctl disable firewalld"
    TIME_SVC="chronyd"
fi
print_success "Package manager configured ($PKG_INSTALL)"

print_sub 100 "Detecting SSH service name..."
if systemctl list-unit-files | grep -q "^sshd.service"; then
    SSH_SVC="sshd"
else
    SSH_SVC="ssh"
fi
print_success "SSH service identified as '$SSH_SVC'"

# ---------------------------------------------------------
# Step 2: อัปเดตระบบ
# ---------------------------------------------------------
show_progress "Updating System Packages"

print_sub 33 "Updating repository lists..."
eval "$PKG_UPDATE" > /dev/null 2>&1
print_success "Repository lists updated"

print_sub 66 "Upgrading installed packages..."
eval "$PKG_UPGRADE" > /dev/null 2>&1
print_success "System packages upgraded to latest versions"

print_sub 100 "Cleaning up unnecessary files..."
eval "$PKG_CLEAN" > /dev/null 2>&1
print_success "Unnecessary cache and orphaned packages removed"

# ---------------------------------------------------------
# Step 3: ติดตั้ง Tools และ QEMU Agent
# ---------------------------------------------------------
show_progress "Installing Essential Tools and QEMU Agent"
TOTAL_TOOLS=${#TOOLS[@]}
CURRENT_TOOL=0

for tool in "${TOOLS[@]}"; do
    CURRENT_TOOL=$((CURRENT_TOOL + 1))
    TOOL_PCT=$((CURRENT_TOOL * 100 / TOTAL_TOOLS))
    
    print_sub "$TOOL_PCT" "Installing $tool..."
    $PKG_INSTALL "$tool" > /dev/null 2>&1
    print_success "Installed package: $tool"
done

print_sub 100 "Enabling QEMU Guest Agent..."
systemctl enable --now qemu-guest-agent > /dev/null 2>&1
print_success "QEMU Guest Agent service enabled and running"

# ---------------------------------------------------------
# Step 4: ปิด Firewall
# ---------------------------------------------------------
show_progress "Disabling Firewall for Cluster Compatibility"

print_sub 50 "Stopping firewall service..."
eval "$FW_STOP" > /dev/null 2>&1 || true
print_success "Firewall service stopped"

print_sub 100 "Disabling firewall on boot..."
eval "$FW_DISABLE" > /dev/null 2>&1 || true
print_success "Firewall disabled from starting on boot"

# ---------------------------------------------------------
# Step 5: ตั้งค่า Timezone และ Time Sync
# ---------------------------------------------------------
show_progress "Configuring Timezone and Time Sync"

print_sub 33 "Setting timezone to Asia/Bangkok..."
timedatectl set-timezone Asia/Bangkok
print_success "Timezone set to Asia/Bangkok"

print_sub 66 "Enabling time sync service ($TIME_SVC)..."
systemctl enable "$TIME_SVC" > /dev/null 2>&1
print_success "Time sync service ($TIME_SVC) enabled"

print_sub 100 "Starting time sync service..."
systemctl restart "$TIME_SVC" > /dev/null 2>&1
print_success "Time synchronization is now active"

# ---------------------------------------------------------
# Step 6: ตั้งค่า SSH
# ---------------------------------------------------------
show_progress "Configuring SSH Access"

SSH_CONF="/etc/ssh/sshd_config"
print_sub 33 "Backing up sshd_config..."
cp $SSH_CONF "${SSH_CONF}.bak"
print_success "Backup created at ${SSH_CONF}.bak"

print_sub 66 "Applying PasswordAuthentication rule..."
if [[ "$ssh_pass_choice" == "n" || "$ssh_pass_choice" == "N" ]]; then
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' $SSH_CONF
    print_success "SSH Password Authentication configured to: NO"
else
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' $SSH_CONF
    print_success "SSH Password Authentication configured to: YES"
fi

print_sub 100 "Restarting $SSH_SVC service..."
systemctl restart "$SSH_SVC" > /dev/null 2>&1
print_success "SSH service restarted to apply changes"

echo -e "\nSUCCESS: VM Setup completed! Enjoy your system, Admin."
