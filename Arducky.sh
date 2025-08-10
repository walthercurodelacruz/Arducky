#!/usr/bin/env bash
# ==============================================================================
#  Rubber Ducky con Arduino — Utilidad DFU para el ATmega16U2/8U2
#  Autor: Walther Curo
#
#  Menú:
#   0) Configuración (timeout, chip forzado, verbose)
#   1) Instalar dfu-programmer
#   2) Activar / esperar modo DFU
#   3) Limpiar flash del 16U2 (erase)
#   4) Instalar firmware ORIGINAL (serial USB)
#   5) Instalar firmware RUBBER DUCKY (HID teclado)
#   6) Ver estado de puertos (solo lsusb) + diagnóstico
#   7) Salir
#  Requiere .hex junto al script:
#   - Arduino-COMBINED-dfu-usbserial-atmega16u2-Uno-Rev3.hex
#   - Arduino-keyboard-0.3.hex
# ==============================================================================

set -Eeuo pipefail

# ===== Estilo / utilidades =====
BOLD=$'\e[1m'; DIM=$'\e[2m'
RED=$'\e[0;31m'; GREEN=$'\e[0;32m'; YELLOW=$'\e[1;33m'
CYAN=$'\e[0;36m'; MAG=$'\e[0;35m'; WHITE=$'\e[1;37m'; NC=$'\e[0m'

ok(){   echo -e "${GREEN}✓${NC} $*"; }
warn(){ echo -e "${YELLOW}!${NC} $*"; }
fail(){ echo -e "${RED}❌${NC} $*"; read -rp "Pulsa ENTER para volver al menú..." _; return 1; }
pause(){ echo -e "${DIM}>> Presiona [ENTER] para continuar...${NC}"; read -r; }
have(){ command -v "$1" >/dev/null 2>&1; }
onoff(){ [[ "${1:-0}" -eq 1 ]] && echo -e "${GREEN}Activado${NC}" || echo -e "${DIM}Desactivado${NC}"; }
separator(){ printf "${CYAN}%0.s─${NC}" {1..79}; echo; }

banner(){
  clear
  local left="Rubber Ducky con Arduino" right="Arduino UNO R3"
  printf "${CYAN}%0.s═${NC}" {1..79}; echo
  printf "${WHITE}${BOLD}%-50s${NC}${DIM}%28s${NC}\n" "$left" "$right"
  printf "${DIM}Autor:${NC} ${MAG}%s${NC}\n" "Walther Curo"
  printf "${CYAN}%0.s═${NC}" {1..79}; echo
}

# ===== Rutas / archivos =====
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HEX_ORIG="$SCRIPT_DIR/Arduino-COMBINED-dfu-usbserial-atmega16u2-Uno-Rev3.hex"
HEX_HID="$SCRIPT_DIR/Arduino-keyboard-0.3.hex"
CONFIG_FILE="$SCRIPT_DIR/.rducky.env"

# ===== Config por defecto (sobrescribible por .rducky.env) =====
DFU_TIMEOUT=60
FORCED_CHIP="auto"
VERBOSE=0
AUTHOR="Walther Curo"

# Carga robusta (si el .env está corrupto, se ignora y se regenera)
load_config(){
  if [[ -f "$CONFIG_FILE" ]]; then
    set +e
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
    local rc=$?
    set -e
    if [[ $rc -ne 0 ]]; then
      warn "El archivo $(basename "$CONFIG_FILE") está corrupto. Se regenerará al guardar."
      rm -f "$CONFIG_FILE"
    fi
  fi
}

# Guardado con comillas para soportar espacios y caracteres especiales
save_config(){
  cat >"$CONFIG_FILE" <<EOF
# Configuración persistente para rducky.sh
DFU_TIMEOUT="${DFU_TIMEOUT}"
FORCED_CHIP="${FORCED_CHIP}"
VERBOSE="${VERBOSE}"
AUTHOR="${AUTHOR}"
EOF
  ok "Configuración guardada en $(basename "$CONFIG_FILE")"
}

# ===== dfu-programmer =====
dfu_run(){
  local desc="$1"; shift
  echo -e "${CYAN}→${NC} $desc"
  set +e
  sudo dfu-programmer "$@" 2> >(tee /tmp/dfu_stderr.log >&2)
  local rc=$?; set -e
  if [[ $rc -ne 0 ]]; then
    fail "dfu-programmer falló (rc=$rc)"
    echo -e "${DIM}Comando:${NC} dfu-programmer $*"
    echo -e "${DIM}Stderr:${NC}"; cat /tmp/dfu_stderr.log
  fi
  return $rc
}
dfu_get(){ set +e; sudo dfu-programmer "$@" get >/dev/null 2>&1; local rc=$?; set -e; return $rc; }

