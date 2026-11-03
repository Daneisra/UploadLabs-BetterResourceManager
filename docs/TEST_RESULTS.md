# Résultats des tests

## v0.1.0-alpha.5 — 2026-11-03 (tests isolés)

Load 220, Hub 336, Demand 138, Unlocks 158, Translations 76 × 2 : 0 échec. Nouveau contrôle : un `connection_created` reçu juste après la création du hub (câble restauré au chargement) n'ajoute pas d'entrée ; le même signal après 30 itérations en ajoute une.

## v0.1.0-alpha.4 — essai en jeu du 2026-11-03 (Jérémy)

| Point | Résultat |
|---|---|
| Hub rechargé, 10 entrées CPU sur 2 Processeurs Mk.52 | **réussi** : Reçu 2,27 ZHz puis 4,81 ZHz après amélioration des processeurs, tout distribué |
| Hub neuf, entrées branchées une à une (ports de réserve) | **réussi** : chaque entrée révélée reçoit immédiatement (10 entrées CPU, 10 entrées GPU à 687 EHz, 6,87 ZHz) |
| Réserve épuisée | port marqué « après rechargement », état « 1 port(s) actif(s) après sauvegarde et rechargement » ; actif après rechargement |
| Deux hubs alimentés par les mêmes processeurs | chacun ne compte que ses entrées ; « Inutilisé » exact sur le hub sans consommateur |
| Sauvegarde puis rechargement d'un hub créé en alpha.4 | **réussi** : ports et connexions repris |
| Notation des totaux | identique à celle des ports (`ZHz`, `EHz`) |
| Erreurs | aucune erreur BRM ; seules les erreurs propres au jeu (`ad_prompt.gd`, dossier `mods-unpacked`) |
| Défaut | **une entrée vide revient à chaque chargement** (journal : `cpu_in_12` et `gpu_in_13` révélés juste après chaque chargement) — corrigé en alpha.5 |

## v0.1.0-alpha.4 — 2026-11-03 (tests isolés)

Load 219, Hub 336, Demand 138, Unlocks 158, Translations 76 × 2 : 0 échec. Nouveaux contrôles : réserves créées avec la fenêtre, masquées, révélées par `+`, remises en réserve au retrait, complétées au rechargement ; port en direct signalé « après rechargement » une fois les réserves épuisées ; notation des valeurs identique à celle des ports.

## v0.1.0-alpha.3 — essai en jeu du 2026-11-03 (Jérémy)

| Point | Résultat |
|---|---|
| Hub rechargé depuis la sauvegarde (5 entrées CPU sur un Processeur Mk.52) | **réussi** : Reçu 1,13 ZHz, distribué à 3 Enhancer MAX (378 EHz chacun), Inutilisé 0 |
| Chaîne GPU Manager → hub → Neuron Reinforcer, Entraîneur d'IA, générateur de programme (Auto) | **réussi** : Reçu 6,48 ZHz, tout distribué |
| Sauvegarde puis rechargement d'un hub | **réussi** (hub présent au lancement, ports et connexions repris, aucune erreur) |
| Fond du hub, câbles lors du déplacement | **corrigés** (opaques, câbles alignés) |
| Ligne de réglages d'une sortie | lisible |
| Erreurs `canvas_item is null` | **0** |
| Hub neuf avec 10 entrées sur 2 processeurs | **échec partiel** : seule l'entrée créée avec la fenêtre (`cpu_in_1`) reçoit ; les 9 ajoutées en cours de partie restent à 0 |
| Notation | les totaux affichaient `acHz` / `abHz` quand les ports affichent `ZHz` / `EHz` |
| Message de pénurie | permanent avec les Enhancer MAX : leur besoin Auto inclut leur stock de jeux en attente |

## v0.1.0-alpha.3 — 2026-11-02 (tests isolés)

Load 153, Hub 325, Demand 138, Unlocks 158, Translations 73 × 2 : 0 échec. Nouveaux contrôles : `WindowBase._enter_tree` toujours exécuté, ports possédés par la fenêtre et collectés sans ajout tardif (doublure qui collecte comme `find_children()` par défaut), entrée déconnectée remise à 0 et exclue de la réserve.

