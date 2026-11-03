# CLAUDE.md — Better Resource Manager

Référence de travail pour Claude Code. Lire aussi [AGENTS.md](AGENTS.md) (règles communes) et [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Projet

Mod Godot/GDScript pour Upload Labs 3.0.12 (Steam), Mod Loader 7.0.1, Godot 4.7.2. Fork d'Adaptive Smart Manager (guardipee14), lui-même issu de kuuk / Omisse. Le dépôt **est** le dossier du mod (`mods-unpacked/Daneisra-BetterResourceManager/` dans le ZIP).

- Dépôt : https://github.com/Daneisra/UploadLabs-BetterResourceManager (`origin`), amont `guardipee14/Adaptive-Smart-Manager` (`upstream`).
- Branche de travail : `feat/unified-cpu-gpu-hub`.
- Langue : français pour la documentation et les échanges, anglais pour le code et les commentaires.

## Règles de sécurité (impératives)

1. Ne jamais modifier les sauvegardes de `%APPDATA%\Upload Labs` ni `mod_user_profiles.json` sans accord explicite. Toujours copier d'abord dans `D:\Téléchargements\Code\UploadLabs-Backups\<date>_<raison>`.
2. Ne jamais installer ou retirer un mod dans `E:\steam\steamapps\common\Upload Labs\mods` sans accord, et seulement jeu fermé (vérifier le processus).
3. Ne rien publier : pas de release GitHub, pas de Steam Workshop. `tools/New-Release.ps1` construit un ZIP local et c'est tout.
4. Ne pas modifier le projet voisin `UploadLabs-SmartAutomation` (lecture autorisée).
5. Pas de décompilation ni d'extraction du PCK du jeu. Sources autorisées : mods publics, source de Mod Loader, observation à l'exécution (`brm_runtime_probe.gd`).
6. Ne jamais annoncer un test en jeu qui n'a pas eu lieu. Les suites isolées ne prouvent pas la compatibilité en jeu.

## Outils locaux

- Godot console : `D:\Téléchargements\Code\UploadLabs-Tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe`
- GitHub CLI : `D:\Téléchargements\Code\UploadLabs-Tools\gh\bin\gh.exe` (compte Daneisra)
- Jeu : `E:\steam\steamapps\common\Upload Labs` ; journaux : `%APPDATA%\Upload Labs\logs\modloader.log`

## Commandes

```powershell
.\tools\Test-All.ps1                                  # toutes les suites isolées
.\tools\Test-Hub.ps1 -GodotExecutable <godot>         # allocateur, canal, ports, AI Trainer
.\tools\Test-Load.ps1 -GodotExecutable <godot>        # chargement scripts/scènes, alias, sauvegarde du hub
.\tools\Test-Demand.ps1 / Test-Unlocks.ps1            # suites héritées d'ASM
.\tools\Test-Translations.ps1 -GodotExecutable <godot> -Rebuild   # après modification du CSV
.\tools\New-Release.ps1                               # ZIP dans release/ (arbre propre exigé)
.\tools\Test-Package.ps1 -Archive <zip>               # vérification statique du ZIP
```

`release/` est ignoré par Git (dossiers d'exécution des tests et ZIP).

## Pièges connus

- PowerShell 5.1 : une ligne stderr d'un exécutable natif sous `$ErrorActionPreference = 'Stop'` interrompt le script. Les lanceurs basculent sur `Continue` autour de Godot.
- PowerShell 5.1 : `Set-Content -Encoding utf8` ajoute un BOM. Écrire avec `[IO.File]::WriteAllText(..., [Text.UTF8Encoding]::new($false))`.
- GDScript : pas de format `%e` ni `%g` (utiliser `String.num_scientific`).
- Un script `--script` ne voit pas les autoloads comme identifiants à la compilation : passer par `root.get_node("/root/Data")`.
- Un script de test dont un tableau typé référence sa propre classe fuit à la sortie.
- `Compress-Archive` peut produire des `\` dans les entrées ZIP : le packaging utilise `ZipArchive` avec des `/`.

- Ne jamais surcharger `_ready`, `_enter_tree`, `_exit_tree` d'une classe du jeu sans `super()` ; et `super()` ne compile pas si le parent ne définit pas la méthode. Utiliser `_notification(NOTIFICATION_READY / ENTER_TREE / EXIT_TREE)`.
- Un nœud créé par code dans une fenêtre doit avoir `owner = fenêtre`, sinon le jeu ne le voit pas (`find_children` ne renvoie que les nœuds possédés).

- Le jeu écrit `savegame.dat` à chaque sauvegarde, quel que soit l'emplacement. Un essai sur un autre emplacement réécrit donc aussi ce fichier : le copier avant, et le restaurer après avec un horodatage récent, car Steam Cloud est actif.

## Contrats à ne pas casser

- Identifiants de fenêtres `smart_thread_manager`, `smart_gpu_manager`, `better_resource_hub`.
- Chemins des conteneurs (clés de `container_data`) : `PanelContainer/MainContainer/Input|Output` (gestionnaires) et `PanelContainer/MainContainer/<Cpu|Gpu>/<Inputs|Outputs>/<uid>/Port` (hub).
- Champs sauvegardés : `container_mode` (0-2), `use_count`, `brm_auto_mode`, `brm_layout`, `brm_port_state`, `brm_mode`, `brm_compact`, `brm_format`.
- `unique_id` des nœuds hérités dans les `.tscn` (racine 1571110532, Icon 2015431448, Title 570823129) : identiques aux scènes ASM.
- Préfixes d'uid `cpu_in`, `cpu_out`, `gpu_in`, `gpu_out` ; compteurs jamais décroissants.

## État

Voir [docs/PROJECT_TRACKING.md](docs/PROJECT_TRACKING.md) et [docs/TEST_RESULTS.md](docs/TEST_RESULTS.md).
