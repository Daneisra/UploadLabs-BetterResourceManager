# Compatibilité

## Identifiants

| Élément | Valeur |
|---|---|
| Mod | `Daneisra-BetterResourceManager` (namespace `Daneisra`, nom `BetterResourceManager`) |
| Dossier dans le ZIP | `mods-unpacked/Daneisra-BetterResourceManager/` |
| Fenêtres | `smart_thread_manager`, `smart_gpu_manager` (inchangées), `better_resource_hub` (nouvelle) |
| Ressources | `clock_speed` (CPU), `gpu_speed` (GPU) |
| Incompatibilités déclarées | `kuuk-SmartThreadManager`, `kuuk-SmartGPUManager`, `guardipee14-AdaptiveSmartManager` (identifiants vérifiés dans leurs manifestes : namespace + nom) |
| Jeu / chargeur visés | Upload Labs 3.0.12, Mod Loader 7.0.1 (Godot 4.7.2) |

## Mods concurrents

Mod Loader 7.0.1 lit `incompatibilities` mais ne l'applique pas (vérifié dans sa source). BRM vérifie donc lui-même au démarrage, avec `ModLoaderMod.is_mod_active()` :

| Situation | Comportement de BRM |
|---|---|
| Aucun mod concurrent actif | enregistre les 3 fenêtres et installe les 4 alias de chemins |
| kuuk ou ASM actif | n'enregistre **que** le hub, n'installe aucun alias, écrit une erreur explicite dans le journal. Les gestionnaires restent ceux de l'autre mod |
| Un identifiant déjà pris par un mod inconnu | ne l'écrase jamais ; sans les deux identifiants historiques, aucun alias |

Ne laissez jamais deux versions des gestionnaires actives en même temps.

## Sauvegardes existantes

Chaque fenêtre est enregistrée avec un chemin de scène. Dans la sauvegarde actuelle (copie du 2026-11-02 21:12), il y a 6 Smart Thread Managers et 1 Smart GPU Manager de kuuk :

```
"filename": "../../mods-unpacked/kuuk-SmartThreadManager/scenes/windows/window_smart_thread_manager.tscn"
"filename": "../../mods-unpacked/kuuk-SmartGPUManager/scenes/windows/window_smart_gpu_manager.tscn"
```

BRM ne réécrit pas ces lignes. Au démarrage, il charge ses propres scènes de gestionnaires et leur fait occuper ces chemins dans le cache de ressources de Godot (`take_over_path`). Le chargement de la sauvegarde obtient alors la scène BRM. Les noms de nœuds (`PanelContainer/MainContainer/Input` et `Output`), `container_mode` et `use_count` sont identiques, donc les connexions et les réglages sont repris.

Les mêmes alias couvrent les chemins d'Adaptive Smart Manager (`guardipee14-AdaptiveSmartManager`).

Un gestionnaire chargé depuis un chemin kuuk **continue d'enregistrer ce chemin**. Un gestionnaire posé avec BRM enregistre le chemin BRM.

**À vérifier en jeu avant de sauvegarder sur l'emplacement principal** : le journal doit indiquer `Legacy smart manager scene paths resolve to BRM (4 aliases)` et les 7 gestionnaires doivent être présents et connectés.

## Retour arrière vers kuuk

| Élément | Lisible par kuuk après retour ? |
|---|---|
| Gestionnaires posés avant BRM | oui (chemin kuuk conservé) |
| Mode Ratio / Demand / Graph, Base | oui |
| Mode Auto choisi dans BRM | oui, lu comme le dernier mode Ratio/Demand/Graph choisi (`container_mode`) ; `brm_auto_mode` est ignoré |
| Gestionnaires posés avec BRM | non : leur chemin est celui de BRM |
| Better Resource Hub | non : n'existe que dans BRM |

Pour revenir en arrière sans rien perdre, restaurez la sauvegarde faite avant l'installation.

## Migration

Aucune migration n'est nécessaire ni effectuée en `v0.1.0-alpha.1`. Une future migration éventuelle (par exemple réécrire les chemins kuuk) devra être explicite, testée sur une copie et réversible.

## Format de sauvegarde du hub

```
"brm_format": 1,
"brm_layout": {"format": 1, "ports": [{"uid": "cpu_in_1", "kind": 0, "label": ""}, …], "next": {"cpu_in": 2, …}},
"brm_mode": 0,
"brm_compact": false,
"brm_port_state": {"cpu_in_1": {"id": "…", "outputs_id": []}, …},
"container_data": {"PanelContainer/MainContainer/Cpu/Inputs/cpu_in_1/Port": {…}, …}
```

`kind` : 0 entrée CPU, 1 sortie CPU, 2 entrée GPU, 3 sortie GPU. Une disposition illisible est ignorée (ports courants conservés) ; les ports invalides ou en double sont écartés et signalés dans le journal.

## Autres mods présents dans le profil

AkibaCat Where Should I Connect, Jxrdxn EasyTokens, asouy ModManager, ayyEve BetterSplitters, Daneisra SmartAutomation : aucun conflit d'identifiant connu. Where Should I Connect parcourt `window.containers` et `desktop.resources` : les ports du hub y figurent comme des conteneurs natifs. Non testé ensemble en jeu.
