# Résultats des tests

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
