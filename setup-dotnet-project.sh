#!/bin/bash

# --- Configuration du Projet ---
# Récupère le nom du projet de l'utilisateur ou utilise une valeur par défaut
read -p "Entrez le nom de l'application console (ex: ConsoleAppMonProjet): " PROJECT_NAME
if [ -z "$PROJECT_NAME" ]; then
    PROJECT_NAME="ConsoleAppAuto"
    echo "Nom du projet par défaut utilisé: $PROJECT_NAME"
fi

echo "--- Démarrage de la configuration pour $PROJECT_NAME ---"

# 1. Créer le projet avec l'option --use-program-main
echo "Création du projet dotnet..."
dotnet new console --use-program-main -o "$PROJECT_NAME"

# Vérifie si la création du projet a réussi
if [ $? -ne 0 ]; then
    echo "Erreur lors de la création du projet. Arrêt du script."
    exit 1
fi

# 2. Naviguer dans le répertoire du projet
cd "$PROJECT_NAME"

# 3. Automatisation de la découverte de la version du Framework cible
# La version cible (ex: net9.0) se trouve dans le fichier .csproj
# On utilise 'grep' pour trouver la balise <TargetFramework> et 'cut' pour extraire la valeur.
echo "Détermination de la version du Framework .NET..."
TARGET_FRAMEWORK=$(grep -oP '<TargetFramework>\K[^<]+' "${PROJECT_NAME}.csproj")

if [ -z "$TARGET_FRAMEWORK" ]; then
    echo "ATTENTION : Impossible de déterminer la version du Framework cible. Utilisation de 'net9.0' par défaut."
    TARGET_FRAMEWORK="net9.0"
else
    echo "Framework cible détecté : $TARGET_FRAMEWORK"
fi

# 4. Créer le répertoire .vscode
mkdir .vscode

# 5. Créer le fichier launch.json
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
            "console": "integratedTerminal"
        }
    ]
}
EOL

# 6. Créer le fichier tasks.json
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
                "\${workspaceFolder}/${PROJECT_NAME}.csproj", 
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

echo "--- ✅ Configuration terminée pour $PROJECT_NAME ! ---"
echo "Ouvrez le dossier $PROJECT_NAME dans Visual Studio Code pour commencer à coder et déboguer."