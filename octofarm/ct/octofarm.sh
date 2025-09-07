#!/usr/bin/env bash
# OctoFarm CT Payload - Proxmox host executes this to create LXC & deploy OctoFarm+Mongo
# Style & flow mimics community-scripts/ProxmoxVE "ct/*" payloads.
set -euo pipefail

# ── Colors ─────────────────────────────────────────────────────────────────────
GN="\033[32m"; RD="\033[31m"; BL="\033[34m"; NC="\033[0m"; YW="\033[33m"

# ── Require Proxmox host ──────────────────────────────────────────────────────
command -v pveversion >/dev/null || { echo -e "${RD}Run this on the Proxmox host.${NC}"; exit 1; }

# ── Read config from env (defaults if not provided) ────────────────────────────
: "${CTID:=250}"
: "${HOSTNAME:=octofarm}"
: "${STORAGE:=local-lvm}"
: "${DISK_GB:=16}"
: "${CORES:=2}"
: "${MEM_MB:=2048}"
: "${SWAP_MB:=512}"

: "${BRIDGE:=vmbr0}"
: "${VLAN_TAG:=}"
: "${IP_CONF:=dhcp}"
: "${IP_ADDR:=}"
: "${GW_ADDR:=}"

: "${TZ_DEFAULT:=America/Toronto}"
: "${INSTALL_DIR:=/opt/octofarm}"

: "${MONGO_IMAGE:=mongo:6}"
: "${OCTOFARM_IMAGE:=octofarm/octofarm:latest}"
: "${OCTOFARM_PORT:=4000}"

CONF_DIR="/etc/proxmox-lxc-installers"
CONF_FILE="${CONF_DIR}/octofarm.env"

# ── Helpers ────────────────────────────────────────────────────────────────────
die(){ echo -e "${RD}ERROR:${NC} $*" >&2; exit 1; }
info(){ echo -e "${GN}==>${NC} $*"; }
warn(){ echo -e "${YW}==>${NC} $*"; }
ct_exec(){ pct exec "${CTID}" -- bash -lc "$*"; }
ct_ip(){ pct exec "${CTID}" -- bash -lc "hostname -I | awk '{print \$1}'" 2>/dev/null | tr -d '\r' || true; }
randpw(){ tr -dc 'A-Za-z0-9._-' </dev/urandom | head -c 24; }

save_env(){
  mkdir -p "${CONF_DIR}"
  cat > "${CONF_FILE}" <<EOF
# Saved by ct/octofarm.sh
CTID="${CTID}"
HOSTNAME="${HOSTNAME}"
STORAGE="${STORAGE}"
DISK_GB="${DISK_GB}"
CORES="${CORES}"
MEM_MB="${MEM_MB}"
SWAP_MB="${SWAP_MB}"
BRIDGE="${BRIDGE}"
VLAN_TAG="${VLAN_TAG}"
IP_CONF="${IP_CONF}"
IP_ADDR="${IP_ADDR}"
GW_ADDR="${GW_ADDR}"
TZ_DEFAULT="${TZ_DEFAULT}"
INSTALL_DIR="${INSTALL_DIR}"
MONGO_IMAGE="${MONGO_IMAGE}"
OCTOFARM_IMAGE="${OCTOFARM_IMAGE}"
OCTOFARM_PORT="${OCTOFARM_PORT}"
EOF
}

# ── Create LXC ─────────────────────────────────────────────────────────────────
create_ct(){
  pveam update >/dev/null 2>&1 || true
  local template="images:debian-12-standard_12.7-1_amd64.tar.zst"
  if ! pveam list local | grep -q "debian-12-standard_12"; then
    info "Downloading Debian 12 LXC template…"
    pveam download local "$template"
  fi
  local tpath; tpath=$(pveam list local | awk '/debian-12-standard_12/ {print $2}' | tail -n1)
  [[ -n "${tpath}" ]] || die "Template not found after download."

  local NET0="name=eth0,bridge=${BRIDGE}"
  [[ -n "${VLAN_TAG}" ]] && NET0="${NET0},tag=${VLAN_TAG}"
  if [[ "${IP_CONF}" == "dhcp" ]]; then
    NET0="${NET0},ip=dhcp"
  else
    [[ -n "${IP_ADDR}" && -n "${GW_ADDR}" ]] || die "Static selected but IP_ADDR/GW_ADDR not set."
    NET0="${NET0},ip=${IP_ADDR},gw=${GW_ADDR}"
  fi

  if pct status "${CTID}" >/dev/null 2>&1; then
    warn "CT ${CTID} already exists. Skipping creation."
    return
  fi

  local ROOTPASS; ROOTPASS="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)"
  info "Creating CTID=${CTID} on ${STORAGE}:${DISK_GB}G…"
  pct create "${CTID}" "/var/lib/vz/template/cache/${tpath}" \
    -hostname "${HOSTNAME}" -ostype debian -arch amd64 \
    -cores "${CORES}" -memory "${MEM_MB}" -swap "${SWAP_MB}" \
    -rootfs "${STORAGE}:${DISK_GB}" \
    -password "${ROOTPASS}" \
    -unprivileged 1 -features nesting=1,keyctl=1 \
    -net0 "${NET0}"

  pct set "${CTID}" -onboot 1 -startup order=3
  info "Starting CT ${CTID}…"
  pct start "${CTID}"; sleep 5
  info "CT root password: ${ROOTPASS}"
}

