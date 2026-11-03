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
#   1. ouvre le .Rproj du projet cloné s'il en contient un,
#      ou le crée si l'argument rproj est donné ;
#   2. applique mes préférences RStudio ;
#   3. installe les packages listés dans packages.txt (racine du projet) ;
#   4. installe Claude Code ;
#   5. clone mon dépôt privé de skills et le relie à Claude Code.
# =============================================================================

# --- Argument facultatif (champ des arguments du script dans l'onglet Init) ----
#   rproj : crée le projet RStudio s'il n'existe pas encore (nouveau projet R)
#   (sans argument : le .Rproj est ouvert s'il existe, rien n'est créé sinon)
CREER_RPROJ="no"
[ "$1" = "rproj" ] && CREER_RPROJ="yes"

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

AIDE_GIT='!f() { test "$1" = get && echo username=x-access-token && echo "password=${GIT_PERSONAL_ACCESS_TOKEN}"; }; f'
git config --file /home/onyxia/.gitconfig "credential.https://github.com.helper" "$AIDE_GIT"
chown onyxia:users /home/onyxia/.gitconfig 2>/dev/null

for DEPOT in "$WORK_DIR"/*/; do
  [ -d "$DEPOT/.git" ] || continue
  URL=$(en_onyxia "git -C '$DEPOT' remote get-url origin" 2>/dev/null)
  URL_SANS_JETON=$(echo "$URL" | sed -E 's#^https://[^/@]+@#https://#')
  if [ -n "$URL" ] && [ "$URL" != "$URL_SANS_JETON" ]; then
    en_onyxia "git -C '$DEPOT' remote set-url origin '$URL_SANS_JETON'"
    echo "[init] Jeton retiré de l'adresse du dépôt $(basename "$DEPOT")."
  fi
done


# 1 ###########################################################################
# Ouverture automatique du projet RStudio, uniquement si le dépôt cloné
# contient déjà un fichier .Rproj (un projet non R n'est pas touché),
# et options de la console R
# -----------------------------------------------------------------------------

SUBDIR=$(basename "$(ls -d "$WORK_DIR"/*/ 2>/dev/null | grep -v "/$DEPOT_SKILLS/" | head -n 1)")
RPROJ=""
if [ -n "$SUBDIR" ]; then
  RPROJ=$(ls "$WORK_DIR/$SUBDIR"/*.Rproj 2>/dev/null | head -n 1)
fi

# Nouveau projet R demandé (argument rproj) : RStudio créera le .Rproj
# en ouvrant le dossier ; .Rproj.user/ est exclu de Git d'avance.
if [ -z "$RPROJ" ] && [ "$CREER_RPROJ" = "yes" ] && [ -n "$SUBDIR" ]; then
  RPROJ="$WORK_DIR/$SUBDIR"
  grep -qx '.Rproj.user/' "$WORK_DIR/$SUBDIR/.gitignore" 2>/dev/null \
    || echo '.Rproj.user/' >> "$WORK_DIR/$SUBDIR/.gitignore"
  chown onyxia:users "$WORK_DIR/$SUBDIR/.gitignore" 2>/dev/null
  echo "[init] Argument rproj : création du projet RStudio $SUBDIR"
fi

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
  echo "[init] Pas de fichier .Rproj dans le projet : pas d'ouverture automatique (argument rproj pour le créer)."
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

# Premier lancement sans questions : thème choisi et accueil marqué comme fait.
# La connexion se fait par le jeton CLAUDE_CODE_OAUTH_TOKEN (généré par
# `claude setup-token`), injecté depuis un secret Vault d'Onyxia.
if [ ! -f /home/onyxia/.claude.json ]; then
  echo '{"hasCompletedOnboarding": true, "theme": "dark"}' > /home/onyxia/.claude.json
  chown onyxia:users /home/onyxia/.claude.json 2>/dev/null
fi
if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
  echo "[init] Jeton Claude présent : connexion automatique."
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
