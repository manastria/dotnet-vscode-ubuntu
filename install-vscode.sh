#!/usr/bin/env bash
# install-vscode.sh — Installe/Met à jour VS Code (stable ou insiders) sur Debian/Ubuntu (idempotent)
# Options :
#   --insiders      : installe code-insiders au lieu de code
#   --refresh-key   : force la (ré)importation de la clé Microsoft
#   --remove        : (facultatif) supprime VS Code + dépôt + clé
# Exemples :
#   ./install-vscode.sh
#   ./install-vscode.sh --insiders
#   ./install-vscode.sh --refresh-key

set -Eeuo pipefail

PKG="code"              # par défaut stable
FORCE_REFRESH_KEY="no"
DO_REMOVE="no"

# --- Parse args ---
for arg in "$@"; do
  case "$arg" in
    --insiders) PKG="code-insiders" ;;
    --refresh-key) FORCE_REFRESH_KEY="yes" ;;
    --remove) DO_REMOVE="yes" ;;
    *) echo "Option inconnue: $arg" >&2; exit 2 ;;
  esac
done

# --- Vérifs OS ---
if [[ -r /etc/os-release ]]; then
  . /etc/os-release
  LIKE="${ID_LIKE:-}"
  if [[ "${ID:-}" != "debian" && "${ID:-}" != "ubuntu" && "$LIKE" != *debian* && "$LIKE" != *ubuntu* ]]; then
    echo "Cet installateur cible Debian/Ubuntu (ou dérivés). Trouvé: ID=${ID:-?} ID_LIKE=${LIKE}" >&2
    exit 1
  fi
else
  echo "/etc/os-release introuvable : OS non supporté." >&2
  exit 1
fi

# --- Élévation des privilèges (Tier 1 : auto-relaunch sans -E) ---
if [[ "$EUID" -ne 0 ]]; then
    exec sudo "$(readlink -f "$0")" "$@"
fi

# --- Utilitaires requis ---
apt-get update -y -o Dir::Etc::sourcelist="sources.list" -o Dir::Etc::sourceparts="sources.list.d" -o APT::Get::List-Cleanup="0" >/dev/null || true
DEPS=(wget gpg)
apt-get install -y --no-install-recommends "${DEPS[@]}"

KEY_DST="/usr/share/keyrings/microsoft.gpg"
SRC_DIR="/etc/apt/sources.list.d"
SRC_FILE="${SRC_DIR}/vscode.sources"

# --- Suppression (optionnelle) ---
if [[ "$DO_REMOVE" == "yes" ]]; then
  if dpkg -s "$PKG" >/dev/null 2>&1; then
    apt-get purge -y "$PKG"
  fi
  rm -f "$SRC_FILE"
  rm -f "$KEY_DST"
  apt-get update || true
  echo "VS Code (${PKG}) et le dépôt Microsoft ont été supprimés."
  exit 0
fi

# --- Import clé (idempotent) ---
import_key() {
  tmp="$(mktemp)"
  # Clé publique Microsoft (packages.microsoft.com)
  wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > "$tmp"
  install -D -o root -g root -m 0644 "$tmp" "$KEY_DST"
  rm -f "$tmp"
}

if [[ ! -f "$KEY_DST" ]]; then
  import_key
elif [[ "$FORCE_REFRESH_KEY" == "yes" ]]; then
  import_key
fi

# --- Dépôt (Deb822 .sources, idempotent) ---
mkdir -p "$SRC_DIR"
ARCH="$(dpkg --print-architecture)" # amd64, arm64, armhf...
# On limite aux archs supportées, mais on inclut l’arch locale si compatible
case "$ARCH" in
  amd64|arm64|armhf) ARCH_LINE="Architectures: amd64,arm64,armhf" ;;
  *)                 ARCH_LINE="Architectures: amd64,arm64,armhf" ;; # par défaut (APT ignorera les arch non concernées)
esac

desired_content=$(cat <<EOF
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
${ARCH_LINE}
Signed-By: ${KEY_DST}
EOF
)

if [[ -f "$SRC_FILE" ]]; then
  # Réécrire seulement si différent (idempotence)
  if ! diff -q <(printf '%s\n' "$desired_content") "$SRC_FILE" >/dev/null 2>&1; then
    printf '%s\n' "$desired_content" > "$SRC_FILE"
  fi
else
  printf '%s\n' "$desired_content" > "$SRC_FILE"
fi

# --- Update + Install/Upgrade ---
apt-get update

# Installer ou mettre à jour vers la dernière version (idempotent)
if dpkg -s "$PKG" >/dev/null 2>&1; then
  # Mettre à jour seulement si une version plus récente est disponible
  apt-get install -y "$PKG"
else
  apt-get install -y "$PKG"
fi

# --- Afficher la version installée ---
INSTALLED_VER="$(dpkg-query -W -f='${Version}\n' "$PKG" 2>/dev/null || true)"
echo "VS Code package: $PKG"
echo "Version installée : ${INSTALLED_VER:-inconnue}"

# --- Conseils ---
# Le dépôt Microsoft peut avoir jusqu'à ~3h de décalage avant la dispo de la dernière version.
# Code se mettra ensuite à jour via APT comme les autres paquets.