# ===== Instalación =====
install_dfu_pkg(){
  if have apt; then sudo apt update && sudo apt install -y dfu-programmer
  elif have dnf5; then sudo dnf5 install -y dfu-programmer
  elif have dnf; then sudo dnf install -y dfu-programmer
  elif have pacman; then sudo pacman -Sy --noconfirm dfu-programmer
  else return 1; fi
}
install_build_deps(){
  if have apt; then
    sudo apt update
    sudo apt install -y git build-essential libusb-dev libusb-1.0-0-dev autoconf automake libtool pkg-config gettext
  elif have dnf5; then
    sudo dnf5 install -y git gcc make autoconf automake libtool pkgconf-pkg-config gettext libusb1-devel
  elif have dnf; then
    sudo dnf install -y git gcc make autoconf automake libtool pkgconf-pkg-config gettext libusb1-devel
  elif have pacman; then
    sudo pacman -Sy --noconfirm git base-devel libusb autoconf automake libtool pkgconf gettext
  fi
}
need_tools_or_install(){
  local need=(git gcc make autoconf automake libtool pkg-config)
  local miss=(); for t in "${need[@]}"; do have "$t" || miss+=("$t"); done
  ((${#miss[@]})) && install_build_deps
  for t in "${need[@]}"; do have "$t" || { fail "Falta herramienta: $t"; return 1; }; done
}
build_dfu_from_source(){
  echo -e "${CYAN}Compilando dfu-programmer desde fuente…${NC}"
  need_tools_or_install || return 1
  if have dnf5; then rpm -q libusb1-devel >/dev/null 2>&1 || sudo dnf5 install -y libusb1-devel || true
  elif have dnf; then rpm -q libusb1-devel >/dev/null 2>&1 || sudo dnf install -y libusb1-devel || true
  elif have apt; then dpkg -s libusb-1.0-0-dev >/dev/null 2>&1 || sudo apt install -y libusb-1.0-0-dev || true
  elif have pacman; then pacman -Qi libusb >/dev/null 2>&1 || sudo pacman -Sy --noconfirm libusb || true
  fi
  TMPDIR="$(mktemp -d)"; trap 'rm -rf "$TMPDIR"' EXIT
  pushd "$TMPDIR" >/dev/null
  git clone --depth 1 https://github.com/dfu-programmer/dfu-programmer.git
  cd dfu-programmer
  [[ -x ./bootstrap.sh ]] && ./bootstrap.sh || true
  [[ -f ./configure ]] || autoreconf -i
  [[ -f ./configure ]] || { fail "No se pudo generar ./configure (autotools)."; popd >/dev/null; return 1; }
  ./configure && make -j"$(nproc || echo 2)" && sudo make install
  sudo ldconfig || true; hash -r
  popd >/dev/null
  ok "dfu-programmer compilado e instalado."
}
ensure_dfu(){
  if have dfu-programmer; then ok "dfu-programmer ya está instalado."; return 0; fi
  warn "dfu-programmer no está instalado."
  read -rp "¿Instalar ahora? (s/n): " a
  [[ "$a" =~ ^[sS]$ ]] || { fail "Sin dfu-programmer no se puede continuar."; return 1; }
  if install_dfu_pkg && have dfu-programmer; then ok "Instalado desde repos."; else build_dfu_from_source || return 1; fi
}

# ===== DFU detect/wait =====
detect_mcu(){
  [[ "$FORCED_CHIP" != "auto" ]] && { echo "$FORCED_CHIP"; return 0; }
  for m in atmega16u2 atmega8u2; do dfu_get "$m" && { echo "$m"; return 0; }; done
  echo "atmega16u2"
}
wait_for_dfu(){
  local mcu="$1" timeout="$2" i=0
  echo -e "${YELLOW}Esperando DFU ($mcu) hasta ${timeout}s…${NC}"
  while (( i < timeout )); do
    if dfu_get "$mcu"; then ok "DFU detectado ($mcu)."; return 0; fi
    ((VERBOSE)) && echo -ne "\rIntento $((i+1))/${timeout}…"
    ((i+=1)) || true; sleep 1
  done
  echo; fail "No se detectó DFU ($mcu) en ${timeout}s."
}

# ===== ERASE que acepta rc=5 =====
dfu_erase_accept_rc5(){
  local mcu="$1" mode="${2:-}"
  set +e
  sudo dfu-programmer "$mcu" erase 2> >(tee /tmp/dfu_stderr.log >&2)
  local rc=$?; set -e
  if [[ $rc -eq 0 || $rc -eq 5 ]]; then
    echo -e "${DIM}Stderr (erase):${NC}"; cat /tmp/dfu_stderr.log
    ok "Erase aceptado (rc=$rc)."
    [[ "$mode" == "reset" ]] && dfu_run "Reset ($mcu)..." "$mcu" reset || true
    return 0
  else
    echo -e "${DIM}Stderr:${NC}"; cat /tmp/dfu_stderr.log
    return 1
  fi
}

check_hex_files(){
  [[ -s "$HEX_ORIG" ]] || { fail "No se encuentra HEX original: $HEX_ORIG"; return 1; }
  [[ -s "$HEX_HID"  ]] || { fail "No se encuentra HEX HID:      $HEX_HID";  return 1; }
  ok "Archivos .hex encontrados."
}

# ===== Acciones =====
accion_0_config(){
  while true; do
    banner
    echo -e "${WHITE}${BOLD}CONFIGURACIÓN — (.rducky.env)${NC}"
    separator
    echo -e "Tiempo de espera DFU: ${GREEN}${DFU_TIMEOUT}s${NC}"
    echo -e "Chip forzado:         ${MAG}${FORCED_CHIP}${NC}"
    echo -e "Modo verbose:         $(onoff "$VERBOSE")"
    echo
    echo -e " 1) Cambiar tiempo de espera"
    echo -e " 2) Seleccionar chip forzado  ${DIM}[auto/16u2/8u2]${NC}"
    echo -e " 3) Alternar verbose"
    echo -e " 4) Guardar y volver"
    echo -e " 5) Volver sin guardar"
    echo
    read -rp "Opción [1-5]: " c
    case "${c:-}" in
      1) read -rp "Nuevo tiempo (segundos): " t
         [[ "$t" =~ ^[0-9]+$ ]] && DFU_TIMEOUT="$t" || warn "Valor inválido";;
      2) read -rp "Elige [auto|atmega16u2|atmega8u2]: " s
         case "$s" in
           auto|atmega16u2|atmega8u2) FORCED_CHIP="$s" ;;
           *) warn "Selección inválida" ;;
         esac;;
      3) [[ "$VERBOSE" -eq 0 ]] && VERBOSE=1 || VERBOSE=0 ;;
      4) save_config; pause; break ;;
      5) warn "Sin guardar cambios."; pause; break ;;
      *) warn "Opción inválida."; sleep 1 ;;
    esac
  done
}