## v0.1.0-alpha.2 — essai en jeu du 2026-11-02 (Jérémy)

| Point | Résultat |
|---|---|
| Entrées CPU branchées directement sur un Processeur Mk.52 (5 câbles, sans Smart Manager) | **échec** : 0 Hz reçu sur toutes les entrées, y compris après débranchement et rebranchement |
| Sortie CPU vers 3 Enhancer MAX | besoin lu (60,1 acHz), rien distribué faute d'offre |
| Affichage compact | la fenêtre se réduit ; **fond transparent**, câbles qui traversent le nœud quand on le déplace |
| Réglages d'une sortie | **illisibles** : libellés coupés lettre par lettre, cases très hautes |
| Entrée libre ajoutée automatiquement | fonctionne (6e entrée libre visible) |
| Erreurs `canvas_item is null` | 196 (contre 662 avec l'alpha.1) |
| Journal | ports toujours « missing from window containers » ; `window_moved` est écouté par `res://scripts/connectors.gd`, `window_initialized` par `desktop.gd` et d'autres |

## v0.1.0-alpha.2 — 2026-11-02 (tests isolés)

| Suite | Résultat |
|---|---|
| `tests/load` | 149 contrôles, 0 échec (dont : ports d'un nouveau hub collectés par la fenêtre sans ajout tardif, avec une doublure `WindowBase` qui collecte via `@onready` comme le jeu ; l'affichage compact réduit la fenêtre et l'affichage complet la rétablit ; entrée libre ajoutée quand la dernière est branchée ; mode Graphe reconstruit après réinsertion ; scripts compilables même si `DesktopButton` n'a pas de `_ready`) |
| `tests/hub` | 320 contrôles, 0 échec (section 20 : régressions de la revue Codex) |
| `tests/demand`, `tests/unlocks` | 138 et 158, 0 échec |
| `tests/translations` | 73 messages × 2 langues |

Constats de la revue Codex (commit `3092e8d`) et suite donnée :

| # | Constat | Suite |
|---|---|---|
| 1 | une sortie coupée ou plafonnée laissait passer du CPU/GPU par le second câble d'une machine branchée sur deux sorties | corrigé, testé |
| 2 | débordement vers INF / NaN avec des valeurs finies proches de 1e308 | corrigé (plafond 1e300, demandes normalisées), testé |
| 3 | un hub en aval n'alimentant que des cibles non bornées recevait 0 de l'amont | corrigé (indicateur non borné remonté), testé |
| 4 | offre totale infinie distribuée en mode Graphe | corrigé, testé dans les 5 modes |
| 5 | mode Graphe perdu après sortie puis retour dans l'arbre | corrigé, testé |
| 6 | redimensionnement compact calculé avant la mise à jour du contenu | corrigé, testé |
| 7 | `DesktopButton` sans `_ready` natif (hypothèse sur l'API du jeu) | corrigé par `NOTIFICATION_READY` ; effet sur les erreurs `canvas_item` à vérifier en jeu |
| 8 | ordre des requêtes influençant la correction de conservation | corrigé, testé |

## v0.1.0-alpha.1 — essai en jeu du 2026-11-02 (Jérémy, partie principale)

Sources : captures d'écran et journaux `modloader.log` / `godot.log`.

| Point | Résultat |
|---|---|
| Chargement du mod | réussi : prévol de 26 ressources, 3 fenêtres enregistrées, 4 alias actifs, aucune erreur de script BRM |
| Gestionnaires existants (6 Smart Thread, 1 Smart GPU) | repris et connectés, modes changeables (Ratio, Demande, Graphe, Auto) |
| Better Resource Hub dans Add Node | présent, posable |
| Ports connectables | oui, y compris les ports ajoutés en cours de partie (inscrits par le jeu lui-même) |
| Plusieurs sources sur une même entrée | impossible : une entrée native n'accepte qu'un câble ; il faut un port par source |
| Smart GPU Manager, chaîne AI (texte), mode Demande | AI Trainer 589 EHz, ~736 k neurones/s ; surplus de ~5,23 ZHz envoyé au Text Generator, détecté comme cible non bornée |
| Smart GPU Manager, chaîne AI (programme), mode Auto | AI Trainer ~5,23 ZHz |
| Affichage | défauts : la fenêtre ne rétrécit pas en compact, bouton Mode étiré, contenu hors du cadre ; 662 erreurs `canvas_item is null` liées aux boutons du hub |
| Entrées du hub alimentées par des Smart Thread Managers | 0 Hz tant qu'aucune machine n'est branchée sur les sorties : l'amont n'envoie que le besoin déclaré par le hub |
| Sauvegarde/rechargement d'un hub | **non testé** (aucun hub dans la sauvegarde au moment de la lecture) |
| Probe | fenêtre = `VBoxContainer` ; tous les membres attendus des conteneurs présents ; `desktop.resources` est un dictionnaire ; les conteneurs créés dans le `_ready` de la sous-classe ne sont pas collectés par la fenêtre |

## v0.1.0-alpha.1 — 2026-11-02

Environnement : Windows 10 Pro 19045, Godot `4.7.2.stable.official.ed1daf0bf` (console, mode headless), PowerShell 5.1. Commit testé : `9f50ad2`.

### Réussis

| Suite | Résultat | Ce que cela prouve |
|---|---|---|
| `tests/load` | 141 contrôles, 0 échec | tous les scripts et les 5 scènes se chargent et s'instancient avec des doublures du jeu ; enregistrement des 3 fenêtres ; alias kuuk/ASM résolus par le cache réel de Godot (y compris `ResourceLoader.exists`) ; aucun alias sans propriété des identifiants ; cycle du hub « champs sauvegardés avant `_ready` → sauvegarde → rechargement » : ports aux mêmes chemins, mêmes identifiants, connexions, mode et compteurs conservés ; `export()` sans identifiants ; les 5 modes, les ticks et toutes les actions d'interface s'exécutent sans erreur ; gestionnaire chargé par chemin kuuk qui réenregistre ce chemin |
| `tests/hub` | 297 contrôles, 0 échec | voir le détail ci-dessous |
| `tests/demand` (ASM) | 138 contrôles, 0 échec | demande des Process 3.0 inchangée après les ajouts |
| `tests/unlocks` (ASM) | 158 contrôles, 0 échec | déverrouillages 2.2 / 3.0 inchangés |
| `tests/translations` | 73 messages × 2 langues | CSV = compilés, mêmes paramètres `%s`/`%d` en anglais et en français |
| `Test-Package.ps1` | 37 fichiers | structure `mods-unpacked/Daneisra-BetterResourceManager/`, entrées en `/`, octets identiques à la source, manifeste, 3 incompatibilités, 3 scènes de fenêtres présentes, toutes les références `res://` résolues ; 5 ressources du jeu attendues |
| Montage du ZIP | réussi | `ProjectSettings.load_resource_pack()` (comme Mod Loader) monte l'archive ; manifeste, traductions, scènes et 21 scripts lisibles |

Détail de `tests/hub` :

| Section | Contrôles |
|---|---|
| 01–02 Agrégation de 2, 10, 50 entrées CPU puis GPU | 24 |
| 03 Distribution vers 2, 10, 30, 100 consommateurs (abondance et pénurie) | 24 |
| 04 CPU et GPU indépendants | 6 |
| 05 Conservation : 600 cas aléatoires × 4 politiques | 3 |
| 06 Valeurs extrêmes (1e300, 1e-300, NaN, ±INF, négatifs) | 61 |
| 07 Équité en pénurie (max-min, pas d'échelle GHz → Hz) | 19 |
| 08 Priorités, poids, min, max, désactivation | 13 |
| 09 Redistribution du surplus et de la part d'une machine en pause | 9 |
| 10 Variations de demande (lissage) | 11 |
| 11 Boucles (gestionnaire en boucle, auto-boucle, liste `looping` native, graphe de 10 000 nœuds borné) | 10 |
| 12 Consommateurs non bornés | 18 |
| 13 Ports ajoutés/supprimés, port Manuel, port coupé | 22 |
| 14 Uid après sauvegarde/rechargement, sauvegarde corrompue | 12 |
| 15 Compatibilité des gestionnaires (chemins, registre, déverrouillages, Auto historique) | 28 |
| 16 Régression AI Trainer | 15 |
| 17 Déterminisme | 8 |
| 18 Diagnostics | 9 |
| 19 Performance | 5 |

Performance mesurée (Godot éditeur, 100 consommateurs, 10 sorties, 20 entrées) : **1,9 ms** par itération en régime stable, **3,9 ms** quand l'offre change à chaque itération.

### Régression AI Trainer (simulation)

Avec les valeurs de la sauvegarde (offre 5,36 ZHz ; besoins count/s 268 EHz, 73,6 EHz, 588 MHz ; stock de texte 1,84e16) :

- Ratio et Graph d'origine : AI Trainer limité à 2,68e20, le reste n'est distribué à personne. **Bug reproduit.**
- Hub en Auto, Demande et Priorité : AI Trainer ≥ 2,95e21 (valeur du branchement direct), les 5,36 ZHz entièrement distribués, les autres machines servies.
- Pénurie (3e20) : l'AI Trainer garde la plus grande part grâce à son stock, le Reinforcer n'est pas affamé.

Cette simulation porte sur l'allocation de GPU, pas sur la production de neurones.

### Défauts trouvés par les tests puis corrigés

- `water_fill` : après soustraction d'un très grand poids, le poids restant tombait à 0 par annulation flottante et une partie de l'offre n'était pas distribuée. Corrigé par sommes suffixes.
- Formats `%e` / `%g` inexistants en GDScript dans l'affichage des limites. Remplacés par `String.num_scientific`.
- Retour à zéro du lissage jamais atteint. Corrigé (référence au dernier pic).
- Compteur de cibles non bornées qui comptait les ports au lieu des machines.
- Alias installés même quand BRM ne possédait pas les identifiants historiques. Conditionnés.
- `export()` pouvait transmettre les identifiants de conteneurs si l'implémentation parente appelait `save()`. Retirés explicitement.
- Lanceurs PowerShell interrompus à la première ligne d'erreur de Godot (journal tronqué). Corrigés.

### Échoués

Aucun à ce jour.

### Non exécutés

- **Aucun test en jeu.** Rien de ce qui suit n'a été vérifié dans Upload Labs : chargement du mod, présence des gestionnaires existants, Better Resource Hub dans Add Node, connexions réelles, ports ajoutés en cours de partie, sauvegarde/rechargement réels, journaux, production de l'AI Trainer.
- Godot 4.6.1 (non installé sur cette machine).
- Interaction avec Where Should I Connect, BetterSplitters, EasyTokens, ModManager, SmartAutomation.

## Protocole de test en jeu (à faire avec Jérémy)

Préparation, jeu fermé et avec accord :

1. Copier tout `%APPDATA%\Upload Labs` dans `UploadLabs-Backups\<date>_avant-brm-alpha.1`.
2. Copier le ZIP dans `…\Upload Labs\mods\`.
3. Désactiver `kuuk-SmartThreadManager` et `kuuk-SmartGPUManager` dans le profil.
4. Jouer sur une copie de la sauvegarde si possible (l'autosauvegarde écrit dans l'emplacement chargé).

Dans le jeu :

| # | Étape | Attendu | Preuve |
|---|---|---|---|
| 1 | Lancer le jeu | pas d'erreur BRM | journal |
| 2 | Charger la sauvegarde | 6 Smart Thread + 1 Smart GPU Manager présents et connectés | capture |
| 3 | Add Node → CPU → management | Better Resource Hub présent | capture |
| 4 | Poser un hub, `+ Entrée CPU`, `+ Sortie GPU`… | ports connectables, pas d'alerte « port non reconnu » | capture |
| 5 | Brancher 2 sources CPU et 2 sources GPU, plusieurs consommateurs | totaux cohérents, rien d'inventé | capture |
| 6 | Supprimer un port déconnecté, essayer un port connecté | le second est refusé | capture |
| 7 | GPU Manager → hub → Reinforcer, AI Trainer, Text Generator | AI Trainer ≥ ~736 k neurones/s | capture |
| 8 | Sauvegarder, revenir au menu, recharger | ports, noms, réglages et connexions identiques | capture |
| 9 | Quitter normalement | — | `modloader.log` (lignes `[Probe]`, `[Hub]`, `BRM`) |
