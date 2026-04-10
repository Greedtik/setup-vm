#!/bin/bash

# ==========================================
# 0. Pre-flight Checks & Logging Setup
# ==========================================
if [ "$EUID" -ne 0 ]; then
  echo "Error: Please run as root or use sudo"
  exit 1
fi

LOG_FILE="/var/log/vm-provisioning.log"
# เคลียร์ไฟล์ Log เก่า (ถ้ามี) ก่อนเริ่มงานใหม่
> "$LOG_FILE"

echo "Starting Provisioning Script... Log will be saved to $LOG_FILE"
# ส่งเฉพาะ Output ของ UI ไปที่หน้าจอและ Log
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=========================================="
echo "    Universal VM Provisioning Script      "
echo "=========================================="

# 1. Interactive Input
read -p "[?] Allow SSH Password Authentication? (y/n): " ssh_pass_choice < /dev/tty

# ==========================================
# Functions for Progress & Logging
# ==========================================
TOTAL_STEPS=7
CURRENT_STEP=0

show_progress() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    echo -e "\n=========================================="
    echo -e "Step ${CURRENT_STEP}/${TOTAL_STEPS}: $1"
    echo -e "=========================================="
}

print_sub() {
    local pct=$1
    local msg=$2
    printf "\r    -> [%3d%%] %-45s\e[K" "$pct" "$msg"
}

print_success() {
    local msg=$1
    printf "\r    [+] %-50s\e[K\n" "$msg"
}

print_error() {
    local msg=$1
    printf "\r    [!] %-50s\e[K\n" "$msg"
}

# ฟังก์ชันสำหรับเขียน Log คั่นจังหวะเพื่อให้อ่านง่าย
log_separator() {
    echo -e "\n[LOG] --- $1 ---" >> "$LOG_FILE"
}

# ==========================================
# Step 1: ตรวจสอบ OS และเตรียมตัวแปร
# ==========================================
show_progress "Detecting OS and Setting up Variables"
log_separator "Starting OS Detection"

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
    TOOLS=(psmisc htop vim curl wget jq net-tools tar unzip qemu-guest-agent systemd-timesyncd)
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
print_success "Package manager configured"

print_sub 100 "Detecting SSH service name..."
if systemctl list-unit-files | grep -q "^sshd.service"; then
    SSH_SVC="sshd"
else
    SSH_SVC="ssh"
fi
print_success "SSH service identified as '$SSH_SVC'"

# ==========================================
# Step 2: อัปเดตระบบ (พร้อมระบบ Wait for Lock)
# ==========================================
show_progress "Updating System Packages"
log_separator "System Update Process"

if [[ "$OS_FAMILY" == *"debian"* ]]; then
    print_sub 10 "Waiting for other package managers to finish..."
    if command -v fuser >/dev/null 2>&1; then
        while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
            sleep 5
        done
    fi
    print_success "System ready for package management"
fi

print_sub 33 "Updating repository lists..."
eval "$PKG_UPDATE" >> "$LOG_FILE" 2>&1
print_success "Repository lists updated"

print_sub 66 "Upgrading installed packages..."
eval "$PKG_UPGRADE" >> "$LOG_FILE" 2>&1
print_success "System packages upgraded"

print_sub 100 "Cleaning up unnecessary files..."
eval "$PKG_CLEAN" >> "$LOG_FILE" 2>&1
print_success "Cleanup completed"

# ==========================================
# Step 3: ติดตั้ง Tools และ QEMU Agent
# ==========================================
show_progress "Installing Essential Tools and QEMU Agent"
log_separator "Tools Installation Process"

