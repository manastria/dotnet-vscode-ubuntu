#!/bin/bash

# ============================================================
# install-dotnet-from-prof.sh
# Installe les extensions VS Code et vsdbg pour développer en .NET,
# en téléchargeant les fichiers depuis le poste prof du lab.
# Aucun accès Internet n'est nécessaire.
#
# Prérequis : dotnet SDK, VS Code, curl, python3, tar.
# Usage     : bash install-dotnet-from-prof.sh
# ============================================================

# ------------------------------------------------------------
# Configuration — À AJUSTER avant déploiement dans le master
# ------------------------------------------------------------
PROF_HOST="192.168.1.10"      # IP du poste prof dans le lab
PROF_PORT="8000"
PROF_URL="http://${PROF_HOST}:${PROF_PORT}"

# ------------------------------------------------------------
# Chemins (ne devraient pas avoir à changer)
# ------------------------------------------------------------
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
CACHE_DIR="${HOME}/cache-dotnet"
VSDBG_DIR="${HOME}/.vsdbg"
MANIFEST="${CACHE_DIR}/manifest.json"
DOTNET_INSTALL_CMD="apt install --install-suggests -y dotnet-sdk-10.0"
VSCODE_INSTALL_SCRIPT="${SCRIPT_DIR}/install-vscode.sh"

# ------------------------------------------------------------
# Couleurs (désactivées hors terminal)
# ------------------------------------------------------------
if [ -t 1 ]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_RED=$'\033[0;31m'
    C_GREEN=$'\033[0;32m'
    C_YELLOW=$'\033[1;33m'
    C_BLUE=$'\033[1;34m'
    C_CYAN=$'\033[1;36m'
    C_MAGENTA=$'\033[1;35m'
else
    C_RESET= C_BOLD= C_RED= C_GREEN= C_YELLOW= C_BLUE= C_CYAN= C_MAGENTA=
fi

section() { echo; echo "${C_CYAN}${C_BOLD}=== $* ===${C_RESET}"; }
info()    { echo "  ${C_BLUE}→${C_RESET} $*"; }
success() { echo "  ${C_GREEN}✓${C_RESET} $*"; }
warn()    { echo "  ${C_YELLOW}↩${C_RESET} $*"; }
error()   { echo "  ${C_RED}✗${C_RESET} $*"; }
note()    { echo "${C_MAGENTA}$*${C_RESET}"; }

# ============================================================
# Vérifications de prérequis
# ============================================================

check_dotnet() {
    section "Vérification du SDK .NET"
    if command -v dotnet >/dev/null 2>&1; then
        local version
        version=$(dotnet --version 2>/dev/null)
        if [ -n "$version" ]; then
            success "dotnet détecté — version ${C_BOLD}${version}${C_RESET}"
        else
            warn "dotnet est présent mais ne répond pas à --version"
        fi
        return 0
    fi
    error "Le SDK .NET n'est pas installé sur cette machine."
    echo
    echo "  Pour l'installer, exécutez :"
    echo "    ${C_BOLD}${C_GREEN}sudo ${DOTNET_INSTALL_CMD}${C_RESET}"
    echo
    note "Relancez ensuite ce script."
    exit 1
}

check_vscode() {
    section "Vérification de VS Code"
    if command -v code >/dev/null 2>&1; then
        local version
        version=$(code --version 2>/dev/null | head -n 1)
        if [ -n "$version" ]; then
            success "VS Code détecté — version ${C_BOLD}${version}${C_RESET}"
        else
            warn "code est présent mais ne répond pas à --version"
        fi
        return 0
    fi
    error "VS Code (commande ${C_BOLD}code${C_RESET}) n'est pas installé."
    echo
    if [ -x "$VSCODE_INSTALL_SCRIPT" ]; then
        echo "  Pour l'installer : ${C_BOLD}${C_GREEN}${VSCODE_INSTALL_SCRIPT}${C_RESET}"
    elif [ -f "$VSCODE_INSTALL_SCRIPT" ]; then
        echo "  Pour l'installer : ${C_BOLD}${C_GREEN}bash ${VSCODE_INSTALL_SCRIPT}${C_RESET}"
    else
        warn "Script ${VSCODE_INSTALL_SCRIPT} introuvable — demandez à l'enseignant."
    fi
    echo
    note "Relancez ensuite ce script."
    exit 1
}

check_prof_server() {
    section "Vérification du poste prof"
    info "Adresse configurée : ${C_BOLD}${PROF_URL}${C_RESET}"
    if ! curl -sf --connect-timeout 5 "${PROF_URL}/manifest.json" -o /dev/null; then
        error "Poste prof injoignable à ${PROF_URL}"
        echo
        echo "  Vérifiez auprès de l'enseignant :"
        echo "    - le poste prof est allumé et connecté au réseau du lab ;"
        echo "    - le service ${C_BOLD}dotnet-cache${C_RESET} est démarré sur le poste prof."
        echo
        exit 1
    fi
    success "Poste prof accessible"
}

