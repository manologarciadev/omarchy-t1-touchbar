#!/usr/bin/env bash
# install.sh — T1 Touch Bar driver installer for Omarchy / Arch Linux.
#
# Activates the Touch Bar (Esc, F1–F12, brightness, volume, ALS) on
# MacBook Pro 13,x / 14,x (2016–2017, T1 chip) running Omarchy or Arch.
#
# Compila e instala el driver vía DKMS, lo que permite que los módulos
# se recompilen automáticamente con cada actualización de kernel
# (pacman -Syu linux linux-headers). No hay que tocar nada manualmente.
#
# Usage:
#   sudo ./install.sh          # install drivers + persistence
#   sudo ./install.sh uninstall  # remove everything we installed
#   ./install.sh --help        # show usage
#
# License: GPL-2.0

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
ok()   { printf "${GREEN}[✓]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[!]${NC} %s\n" "$*"; }
err()  { printf "${RED}[✗]${NC} %s\n" "$*" >&2; }
info() { printf "${BLUE}[i]${NC} %s\n" "$*"; }
die()  { err "$*"; exit 1; }

# ─── Constantes ───────────────────────────────────────────────────────────
DKMS_PKG=mbp-t1-touchbar
DKMS_VER=0.1
DKMS_SRC=/usr/src/${DKMS_PKG}-${DKMS_VER}
UPSTREAM_URL=https://github.com/parport0/mbp-t1-touchbar-driver.git

usage() {
  cat <<EOF
T1 Touch Bar installer for Omarchy / Arch Linux.

Usage:
  sudo ./install.sh          Install drivers + persistence (needs reboot after)
  sudo ./install.sh uninstall  Remove all files we created
  ./install.sh --help        Show this help

Verifica README.md para el setup completo (incluyendo cómo inicializar
el firmware del T1 arrancando macOS una vez).
EOF
}

# ─── Subcommand dispatch ──────────────────────────────────────────────────
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage; exit 0
fi

ACTION="${1:-install}"

# ─── Root check ───────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || die "Ejecuta con sudo: sudo $0 $ACTION"

KVER=$(uname -r)

# ─── Detector de modelo (informativo) ───────────────────────────────────
detect_model() {
  local board
  board=$(cat /sys/class/dmi/id/board_name 2>/dev/null || echo unknown)
  case "$board" in
    Mac-66E35819EE2D0D05) echo "MacBookPro13,2 (13\" 2016, Touch Bar)" ;;
    Mac-551B86E5744E2388) echo "MacBookPro14,3 (15\" 2017, Touch Bar)" ;;
    Mac-*) echo "MacBook (board: $board)" ;;
    *) echo "non-Mac hardware" ;;
  esac
}