TOTAL_TOOLS=${#TOOLS[@]}
CURRENT_TOOL=0

for tool in "${TOOLS[@]}"; do
    CURRENT_TOOL=$((CURRENT_TOOL + 1))
    TOOL_PCT=$((CURRENT_TOOL * 100 / TOTAL_TOOLS))
    
    print_sub "$TOOL_PCT" "Installing $tool..."
    
    # บันทึกรายละเอียดการติดตั้งลงไฟล์ Log โดยตรง
    echo "[LOG] Installing: $tool" >> "$LOG_FILE"
    $PKG_INSTALL "$tool" >> "$LOG_FILE" 2>&1
    
    if [ $? -eq 0 ]; then
        print_success "Installed package: $tool"
    else
        print_error "FAILED to install package: $tool"
    fi
done

print_sub 100 "Enabling QEMU Guest Agent..."
systemctl enable --now qemu-guest-agent >> "$LOG_FILE" 2>&1
print_success "QEMU Guest Agent configuration applied"

# ==========================================
# Step 4: ปิด Firewall
# ==========================================
show_progress "Disabling Firewall"
log_separator "Firewall Configuration"

print_sub 50 "Stopping firewall service..."
eval "$FW_STOP" >> "$LOG_FILE" 2>&1 || true
print_success "Firewall service stopped"

print_sub 100 "Disabling firewall on boot..."
eval "$FW_DISABLE" >> "$LOG_FILE" 2>&1 || true
print_success "Firewall disabled from boot"

# ==========================================
# Step 5: ตั้งค่า Timezone และ Time Sync
# ==========================================
show_progress "Configuring Timezone and Time Sync"
log_separator "Timezone and Sync Process"

print_sub 33 "Setting timezone to Asia/Bangkok..."
timedatectl set-timezone Asia/Bangkok >> "$LOG_FILE" 2>&1
print_success "Timezone set to Asia/Bangkok"

print_sub 66 "Enabling time sync service ($TIME_SVC)..."
systemctl enable "$TIME_SVC" >> "$LOG_FILE" 2>&1
print_success "Time sync service enabled"

print_sub 100 "Starting time sync service..."
systemctl restart "$TIME_SVC" >> "$LOG_FILE" 2>&1
print_success "Time synchronization is now active"

# ==========================================
# Step 6: ตั้งค่า SSH
# ==========================================
show_progress "Configuring SSH Access"
log_separator "SSH Configuration"

SSH_CONF="/etc/ssh/sshd_config"
print_sub 33 "Backing up sshd_config..."
cp $SSH_CONF "${SSH_CONF}.bak"
print_success "Backup created at ${SSH_CONF}.bak"

print_sub 66 "Applying PasswordAuthentication rule..."
if [[ "$ssh_pass_choice" == "n" || "$ssh_pass_choice" == "N" ]]; then
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' $SSH_CONF
    SSH_STATUS="NO"
else
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' $SSH_CONF
    SSH_STATUS="YES"
fi
print_success "SSH Password Authentication set to: $SSH_STATUS"

print_sub 100 "Restarting $SSH_SVC service..."
systemctl restart "$SSH_SVC" >> "$LOG_FILE" 2>&1
print_success "SSH service restarted"

# ==========================================
# Step 7: Final Verification
# ==========================================
show_progress "Verifying Tools and Services"
log_separator "Final Verification"

# ตรวจสอบคำสั่ง
TOOLS_CHECK=(htop vim curl wget jq tar unzip ifconfig netstat)
for cmd in "${TOOLS_CHECK[@]}"; do
    if command -v "$cmd" > /dev/null 2>&1; then
        print_success "Verified: '$cmd' is ready to use"
    else
        print_error "Missing: '$cmd' is NOT installed correctly"
    fi
done

# ตรวจสอบเซอร์วิส
SVCS_CHECK=(qemu-guest-agent "$TIME_SVC" "$SSH_SVC")
for svc in "${SVCS_CHECK[@]}"; do
    if systemctl is-active --quiet "$svc"; then
        print_success "Verified: Service '$svc' is RUNNING"
    else
        print_error "Error: Service '$svc' is NOT active"
    fi
done

echo -e "\n=========================================="
echo "SUCCESS: VM Setup completed! Enjoy your system."
echo "Log file saved at: $LOG_FILE"
echo "=========================================="
