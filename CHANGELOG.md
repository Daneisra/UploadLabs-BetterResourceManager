# Changelog

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