# ─── UNINSTALL ────────────────────────────────────────────────────────────
do_uninstall() {
  info "Quitando driver T1..."

  # Quitar módulos cargados (mejor esfuerzo)
  modprobe -r apple_ib_tb 2>/dev/null || true
  modprobe -r apple_ib_als 2>/dev/null || true
  modprobe -r apple_ibridge 2>/dev/null || true

  # Quitar DKMS si está registrado
  if [[ -d /var/lib/dkms/${DKMS_PKG} ]]; then
    info "Quitando DKMS module ${DKMS_PKG}..."
    for ver in /var/lib/dkms/${DKMS_PKG}/*; do
      [[ -d "$ver" ]] || continue
      dkms remove -m ${DKMS_PKG} -v "$(basename "$ver")" --all 2>/dev/null || true
    done
  fi

  # Quitar DKMS contaminado de t2linux (apple-ib-drv, era T2)
  if [[ -d /var/lib/dkms/apple-ib-drv ]]; then
    warn "Quitando DKMS apple-ib-drv (driver T2, no sirve para T1)"
    for ver in /var/lib/dkms/apple-ib-drv/*; do
      [[ -d "$ver" ]] || continue
      dkms remove -m apple-ib-drv -v "$(basename "$ver")" --all 2>/dev/null || true
    done
  fi

  # Quitar paquete AUR T2 si quedó
  if pacman -Q apple-ib-drv-dkms-git >/dev/null 2>&1; then
    warn "Quitando apple-ib-drv-dkms-git (paquete T2)"
    pacman -Rns --noconfirm apple-ib-drv-dkms-git >/dev/null 2>&1 || true
  fi

  # Limpiar source dirs y archivos creados
  rm -rf /usr/src/${DKMS_PKG}-* 2>/dev/null || true
  rm -f /etc/modprobe.d/blacklist-hid-sensor-ibridge.conf \
        /etc/modules-load.d/apple-t1-touchbar.conf \
        /etc/udev/rules.d/99-apple-t1-touchbar.rules

  # Quitar servicio systemd de autoinstall
  if [[ -f /etc/systemd/system/dkms-autoinstall.service ]]; then
    info "Quitando servicio dkms-autoinstall.service..."
    systemctl disable dkms-autoinstall.service 2>/dev/null || true
    rm -f /etc/systemd/system/dkms-autoinstall.service
    systemctl daemon-reload
  fi

  depmod -a
  ok "Desinstalación completa. Reinicia para limpiar todo."
  exit 0
}

[[ "$ACTION" == "uninstall" ]] && do_uninstall

# ─── Banner ───────────────────────────────────────────────────────────────
echo
echo "${GREEN}╭──────────────────────────────────────────────╮${NC}"
echo "${GREEN}│ T1 Touch Bar installer · MacBookPro 13,x/14,x │${NC}"
echo "${GREEN}╰──────────────────────────────────────────────╯${NC}"
echo
info "Equipo detectado: $(detect_model)"
info "Kernel: $KVER"

# ─── Prereq: distro ───────────────────────────────────────────────────────
command -v pacman >/dev/null || die "Esta distro no es Arch-based (no hay pacman)."

# ─── Prereq: iBridge 05ac:8600 (con fallback /sys si falta lsusb) ────────
# `lsusb` viene de usbutils (no siempre preinstalado en Omarchy).
# Si no está, parseamos /sys/bus/usb/devices/*/{idVendor,idProduct} directamente.
detect_ibridge() {
  if command -v lsusb >/dev/null; then
    lsusb -d 05ac: 2>/dev/null | grep -q "8600" && return 0
    return 1
  fi
  # Fallback: escanear sysfs
  for d in /sys/bus/usb/devices/*; do
    [[ -f "$d/idVendor" && -f "$d/idProduct" ]] || continue
    local vid pid
    vid=$(cat "$d/idVendor" 2>/dev/null)
    pid=$(cat "$d/idProduct" 2>/dev/null)
    [[ "$vid" == "05ac" && "$pid" == "8600" ]] && return 0
  done
  return 1
}

if ! detect_ibridge; then
  err "El iBridge (05ac:8600) no se detecta."
  echo
  warn "Antes de instalar el driver necesitas arrancar macOS completo una vez"
  warn "para inicializar el firmware del T1."
  echo
  warn "Resumen rápido (ver README.md §3 para detalle):"
  warn "  1. Crea USB booteable macOS Monterey (ver macos-usb.md)"
  warn "  2. Arranca con Opción (⌥) → selecciona USB"
  warn "  3. Utilidad de Discos → borra un disco como APFS/GUID"
  warn "  4. Reinstala macOS → llega al escritorio"
  warn "  5. Apaga bien → vuelve a Linux"
  echo
  warn "Tras eso, lsusb debe mostrar: 'Apple, Inc. iBridge' (05ac:8600)"
  if ! command -v lsusb >/dev/null; then
    echo
    info "(Tip: lsusb no está instalado. Puedes usar usbutils: pacman -S usbutils"
    info " o verificar via: for d in /sys/bus/usb/devices/*; do echo \"\$d: \$(cat \$d/idVendor 2>/dev/null):\$(cat \$d/idProduct 2>/dev/null)\"; done)"
  fi
  exit 1
fi
ok "iBridge (05ac:8600) detectado"

# Sugerir usbutils si no está (no bloquea: el script funciona sin él,
# pero lsusb es útil para verificar tras reboot).
if ! command -v lsusb >/dev/null; then
  warn "lsusb no está instalado. Recomendado: pacman -S usbutils (para verificar tras reboot)"
fi

# ─── Prereq: kernel headers + build tools + dkms ────────────────────────
[[ -d /usr/lib/modules/$KVER/build ]] \
  || die "Faltan headers del kernel $KVER. Instala con: pacman -S linux-headers"

for c in gcc make git dkms; do
  command -v $c >/dev/null || die "Falta $c. Instala con: pacman -S --needed base-devel dkms"
done
ok "Headers + build tools + dkms OK"

# ─── Limpieza de versiones previas (re-runnable) ────────────────────────
# Si ya hay un DKMS instalado, lo quitamos para reconstruir limpio.
if [[ -d /var/lib/dkms/${DKMS_PKG} ]]; then
  info "Reinstalando DKMS module existente..."
  dkms remove -m ${DKMS_PKG} -v ${DKMS_VER} --all 2>/dev/null || true
fi
rm -rf "${DKMS_SRC}"

# Quitar paquetes DKMS T2 contaminados si existen
if pacman -Q apple-ib-drv-dkms-git >/dev/null 2>&1; then
  warn "Quitando apple-ib-drv-dkms-git (paquete T2 — no sirve para T1)"
  pacman -Rns --noconfirm apple-ib-drv-dkms-git >/dev/null 2>&1 || true
fi
if [[ -d /var/lib/dkms/apple-ib-drv ]]; then
  warn "Quitando DKMS apple-ib-drv (driver T2 — no sirve para T1)"
  for ver in /var/lib/dkms/apple-ib-drv/*; do
    [[ -d "$ver" ]] || continue
    dkms remove -m apple-ib-drv -v "$(basename "$ver")" --all 2>/dev/null || true
  done
fi

# Quitar módulos sueltos (instalación previa con make install directo,
# no via DKMS) si existen para este kernel.
rm -f /lib/modules/$KVER/updates/apple-ibridge.ko.zst \
      /lib/modules/$KVER/updates/apple-ib-tb.ko.zst \
      /lib/modules/$KVER/updates/apple-ib-als.ko.zst 2>/dev/null || true

# ─── Stage source en /usr/src/mbp-t1-touchbar-0.1/ ─────────────────────
info "Descargando ${UPSTREAM_URL}..."
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
git clone --depth=1 "$UPSTREAM_URL" "$WORK/driver"

info "Staging source en ${DKMS_SRC}..."
mkdir -p "$DKMS_SRC"
# Copiar fuentes (incluyendo subdir linux/ con apple-ibridge.h)
cp -r "$WORK/driver/." "$DKMS_SRC/"
rm -rf "$DKMS_SRC/.git"

# Copiar nuestro dkms.conf (del repo actual) sobre el staged source
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
if [[ -f "$SCRIPT_DIR/dkms.conf" ]]; then
  cp "$SCRIPT_DIR/dkms.conf" "$DKMS_SRC/dkms.conf"
else
  die "No se encontró dkms.conf en $SCRIPT_DIR"
fi

# ─── DKMS: add + build + install ───────────────────────────────────────
info "Registrando ${DKMS_PKG}/${DKMS_VER} con DKMS..."
dkms add -m ${DKMS_PKG} -v ${DKMS_VER}

info "Compilando con $(nproc) cores..."
dkms build -m ${DKMS_PKG} -v ${DKMS_VER}

info "Instalando módulos para kernel $KVER..."
dkms install -m ${DKMS_PKG} -v ${DKMS_VER} --force

depmod -a
ok "Módulos DKMS instalados: apple-ibridge, apple-ib-tb, apple-ib-als"

# ─── Persistencia ───────────────────────────────────────────────────────
info "Escribiendo blacklist para hid_sensor_hub..."
cat > /etc/modprobe.d/blacklist-hid-sensor-ibridge.conf <<'EOF'
# T1 iBridge: hid_sensor_hub secuestra la 2ª interfaz antes que apple-ibridge
# (ver github.com/michaelahess/macbook-pro-t1-touchbar-linux)
blacklist hid_sensor_hub
blacklist hid_sensor_als
blacklist hid_sensor_trigger
blacklist hid_sensor_iio_common
EOF

info "Escribiendo modules-load..."
cat > /etc/modules-load.d/apple-t1-touchbar.conf <<'EOF'
apple-ibridge
apple-ib-tb
apple-ib-als
EOF

info "Escribiendo udev rule..."
cat > /etc/udev/rules.d/99-apple-t1-touchbar.rules <<'EOF'
# Al detectar iBridge, asegurar carga de apple-ibridge
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="05ac", ATTR{idProduct}=="8600", RUN+="/sbin/modprobe apple-ibridge"
EOF

# ─── Servicio systemd: dkms-autoinstall al boot ─────────────────────────
# Cubre la race condition entre `pacman -Syu linux` (dispara hook DKMS) y
# `reboot` cuando el módulo DKMS se registró DESPUÉS del hook.
# (En Omarchy, dkms no provee un servicio boot — solo hooks de pacman.)
info "Creando servicio systemd dkms-autoinstall.service..."
cat > /etc/systemd/system/dkms-autoinstall.service <<'EOF'
[Unit]
Description=Build DKMS modules for the running kernel if missing
Documentation=https://github.com/manologarciadev/omarchy-t1-touchbar
# Es seguro correrlo antes que cualquier cosa que necesite los módulos;
# dkms autoinstall es no-op si ya están instalados.
DefaultDependencies=no
Before=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
# -k $(uname -r) limita al kernel en uso; --no-depmod evita trabajo extra
# (depmod lo corre después install.sh vía systemd-modules-load.service).
ExecStart=/usr/bin/dkms autoinstall --no-depmod -k $(uname -r)
# Fallar el servicio no debe romper el boot — registramos pero no paramos.
SuccessExitStatus=0 9

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable dkms-autoinstall.service
ok "Servicio dkms-autoinstall habilitado (corre en cada boot)"

# ─── Hecho ──────────────────────────────────────────────────────────────
echo
ok "Instalación completa."
echo
echo "  ${GREEN}Siguiente paso:${NC}  sudo reboot"
echo
echo "  Tras reboot, verifica con:"
echo "    lsmod | grep apple_ib          # los 3 módulos cargados"
echo "    ls /sys/bus/hid/drivers/apple-ibridge-hid/0003:05AC:8600.*"
echo "                                    # 2 sub-devs (touch + keys)"
echo
echo "  Si quieres desinstalar:  sudo ./install.sh uninstall"
echo
echo "  ${BLUE}Actualizaciones de kernel:${NC} el hook de pacman + DKMS"
echo "  recompilan los módulos automáticamente. No hay que hacer nada."
echo "  (Si fallara: sudo dkms autoinstall)"
