#!/bin/bash

# ============================================================
# create-dotnet-project.sh
# Crée un nouveau projet .NET console avec sa configuration VS Code
# (launch.json + tasks.json), prêt à être débogué avec F5.
#
# Prérequis : dotnet SDK, VS Code
#             (les extensions doivent avoir été installées au préalable
#              via install-dotnet-deps.sh)
# Usage     : bash create-dotnet-project.sh
# ============================================================

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
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

# ============================================================
# Exécution
# ============================================================

check_dotnet
check_vscode

# ------------------------------------------------------------
# Création du projet .NET
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
# Configuration VS Code
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
