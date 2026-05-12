# Déploiement .NET en lab — poste prof + postes étudiants

## Vue d'ensemble

```
                Internet (annuel)
                       │
                       ▼
            ┌──────────────────────┐
            │     Poste prof       │
            │                      │
            │  install-dotnet-     │  ← toi, 1×/an (ou par version dotnet)
            │  deps.sh             │
            │     │                │
            │     ▼                │
            │  ~/cache-dotnet/     │
            │  ├── *.vsix          │
            │  ├── vsdbg/          │
            │  ├── manifest.json   │  ← prepare-cache.sh
            │  └── vsdbg.tar.gz    │
            │                      │
            │  python -m http.server 8000  ← dotnet-cache.service (auto)
            └──────────┬───────────┘
                       │ HTTP (lab)
        ┌──────────────┼──────────────┐
        ▼              ▼              ▼
    Étudiant 1    Étudiant 2    Étudiant N
    install-dotnet-from-prof.sh  (1 clic)
```

L'enseignant ne touche à rien : le poste prof démarre, le service systemd lance
le serveur HTTP, et chaque étudiant lance le script qui télécharge depuis le
réseau local.

---

## A. Poste prof — mise en place (à faire 1 fois par JP)

### 1. Remplir le cache (téléchargement Internet)

```bash
bash install-dotnet-deps.sh
bash prepare-cache.sh
```

Le second script génère `manifest.json` et `vsdbg.tar.gz` dans `~/cache-dotnet/`.

### 2. Installer le service systemd

```bash
sudo cp dotnet-cache.service /etc/systemd/system/
# Vérifier User= et WorkingDirectory= si le compte enseignant ≠ "prof"
sudo systemctl daemon-reload
sudo systemctl enable --now dotnet-cache
sudo systemctl status dotnet-cache    # vérification
```

Tester depuis une autre machine du lab :
```bash
curl http://IP_DU_POSTE_PROF:8000/manifest.json
```

### 3. Ouvrir le pare-feu si nécessaire

XUbuntu par défaut n'a pas ufw actif, mais si tu l'as activé :
```bash
sudo ufw allow from 192.168.1.0/24 to any port 8000 proto tcp
```

### 4. Mise à jour annuelle

Quand une nouvelle version de .NET sort, ou pour rafraîchir les extensions :
```bash
rm -rf ~/cache-dotnet      # forcer un téléchargement complet (optionnel)
bash install-dotnet-deps.sh
bash prepare-cache.sh
# Le service tourne déjà, rien d'autre à faire.
```

---

## B. Postes étudiants — intégration au master

### 1. Ajuster l'IP du poste prof

Dans `install-dotnet-from-prof.sh` :
```bash
PROF_HOST="192.168.1.10"   # ← mettre l'IP réelle du poste prof
```

### 2. Déposer le script

```bash
sudo install -m 0755 install-dotnet-from-prof.sh /usr/local/bin/install-dotnet
sudo install -m 0755 install-vscode.sh /usr/local/bin/install-vscode   # si dispo
```

### 3. Icône de bureau (recommandé pour des 1A/S1)

Créer `/usr/local/share/applications/install-dotnet.desktop` :

```ini
[Desktop Entry]
Type=Application
Name=Installer .NET pour VS Code
Comment=Télécharge et installe les extensions depuis le poste prof
Exec=xfce4-terminal --title="Installation .NET" --hold -e "/usr/local/bin/install-dotnet"
Icon=visual-studio-code
Terminal=false
Categories=Development;
```

Puis déposer un raccourci sur le bureau des étudiants :
```bash
sudo install -m 0755 /usr/local/share/applications/install-dotnet.desktop \
    /etc/skel/Desktop/
```
(les nouveaux comptes auront automatiquement l'icône ; pour les comptes
existants, copier manuellement dans `~/Desktop/`).

### 4. Préinstaller dotnet SDK et VS Code dans le master

Le script étudiant **vérifie** ces prérequis mais ne les installe pas (besoin
de sudo). Le plus simple : les inclure dans l'image XUbuntu master.

---

## C. Expérience finale

**Enseignant**
- Allume le poste prof. C'est tout.
- Pour vérifier le serveur : ouvrir Firefox sur `http://localhost:8000/manifest.json`.

**Étudiant**
- Double-clic sur l'icône "Installer .NET" du bureau.
- 1–2 minutes de progression colorée.
- Fermer la fenêtre.

**Toi, 1×/an**
- Sur le poste prof : `bash install-dotnet-deps.sh && bash prepare-cache.sh`.

---

## Dépannage rapide

| Symptôme étudiant | Cause probable | Action |
|---|---|---|
| `Poste prof injoignable` | Service arrêté ou réseau | `sudo systemctl status dotnet-cache` côté prof |
| `SHA256 incorrecte` | Téléchargement coupé | Relancer le script (le fichier corrompu est supprimé automatiquement) |
| `dotnet n'est pas installé` | Master incomplet | Master à refaire, ou apt côté étudiant |
| `code n'est pas installé` | Master incomplet | Idem |

Côté prof, logs du serveur :
```bash
journalctl -u dotnet-cache -f
```
On y voit les requêtes HTTP des étudiants en direct (utile pour vérifier que
toute la classe télécharge bien).