# ============================================================
# Manifest
# ============================================================

fetch_manifest() {
    mkdir -p "$CACHE_DIR"
    info "Téléchargement du manifest..."
    if ! curl -sSL --fail -o "$MANIFEST" "${PROF_URL}/manifest.json"; then
        error "Échec du téléchargement du manifest"
        exit 1
    fi
    success "manifest.json récupéré"
}

# Parse le manifest et imprime, pour chaque extension : id<TAB>file<TAB>sha256
parse_extensions() {
    python3 - "$MANIFEST" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    m = json.load(f)
for ext in m.get("extensions", []):
    print(f"{ext['id']}\t{ext['file']}\t{ext['sha256']}")
PYEOF
}

# Parse le manifest et imprime, si vsdbg présent : file<TAB>sha256
parse_vsdbg() {
    python3 - "$MANIFEST" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    m = json.load(f)
v = m.get("vsdbg")
if v:
    print(f"{v['file']}\t{v['sha256']}")
PYEOF
}

# ============================================================
# Téléchargement avec vérification SHA256
# ============================================================

# Args : nom_fichier sha256_attendu
# Retourne 0 si fichier en cache local valide ou téléchargement OK ; 1 sinon.
ensure_file() {
    local file="$1"
    local sha="$2"
    local local_path="${CACHE_DIR}/${file}"

    if [ -f "$local_path" ]; then
        local local_sha
        local_sha=$(sha256sum "$local_path" | cut -d' ' -f1)
        if [ "$local_sha" = "$sha" ]; then
            return 0
        fi
        warn "Cache local corrompu pour ${file}, re-téléchargement..."
        rm -f "$local_path"
    fi

    info "Téléchargement de ${file}..."
    if ! curl -sSL --fail -o "$local_path" "${PROF_URL}/${file}"; then
        error "Échec du téléchargement de ${file}"
        return 1
    fi

    local got_sha
    got_sha=$(sha256sum "$local_path" | cut -d' ' -f1)
    if [ "$got_sha" != "$sha" ]; then
        error "Somme SHA256 incorrecte pour ${file}"
        rm -f "$local_path"
        return 1
    fi
    return 0
}

# ============================================================
# Extensions VS Code
# ============================================================

install_extensions() {
    section "Extensions VS Code"

    # Liste des extensions déjà installées (en minuscules pour comparaison)
    local installed
    installed=$(code --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]')

    local ext_id file sha ext_id_lc local_path
    while IFS=$'\t' read -r ext_id file sha; do
        ext_id_lc="${ext_id,,}"

        # Skip silencieux si déjà installée
        if echo "$installed" | grep -qix "$ext_id_lc"; then
            success "Déjà installée : ${C_BOLD}${ext_id}${C_RESET}"
            continue
        fi

        if ! ensure_file "$file" "$sha"; then
            continue
        fi

        local_path="${CACHE_DIR}/${file}"
        info "Installation de ${ext_id}..."
        if code --install-extension "$local_path" --force >/dev/null 2>&1; then
            success "Installée : ${C_BOLD}${ext_id}${C_RESET}"
        else
            error "Échec de l'installation de ${ext_id}"
        fi
    done < <(parse_extensions)
}

# ============================================================
# vsdbg
# ============================================================

install_vsdbg() {
    section "Débogueur vsdbg"

    if [ -f "$VSDBG_DIR/vsdbg" ]; then
        success "Déjà installé dans ${VSDBG_DIR}"
        return 0
    fi

    local vsdbg_info file sha
    vsdbg_info=$(parse_vsdbg)
    if [ -z "$vsdbg_info" ]; then
        warn "Pas d'archive vsdbg dans le manifest — étape ignorée."
        return 0
    fi
    IFS=$'\t' read -r file sha <<< "$vsdbg_info"

    if ! ensure_file "$file" "$sha"; then
        return 1
    fi

    info "Extraction dans ${VSDBG_DIR}..."
    mkdir -p "$VSDBG_DIR"
    if ! tar -xzf "${CACHE_DIR}/${file}" -C "$VSDBG_DIR"; then
        error "Échec de l'extraction"
        return 1
    fi

    if [ -f "$VSDBG_DIR/vsdbg" ]; then
        chmod +x "$VSDBG_DIR/vsdbg"
        success "Installé dans ${VSDBG_DIR}"
    else
        error "Archive extraite mais binaire vsdbg manquant"
        return 1
    fi
}

# ============================================================
# Exécution
# ============================================================

check_dotnet
check_vscode
check_prof_server

fetch_manifest
install_extensions
install_vsdbg

echo
note "✅ Installation terminée."
echo "  Vous pouvez fermer cette fenêtre et lancer VS Code."
echo
echo "  Appuyez sur Entrée pour fermer..."
read -r
