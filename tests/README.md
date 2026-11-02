# Tests

Toutes les suites tournent dans un projet Godot isolé créé sous `release/` (ignoré par Git). Aucune ne lance Upload Labs ni n'ouvre une sauvegarde : elles valident la logique et les contrats, pas le comportement en jeu.

```powershell
.\tools\Test-All.ps1   # Godot 4.7.2 console attendu dans ..\UploadLabs-Tools\godot-4.7.2\
```

| Suite | Dossier | Contenu |
|---|---|---|
| Hub | `tests/hub` | vrais scripts `scripts/core`, `scripts/hub`, `smart_window_data.gd`, `distribution_modes.gd` avec des doublures de `WindowBase` / `ResourceContainer` / `Utils`. 19 sections (agrégation, distribution, indépendance CPU/GPU, conservation aléatoire, extrêmes, équité, priorités, surplus, variations, boucles, non bornés, ports dynamiques, persistance, compatibilité, AI Trainer, déterminisme, diagnostics, performance) |
| Load | `tests/load` | charge tous les scripts et scènes du mod avec des doublures des classes, autoloads et scènes de base du jeu ; vérifie l'enregistrement, les alias de chemins dans le cache réel de Godot, et le cycle « champs sauvegardés → `_ready` → sauvegarde → rechargement » du hub. Les copies des scènes remplacent l'icône PNG du jeu par une texture factice |
| Demand | `tests/demand` | suite d'ASM test23 (demande des Process 3.0, rôles, 25 cibles) |
| Unlocks | `tests/unlocks` | suite d'ASM test22 (déverrouillages 2.2 / 3.0) |
| Translations | `tests/translations` | CSV ↔ traductions compilées (en, fr), paramètres `%s`/`%d` identiques entre langues |

Le ZIP se vérifie à part : `.\tools\Test-Package.ps1 -Archive <zip>` (structure, manifeste, incompatibilités, octets identiques à la source, références `res://` résolues).

Résultats : [docs/TEST_RESULTS.md](../docs/TEST_RESULTS.md).
