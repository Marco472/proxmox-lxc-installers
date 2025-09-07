# Proxmox LXC Installers 🚀

This project provides **one-liner scripts** to automatically deploy Docker-ready **LXC containers** on **Proxmox VE** with popular apps preconfigured.  
Inspired by the [Proxmox Helper Scripts](https://tteck.github.io/Proxmox/) style.

Currently supported:
- ✅ [OctoFarm](https://github.com/OctoFarm/OctoFarm) (multi-OctoPrint management)  
- More apps coming soon!

---

## ✨ Features

- **One-liner install** directly from GitHub (no manual steps).  
- Creates an **unprivileged LXC** with:
  - Debian 12 template  
  - Docker + Docker Compose plugin  
  - `nesting=1` and `keyctl=1` enabled (for Docker support)  
- Deploys **OctoFarm + MongoDB** automatically.  
- Generates **secure random database credentials** on first run.  
- Provides **self-update mechanism** (script updates itself from GitHub).  
- Includes commands to:
  - Install  
  - Update (pull new images)  
  - Status (see containers and IP)  
  - Logs (tail app logs)  
  - Reconfigure (save config overrides)  
  - Uninstall (destroy LXC and cleanup)

---

## 📋 Requirements

- Proxmox VE 8 or 9 host  
- Internet access (to fetch LXC template and Docker images)  
- At least:
  - 2 vCPU  
  - 2 GB RAM  
  - 16 GB disk space  

---

## ⚡ Quick Start (OctoFarm)

Run this on your **Proxmox host shell**:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Marco472/proxmox-lxc-installers/main/octofarm/install_octofarm_lxc.sh)" install

When it finishes, it will print:

CTID

LXC IP address

OctoFarm URL

Database credentials (Mongo root + OctoFarm app user)

Open your browser and go to:
http://<LXC-IP>:4000

🔧 Commands

All commands run from Proxmox host shell:

Install (default DHCP, no VLAN):
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Marco472/proxmox-lxc-installers/main/octofarm/install_octofarm_lxc.sh)" install

Update (pull latest Docker images & redeploy):
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Marco472/proxmox-lxc-installers/main/octofarm/install_octofarm_lxc.sh)" update

Status (show container, IP, stack info):
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Marco472/proxmox-lxc-installers/main/octofarm/install_octofarm_lxc.sh)" status

Logs (tail Docker logs inside the container):
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Marco472/proxmox-lxc-installers/main/octofarm/install_octofarm_lxc.sh)" logs

Uninstall (remove stack + destroy LXC):
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Marco472/proxmox-lxc-installers/main/octofarm/install_octofarm_lxc.sh)" uninstall

⚙️ Advanced Configuration

You can override defaults by prefixing environment variables.

Example: Static IP
CTID=251 IP_CONF=static IP_ADDR=192.168.50.40/24 GW_ADDR=192.168.50.1 \
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Marco472/proxmox-lxc-installers/main/octofarm/install_octofarm_lxc.sh)" install

Example: VLAN Tag
VLAN_TAG=201 \
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Marco472/proxmox-lxc-installers/main/octofarm/install_octofarm_lxc.sh)" install

Example: Custom resources
CTID=300 CORES=4 MEM_MB=4096 DISK_GB=32 \
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Marco472/proxmox-lxc-installers/main/octofarm/install_octofarm_lxc.sh)" install

📂 Where things live

Inside the LXC:

OctoFarm + Mongo stack lives in: /opt/octofarm

Docker Compose file: /opt/octofarm/docker-compose.yml

Mongo init script: /opt/octofarm/mongo-init/init.js

Generated DB credentials: /opt/octofarm/.creds

On the Proxmox host:

Saved config: /etc/proxmox-lxc-installers/octofarm.env

🔒 Security Notes

The script auto-generates random credentials for Mongo root and the OctoFarm DB user.

MongoDB is not exposed externally (only available inside the LXC network).

OctoFarm web UI is accessible on port 4000.

Change passwords in .creds if desired.

🔄 Updates

Script self-updates: each run checks GitHub VERSION.

Stack update is manual (update command) to avoid breaking changes by surprise.

Proxmox LXC can be backed up with native CT backups.

💾 Backups

Options:

Use Proxmox CT backups (recommended).

Or inside LXC: back up /opt/octofarm volumes (Mongo + OctoFarm data).

📜 License

This project is licensed under the MIT License — see LICENSE

---

✅ This is the **single, full README file** you can paste into GitHub when creating or editing your repo — no broken formatting, no extra explanations.  

Do you want me to also prepare the **LICENSE file** (MIT text) and `VERSION` file in the same ready-to-paste way, so you’ll have a complete repo in one go?
