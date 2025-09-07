#!/usr/bin/env bash
# OctoFarm Installer (entrypoint) - Proxmox host
# Mirrors the community-scripts flow: small wrapper downloads and runs ct/octofarm.sh
# Repo: https://github.com/Marco472/proxmox-lxc-installers
set -euo pipefail

# ── Config: where to fetch the CT payload from ─────────────────────────────────
GITHUB_USER="${GITHUB_USER:-Marco472}"
GITHUB_REPO="${GITHUB_REPO:-proxmox-lxc-installers}"
BRANCH="${BRANCH:-main}"
RAW_BASE="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${BRANCH}"
CT_SCRIPT_URL="${RAW_BASE}/ct/octofarm.sh"

# ── Pretty banner (community vibe) ─────────────────────────────────────────────
echo -e "\033[1;32m
  ┌─────────────────────────────────────────────────────┐
  │        Proxmox LXC Installer • OctoFarm            │
  │        by ${GITHUB_USER}/${GITHUB_REPO}                          │
  └─────────────────────────────────────────────────────┘
\033[0m"

# ── Sanity checks ──────────────────────────────────────────────────────────────
command -v pveversion >/dev/null || { echo "Run this on the Proxmox host."; exit 1; }
if ! command -v wget >/dev/null && ! command -v curl >/dev/null; then
  echo "Need either wget or curl available on the Proxmox host."; exit 1
fi

# ── Defaults (can be overridden with env vars on the command line) ─────────────
: "${CTID:=250}"
: "${HOSTNAME:=octofarm}"
: "${STORAGE:=local-lvm}"
: "${DISK_GB:=16}"
: "${CORES:=2}"
: "${MEM_MB:=2048}"
: "${SWAP_MB:=512}"

: "${BRIDGE:=vmbr0}"
: "${VLAN_TAG:=}"             # leave empty for no VLAN
: "${IP_CONF:=dhcp}"          # dhcp|static
: "${IP_ADDR:=}"              # required if IP_CONF=static (e.g. 192.168.50.40/24)
: "${GW_ADDR:=}"              # required if IP_CONF=static (e.g. 192.168.50.1)

: "${TZ_DEFAULT:=America/Toronto}"
: "${INSTALL_DIR:=/opt/octofarm}"

: "${MONGO_IMAGE:=mongo:6}"
: "${OCTOFARM_IMAGE:=octofarm/octofarm:latest}"
: "${OCTOFARM_PORT:=4000}"

echo "Fetching CT payload from: ${CT_SCRIPT_URL}"
echo ""

# ── Export vars so ct script can read them ─────────────────────────────────────
export CTID HOSTNAME STORAGE DISK_GB CORES MEM_MB SWAP_MB
export BRIDGE VLAN_TAG IP_CONF IP_ADDR GW_ADDR
export TZ_DEFAULT INSTALL_DIR
export MONGO_IMAGE OCTOFARM_IMAGE OCTOFARM_PORT

# ── Fetch & execute ct script ─────────────────────────────────────────────────
if command -v wget >/dev/null; then
  bash -c "$(wget -qLO - "${CT_SCRIPT_URL}")"
else
  bash -c "$(curl -fsSL "${CT_SCRIPT_URL}")"
fi
