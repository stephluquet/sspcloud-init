# sspcloud-init

Script d'initialisation personnel pour mes services **RStudio** sur le [SSPCloud](https://datalab.sspcloud.fr).

> ⚠️ Dépôt **public** : aucun jeton, mot de passe, adresse interne ni donnée ne doit y figurer, même temporairement (l'historique Git conserve tout).

## Ce que fait le script

0. Retire le jeton GitHub des adresses de dépôts clonés par Onyxia (il serait sinon écrit en clair dans `.git/config`) ; Git le lit à la volée dans `GIT_PERSONAL_ACCESS_TOKEN`.
1. Ouvre automatiquement le projet RStudio du dépôt cloné au lancement du service, pour avoir l’onglet Git (RStudio ne l’affiche que dans un projet). Si le dépôt n’a pas de `.Rproj` (dépôt vide, projet non R…), il est créé et exclu de Git localement via `.git/info/exclude`, comme `.Rproj.user/` : le dépôt et son `.gitignore` ne sont pas modifiés. Pour versionner ce `.Rproj`, le retirer de `.git/info/exclude`.
2. Applique mes préférences RStudio (pipe natif, pas de sauvegarde du workspace, thème sombre…).
3. Installe les packages listés dans un fichier `packages.txt` à la racine du projet, s'il existe.
4. Installe **Claude Code** (modèle Opus par défaut, ou celui passé en argument du script ; thème automatique, connexion par le jeton Vault s’il est fourni).
5. Installe l'**équipe SED** : plugin `sed-equipe` (skills et six agents de rôle) depuis la marketplace privée `stephluquet/sspcloud-skills`, avec le jeton GitHub d'Onyxia. Autorise aussi les agents à lire `~/.claude/plugins` (réglage utilisateur de Claude Code). Pose enfin le **cadre de l'équipe** dans `~/.claude/CLAUDE.md` (contexte Insee, charte et modèle diaporama Insee appliqués, suivi demandé en début de session) : ouvrir ce service vaut demande de travailler avec l'équipe. Un bloc « Cadre » dans le `CLAUDE.md` d'un projet l'emporte, ligne par ligne. `~/.claude` n'étant pas conservé entre deux services, le plugin est réinstallé à chaque lancement, donc toujours à jour avec `main`.
6. Installe les **modules Python des outils de l'équipe** (pandas, openpyxl, odf : tableau de bord, lecture des classeurs, figures), seulement s'ils manquent : paquets Ubuntu pour le Python du système, `pip` sinon. Installe aussi LibreOffice si l'argument `libreoffice` est passé au lanceur (communicant : fichier des figures `.ods`, diaporamas `.odp`). Désactivé par défaut : quelques minutes de plus au lancement.
7. **Reprend l'étude** : restaure depuis `s3://<identifiant>/sed/<dépôt>/` le travail sauvegardé en fin de tâche (`suivi/`, `output/`, `a_partager/`, tableau de bord) ; le code vient du dépôt Git cloné par le service. Le bucket est lu dans le jeton S3 d'Onyxia ; à défaut, argument `s3=<bucket>` du lanceur.

Chaque étape écrit une ligne commençant par `[init]` dans les journaux du service, pour repérer facilement un éventuel problème.

## Pré-requis (une fois pour toutes)

- **Jeton GitHub** renseigné dans Onyxia : *Mon compte* → *Git* → *Token d'accès personnel*. Il est injecté dans les services sous le nom `GIT_PERSONAL_ACCESS_TOKEN` et sert à lire le dépôt privé `sspcloud-skills` (plugin de l'équipe SED) : il doit donc y avoir accès en lecture. À renouveler avant son expiration.
- **Jeton Claude** (facultatif, évite la connexion à chaque service) : généré une fois avec `claude setup-token`, rangé dans un secret Vault d'Onyxia sous le nom `CLAUDE_CODE_OAUTH_TOKEN`, et injecté dans le service (onglet Vault de sa configuration). Copier la valeur **entière** affichée par `claude setup-token` (attention aux retours à la ligne du terminal). Pour vérifier un jeton : `CLAUDE_CODE_OAUTH_TOKEN='…' claude -p ok` doit répondre au lieu d’afficher `401 Invalid bearer token`. Ne jamais l'écrire dans ce dépôt.
- **Variables** en haut de `init-sspcloud.sh` : `MARKETPLACE_SED` et `PLUGIN_SED` (plugin de l'équipe SED ; laisser `PLUGIN_SED` vide pour ne pas l'installer).

## Utilisation dans Onyxia

Dans la configuration du service RStudio, avant de le lancer :

| Onglet | Réglage |
| --- | --- |
| Init | Script personnel : `https://raw.githubusercontent.com/stephluquet/sspcloud-init/main/init-sspcloud.sh` (arguments facultatifs, séparés par des espaces, dans n'importe quel ordre : un modèle Claude Code, ex. `sonnet`, Opus par défaut ; `libreoffice` pour installer LibreOffice. Ex. : `libreoffice` ou `sonnet libreoffice`) |
| Git | Adresse HTTPS du dépôt du projet à cloner |
| Ressources | Au moins 4 Go de RAM (minimum pour Claude Code) |

Puis **enregistrer la configuration** pour la relancer en un clic.

## Après le lancement

Dans le terminal RStudio :

```bash
claude          # sans jeton Vault : connexion avec le compte Claude au premier lancement
/status         # dans Claude Code : vérifier que c'est bien l'abonnement, pas une clé API
/agents         # dans Claude Code : les six agents sed-equipe:sed-* doivent apparaître
```

Pour une étude, lancer `claude` depuis le dossier du projet : l'équipe est déjà active, Claude demande seulement « suivi continu ou pas à pas ? » à la première tâche. Pour régler autrement une étude (contexte perso, charte libre…), copier `sed-equipe/modele-projet/CLAUDE.md` à la racine du projet et n'y garder que les lignes du « Cadre » à changer. La conversation principale est l'orchestrateur ; chaque rôle tourne comme agent avec son modèle. Le travail est rangé dans le projet (`suivi/`, `scripts/`, `output/`, `a_partager/`) et se pousse par l'onglet Git de RStudio.

En cas de problème, les lignes `[init]` des journaux du service disent quelle étape a échoué ; le détail de l'installation de l'équipe est dans `/tmp/init-sed.log`.

## Règles d'usage

- SSPCloud = **open data ou données fictives uniquement** : tout ce que Claude Code lit est envoyé à Anthropic.
- Ne jamais définir `ANTHROPIC_API_KEY` (facturation à l'usage au lieu de l'abonnement).
- Les données vont sur le stockage S3, jamais dans les dépôts Git. Dans un projet de l'équipe SED, Git ne reçoit que le code ; les résultats et le travail (qui portent des chiffres) vont dans `s3://<identifiant>/sed/<dépôt>/`.
