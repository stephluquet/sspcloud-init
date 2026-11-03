# sspcloud-init

Script d'initialisation personnel pour mes services **RStudio** sur le [SSPCloud](https://datalab.sspcloud.fr).

> ⚠️ Dépôt **public** : aucun jeton, mot de passe, adresse interne ni donnée ne doit y figurer, même temporairement (l'historique Git conserve tout).

## Ce que fait le script

0. Retire le jeton GitHub des adresses de dépôts clonés par Onyxia (il serait sinon écrit en clair dans `.git/config`) ; Git le lit à la volée dans `GIT_PERSONAL_ACCESS_TOKEN`.
1. Ouvre automatiquement le projet RStudio du dépôt cloné au lancement du service, pour avoir l’onglet Git (RStudio ne l’affiche que dans un projet). Si le dépôt n’a pas de `.Rproj` (dépôt vide, projet non R…), il est créé et exclu de Git localement via `.git/info/exclude`, comme `.Rproj.user/` : le dépôt et son `.gitignore` ne sont pas modifiés. Pour versionner ce `.Rproj`, le retirer de `.git/info/exclude`.
2. Applique mes préférences RStudio (pipe natif, pas de sauvegarde du workspace, thème sombre…).
3. Installe les packages listés dans un fichier `packages.txt` à la racine du projet, s'il existe.
4. Installe **Claude Code** (modèle Opus par défaut, thème automatique, connexion par le jeton Vault s’il est fourni).
5. Clone mon dépôt privé de skills et le relie à Claude Code (`~/.claude/skills`).

Chaque étape écrit une ligne commençant par `[init]` dans les journaux du service, pour repérer facilement un éventuel problème.

## Pré-requis (une fois pour toutes)

- **Jeton GitHub** renseigné dans Onyxia : *Mon compte* → *Git* → *Token d'accès personnel*. Il est injecté dans les services sous le nom `GIT_PERSONAL_ACCESS_TOKEN` et sert à cloner le dépôt privé de skills. À renouveler avant son expiration.
- **Jeton Claude** (facultatif, évite la connexion à chaque service) : généré une fois avec `claude setup-token`, rangé dans un secret Vault d'Onyxia sous le nom `CLAUDE_CODE_OAUTH_TOKEN`, et injecté dans le service (onglet Vault de sa configuration). Copier la valeur **entière** affichée par `claude setup-token` (attention aux retours à la ligne du terminal). Pour vérifier un jeton : `CLAUDE_CODE_OAUTH_TOKEN='…' claude -p ok` doit répondre au lieu d’afficher `401 Invalid bearer token`. Ne jamais l'écrire dans ce dépôt.
- **Variable à personnaliser** en haut de `init-sspcloud.sh` : `DEPOT_SKILLS` (nom du dépôt privé de skills). L’identifiant GitHub est retrouvé automatiquement à partir du jeton.

## Utilisation dans Onyxia

Dans la configuration du service RStudio, avant de le lancer :

| Onglet | Réglage |
| --- | --- |
| Init | Script personnel : `https://raw.githubusercontent.com/stephluquet/sspcloud-init/main/init-sspcloud.sh` (aucun argument) |
| Git | Adresse HTTPS du dépôt du projet à cloner |
| Ressources | Au moins 4 Go de RAM (minimum pour Claude Code) |

Puis **enregistrer la configuration** pour la relancer en un clic.

## Après le lancement

Dans le terminal RStudio :

```bash
claude          # sans jeton Vault : connexion avec le compte Claude au premier lancement
/status         # dans Claude Code : vérifier que c'est bien l'abonnement, pas une clé API
```

## Règles d'usage

- SSPCloud = **open data ou données fictives uniquement** : tout ce que Claude Code lit est envoyé à Anthropic.
- Ne jamais définir `ANTHROPIC_API_KEY` (facturation à l'usage au lieu de l'abonnement).
- Les données vont sur le stockage S3, jamais dans les dépôts Git.
