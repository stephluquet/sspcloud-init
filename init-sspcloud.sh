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
#   5. installe l'équipe SED (plugin sed-equipe : skills et agents) et
#      pose son cadre dans ~/.claude/CLAUDE.md ;
#   6. installe LibreOffice si demandé (figures .ods et diaporamas .odp) ;
#   7. restaure le travail de l'étude depuis S3 (suivi/, output/, a_partager/).
# =============================================================================

# --- À personnaliser ---------------------------------------------------------
MARKETPLACE_SED="stephluquet/sspcloud-skills"  # dépôt privé (marketplace Claude Code)
PLUGIN_SED="sed-equipe@sspcloud-skills"        # plugin de l'équipe (laisser vide pour ignorer)
# -----------------------------------------------------------------------------

# Arguments du lanceur Onyxia (onglet Init), dans n'importe quel ordre, séparés
# par des espaces : « libreoffice » installe LibreOffice (communicant : .ods,
# .odp ; quelques minutes de plus) ; tout autre mot est le modèle Claude Code
# (ex. « sonnet », « claude-opus-5-5 »). Exemples : « libreoffice »,
# « sonnet libreoffice ». Sans argument : Opus, pas de LibreOffice.
# « s3=<bucket> » : bucket S3 personnel, seulement s'il n'est pas lu dans le
# jeton S3 d'Onyxia (cas normal : rien à indiquer).
LIBREOFFICE="non"
MODELE_ARG=""
S3_ARG=""
for ARG in $*; do
  case "${ARG,,}" in
    libreoffice) LIBREOFFICE="oui" ;;
    s3=*) S3_ARG="${ARG#*=}" ;;
    *) MODELE_ARG="$ARG" ;;
  esac
done

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

SUBDIR=$(basename "$(ls -d "$WORK_DIR"/*/ 2>/dev/null | head -n 1)")
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

# Modèle par défaut : Opus, ou celui passé en argument du lanceur (voir en tête)
# (ex. « sonnet », « haiku », « claude-opus-5-5 »). Posé via ANTHROPIC_MODEL dans le
# .bashrc : plus fiable qu'un settings.json, et /model ou --model restent possibles.
MODELE_CLAUDE="${MODELE_ARG:-opus}"
case "$MODELE_CLAUDE" in
  *[!A-Za-z0-9._-]*) echo "[init] Modèle « $MODELE_CLAUDE » invalide : opus utilisé."; MODELE_CLAUDE=opus ;;
esac
sed -i '/ANTHROPIC_MODEL/d' /home/onyxia/.bashrc 2>/dev/null
echo "export ANTHROPIC_MODEL=$MODELE_CLAUDE  # modèle Claude Code (voir init-sspcloud.sh)" >> /home/onyxia/.bashrc
echo "[init] Modèle Claude Code par défaut : $MODELE_CLAUDE."

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
# Équipe SED : plugin sed-equipe (skills et six agents de rôle)
# La marketplace est le dépôt privé stephluquet/sspcloud-skills : Git le lit
# avec le jeton GitHub d'Onyxia, par l'aide configurée à l'étape 0. Le jeton
# est passé à Claude Code par l'entrée standard, jamais en argument ni en
# fichier. ~/.claude n'étant pas conservé entre deux services, le plugin est
# réinstallé à chaque lancement : c'est donc toujours la dernière version de main.
# -----------------------------------------------------------------------------

CLAUDE_BIN=/home/onyxia/.local/bin/claude

# Dans le terminal, les agents lisent les fichiers de référence des skills
# dans ~/.claude/plugins : autorisation donnée une fois pour tous les projets.
FICHIER_REGLAGES=/home/onyxia/.claude/settings.json
mkdir -p /home/onyxia/.claude
if [ -f "$FICHIER_REGLAGES" ] && command -v jq > /dev/null; then
  jq '.permissions.additionalDirectories = ((.permissions.additionalDirectories // []) + ["~/.claude/plugins"] | unique)' \
    "$FICHIER_REGLAGES" > "$FICHIER_REGLAGES.tmp" && mv "$FICHIER_REGLAGES.tmp" "$FICHIER_REGLAGES"
elif [ ! -f "$FICHIER_REGLAGES" ]; then
  echo '{"permissions": {"additionalDirectories": ["~/.claude/plugins"]}}' > "$FICHIER_REGLAGES"
else
  echo "[init] jq absent : ajouter ~/.claude/plugins à permissions.additionalDirectories de $FICHIER_REGLAGES."
fi
chown -R onyxia:users /home/onyxia/.claude 2>/dev/null

if [ -z "$PLUGIN_SED" ]; then
  echo "[init] Équipe SED non demandée."
elif [ ! -x "$CLAUDE_BIN" ]; then
  echo "[init] Claude Code absent : équipe SED non installée."
