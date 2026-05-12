#!/bin/bash

# ============================================================
# prepare-cache.sh
# À exécuter sur le poste prof, APRÈS install-dotnet-deps.sh.
# Génère deux artefacts dans ~/cache-dotnet/ servis ensuite via HTTP :
#   - manifest.json     : index des extensions (id, fichier, sha256, taille)
#   - vsdbg.tar.gz      : archive du débogueur vsdbg
#
# Le manifest est le point d'entrée du script étudiant.
# ============================================================

set -e

CACHE_DIR="${HOME}/cache-dotnet"
VSDBG_CACHE_DIR="${CACHE_DIR}/vsdbg"
MANIFEST="${CACHE_DIR}/manifest.json"
VSDBG_ARCHIVE="${CACHE_DIR}/vsdbg.tar.gz"

# ------------------------------------------------------------
# Couleurs
# ------------------------------------------------------------
if [ -t 1 ]; then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
    C_GREEN=$'\033[0;32m'; C_RED=$'\033[0;31m'; C_YELLOW=$'\033[1;33m'
    C_CYAN=$'\033[1;36m'; C_BLUE=$'\033[1;34m'; C_MAGENTA=$'\033[1;35m'
else
    C_RESET= C_BOLD= C_GREEN= C_RED= C_YELLOW= C_CYAN= C_BLUE= C_MAGENTA=
fi

section() { echo; echo "${C_CYAN}${C_BOLD}=== $* ===${C_RESET}"; }
info()    { echo "  ${C_BLUE}→${C_RESET} $*"; }
success() { echo "  ${C_GREEN}✓${C_RESET} $*"; }
warn()    { echo "  ${C_YELLOW}↩${C_RESET} $*"; }
error()   { echo "  ${C_RED}✗${C_RESET} $*"; }
note()    { echo "${C_MAGENTA}$*${C_RESET}"; }

# ------------------------------------------------------------
# Vérifications
# ------------------------------------------------------------

if [ ! -d "$CACHE_DIR" ]; then
    error "Répertoire ${CACHE_DIR} introuvable."
    echo "  Exécutez d'abord install-dotnet-deps.sh."
    exit 1
fi

shopt -s nullglob
vsix_files=("$CACHE_DIR"/*.vsix)
if [ ${#vsix_files[@]} -eq 0 ]; then
    error "Aucun .vsix trouvé dans ${CACHE_DIR}."
    echo "  Exécutez d'abord install-dotnet-deps.sh."
    exit 1
fi

# ------------------------------------------------------------
# Archive vsdbg (avant le manifest, pour calculer son sha256)
# ------------------------------------------------------------

vsdbg_sha=""
vsdbg_size=0

if [ -d "$VSDBG_CACHE_DIR" ] && [ -f "$VSDBG_CACHE_DIR/vsdbg" ]; then
    section "Création de vsdbg.tar.gz"
    info "Compression de ${VSDBG_CACHE_DIR}..."
    tar -czf "$VSDBG_ARCHIVE" -C "$VSDBG_CACHE_DIR" .
    vsdbg_sha=$(sha256sum "$VSDBG_ARCHIVE" | cut -d' ' -f1)
    vsdbg_size=$(stat -c%s "$VSDBG_ARCHIVE")
    success "Archive créée : $(numfmt --to=iec "$vsdbg_size")"
else
    warn "vsdbg absent — l'archive ne sera pas créée."
fi

# ------------------------------------------------------------
# Manifest JSON
# ------------------------------------------------------------

section "Génération du manifest.json"

python3 - "$MANIFEST" "$vsdbg_sha" "$vsdbg_size" "${vsix_files[@]}" <<'PYEOF'
import json
import sys
import re
import os
import hashlib
from datetime import datetime, timezone

manifest_path = sys.argv[1]
vsdbg_sha     = sys.argv[2]
vsdbg_size    = int(sys.argv[3])
vsix_paths    = sys.argv[4:]

def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()

# Nom de fichier attendu : publisher.package-VERSION.vsix
# La version commence au dernier '-' suivi d'un chiffre.
NAME_RE = re.compile(r"^(?P<id>.+)-(?P<ver>\d[^-].*?)\.vsix$")

extensions = []
for path in sorted(vsix_paths):
    name = os.path.basename(path)
    m = NAME_RE.match(name)
    if not m:
        print(f"  ! Nom inattendu, ignoré : {name}", file=sys.stderr)
        continue
    extensions.append({
        "id":      m.group("id"),
        "version": m.group("ver"),
        "file":    name,
        "sha256":  sha256_of(path),
        "size":    os.path.getsize(path),
    })

manifest = {
    "generated":  datetime.now(timezone.utc).isoformat(timespec="seconds"),
    "platform":   "linux-x64",
    "extensions": extensions,
}

if vsdbg_sha:
    manifest["vsdbg"] = {
        "file":   "vsdbg.tar.gz",
        "sha256": vsdbg_sha,
        "size":   vsdbg_size,
    }
else:
    manifest["vsdbg"] = None

with open(manifest_path, "w") as f:
    json.dump(manifest, f, indent=2)
    f.write("\n")

print(f"  ✓ {len(extensions)} extension(s) référencée(s)")
PYEOF

success "Manifest écrit : ${MANIFEST}"

# ------------------------------------------------------------
# Résumé
# ------------------------------------------------------------

section "Résumé"
echo "  ${C_BOLD}${CACHE_DIR}${C_RESET} est prêt à être servi :"
ls -lh "$CACHE_DIR"/*.vsix "$CACHE_DIR"/manifest.json 2>/dev/null \
    | awk '{ printf "    %s  %s\n", $5, $9 }'
[ -f "$VSDBG_ARCHIVE" ] && ls -lh "$VSDBG_ARCHIVE" \
    | awk '{ printf "    %s  %s\n", $5, $9 }'

echo
note "Vérifiez que le service est actif :"
echo "  sudo systemctl status dotnet-cache"
