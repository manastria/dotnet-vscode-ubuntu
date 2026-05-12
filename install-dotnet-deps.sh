#!/bin/bash

# ============================================================
# install-dotnet-deps.sh
# Installe les extensions VS Code et vsdbg pour développer en .NET.
# Met en cache les téléchargements dans ${HOME}/cache-dotnet,
# de sorte que le répertoire peut être distribué (clé USB, partage, etc.)
# pour une installation hors-ligne sur les postes des étudiants.
#
# Prérequis : dotnet SDK, VS Code, curl, python3
# Usage     : bash install-dotnet-deps.sh
# ============================================================

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
CACHE_DIR="${HOME}/cache-dotnet"
VSDBG_CACHE_DIR="${CACHE_DIR}/vsdbg"
VSDBG_DIR="${HOME}/.vsdbg"
PLATFORM="linux-x64"
DOTNET_INSTALL_CMD="apt install --install-suggests -y dotnet-sdk-10.0"
VSCODE_INSTALL_SCRIPT="${SCRIPT_DIR}/install-vscode.sh"

# Extensions requises, dans l'ordre d'installation
EXTENSIONS=(
    "ms-dotnettools.vscode-dotnet-runtime"
    "ms-dotnettools.csharp"
    "ms-dotnettools.csdevkit"
)

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

# ------------------------------------------------------------
# Vérification des prérequis
# ------------------------------------------------------------

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

    error "VS Code (commande ${C_BOLD}code${C_RESET}) n'est pas installé sur cette machine."
    echo
    if [ -x "$VSCODE_INSTALL_SCRIPT" ]; then
        echo "  Pour l'installer, exécutez le script fourni :"
        echo "    ${C_BOLD}${C_GREEN}${VSCODE_INSTALL_SCRIPT}${C_RESET}"
    elif [ -f "$VSCODE_INSTALL_SCRIPT" ]; then
        echo "  Pour l'installer, exécutez le script fourni :"
        echo "    ${C_BOLD}${C_GREEN}bash ${VSCODE_INSTALL_SCRIPT}${C_RESET}"
    else
        warn "Script ${VSCODE_INSTALL_SCRIPT} introuvable."
        echo "  Récupérez install-vscode.sh dans le même dossier que ce script, puis exécutez-le."
    fi
    echo
    note "Relancez ensuite ce script."
    exit 1
}

# ------------------------------------------------------------
# Extensions VS Code (téléchargement + installation)
# ------------------------------------------------------------

get_latest_version() {
    local extension_id="$1"
    curl -s -X POST "https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json;api-version=7.1-preview.1" \
        -d "{\"filters\":[{\"criteria\":[{\"filterType\":7,\"value\":\"${extension_id}\"}]}],\"flags\":529}" \
        | python3 -c "import sys,json; data=json.load(sys.stdin); print(data['results'][0]['extensions'][0]['versions'][0]['version'])" 2>/dev/null
}

is_valid_zip() {
    # Vérifie la magic signature ZIP (PK = 0x504B)
    local file="$1"
    [ -f "$file" ] && [ "$(xxd -p -l 2 "$file")" = "504b" ]
}

# Cherche dans le cache un VSIX déjà présent pour cet extension_id, indépendamment de la version
find_cached_vsix() {
    local extension_id="$1"
    ls "${CACHE_DIR}/${extension_id}-"*.vsix 2>/dev/null | head -1
}

