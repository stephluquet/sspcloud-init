# sspcloud-init

Script d'initialisation personnel pour mes services **RStudio** sur le [SSPCloud](https://datalab.sspcloud.fr).

> ⚠️ Dépôt **public** : aucun jeton, mot de passe, adresse interne ni donnée ne doit y figurer, même temporairement (l'historique Git conserve tout).

## Ce que fait le script

0. Retire le jeton GitHub des adresses de dépôts clonés par Onyxia (il serait sinon écrit en clair dans `.git/config`) ; Git le lit à la volée dans `GIT_PERSONAL_ACCESS_TOKEN`.
1. Ouvre automatiquement le projet RStudio du dépôt cloné au lancement du service, pour avoir l’onglet Git (RStudio ne l’affiche que dans un projet). Si le dépôt n’a pas de `.Rproj` (dépôt vide, projet non R…), il est créé et exclu de Git localement via `.git/info/exclude`, comme `.Rproj.user/` : le dépôt et son `.gitignore` ne sont pas modifiés. Pour versionner ce `.Rproj`, le retirer de `.git/info/exclude`.
2. Applique mes préférences RStudio (pipe natif, pas de sauvegarde du workspace, thème sombre…).
3. Installe les packages listés dans un fichier `packages.txt` à la racine du projet, s'il existe.
4. Installe **Claude Code** (modèle Opus par défaut, ou celui passé en argument du script ; thème automatique, connexion par le jeton Vault s’il est fourni).
5. Installe l'**équipe SED** : plugin `sed-equipe` (skills et six agents de rôle) depuis la marketplace privée `stephluquet/sspcloud-skills`, avec le jeton GitHub d'Onyxia. Autorise aussi les agents à lire `~/.claude/plugins` (réglage utilisateur de Claude Code). `~/.claude` n'étant pas conservé entre deux services, le plugin est réinstallé à chaque lancement, donc toujours à jour avec `main`.
6. Installe LibreOffice si `LIBREOFFICE="oui"` (communicant : fichier des figures `.ods`, diaporamas `.odp`). Désactivé par défaut : quelques minutes de plus au lancement.

Chaque étape écrit une ligne commençant par `[init]` dans les journaux du service, pour repérer facilement un éventuel problème.

## Pré-requis (une fois pour toutes)

- **Jeton GitHub** renseigné dans Onyxia : *Mon compte* → *Git* → *Token d'accès personnel*. Il est injecté dans les services sous le nom `GIT_PERSONAL_ACCESS_TOKEN` et sert à lire le dépôt privé `sspcloud-skills` (plugin de l'équipe SED) : il doit donc y avoir accès en lecture. À renouveler avant son expiration.
- **Jeton Claude** (facultatif, évite la connexion à chaque service) : généré une fois avec `claude setup-token`, rangé dans un secret Vault d'Onyxia sous le nom `CLAUDE_CODE_OAUTH_TOKEN`, et injecté dans le service (onglet Vault de sa configuration). Copier la valeur **entière** affichée par `claude setup-token` (attention aux retours à la ligne du terminal). Pour vérifier un jeton : `CLAUDE_CODE_OAUTH_TOKEN='…' claude -p ok` doit répondre au lieu d’afficher `401 Invalid bearer token`. Ne jamais l'écrire dans ce dépôt.
- **Variables** en haut de `init-sspcloud.sh` : `MARKETPLACE_SED` et `PLUGIN_SED` (plugin de l'équipe SED ; laisser `PLUGIN_SED` vide pour ne pas l'installer), `LIBREOFFICE` (`oui` ou `non`).

## Utilisation dans Onyxia

Dans la configuration du service RStudio, avant de le lancer :

| Onglet | Réglage |
| --- | --- |
| Init | Script personnel : `https://raw.githubusercontent.com/stephluquet/sspcloud-init/main/init-sspcloud.sh` (argument facultatif : modèle Claude Code, ex. `sonnet` ; Opus par défaut) |
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

Pour une étude, copier `sed-equipe/modele-projet/` (`CLAUDE.md` et `.claude/settings.json`) à la racine du dépôt du projet, remplir le bloc « Cadre », puis lancer `claude` depuis ce dossier. La conversation principale est l'orchestrateur ; chaque rôle tourne comme agent avec son modèle. Le travail est rangé dans le projet (`suivi/`, `scripts/`, `output/`, `a_partager/`) et se pousse par l'onglet Git de RStudio.

En cas de problème, les lignes `[init]` des journaux du service disent quelle étape a échoué ; le détail de l'installation de l'équipe est dans `/tmp/init-sed.log`.

## Règles d'usage

- SSPCloud = **open data ou données fictives uniquement** : tout ce que Claude Code lit est envoyé à Anthropic.
- Ne jamais définir `ANTHROPIC_API_KEY` (facturation à l'usage au lieu de l'abonnement).
- Les données vont sur le stockage S3, jamais dans les dépôts Git.
