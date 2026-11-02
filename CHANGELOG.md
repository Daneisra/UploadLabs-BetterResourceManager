# Changelog

## v0.1.0-alpha.2

Corrections après le premier essai en jeu de l'alpha.1 et la revue Codex du commit `3092e8d`.

### Corrigé

- Erreurs `Parameter "canvas_item" is null` au survol et au clic des boutons du hub : le bouton ne remplace plus le `_ready()` natif de `DesktopButton` (même correction pour le bouton Base des Smart Managers).
- Affichage compact : la fenêtre se réduit réellement (la racine est un `VBoxContainer` qui ne rétrécit pas seule), le contenu ne déborde plus du cadre, le bouton Mode ne s'étire plus.
- Ports d'un nouveau hub créés avant la collecte des conteneurs par le jeu (plus d'ajout tardif).
- Machine branchée sur deux sorties : seule la sortie propriétaire (la première active) l'alimente ; une sortie coupée ou plafonnée ne laisse plus rien passer par un second câble.
- Valeurs finies très grandes : plus de débordement vers INF ni de part NaN dans l'allocateur ; une offre totale infinie est refusée dans tous les modes, y compris Graphe.
- Mode Graphe rétabli quand le hub revient dans l'arbre de scène.
- Somme de conservation calculée dans un ordre canonique (déterminisme exact).

### Ajouté

- Un hub qui n'alimente que des cibles non bornées le signale au gestionnaire en amont, qui lui transmet les restes au lieu de 0.
- Quand la dernière entrée libre d'une ressource est branchée, une nouvelle entrée libre est ajoutée automatiquement (une entrée native n'accepte qu'un câble).
- Message plus clair quand un Smart Manager en amont n'envoie rien faute de besoin en sortie.
- La sonde liste aussi les gestionnaires branchés sur `window_moved`, `register_resource`, `window_created` et `window_initialized`.

## v0.1.0-alpha.1

Première alpha de Better Resource Manager, fork d'Adaptive Smart Manager v0.1.0-test23. Tests isolés réussis ; validation en jeu en attente.

### Ajouté

- **Better Resource Hub** (`better_resource_hub`) : réserves CPU et GPU indépendantes, entrées et sorties ajoutées ou supprimées en cours de partie, uid de port stables, réglages par sortie (priorité, poids, min, max, active, Auto/Manuel), modes Auto, Demande, Ratio, Priorité, Graphe, résumé et alertes par ressource, affichage compact.
- Allocateur partagé (`scripts/core/brm_allocator.gd`) : remplissage pondéré max-min, conservation garantie, résultats déterministes.
- Mode **Auto** pour Smart Thread Manager et Smart GPU Manager (option 4), enregistré dans `brm_auto_mode`.
- Demande Auto tenant compte de la matière en attente dans le stock des machines.
- Alias des chemins de scène kuuk et ASM : les gestionnaires existants se rechargent sans modifier la sauvegarde.
- Détection des mods concurrents actifs (Mod Loader 7.0.1 n'applique pas les incompatibilités déclarées).
- Sonde d'exécution en lecture seule des API du jeu utilisées par le hub.
- Traduction française ; vérification que chaque langue garde les mêmes paramètres `%s`/`%d`.
- Suites de tests `tests/hub` (297 contrôles) et `tests/load` (126 contrôles), lanceur `tools/Test-All.ps1`.

### Corrigé

- Sous-allocation de l'AI Trainer (et de toute machine finie avec un stock en attente) : le surplus n'est plus perdu quand aucune cible non bornée n'existe, et la demande Auto compte le stock. Voir [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

### Modifié

- Identité : `Daneisra-BetterResourceManager`, registre `data/brm_data.json`, traductions `BetterResourceManager.*`.
- Les Smart Managers enregistrent le chemin de scène depuis lequel ils ont été chargés.
- ZIP construit avec des chemins `/` (lisibles par Godot) ; le script de release ne publie plus rien.

### Retiré

- Workflow GitHub de publication automatique d'ASM.

L'historique d'Adaptive Smart Manager (test20 à test23) est conservé dans [docs/history/ASM_CHANGELOG.md](docs/history/ASM_CHANGELOG.md).
