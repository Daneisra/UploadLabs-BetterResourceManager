# Changelog

## v0.1.0-alpha.5

### Corrigé

- Une entrée vide ne s'ajoute plus à chaque chargement de la sauvegarde. Le jeu rejoue `connection_created` pour chaque câble restauré ; l'ajout automatique d'une entrée libre ne réagit plus qu'aux branchements faits après une trentaine d'itérations du hub. Un port retiré volontairement ne revient donc plus.

## v0.1.0-alpha.4

Après l'essai en jeu de l'alpha.3 : le hub fonctionne, mais un port ajouté en cours de partie reste à 0 jusqu'au rechargement (10 entrées branchées, seule la première, créée avec la fenêtre, recevait).

### Ajouté

- **Ports de réserve** : chaque hub prépare dès sa création 8 entrées et 4 sorties masquées par ressource. `+ Entrée` / `+ Sortie` et l'entrée libre automatique révèlent un port de réserve, qui fonctionne tout de suite. Retirer un port le remet en réserve. Les réserves sont complétées à chaque chargement.
- Au-delà des réserves, un port créé en direct est marqué « après rechargement » (et signalé dans l'état de la ressource) au lieu de paraître fonctionnel.
- Diagnostic en jeu : si une entrée branchée reste à 0, le journal compare ses propriétés et connexions de signaux à celles d'une entrée qui reçoit, pour trouver la vraie cause.

### Modifié

- Les totaux du hub utilisent la même notation que les ports du jeu (`486EHz`, `1.13ZHz`) au lieu de celle de `Utils.print_string` (`486abHz`, `1.13acHz`).

## v0.1.0-alpha.3

Corrections après l'essai en jeu de l'alpha.2 (entrées à 0 même branchées directement sur un Processeur Mk.52, fond transparent, câbles qui ne suivent pas le nœud, réglages illisibles).

### Corrigé

- Le hub ne remplace plus `_enter_tree()` / `_exit_tree()` de `WindowBase` (remplacés par des notifications) : l'initialisation native de la fenêtre s'exécute à nouveau. C'est la cause probable du fond transparent, des câbles mal placés et des erreurs `canvas_item is null` restantes.
- Les ports sont possédés (`owner`) par la fenêtre, comme les nœuds d'une scène de fenêtre classique : le jeu les trouve lui-même parmi les conteneurs de la fenêtre. C'est la cause probable des entrées qui ne recevaient rien.
- Une entrée déconnectée qui garde une ancienne valeur n'est plus comptée dans la réserve ; elle est remise à 0.
- Ligne de réglages d'une sortie : les libellés ne se coupent plus après chaque lettre.
- Smart Managers : leur conteneur de sortie ne remplace plus `_exit_tree()` du conteneur natif.

### Ajouté

- Diagnostic en jeu (3 rapports par session au plus) : si des entrées branchées ne reçoivent rien, le journal décrit leur source telle que le jeu la voit.

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