download_vsix() {
    local extension_id="$1"
    local publisher="${extension_id%%.*}"
    local package="${extension_id##*.}"

    # Si un VSIX pour cette extension existe déjà dans le cache, on l'utilise tel quel
    local cached
    cached=$(find_cached_vsix "$extension_id")
    if [ -n "$cached" ]; then
        success "Cache HIT : $(basename "$cached")"
        return 0
    fi

    info "Récupération de la version de ${C_BOLD}${extension_id}${C_RESET}..."
    local version
    version=$(get_latest_version "$extension_id")

    if [ -z "$version" ]; then
        error "Impossible de récupérer la version de ${extension_id}. Vérifiez la connexion."
        return 1
    fi

    local filename="${extension_id}-${version}.vsix"
    local filepath="${CACHE_DIR}/${filename}"
    local base_url="https://marketplace.visualstudio.com/_apis/public/gallery/publishers/${publisher}/vsextensions/${package}/${version}/vspackage"

    # Tentative 1 : avec targetPlatform
    # --compressed : indispensable, le marketplace renvoie le VSIX avec Content-Encoding: gzip
    # --fail       : renvoie une erreur sur HTTP != 2xx au lieu d'enregistrer le corps d'erreur JSON
    info "Téléchargement de ${filename} (${PLATFORM})..."
    curl -sSL --compressed --fail -o "$filepath" "${base_url}?targetPlatform=${PLATFORM}"

    if is_valid_zip "$filepath"; then
        success "Téléchargé : ${filename}"
        return 0
    fi

    # Tentative 2 : sans targetPlatform (extension universelle)
    warn "Pas de build ${PLATFORM}, tentative universelle..."
    curl -sSL --compressed --fail -o "$filepath" "${base_url}"

    if is_valid_zip "$filepath"; then
        success "Téléchargé : ${filename} (universel)"
        return 0
    fi

    error "Échec du téléchargement de ${filename}"
    rm -f "$filepath"
    return 1
}

install_vsix() {
    local extension_id="$1"
    local filepath
    filepath=$(find_cached_vsix "$extension_id")

    if [ -z "$filepath" ]; then
        error "Fichier VSIX introuvable pour ${extension_id} dans ${CACHE_DIR}"
        return 1
    fi

    info "Installation de $(basename "$filepath")..."
    code --install-extension "$filepath" --force
    if [ $? -eq 0 ]; then
        success "Installé : $(basename "$filepath")"
    else
        error "Échec de l'installation de $(basename "$filepath")"
        return 1
    fi
}

# ------------------------------------------------------------
# vsdbg (cache + installation dans $HOME/.vsdbg)
# ------------------------------------------------------------

install_vsdbg() {
    if [ -f "$VSDBG_DIR/vsdbg" ]; then
        success "vsdbg déjà installé dans $VSDBG_DIR"
        return 0
    fi

    if [ -f "$VSDBG_CACHE_DIR/vsdbg" ]; then
        info "Restauration de vsdbg depuis le cache ($VSDBG_CACHE_DIR)..."
        mkdir -p "$VSDBG_DIR"
        cp -a "$VSDBG_CACHE_DIR/." "$VSDBG_DIR/"
        if [ -f "$VSDBG_DIR/vsdbg" ]; then
            success "vsdbg restauré dans $VSDBG_DIR"
            return 0
        fi
        error "Échec de la copie depuis le cache"
        return 1
    fi

    info "Téléchargement de vsdbg vers le cache ($VSDBG_CACHE_DIR)..."
    mkdir -p "$VSDBG_CACHE_DIR"
    curl -sSL https://aka.ms/getvsdbgsh | bash /dev/stdin -v latest -l "$VSDBG_CACHE_DIR" -r "$PLATFORM"

    if [ ! -f "$VSDBG_CACHE_DIR/vsdbg" ]; then
        error "Échec du téléchargement de vsdbg"
        return 1
    fi
    success "vsdbg mis en cache"

    info "Copie de vsdbg dans $VSDBG_DIR..."
    mkdir -p "$VSDBG_DIR"
    cp -a "$VSDBG_CACHE_DIR/." "$VSDBG_DIR/"
    if [ -f "$VSDBG_DIR/vsdbg" ]; then
        success "vsdbg installé dans $VSDBG_DIR"
    else
        error "Échec de l'installation de vsdbg"
        return 1
    fi
}

# ============================================================
# Exécution
# ============================================================

check_dotnet
check_vscode

section "Cache de distribution"
mkdir -p "$CACHE_DIR"
info "Répertoire de cache : ${C_BOLD}${CACHE_DIR}${C_RESET}"

section "Téléchargement des extensions VS Code"
for ext in "${EXTENSIONS[@]}"; do
    download_vsix "$ext"
done

section "Installation des extensions VS Code"
for ext in "${EXTENSIONS[@]}"; do
    install_vsix "$ext"
done

section "Débogueur vsdbg"
install_vsdbg

echo
note "✅ Installation terminée."
echo "  Le contenu de ${C_BOLD}${CACHE_DIR}${C_RESET} peut être distribué aux étudiants"
echo "  (à recopier dans leur propre ${C_BOLD}\$HOME/cache-dotnet${C_RESET} avant de relancer ce script)."
