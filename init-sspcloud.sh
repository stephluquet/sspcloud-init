#!/bin/bash
# =============================================================================
# Script d'initialisation personnel - service RStudio sur le SSPCloud
# Stéphane Luquet - SED Insee Corse
#
# Ce dépôt est PUBLIC : ne jamais y mettre de jeton, de mot de passe,
# d'adresse interne ni de donnée.
#
# Ce que fait le script :
#   0. retire le jeton GitHub des adresses de dépôts (il reste dans Onyxia) ;
#   1. ouvre le projet RStudio du dépôt cloné (onglet Git), en créant
#      le .Rproj s'il n'existe pas (exclu de Git localement) ;
#   2. applique mes préférences RStudio ;
#   3. installe les packages listés dans packages.txt (racine du projet) ;
#   4. installe Claude Code ;
#   5. clone mon dépôt privé de skills et le relie à Claude Code.
# =============================================================================

# --- À personnaliser ---------------------------------------------------------
DEPOT_SKILLS="mes-skills"    # dépôt privé de skills (laisser vide pour ignorer)
# -----------------------------------------------------------------------------
# L'identifiant GitHub n'est pas écrit ici : il est retrouvé à partir du jeton
# fourni par Onyxia (Mon compte > Git), sans jamais afficher ce jeton.

WORK_DIR="${WORKSPACE_DIR:-/home/onyxia/work}"

# Exécute une commande en tant qu'utilisateur onyxia, que le script tourne en root ou non
en_onyxia() {
  if [ "$(id -un)" = "onyxia" ]; then bash -c "$1"; else su - onyxia -c "$1"; fi
}


# 0 ###########################################################################
# Git sans jeton écrit dans les fichiers
# Onyxia clone le projet avec le jeton dans l'adresse du dépôt : il se retrouve
# en clair dans .git/config, lisible par tout programme (Claude Code compris).
# On retire le jeton des adresses et on configure Git pour le lire à la volée
# dans la variable GIT_PERSONAL_ACCESS_TOKEN, sans jamais l'écrire nulle part.
# -----------------------------------------------------------------------------

#
# La valeur vide efface d'abord, pour github.com, les helpers déjà déclarés
# (cache de /etc/gitconfig et d'Onyxia) : sinon Git leur confierait le jeton
# après chaque authentification réussie, gardé en mémoire jusqu'à une heure.
AIDE_GIT='!f() { test "$1" = get && echo username=x-access-token && echo "password=${GIT_PERSONAL_ACCESS_TOKEN}"; }; f'
git config --file /home/onyxia/.gitconfig --replace-all "credential.https://github.com.helper" ""
git config --file /home/onyxia/.gitconfig --add "credential.https://github.com.helper" "$AIDE_GIT"
chown onyxia:users /home/onyxia/.gitconfig 2>/dev/null

