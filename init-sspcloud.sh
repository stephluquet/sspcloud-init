#!/bin/bash
# =============================================================================
# Script d'initialisation personnel - service RStudio sur le SSPCloud
# Stéphane Luquet - SED Insee Corse
#
# Ce dépôt est PUBLIC : ne jamais y mettre de jeton, de mot de passe,
# d'adresse interne ni de donnée.
#
# Ce que fait le script :
#   1. ouvre automatiquement le .Rproj du projet cloné ;
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


# 1 ###########################################################################
# Ouverture automatique du .Rproj et options de la console
# -----------------------------------------------------------------------------

SUBDIR=$(basename "$(ls -d "$WORK_DIR"/*/ 2>/dev/null | grep -v "/$DEPOT_SKILLS/" | head -n 1)")

if [ -n "$SUBDIR" ]; then
  echo "[init] Ouverture du Rproj du dossier $SUBDIR"
  cat >> "$WORK_DIR/.Rprofile" << RPROFILE

setHook('rstudio.sessionInit', function(newSession) {
  if (newSession && identical(getwd(), '${WORK_DIR}')) {
    message('Activation du projet RStudio')
    rstudioapi::openProject('${SUBDIR}')
  }
}, action = 'append')

options(
  prompt = 'R> ',
  digits = 4,
  continue = '+++ '
)
RPROFILE
else
  echo "[init] Aucun projet trouvé dans $WORK_DIR : pas d'ouverture automatique."
fi


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
    if [ -n "$GIT_PERSONAL_ACCESS_TOKEN" ]; then
      echo "[init] Clonage du dépôt de skills..."
      en_onyxia "git clone -q https://x-access-token:${GIT_PERSONAL_ACCESS_TOKEN}@github.com/$GITHUB_COMPTE/$DEPOT_SKILLS.git '$DOSSIER_SKILLS'" \
        && en_onyxia "git -C '$DOSSIER_SKILLS' remote set-url origin '$URL_PROPRE'" \
        && echo "[init] Skills clonés." \
        || echo "[init] Clonage des skills impossible (jeton ou nom de dépôt ?)."
    fi
  fi

  if [ -d "$DOSSIER_SKILLS" ]; then
    mkdir -p /home/onyxia/.claude
    ln -sfn "$DOSSIER_SKILLS" /home/onyxia/.claude/skills
    chown -R onyxia:users /home/onyxia/.claude 2>/dev/null
    echo "[init] Skills reliés à Claude Code."
  fi
fi

echo "[init] Initialisation terminée."