accion_1_instalar_dfu(){ banner; ensure_dfu || return 1; pause; }

accion_2_activar_esperar_dfu(){
  banner
  ensure_dfu || return 1
  local mcu; mcu="$(detect_mcu)"
  echo -e "${CYAN}Para entrar en DFU:${NC} puentea ${YELLOW}RESET${NC} y ${YELLOW}GND${NC} del 16U2/8U2, suelta el puente y continúa."
  echo -e "Tiempo de espera DFU: ${GREEN}${DFU_TIMEOUT}s${NC}"
  wait_for_dfu "$mcu" "$DFU_TIMEOUT" || return 1
  pause
}

accion_3_limpiar_flash(){
  banner
  ensure_dfu || return 1
  local mcu; mcu="$(detect_mcu)"
  wait_for_dfu "$mcu" "$DFU_TIMEOUT" || return 1
  echo -e "${CYAN}Borrando flash (${mcu})...${NC}"
  dfu_erase_accept_rc5 "$mcu" "reset" || return 1
  ok "Flash del $mcu limpiada."
  pause
}

accion_4_instalar_original(){
  banner
  ensure_dfu || return 1
  check_hex_files || return 1
  local mcu; mcu="$(detect_mcu)"
  wait_for_dfu "$mcu" "$DFU_TIMEOUT" || return 1
  dfu_erase_accept_rc5 "$mcu" || return 1
  if ! dfu_run "Flasheando firmware ORIGINAL ($mcu)..." \
        "$mcu" flash --suppress-bootloader-mem "$HEX_ORIG"; then
    warn "Reintentando ORIGINAL con --force…"
    dfu_run "Flasheando ORIGINAL (force)..." \
        "$mcu" flash --force --suppress-bootloader-mem "$HEX_ORIG" || return 1
  fi
  dfu_run "Reset ($mcu)..." "$mcu" reset || warn "Reset devolvió error (a veces normal)."
  ok "Firmware ORIGINAL instalado (serial USB)."
  pause
}