# Onyxia lance ce script en root, AVANT de rendre le dépôt à onyxia (chown fait
# après le script) : git est donc lancé par l'utilisateur courant, pas par onyxia,
# qui le refuserait (« dubious ownership ») et laisserait le jeton en place.
for DEPOT in "$WORK_DIR"/*/; do
  [ -d "$DEPOT/.git" ] || continue
  URL=$(git -c safe.directory='*' -C "$DEPOT" remote get-url origin 2>/dev/null)
  # Onyxia produit parfois « https:///jeton@github.com/... » (trois barres)
  URL_SANS_JETON=$(echo "$URL" | sed -E 's#^https://+[^/@]*@#https://#')
  if [ -n "$URL" ] && [ "$URL" != "$URL_SANS_JETON" ]; then
    if git -c safe.directory='*' -C "$DEPOT" remote set-url origin "$URL_SANS_JETON"; then
      echo "[init] Jeton retiré de l'adresse du dépôt $(basename "$DEPOT")."
    else
      echo "[init] ATTENTION : jeton NON retiré de l'adresse du dépôt $(basename "$DEPOT")."
    fi
  fi
  # Contrôle final : aucun jeton ne doit rester dans .git/config
  grep -qE 'https://+[^/@[:space:]]+@' "$DEPOT/.git/config" \
    && echo "[init] ATTENTION : un jeton reste dans $(basename "$DEPOT")/.git/config."
done


# 1 ###########################################################################
# Ouverture automatique du projet RStudio du dépôt cloné, et options de la
# console R. RStudio n'affiche l'onglet Git que dans un projet : le .Rproj est
# donc créé s'il n'existe pas, même pour un dépôt vide ou non R.
# -----------------------------------------------------------------------------

SUBDIR=$(basename "$(ls -d "$WORK_DIR"/*/ 2>/dev/null | grep -v "/$DEPOT_SKILLS/" | head -n 1)")
RPROJ=""
if [ -n "$SUBDIR" ]; then
  DOSSIER_PROJET="$WORK_DIR/$SUBDIR"
  RPROJ=$(ls "$DOSSIER_PROJET"/*.Rproj 2>/dev/null | head -n 1)

  # Fichiers propres à RStudio exclus de Git localement (.git/info/exclude) :
  # le dépôt et son .gitignore ne sont pas modifiés.
  EXCLUSIONS=".Rproj.user/"
  if [ -z "$RPROJ" ]; then
    RPROJ="$DOSSIER_PROJET/$SUBDIR.Rproj"
    cat > "$RPROJ" << 'RPROJ'
Version: 1.0

RestoreWorkspace: No
SaveWorkspace: No
AlwaysSaveHistory: No

EnableCodeIndexing: Yes
UseSpacesForTab: Yes
NumSpacesForTab: 2
Encoding: UTF-8

RnwWeave: Sweave
LaTeX: pdfLaTeX
RPROJ
    chown onyxia:users "$RPROJ" 2>/dev/null
    EXCLUSIONS="$EXCLUSIONS $(basename "$RPROJ")"
    echo "[init] Projet RStudio $(basename "$RPROJ") créé (exclu de Git localement)."
  fi

  if [ -d "$DOSSIER_PROJET/.git" ]; then
    mkdir -p "$DOSSIER_PROJET/.git/info"
    for MOTIF in $EXCLUSIONS; do
      grep -qxF "$MOTIF" "$DOSSIER_PROJET/.git/info/exclude" 2>/dev/null \
        || echo "$MOTIF" >> "$DOSSIER_PROJET/.git/info/exclude"
    done
    chown -R onyxia:users "$DOSSIER_PROJET/.git/info" 2>/dev/null
  fi
fi

# R ne lit qu'UN seul .Rprofile : celui du dossier courant masque ~/.Rprofile.
# On charge ce dernier SAUF son ouverture du projet par Onyxia :
# l'ouverture (et la création du .Rproj) est gérée ci-dessus et ci-dessous.
cat >> "$WORK_DIR/.Rprofile" << 'RPROFILE'
if (file.exists('~/.Rprofile')) {
  lignes <- readLines('~/.Rprofile', warn = FALSE)
  try(eval(parse(text = lignes[!grepl('openProject', lignes)])), silent = TRUE)
  rm(lignes)
}
RPROFILE

if [ -n "$RPROJ" ]; then
  echo "[init] Ouverture automatique du projet $(basename "$RPROJ")"
  cat >> "$WORK_DIR/.Rprofile" << RPROFILE

setHook('rstudio.sessionInit', function(newSession) {
  if (newSession && identical(getwd(), '${WORK_DIR}')) {
    message('Activation du projet RStudio')
    rstudioapi::openProject('${RPROJ}')
  }
}, action = 'append')
RPROFILE
else
  echo "[init] Aucun dépôt cloné : pas de projet RStudio à ouvrir."
fi

cat >> "$WORK_DIR/.Rprofile" << 'RPROFILE'

options(
  prompt = 'R> ',
  digits = 4,
  continue = '+++ '
)
RPROFILE


# 2 ###########################################################################
# Préférences RStudio (Global Options)
# Pour les modifier : régler les Global Options dans RStudio, puis copier ici
# le contenu de ~/.config/rstudio/rstudio-prefs.json.
# -----------------------------------------------------------------------------

mkdir -p /home/onyxia/.config/rstudio
cat > /home/onyxia/.config/rstudio/rstudio-prefs.json << 'PREFS'
{
    "save_workspace": "never",
    "load_workspace": false,
    "always_save_history": false,
    "insert_native_pipe_operator": true,
    "editor_theme": "Pastel On Dark",
    "posix_terminal_shell": "bash",
    "show_hidden_files": true
}
PREFS
chown -R onyxia:users /home/onyxia/.config/ 2>/dev/null
echo "[init] Préférences RStudio appliquées."


# 3 ###########################################################################
# Packages listés dans packages.txt à la racine du projet
# (un package par ligne, lignes vides et commentaires # ignorés)
# -----------------------------------------------------------------------------

FICHIER_PACKAGES="$WORK_DIR/$SUBDIR/packages.txt"

if [ -n "$SUBDIR" ] && [ -f "$FICHIER_PACKAGES" ]; then
  PACKAGES=$(grep -v '^#' "$FICHIER_PACKAGES" | grep -v '^[[:space:]]*$' \
             | sed 's/[[:space:]]//g; s/.*/"&"/' | tr '\n' ',' | sed 's/,$//')
  if [ -n "$PACKAGES" ]; then
    echo "[init] Installation des packages manquants..."
    Rscript -e "
      packages <- c($PACKAGES)
      a_installer <- packages[!(packages %in% rownames(installed.packages()))]
      if (length(a_installer) > 0) install.packages(a_installer) else message('Tous les packages sont déjà installés.')
    "
  fi
else
  echo "[init] Pas de fichier packages.txt : aucun package supplémentaire."
fi


# 4 ###########################################################################
# Claude Code (SSPCloud : open data et données fictives uniquement)
# Connexion par l'abonnement. Ne jamais définir ANTHROPIC_API_KEY.
# -----------------------------------------------------------------------------

echo "[init] Installation de Claude Code..."
en_onyxia 'curl -fsSL https://claude.ai/install.sh | bash' \
  && echo "[init] Claude Code installé." \
  || echo "[init] Installation de Claude Code impossible."
grep -q '.local/bin' /home/onyxia/.bashrc 2>/dev/null \
  || echo 'export PATH="$HOME/.local/bin:$PATH"' >> /home/onyxia/.bashrc

# Premier lancement sans questions : thème automatique et accueil marqué comme fait.
FICHIER_CLAUDE=/home/onyxia/.claude.json
if [ -f "$FICHIER_CLAUDE" ] && command -v jq > /dev/null; then
  jq '.theme = "auto" | .hasCompletedOnboarding = true' "$FICHIER_CLAUDE" > "$FICHIER_CLAUDE.tmp" \
    && mv "$FICHIER_CLAUDE.tmp" "$FICHIER_CLAUDE"
else
  echo '{"hasCompletedOnboarding": true, "theme": "auto"}' > "$FICHIER_CLAUDE"
fi
chown onyxia:users "$FICHIER_CLAUDE" 2>/dev/null

# Modèle par défaut : Opus (équivalent de /model, perdu à chaque nouveau service).
REGLAGES_CLAUDE=/home/onyxia/.claude/settings.json
mkdir -p /home/onyxia/.claude
if [ -f "$REGLAGES_CLAUDE" ] && command -v jq > /dev/null; then
  jq '.model = "opus"' "$REGLAGES_CLAUDE" > "$REGLAGES_CLAUDE.tmp" \
    && mv "$REGLAGES_CLAUDE.tmp" "$REGLAGES_CLAUDE"
else
  echo '{"model": "opus"}' > "$REGLAGES_CLAUDE"
fi
chown -R onyxia:users /home/onyxia/.claude 2>/dev/null

# Connexion par le jeton CLAUDE_CODE_OAUTH_TOKEN (généré par `claude setup-token`),
# rangé dans un secret Vault d'Onyxia. Onyxia ne le transmet qu'à R
# (Renviron.site) et à /etc/environment, que le terminal RStudio ne lit pas :
# le .bashrc va l'y chercher à chaque ouverture de terminal (sans le recopier).
grep -q 'CLAUDE_CODE_OAUTH_TOKEN' /home/onyxia/.bashrc 2>/dev/null \
  || cat >> /home/onyxia/.bashrc << 'BASHRC'

# Jeton Claude Code injecté par Vault (voir init-sspcloud.sh)
if [ -z "$CLAUDE_CODE_OAUTH_TOKEN" ] && [ -r /etc/environment ]; then
  CLAUDE_CODE_OAUTH_TOKEN=$(sed -n 's/^CLAUDE_CODE_OAUTH_TOKEN="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' /etc/environment | tail -n 1)
  if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then export CLAUDE_CODE_OAUTH_TOKEN; else unset CLAUDE_CODE_OAUTH_TOKEN; fi
fi
BASHRC

if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
  echo "[init] Jeton Claude présent (${#CLAUDE_CODE_OAUTH_TOKEN} caractères) : connexion automatique."
else
  echo "[init] Pas de jeton Claude : connexion manuelle au premier lancement."
fi


# 5 ###########################################################################
# Skills personnels : dépôt privé cloné avec le jeton fourni par Onyxia
# (Mon compte > Git > Token d'accès personnel), puis relié à ~/.claude/skills
# -----------------------------------------------------------------------------

GITHUB_COMPTE=""
if [ -n "$GIT_PERSONAL_ACCESS_TOKEN" ]; then
  GITHUB_COMPTE=$(curl -s -H "Authorization: Bearer $GIT_PERSONAL_ACCESS_TOKEN" \
                  https://api.github.com/user \
                  | grep -m1 '"login"' | sed 's/.*"login": *"\([^"]*\)".*/\1/')
fi

if [ -n "$DEPOT_SKILLS" ] && [ -z "$GITHUB_COMPTE" ]; then
  echo "[init] Compte GitHub introuvable (jeton absent ou invalide) : skills non clonés."
fi

if [ -n "$DEPOT_SKILLS" ] && [ -n "$GITHUB_COMPTE" ]; then
  DOSSIER_SKILLS="$WORK_DIR/$DEPOT_SKILLS"
  URL_PROPRE="https://github.com/$GITHUB_COMPTE/$DEPOT_SKILLS.git"

  if [ ! -d "$DOSSIER_SKILLS" ]; then
    echo "[init] Clonage du dépôt de skills..."
    en_onyxia "git clone -q '$URL_PROPRE' '$DOSSIER_SKILLS'" \
      && echo "[init] Skills clonés." \
      || echo "[init] Clonage des skills impossible (jeton ou nom de dépôt ?)."
  fi

  if [ -d "$DOSSIER_SKILLS" ]; then
    mkdir -p /home/onyxia/.claude
    ln -sfn "$DOSSIER_SKILLS" /home/onyxia/.claude/skills
    chown -R onyxia:users /home/onyxia/.claude 2>/dev/null
    echo "[init] Skills reliés à Claude Code."
  fi
fi

echo "[init] Initialisation terminée."
