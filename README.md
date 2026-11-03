# sspcloud-init

Script d'initialisation personnel pour mes services **RStudio** sur le [SSPCloud](https://datalab.sspcloud.fr).

> ⚠️ Dépôt **public** : aucun jeton, mot de passe, adresse interne ni donnée ne doit y figurer, même temporairement (l'historique Git conserve tout).

## Ce que fait le script

1. Ouvre automatiquement le `.Rproj` du projet cloné au lancement du service.
2. Applique mes préférences RStudio (pipe natif, pas de sauvegarde du workspace, thème sombre…).
3. Installe les packages listés dans un fichier `packages.txt` à la racine du projet, s'il existe.
4. Installe **Claude Code**.
5. Clone mon dépôt privé de skills et le relie à Claude Code (`~/.claude/skills`).

Chaque étape écrit une ligne commençant par `[init]` dans les journaux du service, pour repérer facilement un éventuel problème.

## Pré-requis (une fois pour toutes)

- **Jeton GitHub** renseigné dans Onyxia : *Mon compte* → *Git* → *Token d'accès personnel*. Il est injecté dans les services sous le nom `GIT_PERSONAL_ACCESS_TOKEN` et sert à cloner le dépôt privé de skills. À renouveler avant son expiration.
- **Variable à personnaliser** en haut de `init-sspcloud.sh` : `DEPOT_SKILLS` (nom du dépôt privé de skills). L’identifiant GitHub est retrouvé automatiquement à partir du jeton.

## Utilisation dans Onyxia

Dans la configuration du service RStudio, avant de le lancer :

| Onglet | Réglage |
| --- | --- |
| Init | Script personnel : `https://raw.githubusercontent.com/stephluquet/sspcloud-init/main/init-sspcloud.sh` |
| Git | Adresse du dépôt du projet à cloner (doit contenir un `.Rproj`) |
| Ressources | Au moins 4 Go de RAM (minimum pour Claude Code) |

Puis **enregistrer la configuration** pour la relancer en un clic.

## Après le lancement

Dans le terminal RStudio :

```bash
claude          # première fois : connexion avec le compte Claude (abonnement)
/status         # dans Claude Code : vérifier que c'est bien l'abonnement, pas une clé API
```

## Règles d'usage

- SSPCloud = **open data ou données fictives uniquement** : tout ce que Claude Code lit est envoyé à Anthropic.
- Ne jamais définir `ANTHROPIC_API_KEY` (facturation à l'usage au lieu de l'abonnement).
- Les données vont sur le stockage S3, jamais dans les dépôts Git.
