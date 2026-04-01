# Linux VM Initial Setup Script

สคริปต์สำหรับการตั้งค่า OS Linux พื้นฐานสำหรับ VM ใหม่ (Post-installation) ออกแบบมาให้รองรับหลาย Distribution และสามารถรันได้ด้วยคำสั่งเดียว เหมาะสำหรับใช้งานในแวดล้อม Virtualization เช่น Proxmox

## ความสามารถของสคริปต์ (Features)
- **Universal Support:** รองรับ Debian, Ubuntu, CentOS, Rocky Linux, AlmaLinux
- **System Update:** อัปเดตแพ็กเกจเป็นเวอร์ชันล่าสุดอัตโนมัติ
- **Security:** เลือกปิด/เปิด SSH Password Authentication ได้ (Interactive)
- **Firewall:** ปิด Firewall (UFW/Firewalld) เพื่อความสะดวกในการทำ Cluster (K8s/Ceph)
- **Timezone:** ตั้งค่าโซนเวลาเป็น `Asia/Bangkok` และตั้งค่า Time Sync
- **Infrastructure:** ติดตั้ง `QEMU Guest Agent` ให้อัตโนมัติ
- **Essential Tools:** ติดตั้งเครื่องมือพื้นฐาน (`htop`, `vim`, `curl`, `wget`, `jq`, `net-tools`, ฯลฯ)

## วิธีใช้งานผ่านคำสั่งเดียว (Quick Start)

รันคำสั่งด้านล่างนี้บน VM ที่เพิ่งสร้างใหม่ (ต้องมีสิทธิ์ sudo/root):

```bash
curl -sSL https://raw.githubusercontent.com/Greedtik/setup-vm/refs/heads/main/setup-vm.sh | sudo bash
