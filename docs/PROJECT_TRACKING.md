# Suivi du projet

## Objectif

Un gestionnaire unique, fiable et extensible, qui centralise toutes les ressources CPU et GPU et les répartit efficacement, sans cascades de gestionnaires.

## État au 2026-11-03 — v0.1.0-alpha.7

| Livrable | État |
|---|---|
| Fork GitHub `Daneisra/UploadLabs-BetterResourceManager`, remotes `origin` / `upstream`, branche `feat/unified-cpu-gpu-hub` | fait |
| Identité BRM (manifeste, chemins, traductions, packaging) | fait |
| Smart Thread / GPU Manager conservés, mode Auto ajouté | fait, vérifié en jeu (7 gestionnaires kuuk repris, modes changeables) |
| Alias des chemins kuuk / ASM pour les sauvegardes existantes | fait, vérifié en jeu, aller-retour vers kuuk compris (2026-11-03) |
| Better Resource Hub : ports, réserves, modes, réglages, interface | fait, vérifié en jeu (alpha.7) |
| Correction AI Trainer (surplus + stock en attente) | vérifiée en jeu : ~736 k neurones/s avec le gestionnaire repris, 3,55 ZHz via le hub |
| Tests isolés (hub, load, demand, unlocks, translations) | réussis |
| ZIP installable vérifié | fait |
| Validation en jeu | alpha.7 validée le 2026-11-03 : hubs CPU et GPU, réserves, sauvegarde/rechargement, chaînage, sorties coupées ou plafonnées, copier-coller, affichage de l'état (voir [TEST_RESULTS.md](TEST_RESULTS.md)) |

## Problèmes connus à traiter

- **Port créé en cours de partie inactif jusqu'au rechargement** (essai alpha.3, 2026-11-03). Contourné en alpha.4 par les ports de réserve, **vérifié en jeu** le 2026-11-03. Cause exacte toujours inconnue (le diagnostic `Input diff` ne se déclenche que si une entrée branchée reste à 0).
- **Pénurie affichée en permanence** avec un gros stock en attente : corrigé en alpha.7, vérifié en jeu le 2026-11-03.

- **Entrée déconnectée qui garde une ancienne valeur positive** (signalé le 2026-11-02 ; corrigé pour le hub en alpha.3 et pour les Smart Managers en rc.1, vérifié en jeu le 2026-11-03). Si le jeu ne remet pas à 0 le `count` d'une entrée quand son câble est retiré, `_read_supply()` (`scripts/hub/brm_resource_channel.gd`) continue de l'additionner. Le hub distribuerait alors une ressource qui n'arrive plus, ce qui violerait la règle de conservation. Piste : ignorer, ou remettre à 0, toute entrée sans source (`input_id` vide / `input` nul). Vérifier en jeu si le cas se produit, puis ajouter un test de régression. Le même risque existe pour les entrées des Smart Managers (comportement hérité, à vérifier).

## Prochaines étapes

1. Trouver la cause des ports créés en cours de partie inactifs avant rechargement (diagnostic `Input diff`).
2. Publication éventuelle de la `v0.1.0` (GitHub, Workshop) : seulement sur décision de Jérémy.

## Idées pour plus tard

- Sections CPU/GPU repliables séparément.
- Glisser-déposer pour réordonner les ports.
- Migration optionnelle et réversible des chemins kuuk vers les chemins BRM.
- Réglages par machine (pas seulement par sortie).
- Mode Graph tenant compte des réglages des ports.

## Journal

- **2026-11-02** — Environnement vérifié (Git 2.51, gh 2.101 connecté en Daneisra, Godot 4.7.2 console, jeu fermé). Fork créé avec l'historique d'ASM (`main` = test23 + merge). Analyse : la sauvegarde référence 6 STM et 1 SGM de kuuk par chemin de scène ; ML 7.0.1 monte les ZIP désactivés et n'applique pas les incompatibilités ; le SGM de kuuk perdait ~2,87 ZHz de surplus. Hub, allocateur, alias, tests et documentation livrés.
