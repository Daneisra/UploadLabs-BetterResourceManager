# AGENTS.md — Better Resource Manager

Guide pour Codex et tout agent de revue. Lecture minimale : ce fichier, puis [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## En une phrase

Mod Upload Labs (Godot 4.7.2, GDScript, Mod Loader 7.0.1) : **Better Resource Hub** regroupe CPU (`clock_speed`) et GPU (`gpu_speed`) depuis des ports d'entrée extensibles et les répartit entre des ports de sortie extensibles ; le mod conserve aussi Smart Thread Manager et Smart GPU Manager (fork d'Adaptive Smart Manager test23).

## Règles

- **Lecture seule** sur l'installation du jeu, les sauvegardes (`%APPDATA%\Upload Labs`), le profil de mods et le projet voisin `UploadLabs-SmartAutomation`.
- Aucune publication (release, Workshop). Aucune décompilation du jeu.
- Une revue ne doit pas présenter un test isolé comme une preuve de fonctionnement en jeu.
- Code et commentaires en anglais ; documentation en français. Indentation : 4 espaces dans les `.gd`. Fins de ligne LF (CRLF pour `.ps1`), voir `.gitattributes`.

## Carte du code

| Couche | Fichiers | Dépend du jeu ? |
|---|---|---|
| Logique pure | `scripts/core/*.gd` | non |
| Demande, rôles, modes d'origine | `scripts/global/smart_window_data.gd`, `distribution_modes.gd` | membres de `ResourceContainer`/Process lus défensivement |
| Hub, une ressource | `scripts/hub/brm_resource_channel.gd` | oui (conteneurs) |
| Fenêtre du hub, interface, sauvegarde | `scenes/windows/window_better_resource_hub.gd` | oui |
| Gestionnaires historiques | `scenes/windows/window_smart_manager.gd`, `scripts/smart_resource_container.gd` | oui |
| Enregistrement, conflits, alias | `mod_main.gd`, `scripts/global/legacy_scene_aliases.gd` | oui |

## Tests

```powershell
.\tools\Test-All.ps1      # Godot attendu dans ..\UploadLabs-Tools\godot-4.7.2\
```

Toutes les suites tournent dans des projets isolés sous `release/` avec des doublures des classes du jeu ; aucune n'ouvre le jeu. Résultats et limites : [docs/TEST_RESULTS.md](docs/TEST_RESULTS.md).

## À examiner en priorité

1. **Ports ajoutés en cours de partie** (`add_port`, `_adopt_runtime_container`, ports de réserve dans `brm_port_layout.gd`). Constaté en jeu : un port créé après la mise en place de la fenêtre est connectable mais ne reçoit rien avant un rechargement ; les ports de réserve créés avec la fenêtre contournent le problème. La cause exacte reste à trouver (diagnostic `Input diff` du journal).
2. **Restauration au chargement** : construction des ports dans le setter de `brm_layout` avant `container_data` ; repli `brm_port_state` (réécrit `id` et `outputs_id`). Risque si le jeu restaure autrement.
3. **Alias de chemins** (`legacy_scene_aliases.gd`) : `take_over_path` + cache. Vérifié en jeu, aller-retour vers kuuk compris ; toute modification doit garder ce comportement.
4. **Allocateur** : conservation, plafonds, déterminisme, cas extrêmes (`water_fill`, sommes suffixes, `_enforce_conservation`).
5. **Cache d'allocation** du canal (`_signature`, `_signature_matches`) : ne doit jamais réutiliser une allocation calculée pour une offre plus grande.
6. **Demande Auto** (`get_auto_demand`, horizon de stock de 10 s) : effet sur des machines à stock limité ; interaction avec les cibles non bornées.
7. Détection des boucles (`_upstream_windows`) : uniquement par connexions de la même ressource.
8. Interface sur le bureau : `LineEdit` et raccourcis clavier du jeu (saisie des champs Min/Max utilisée en jeu sans problème signalé ; raccourcis non testés systématiquement).

## Fichiers à ne pas renommer

Voir « Contrats à ne pas casser » dans [CLAUDE.md](CLAUDE.md).
