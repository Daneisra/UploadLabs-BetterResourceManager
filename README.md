# Better Resource Manager (BRM)

Mod Upload Labs qui centralise le CPU et le GPU dans un seul nœud, **Better Resource Hub**, et conserve les **Smart Thread Manager** et **Smart GPU Manager** d'Adaptive Smart Manager.

> **Version : `v0.1.0-alpha.2`** — alpha. Premier essai en jeu de l'alpha.1 : mod chargé, gestionnaires existants repris, hub connectable ; sauvegarde/rechargement du hub encore à vérifier. Voir [docs/TEST_RESULTS.md](docs/TEST_RESULTS.md).

*English summary: Better Resource Hub pools CPU (`clock_speed`) and GPU (`gpu_speed`) from any number of input ports and shares each pool between any number of output ports, with priorities, weights, limits and an Auto mode. It also ships the Smart Thread / Smart GPU Managers (same window ids as kuuk's mods and Adaptive Smart Manager). Alpha: in-game validation pending.*

## Fonctionnalités

### Better Resource Hub (`better_resource_hub`)

- Deux réserves **indépendantes** : CPU et GPU. Aucune conversion entre les deux.
- Ports ajoutés à la demande : `+ Entrée CPU`, `+ Entrée GPU`, `+ Sortie CPU`, `+ Sortie GPU`. Ce sont de vrais conteneurs natifs du jeu, connectables comme ceux des autres machines.
- Toutes les entrées d'une ressource alimentent la même réserve. Le hub ne distribue que ce que ses sources fournissent réellement.
- Un port ne peut être supprimé qu'une fois déconnecté. Son identifiant (`cpu_out_3`…) n'est jamais réutilisé.
- Réglages par sortie : priorité, poids, minimum, maximum, active/coupée, besoin Auto ou Manuel.
- Modes : **Auto** (recommandé), Demande, Ratio, Priorité, Graphe.
- Affichage par ressource : reçu, distribué, inutilisé, besoin, débit et besoin par port, et alertes (pénurie, aucune source, aucune demande, boucle, port non reconnu…).
- Affichage compact pour les grosses installations. Interface en français et en anglais.

### Smart Thread Manager et Smart GPU Manager

- Mêmes identifiants (`smart_thread_manager`, `smart_gpu_manager`), mêmes modes Ratio, Demande et Graphe, même chaînage, même réglage Base, comportement d'Adaptive Smart Manager test23.
- Nouvelle option **Mode : Auto**, enregistrée à part (`brm_auto_mode`) pour que la sauvegarde reste lisible par les mods d'origine.
- Les gestionnaires déjà posés avec les mods de kuuk (ou ASM) se rechargent sans modification de la sauvegarde. Voir [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md).

### Mode Auto

- Estime le besoin de chaque machine, **y compris la matière qui attend dans son stock**.
- Partage les pénuries équitablement (remplissage max-min), en favorisant les priorités sans affamer les autres.
- Sert les cibles non bornées (vendeurs, mineurs) avec les restes, puis rend le vrai surplus aux consommateurs au lieu de le laisser inutilisé.
- Lisse la demande pour éviter les oscillations et ne recalcule rien si rien n'a changé.

L'optimisation n'est pas garantie globalement optimale : certaines machines du jeu ont un fonctionnement interne que le mod ne peut pas lire. Dans ce cas le hub retombe sur un mode dégradé documenté dans [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Installation

Environnement visé : Upload Labs 3.0.12 (Steam), Mod Loader 7.0.1.

1. Fermez Upload Labs.
2. **Sauvegardez** le dossier `%APPDATA%\Upload Labs` (sauvegardes, `mod_user_profiles.json`).
3. Désactivez `kuuk-SmartThreadManager`, `kuuk-SmartGPUManager` et `guardipee14-AdaptiveSmartManager` s'ils sont installés (gestionnaire de mods en jeu, ou `"is_active": false` dans `mod_user_profiles.json`). Mod Loader 7.0.1 n'applique pas lui-même les incompatibilités déclarées : si l'un d'eux reste actif, BRM n'enregistre que le hub et laisse leurs gestionnaires tranquilles.
4. Copiez `Daneisra-BetterResourceManager-v0.1.0-alpha.2.zip` **sans le décompresser** dans `…\steamapps\common\Upload Labs\mods\`.
5. Lancez le jeu. Le journal (`%APPDATA%\Upload Labs\logs\modloader.log`) doit contenir `Better Resource Manager initialized` et `Legacy smart manager scene paths resolve to BRM (4 aliases)`.

## Retour arrière

1. Fermez le jeu.
2. Retirez le ZIP BRM du dossier `mods`.
3. Réactivez les mods de kuuk si vous les utilisiez.
4. Si quelque chose s'est mal passé, restaurez le dossier `%APPDATA%\Upload Labs` sauvegardé à l'étape 2.

Ce que le retour arrière conserve et ne conserve pas est détaillé dans [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md). En résumé : les gestionnaires posés avant BRM restent lisibles par kuuk, mais les hubs et les gestionnaires posés avec BRM n'existent que tant que BRM est installé.

## Développement

```powershell
# Toutes les suites isolées (n'ouvrent ni le jeu ni une sauvegarde)
.\tools\Test-All.ps1

# ZIP installable (ne publie rien), puis sa vérification
.\tools\New-Release.ps1
.\tools\Test-Package.ps1 -Archive .\release\Daneisra-BetterResourceManager-v0.1.0-alpha.2.zip
```

- Architecture : [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- Résultats des tests : [docs/TEST_RESULTS.md](docs/TEST_RESULTS.md)
- Compatibilité et sauvegardes : [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md)
- Suivi du projet : [docs/PROJECT_TRACKING.md](docs/PROJECT_TRACKING.md)
- Consignes pour agents : [CLAUDE.md](CLAUDE.md), [AGENTS.md](AGENTS.md)

## Crédits et licence

Better Resource Manager est un fork d'[Adaptive Smart Manager](https://github.com/guardipee14/Adaptive-Smart-Manager) de **guardipee14**, lui-même basé sur [Smart Thread Manager / Smart GPU Manager](https://github.com/Omisse/ul-stmmod) de **kuuk / Omisse**. Licence MIT, voir [LICENSE](LICENSE) et [NOTICE.md](NOTICE.md). L'historique d'ASM est conservé dans [docs/history](docs/history).
