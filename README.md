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
