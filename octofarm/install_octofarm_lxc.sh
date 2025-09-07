#!/usr/bin/env bash
# OctoFarm in Docker LXC (Proxmox host-side)
# - Self-updating from GitHub (VERSION check)
# - Install / Update stack / Reconfigure / Uninstall / Status / Logs
# Repo: https://github.com/Marco472/proxmox-lxc-installers
set -euo pipefail

# ── Repo locations ──────────────────────────────────────────────────────────────
GITHUB_USER="Marco472"
GITHUB_REPO="proxmox-lxc-installers"
SCRIPT_PATH="octofarm/install_octofarm_lxc.sh"
VERSION_PATH="octofarm/VERSION"
RAW_BASE="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/main"

SELF_URL="${RAW_BASE}/${SCRIPT_PATH}"
REMOTE_VERSION_URL="${RAW_BASE}/${VERSION_PATH}"

# ── Script version ──────────────────────────────────────────────────────────────
SCRIPT_VERSION_LOCAL="1.0.0"

# ── Defaults (universal; override via env or reconfigure) ──────────────────────
CTID="${CTID:-250}"
HOSTNAME="${HOSTNAME:-octofarm}"
STORAGE="${STORAGE:-local-lvm}"
DISK_GB="${DISK_GB:-16}"
CORES="${CORES:-2}"
MEM_MB="${MEM_MB:-2048}"
SWAP_MB="${SWAP_MB:-512}"

BRIDGE="${BRIDGE:-vmbr0}"
VLAN_TAG="${VLAN_TAG:-}"             # <- empty by default (universal)
IP_CONF="${IP_CONF:-dhcp}"           # dhcp by default (universal)
IP_ADDR="${IP_ADDR:-}"               # needed only if IP_CONF=static
GW_ADDR="${GW_ADDR:-}"               # needed only if IP_CONF=static

TZ_DEFAULT="${TZ_DEFAULT:-America/Toronto}"
INSTALL_DIR="${INSTALL_DIR:-/opt/octofarm}"

MONGO_IMAGE="${MONGO_IMAGE:-mongo:6}"
OCTOFARM_IMAGE="${OCTOFARM_IMAGE:-octofarm/octofarm:latest}"
OCTOFARM_PORT="${OCTOFARM_PORT:-4000}"

# ── Persisted config path ───────────────────────────────────────────────────────
CONF_DIR="/etc/proxmox-lxc-installers"
CONF_FILE="${CONF_DIR}/octofarm.env"

# ── Colors ─────────────────────────────────────────────────────────────────────
GN="\033[32m"; RD="\033[31m"; BL="\033[34m"; NC="\033[0m"; YW="\033[33m"

# ── Helpers ────────────────────────────────────────────────────────────────────
die(){ echo -e "${RD}ERROR:${NC} $*" >&2; exit 1; }
info(){ echo -e "${GN}==>${NC} $*"; }
warn(){ echo -e "${YW}==>${NC} $*"; }
need_pve(){ command -v pveversion >/dev/null || die "Run this on the Proxmox host."; }
randpw(){ tr -dc 'A-Za-z0-9._-' </dev/urandom | head -c 24; }

