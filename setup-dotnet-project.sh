#!/bin/bash

# ============================================================
# setup-dotnet-project.sh
# Prérequis  : dotnet SDK, VS Code, curl, python3
# Usage      : bash setup-dotnet-project.sh
# ============================================================

VSIX_DIR="$(dirname "$(realpath "$0")")/vsix"
VSDBG_DIR="$HOME/.vsdbg"
PLATFORM="linux-x64"

# Extensions requises, dans l'ordre d'installation
EXTENSIONS=(
    "ms-dotnettools.vscode-dotnet-runtime"
    "ms-dotnettools.csharp"
    "ms-dotnettools.csdevkit"
)

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

    echo "  → Récupération de la version de ${extension_id}..."
    local version
    version=$(get_latest_version "$extension_id")

    if [ -z "$version" ]; then
        echo "  ✗ Impossible de récupérer la version de ${extension_id}. Vérifiez la connexion."
        return 1
    fi

    local filename="${extension_id}-${version}.vsix"
    local filepath="${VSIX_DIR}/${filename}"

    if [ -f "$filepath" ]; then
        echo "  ✓ Déjà présent : ${filename}"
        return 0
    fi

    local base_url="https://marketplace.visualstudio.com/_apis/public/gallery/publishers/${publisher}/vsextensions/${package}/${version}/vspackage"

    # Tentative 1 : avec targetPlatform
    echo "  → Téléchargement de ${filename} (${PLATFORM})..."
    curl -sSL -o "$filepath" "${base_url}?targetPlatform=${PLATFORM}"

    if is_valid_zip "$filepath"; then
        echo "  ✓ Téléchargé : ${filename}"
        return 0
    fi

    # Tentative 2 : sans targetPlatform (extension universelle)
    echo "  ↩ Pas de build ${PLATFORM}, tentative universelle..."
    curl -sSL -o "$filepath" "${base_url}"

    if is_valid_zip "$filepath"; then
        echo "  ✓ Téléchargé : ${filename} (universel)"
        return 0
    fi

    echo "  ✗ Échec du téléchargement de ${filename}"
    rm -f "$filepath"
    return 1
}

install_vsix() {
    local extension_id="$1"
    # Cherche le fichier vsix correspondant à cet extension_id
    local filepath
    filepath=$(ls "${VSIX_DIR}/${extension_id}-"*.vsix 2>/dev/null | head -1)

    if [ -z "$filepath" ]; then
        echo "  ✗ Fichier VSIX introuvable pour ${extension_id} dans ${VSIX_DIR}"
        return 1
    fi

    echo "  → Installation de $(basename "$filepath")..."
    code --install-extension "$filepath" --force
    if [ $? -eq 0 ]; then
        echo "  ✓ Installé : $(basename "$filepath")"
    else
        echo "  ✗ Échec de l'installation de $(basename "$filepath")"
        return 1
    fi
}

# ------------------------------------------------------------
# ÉTAPE 1 — Téléchargement des extensions VS Code
# ------------------------------------------------------------

echo ""
echo "=== Extensions VS Code ==="
mkdir -p "$VSIX_DIR"

for ext in "${EXTENSIONS[@]}"; do
    download_vsix "$ext"
done

# ------------------------------------------------------------
# ÉTAPE 2 — Installation des extensions VS Code
# ------------------------------------------------------------

echo ""
echo "=== Installation des extensions VS Code ==="

for ext in "${EXTENSIONS[@]}"; do
    install_vsix "$ext"
done

# ------------------------------------------------------------
# ÉTAPE 3 — Installation de vsdbg
# ------------------------------------------------------------

echo ""
echo "=== Débogueur vsdbg ==="

if [ -f "$VSDBG_DIR/vsdbg" ]; then
    echo "  ✓ vsdbg déjà installé dans $VSDBG_DIR"
else
    echo "  → Installation de vsdbg dans $VSDBG_DIR..."
    curl -sSL https://aka.ms/getvsdbgsh | bash /dev/stdin -v latest -l "$VSDBG_DIR" -r "$PLATFORM"
    if [ $? -eq 0 ]; then
        echo "  ✓ vsdbg installé"
    else
        echo "  ✗ Échec de l'installation de vsdbg"
    fi
fi

# ------------------------------------------------------------
# ÉTAPE 4 — Création du projet .NET
# ------------------------------------------------------------

echo ""
echo "=== Projet .NET ==="
read -p "Entrez le nom de l'application console (ex: ConsoleAppMonProjet): " PROJECT_NAME
if [ -z "$PROJECT_NAME" ]; then
    PROJECT_NAME="ConsoleAppAuto"
    echo "Nom du projet par défaut utilisé: $PROJECT_NAME"
fi

echo "--- Démarrage de la configuration pour $PROJECT_NAME ---"

echo "Création du projet dotnet..."
dotnet new console --use-program-main -o "$PROJECT_NAME"

if [ $? -ne 0 ]; then
    echo "Erreur lors de la création du projet. Arrêt du script."
    exit 1
fi

cd "$PROJECT_NAME"

echo "Détermination de la version du Framework .NET..."
TARGET_FRAMEWORK=$(grep -oP '<TargetFramework>\K[^<]+' "${PROJECT_NAME}.csproj")

if [ -z "$TARGET_FRAMEWORK" ]; then
    echo "ATTENTION : Impossible de déterminer la version du Framework cible. Utilisation de 'net10.0' par défaut."
    TARGET_FRAMEWORK="net10.0"
else
    echo "Framework cible détecté : $TARGET_FRAMEWORK"
fi

# ------------------------------------------------------------
# ÉTAPE 5 — Génération de la configuration VS Code
# ------------------------------------------------------------

mkdir -p .vscode

echo "Génération de .vscode/launch.json..."
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

echo "Génération de .vscode/tasks.json..."
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
echo "--- ✅ Configuration terminée pour $PROJECT_NAME ! ---"
echo ""
echo "IMPORTANT : Ouvrez VS Code depuis CE dossier (pas le dossier parent) :"
echo "  code ."
echo ""
read -p "Ouvrir VS Code maintenant dans $(pwd) ? [o/N] " OPEN_CODE
if [[ "$OPEN_CODE" =~ ^[oO]$ ]]; then
    code .
fi