accion_5_instalar_ducky(){
  banner
  ensure_dfu || return 1
  check_hex_files || return 1
  local mcu; mcu="$(detect_mcu)"
  wait_for_dfu "$mcu" "$DFU_TIMEOUT" || return 1
  dfu_erase_accept_rc5 "$mcu" || return 1
  if ! dfu_run "Flasheando firmware RUBBER DUCKY ($mcu)..." "$mcu" flash "$HEX_HID"; then
    warn "Reintentando HID con --force…"
    dfu_run "Flasheando HID (force)..." "$mcu" flash --force "$HEX_HID" || return 1
  fi
  dfu_run "Reset ($mcu)..." "$mcu" reset || warn "Reset devolvió error (a veces normal)."
  ok "Firmware RUBBER DUCKY instalado (HID teclado)."
  pause
}

# ===== Opción 6: SOLO lsusb + diagnóstico de estado (DFU/DUCKY/SERIAL/NONE) =====
accion_6_estado_puertos(){
  banner
  echo -e "${WHITE}${BOLD}Estado de puertos USB (lsusb)${NC}"
  separator

  if ! have lsusb; then
    fail "lsusb no está instalado. En Fedora: 'sudo dnf install usbutils'"
    return 1
  fi

  local all rel status_code
  all="$(lsusb)"
  echo -e "${CYAN}Salida completa de lsusb:${NC}"
  echo "$all"
  echo

  # Líneas relevantes
  rel="$(echo "$all" | grep -Ei 'arduino|2341:|2a03:|03eb:|atmel|microchip|lufa|keyboard|hid|ch340|1a86:7523|cp210|10c4:ea60|ftdi|0403:6001|16u2|8u2|dfu' || true)"

  # Estado
  status_code="NONE"
  if echo "$rel" | grep -Eiq 'LUFA.*Keyboard|Keyboard.*Demo|HID.*Keyboard|03eb:2042'; then
    status_code="RUBBER"
  elif echo "$rel" | grep -Eiq '(dfu|03eb:|atmel).*?(16u2|8u2|dfu)|\b03eb:'; then
    status_code="DFU"
  elif echo "$rel" | grep -Eiq 'arduino|2341:|2a03:|ch340|1a86:7523|cp210|10c4:ea60|ftdi|0403:6001'; then
    status_code="SERIAL"
  fi

  echo -e "${CYAN}Coincidencias relevantes:${NC}"
  [[ -n "$rel" ]] && echo "$rel" || echo "(sin coincidencias relevantes)"
  echo

  case "$status_code" in
    RUBBER)
      ok "Modo Rubber Ducky detectado (HID teclado)"
      echo "Sugerencia: listo para usar como dispositivo HID."
      ;;
    DFU)
      ok "Modo DFU (ATmega16U2/8U2) detectado"
      echo "Sugerencia: listo para flashear con dfu-programmer."
      ;;
    SERIAL)
      ok "Arduino en modo serie (USB-Serial)"
      echo "Sugerencia: listo para subir sketch desde el IDE o avrdude."
      ;;
    NONE)
      echo -e "${RED}❌ Sin Arduino/DFU conectado${NC}"
      echo -e "${YELLOW}Sugerencia:${NC} usa la opción 2) Activar / esperar modo DFU del menú o conecta el Arduino."
      ;;
  esac

  echo
  echo -e "${CYAN}Dispositivos seriales /dev (informativo):${NC}"
  ls -l /dev/ttyACM* /dev/ttyUSB* 2>/dev/null || echo "(ninguno)"

  pause
}

# ===== Menú =====
load_config
menu(){
  banner
  echo -e "${WHITE}${BOLD}MENÚ PRINCIPAL${NC}"
  separator
  echo " 0) Configuración (timeout, chip, verbose)"
  echo " 1) Instalar dfu-programmer"
  echo " 2) Activar / esperar modo DFU"
  echo " 3) Limpiar flash del 16U2 (erase)"
  echo " 4) Instalar firmware ORIGINAL (serial USB)"
  echo " 5) Instalar firmware RUBBER DUCKY (HID teclado)"
  echo " 6) Ver estado de puertos (lsusb)"
  echo " 7) Salir"
  echo
  read -rp "Elige una opción [0-7]: " opt
  case "${opt:-}" in
    0) accion_0_config ;;
    1) accion_1_instalar_dfu ;;
    2) accion_2_activar_esperar_dfu ;;
    3) accion_3_limpiar_flash ;;
    4) accion_4_instalar_original ;;
    5) accion_5_instalar_ducky ;;
    6) accion_6_estado_puertos ;;
    7) echo -e "${DIM}Saliendo…${NC}"; exit 0 ;;
    *) warn "Opción inválida."; sleep 1 ;;
  esac
}
while true; do menu; done