save_env(){
  mkdir -p "${CONF_DIR}"
  cat > "${CONF_FILE}" <<EOF
# Saved by ${SCRIPT_PATH}
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

load_env(){ [[ -f "${CONF_FILE}" ]] && source "${CONF_FILE}" || true; }
ct_exec(){ pct exec "${CTID}" -- bash -lc "$*"; }
ct_ip(){ pct exec "${CTID}" -- bash -lc "hostname -I | awk '{print \$1}'" 2>/dev/null | tr -d '\r' || true; }

# ── Self-update ────────────────────────────────────────────────────────────────
self_update(){
  local remote_ver; remote_ver="$(curl -fsSL "${REMOTE_VERSION_URL}" || echo "")"
  if [[ -z "${remote_ver}" ]]; then
    warn "Could not fetch remote VERSION; continuing with local ${SCRIPT_VERSION_LOCAL}."
    return
  fi
  if [[ "${remote_ver}" != "${SCRIPT_VERSION_LOCAL}" ]]; then
    info "New version: ${remote_ver} (current ${SCRIPT_VERSION_LOCAL}). Updating…"
    local tmp; tmp="$(mktemp)"
    curl -fsSL "${SELF_URL}" -o "${tmp}" || die "Failed to download latest script."
    chmod +x "${tmp}"
    exec "${tmp}" "$@"
  fi
}

# ── LXC creation ───────────────────────────────────────────────────────────────
create_ct(){
  need_pve
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

# ── Install Docker & stack inside CT ──────────────────────────────────────────
install_stack(){
  info "Installing Docker & Compose inside CT…"
  ct_exec "apt-get update -y && apt-get upgrade -y"
  ct_exec "apt-get install -y curl ca-certificates gnupg lsb-release jq"
  ct_exec "curl -fsSL https://get.docker.com | sh"
  ct_exec "systemctl enable --now docker"
  ct_exec "apt-get install -y docker-compose-plugin"
  ct_exec "ln -sf /usr/share/zoneinfo/${TZ_DEFAULT} /etc/localtime && echo '${TZ_DEFAULT}' > /etc/timezone"

  # Generate per-install DB creds if not present
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

    ct_exec "bash -lc 'cat > ${CREDS} <<EOF
MONGO_ROOT_USER=${MONGO_ROOT_USER}
MONGO_ROOT_PASS=${MONGO_ROOT_PASS}
APP_DB=${APP_DB}
APP_USER=${APP_USER}
APP_PASS=${APP_PASS}
EOF'"
  fi

  # Write compose file
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

stack_update(){ info "Updating images & redeploying…"; ct_exec "cd ${INSTALL_DIR} && docker compose pull && docker compose up -d"; }
stack_logs(){ ct_exec "cd ${INSTALL_DIR} && docker compose logs -f --tail=200"; }
stack_status(){
  local ip; ip="$(ct_ip)"
  echo -e "${BL}===== STATUS =====${NC}"
  echo "CTID:     ${CTID}"
  echo "Hostname: ${HOSTNAME}"
  echo "IP:       ${ip}"
  echo "URL:      http://${ip}:${OCTOFARM_PORT}"
  echo "Install:  ${INSTALL_DIR}"
  echo
  ct_exec "docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'"
}
uninstall_all(){
  warn "Stopping & removing stack inside CT ${CTID}…"
  ct_exec "cd ${INSTALL_DIR} && docker compose down || true"
  warn "Removing container ${CTID}…"
  pct stop "${CTID}" || true
  pct destroy "${CTID}" -purge 1 || true
  warn "Leaving config file ${CONF_FILE} (remove manually if desired)."
}
reconfigure(){ save_env; info "Saved updated configuration to ${CONF_FILE}."; }

usage(){
cat <<EOF
Usage: $0 [command]

Commands:
  install        Create LXC (if needed) and deploy OctoFarm stack
  update         Pull latest images & redeploy stack
  reconfigure    Save current env vars into ${CONF_FILE}
  status         Print CT + stack status
  logs           Tail stack logs
  uninstall      Remove stack and destroy the LXC
  help           This help

Defaults (universal):
  BRIDGE=vmbr0, VLAN_TAG=\"\" (none), IP_CONF=dhcp
  CTID=250, CORES=2, MEM_MB=2048, DISK_GB=16, OCTOFARM_PORT=4000

Override examples:
  DHCP (no VLAN):
    bash -c \"\$(curl -fsSL ${SELF_URL})\" install

  Static IP:
    CTID=251 IP_CONF=static IP_ADDR=192.168.50.40/24 GW_ADDR=192.168.50.1 \\
    bash -c \"\$(curl -fsSL ${SELF_URL})\" install

  With VLAN 201:
    VLAN_TAG=201 \\
    bash -c \"\$(curl -fsSL ${SELF_URL})\" install
EOF
}

main(){
  load_env
  self_update "$@"
  local cmd="${1:-install}"
  case "${cmd}" in
    install)      save_env; create_ct; install_stack; stack_status ;;
    update)       stack_update ;;
    reconfigure)  reconfigure  ;;
    status)       stack_status ;;
    logs)         stack_logs   ;;
    uninstall)    uninstall_all ;;
    help|-h|--help) usage ;;
    *)            die "Unknown command: ${cmd}. Try: $0 help" ;;
  esac
}

main "$@"