# ── Install Docker & OctoFarm stack inside CT ─────────────────────────────────
install_stack(){
  info "Installing Docker & Compose in CT…"
  ct_exec "apt-get update -y && apt-get upgrade -y"
  ct_exec "apt-get install -y curl ca-certificates gnupg lsb-release jq"
  ct_exec "curl -fsSL https://get.docker.com | sh"
  ct_exec "systemctl enable --now docker"
  ct_exec "apt-get install -y docker-compose-plugin"
  ct_exec "ln -sf /usr/share/zoneinfo/${TZ_DEFAULT} /etc/localtime && echo '${TZ_DEFAULT}' > /etc/timezone"

  # Generate DB creds if not present
  local CREDS="${INSTALL_DIR}/.creds"
  if ! ct_exec "[ -f ${CREDS} ]"; then
    local MONGO_ROOT_USER="root"
    local MONGO_ROOT_PASS; MONGO_ROOT_PASS="$(randpw)"
    local APP_DB="octofarm"
    local APP_USER="octouser"
    local APP_PASS; APP_PASS="$(randpw)"

    ct_exec "mkdir -p ${INSTALL_DIR}/mongo-init"
    ct_exec "bash -lc 'cat > ${INSTALL_DIR}/mongo-init/init.js <<EOF
db = db.getSiblingDB(\"${APP_DB}\");
db.createUser({ user: \"${APP_USER}\", pwd: \"${APP_PASS}\", roles: [{ role: \"readWrite\", db: \"${APP_DB}\" }] });
EOF'"

    ct_exec "bash -lc 'mkdir -p ${INSTALL_DIR}; cat > ${CREDS} <<EOF
MONGO_ROOT_USER=${MONGO_ROOT_USER}
MONGO_ROOT_PASS=${MONGO_ROOT_PASS}
APP_DB=${APP_DB}
APP_USER=${APP_USER}
APP_PASS=${APP_PASS}
EOF'"
  fi

  # Write docker-compose.yml
  ct_exec "bash -lc '
source ${INSTALL_DIR}/.creds
mkdir -p ${INSTALL_DIR}
cat > ${INSTALL_DIR}/docker-compose.yml <<EOF
version: \"3.8\"
services:
  mongo:
    image: ${MONGO_IMAGE}
    container_name: octofarm_mongo
    restart: unless-stopped
    environment:
      MONGO_INITDB_ROOT_USERNAME: \${MONGO_ROOT_USER}
      MONGO_INITDB_ROOT_PASSWORD: \${MONGO_ROOT_PASS}
      MONGO_INITDB_DATABASE: \${APP_DB}
    command: [\"--bind_ip_all\", \"--wiredTigerCacheSizeGB=0.5\"]
    volumes:
      - mongo_data:/data/db
      - ./mongo-init:/docker-entrypoint-initdb.d:ro

  octofarm:
    image: ${OCTOFARM_IMAGE}
    container_name: octofarm
    restart: unless-stopped
    depends_on: [mongo]
    ports:
      - \"${OCTOFARM_PORT}:4000\"
    environment:
      TZ: ${TZ_DEFAULT}
      MONGO_URI: \"mongodb://\${APP_USER}:\${APP_PASS}@mongo:27017/\${APP_DB}?authSource=\${APP_DB}\"
    volumes:
      - octofarm_data:/app/data

volumes:
  mongo_data:
  octofarm_data:
EOF
'"

  info "Pulling images & starting stack…"
  ct_exec "cd ${INSTALL_DIR} && docker compose pull && docker compose up -d"
}

# ── Status summary ─────────────────────────────────────────────────────────────
summary(){
  local ip; ip="$(ct_ip)"
  echo -e "${BL}================= SUMMARY =================${NC}"
  echo -e " CTID:            ${GN}${CTID}${NC}"
  echo -e " Hostname:        ${GN}${HOSTNAME}${NC}"
  echo -e " LXC IP:          ${GN}${ip}${NC}"
  echo -e " OctoFarm URL:    ${GN}http://${ip}:${OCTOFARM_PORT}${NC}"
  echo -e " Install dir:     ${GN}${INSTALL_DIR}${NC}"
  echo -e " Config saved:    ${GN}${CONF_FILE}${NC}"
  echo -e "${BL}==========================================${NC}"
  echo ""
  ct_exec "docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'"
}

# ── Run flow ───────────────────────────────────────────────────────────────────
save_env
create_ct
install_stack
summary
