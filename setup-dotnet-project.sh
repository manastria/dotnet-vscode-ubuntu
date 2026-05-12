#!/bin/bash

# ============================================================
# setup-dotnet-project.sh
# Prérequis  : dotnet SDK, VS Code, curl, python3
# Usage      : bash setup-dotnet-project.sh
# ============================================================

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
VSIX_DIR="${SCRIPT_DIR}/vsix"
VSDBG_DIR="$HOME/.vsdbg"
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
# Couleurs (désactivées hors terminal, ex: redirection vers fichier)
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
# Fonctions utilitaires
# ------------------------------------------------------------

get_latest_version() {
    local extension_id="$1"
    local publisher="${extension_id%%.*}"
    local package="${extension_id##*.}"
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

download_vsix() {
    local extension_id="$1"
    local publisher="${extension_id%%.*}"
    local package="${extension_id##*.}"

    info "Récupération de la version de ${C_BOLD}${extension_id}${C_RESET}..."
    local version
    version=$(get_latest_version "$extension_id")

    if [ -z "$version" ]; then
        error "Impossible de récupérer la version de ${extension_id}. Vérifiez la connexion."
        return 1
    fi

    local filename="${extension_id}-${version}.vsix"
    local filepath="${VSIX_DIR}/${filename}"

    if [ -f "$filepath" ]; then
        success "Déjà présent : ${filename}"
        return 0
    fi

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
    # Cherche le fichier vsix correspondant à cet extension_id
    local filepath
    filepath=$(ls "${VSIX_DIR}/${extension_id}-"*.vsix 2>/dev/null | head -1)

    if [ -z "$filepath" ]; then
        error "Fichier VSIX introuvable pour ${extension_id} dans ${VSIX_DIR}"
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
# ÉTAPE 0 — Vérification des prérequis (dotnet, VS Code)
# ------------------------------------------------------------

check_dotnet
check_vscode

# ------------------------------------------------------------
# ÉTAPE 1 — Téléchargement des extensions VS Code
# ------------------------------------------------------------

section "Extensions VS Code"
mkdir -p "$VSIX_DIR"

for ext in "${EXTENSIONS[@]}"; do
    download_vsix "$ext"
done

# ------------------------------------------------------------
# ÉTAPE 2 — Installation des extensions VS Code
# ------------------------------------------------------------

section "Installation des extensions VS Code"

for ext in "${EXTENSIONS[@]}"; do
    install_vsix "$ext"
done

# ------------------------------------------------------------
# ÉTAPE 3 — Installation de vsdbg
# ------------------------------------------------------------

section "Débogueur vsdbg"

if [ -f "$VSDBG_DIR/vsdbg" ]; then
    success "vsdbg déjà installé dans $VSDBG_DIR"
else
    info "Installation de vsdbg dans $VSDBG_DIR..."
    curl -sSL https://aka.ms/getvsdbgsh | bash /dev/stdin -v latest -l "$VSDBG_DIR" -r "$PLATFORM"
    if [ $? -eq 0 ]; then
        success "vsdbg installé"
    else
        error "Échec de l'installation de vsdbg"
    fi
fi

# ------------------------------------------------------------
# ÉTAPE 4 — Création du projet .NET
# ------------------------------------------------------------

section "Projet .NET"
read -p "Entrez le nom de l'application console (ex: ConsoleAppMonProjet): " PROJECT_NAME
if [ -z "$PROJECT_NAME" ]; then
    PROJECT_NAME="ConsoleAppAuto"
    info "Nom du projet par défaut utilisé : ${C_BOLD}${PROJECT_NAME}${C_RESET}"
fi

note "--- Démarrage de la configuration pour ${C_BOLD}${PROJECT_NAME}${C_RESET} ---"

info "Création du projet dotnet..."
dotnet new console --use-program-main -o "$PROJECT_NAME"

if [ $? -ne 0 ]; then
    error "Erreur lors de la création du projet. Arrêt du script."
    exit 1
fi

cd "$PROJECT_NAME"

info "Détermination de la version du Framework .NET..."
TARGET_FRAMEWORK=$(grep -oP '<TargetFramework>\K[^<]+' "${PROJECT_NAME}.csproj")

if [ -z "$TARGET_FRAMEWORK" ]; then
    warn "Impossible de déterminer la version du Framework cible. Utilisation de ${C_BOLD}net10.0${C_RESET} par défaut."
    TARGET_FRAMEWORK="net10.0"
else
    success "Framework cible détecté : ${C_BOLD}${TARGET_FRAMEWORK}${C_RESET}"
fi

# ------------------------------------------------------------
# ÉTAPE 5 — Génération de la configuration VS Code
# ------------------------------------------------------------

mkdir -p .vscode

info "Génération de .vscode/launch.json..."
cat > .vscode/launch.json << EOL
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": ".NET Core Launch (console)",
            "type": "coreclr",
            "request": "launch",
            "preLaunchTask": "build",
            "program": "\${workspaceFolder}/bin/Debug/${TARGET_FRAMEWORK}/${PROJECT_NAME}.dll",
            "args": [],
            "cwd": "\${workspaceFolder}",
            "stopAtEntry": false,
            "console": "integratedTerminal",
            "justMyCode": false,
            "requireExactSource": false
        }
    ]
}
EOL

info "Génération de .vscode/tasks.json..."
cat > .vscode/tasks.json << EOL
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "build",
            "command": "dotnet",
            "type": "process",
            "args": [
                "build",
                "\${workspaceFolder}",
                "/property:GenerateFullPaths=true",
                "/consoleloggerparameters:NoSummary"
            ],
            "problemMatcher": "\$msCompile",
            "group": {
                "kind": "build",
                "isDefault": true
            }
        }
    ]
}
EOL

echo ""
echo "${C_GREEN}${C_BOLD}--- ✅ Configuration terminée pour ${PROJECT_NAME} ! ---${C_RESET}"
echo ""
echo "${C_YELLOW}${C_BOLD}IMPORTANT${C_RESET} : Ouvrez VS Code depuis CE dossier (pas le dossier parent) :"
echo "    ${C_BOLD}code .${C_RESET}"
echo ""
read -p "Ouvrir VS Code maintenant dans $(pwd) ? [o/N] " OPEN_CODE
if [[ "$OPEN_CODE" =~ ^[oO]$ ]]; then
    code .
fi