elif [ -z "$GIT_PERSONAL_ACCESS_TOKEN" ]; then
  echo "[init] Jeton GitHub absent (Onyxia > Mon compte > Git) : équipe SED non installée."
else
  echo "[init] Installation de l'équipe SED ($PLUGIN_SED)..."
  COMMANDE_SED="read -r GIT_PERSONAL_ACCESS_TOKEN; export GIT_PERSONAL_ACCESS_TOKEN; cd /home/onyxia; \
    { '$CLAUDE_BIN' plugin marketplace add '$MARKETPLACE_SED' || '$CLAUDE_BIN' plugin marketplace update '${PLUGIN_SED#*@}'; } \
    && '$CLAUDE_BIN' plugin install '$PLUGIN_SED'"
  if [ "$(id -un)" = "onyxia" ]; then
    printf '%s\n' "$GIT_PERSONAL_ACCESS_TOKEN" | bash -c "$COMMANDE_SED" > /tmp/init-sed.log 2>&1
  else
    printf '%s\n' "$GIT_PERSONAL_ACCESS_TOKEN" | su - onyxia -c "$COMMANDE_SED" > /tmp/init-sed.log 2>&1
  fi
  if [ $? -eq 0 ]; then
    echo "[init] Équipe SED installée : agents sed-equipe:sed-* disponibles dans Claude Code."
    # Cadre d'environnement : ouvrir ce service vaut demande de travailler avec
    # l'équipe ; seul le suivi (continu ou pas à pas) est demandé en début de
    # session. Un bloc « Cadre » dans le CLAUDE.md du projet l'emporte.
    CADRE_SED=/home/onyxia/.claude/plugins/marketplaces/${PLUGIN_SED#*@}/sed-equipe/environnement/CLAUDE.md
    if [ -f "$CADRE_SED" ]; then
      cp "$CADRE_SED" /home/onyxia/.claude/CLAUDE.md && chown onyxia:users /home/onyxia/.claude/CLAUDE.md
      echo "[init] Cadre SED posé dans ~/.claude/CLAUDE.md (suivi demandé en début de session)."
    else
      echo "[init] Cadre SED introuvable dans le plugin : l'équipe ne s'activera que sur un CLAUDE.md de projet."
    fi
  else
    echo "[init] Installation de l'équipe SED impossible (détail : /tmp/init-sed.log) :"
    sed 's/^/[init]   /' /tmp/init-sed.log | tail -n 5
  fi
fi


# 6 ###########################################################################
# LibreOffice (facultatif) : le communicant en a besoin pour le fichier des
# figures (.ods) et les diaporamas (.odp). Long à installer : désactivé par défaut.
# -----------------------------------------------------------------------------

if [ "$LIBREOFFICE" = "oui" ] && ! command -v soffice > /dev/null; then
  echo "[init] Installation de LibreOffice..."
  if [ "$(id -u)" = "0" ] \
     && apt-get update -qq > /dev/null \
     && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
          libreoffice-calc libreoffice-impress > /dev/null; then
    echo "[init] LibreOffice installé."
  else
    echo "[init] Installation de LibreOffice impossible."
  fi
elif command -v soffice > /dev/null; then
  echo "[init] LibreOffice présent."
else
  echo "[init] LibreOffice non demandé (argument « libreoffice » du lanceur) : le communicant le signalera."
fi

# 7 ###########################################################################
# Reprise automatique de l'étude : le service a cloné le dépôt (le code) ; le
# travail (suivi/, output/, a_partager/, tableau de bord) est restauré depuis
# s3://<bucket>/sed/<dépôt>/, où l'orchestrateur l'a sauvegardé en fin de tâche.
# -----------------------------------------------------------------------------

if [ -n "$S3_ARG" ]; then
  sed -i '/S3_SED=/d' /home/onyxia/.bashrc 2>/dev/null
  echo "export S3_SED=$S3_ARG  # bucket S3 personnel (argument du lanceur)" >> /home/onyxia/.bashrc
  export S3_SED="$S3_ARG"
fi
OUTIL_SAUVEGARDE=/home/onyxia/.claude/plugins/marketplaces/${PLUGIN_SED#*@}/sed-equipe/skills/sed/outils/sauvegarde.py
if [ -n "$SUBDIR" ] && [ -f "$OUTIL_SAUVEGARDE" ] && command -v aws > /dev/null; then
  RESULTAT=$(timeout 600 python3 "$OUTIL_SAUVEGARDE" "$WORK_DIR/$SUBDIR" reprendre --plateforme sspcloud 2>&1 | tail -n 1)
  echo "[init] $RESULTAT"
  chown -R onyxia:users "$WORK_DIR/$SUBDIR" 2>/dev/null
elif [ -n "$SUBDIR" ]; then
  echo "[init] Reprise depuis S3 impossible (outil de sauvegarde ou client aws absent)."
fi

echo "[init] Initialisation terminée."
