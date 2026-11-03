# Architecture

## Principes

- **Logique pure séparée du jeu.** L'allocation, le lissage, le modèle de ports, la détection de boucles et les diagnostics sont des scripts `RefCounted` sans dépendance au jeu, testés hors jeu (`tests/hub`).
- **Adaptateurs défensifs.** Tout accès à une API du jeu non publique passe par `"membre" in objet` ou `has_method()`. Une API absente désactive la fonction concernée et le signale, sans planter.
- **Rien d'inventé.** Chaque politique garantit des allocations positives dont la somme ne dépasse jamais l'offre réelle. Une offre infinie ou `NaN` est refusée (0 distribué).
- **Sauvegarde non réécrite.** BRM ne modifie aucun fichier de sauvegarde. Les anciens chemins de scène sont résolus en mémoire (alias).

## Structure

```
manifest.json, mod_main.gd        identité, enregistrement, alias, conflits
data/brm_data.json                fenêtres et guides enregistrés dans Data
scripts/core/                     PUR (aucune API du jeu)
  brm_allocator.gd                allocateur : Auto, Demand, Ratio, Priority
  brm_demand_tracker.gd           lissage de la demande (Auto)
  brm_port_layout.gd              modèle de ports, uid stables, validation de sauvegarde
  brm_cycle_guard.gd              parcours borné pour la détection de boucles
  brm_diagnostics.gd              statistiques -> codes d'alerte
scripts/global/                   code partagé avec les Smart Managers (issu d'ASM)
  smart_window_data.gd            détection des rôles et calcul de la demande d'une machine
  distribution_modes.gd           Ratio / Demand / Graph d'origine + distribution_auto
  window_graph.gd, smart_window_graph.gd   graphe pour le mode Graph
  manager_unlocks.gd              déverrouillages calqués sur les gestionnaires natifs
  legacy_scene_aliases.gd         alias des chemins kuuk / ASM
  brm_runtime_probe.gd            observation en lecture seule des API du jeu
scripts/hub/                      adaptateurs du hub
  brm_resource_channel.gd         une ressource : réserve -> ports -> machines
  brm_output_port.gd              port de sortie (neutralise le transfert natif)
  brm_hub_ui.gd, brm_action_button.gd   contrôles d'interface
scenes/windows/                   fenêtres (hub + deux Smart Managers)
scenes/ports/                     scènes des ports (conteneurs natifs instanciés)
translations/                     CSV source + .translation compilés (en, fr)
```

## Flux d'une ressource dans le hub

```
ports d'entrée ──Σ count──> réserve (CPU ou GPU)
                                │
                     allocateur (politique du mode, réglages par port)
                                │
               ┌────────────────┼────────────────┐
           port de sortie   port de sortie   port de sortie
               │ (Demand : max-min puis surplus ∝ demande)
           machines connectées (SmartWindowData.set_count)
```

- Le CPU et le GPU ont chacun leur `brm_resource_channel`. Une machine GPU branchée sur une sortie CPU n'est pas une cible GPU.
- **Topologie** (cibles, rôles, boucles) : recalculée seulement quand un port change (`update_connections`), qu'une connexion est créée ou supprimée, qu'une fenêtre est supprimée, ou toutes les 300 itérations par sécurité.
- **À chaque itération** : lecture de l'offre et des demandes. Les rôles et les `required` sont rafraîchis toutes les 5 itérations.
- **Cache** : si l'offre est *exactement* identique et qu'aucune demande ni réglage n'a varié de plus de 0,1 %, l'allocation précédente est réappliquée. L'égalité stricte sur l'offre interdit de réutiliser un résultat calculé pour une offre plus grande.
- Une machine branchée sur plusieurs sorties appartient à la première sortie **active** qui l'atteint. Seuls les câbles de cette sortie la servent ; ceux des autres sorties restent à 0, si bien qu'une sortie coupée ou plafonnée ne laisse rien passer par un second câble.

## Allocateur (`scripts/core/brm_allocator.gd`)

Une requête : `demand` finie, `uncapped` (accepte n'importe quelle quantité au-delà), `weight`, `priority`, `max`, `min`, `enabled`. Le cœur est un **remplissage pondéré max-min** en O(n log n) : chacun reçoit `budget × poids / poids total`, sauf s'il atteint son plafond, auquel cas le reste est repartagé. Le poids restant est calculé par sommes suffixes (une soustraction pouvait annuler un petit poids à côté d'un très grand et laisser une partie de l'offre inutilisée : défaut trouvé par le test aléatoire).

| Politique | Ordre |
|---|---|
| **Auto** | minimums (par priorité) → demandes finies, toutes priorités ensemble avec poids × 2^priorité → non bornés avec les restes → surplus rendu aux consommateurs finis ∝ poids × demande |
| **Demand** | demandes finies max-min sans poids (= Demand de test23) → non bornés à parts égales → surplus ∝ demande |
| **Ratio** | chaque demande × min(1, offre/demande totale) → restes aux non bornés. Sans non borné, le surplus reste inutilisé (comportement d'origine) |
| **Priority** | minimums → paliers stricts : un palier inférieur ne reçoit que ce qui reste (peut être affamé, c'est voulu) → non bornés par palier → surplus |

Les résultats ne dépendent que des entrées : requêtes triées par priorité puis clé, tris stables par clé à égalité.

**Hub : deux niveaux.** La réserve est d'abord répartie entre les **ports** (requête = somme des demandes de ses machines, réglages du port), puis chaque port répartit sa part entre ses machines en politique Demand. Les réglages s'appliquent donc à la sortie dans son ensemble. Mode Manuel : le port demande exactement son maximum (ou tout ce qui reste sans maximum). Le mode Graph du hub réutilise l'algorithme d'origine sur l'ensemble des machines ; seul l'interrupteur des ports s'y applique.

## Demande d'une machine (`smart_window_data.gd`)

Rôles hérités d'ASM test23 : `MANAGER` (fenêtre exposant `demand`), `CONSUMER` (Process 3.0 avec matière consommée, ou `get_goal()` historique), `STORAGE` (non borné : vendeurs, mineurs…), `ARTIFACT`.

- Demande historique (count/s) : `min(production / required) × goal / rate`.
- **Demande Auto** : `min((production + stock / H) / required) × goal / rate`, avec H = 10 s. Elle ajoute le travail nécessaire pour vider le stock en attente en H secondes. Elle n'est jamais inférieure à la demande historique.
- Une cible qui est un hub (`get_resource_demand`) est interrogée pour la ressource qu'elle reçoit, et non pour un total CPU + GPU.
- Lissage Auto (`brm_demand_tracker.gd`) : hausse rapide (60 % par itération), baisse lente (25 %), bande morte de 2 %, retour à 0 sous 2 % du dernier pic.

## Bug AI Trainer : analyse

Observé (3.0.12, Smart GPU Manager de **kuuk 3.1.1**, celui qui est actif dans le profil) : AI Trainer limité à ~268 EHz (~334 k neurones/s), alors que le branchement direct sur le GPU Manager natif lui donne ~2,95 ZHz (~736 k neurones/s).

Constats vérifiés dans le code et dans une **copie** de la sauvegarde (`UploadLabs-Backups/2026-11-02_21-12-09…`, état du contournement) :

1. Le GPU Manager natif partage à parts égales : l'entrée du Smart GPU Manager et l'entrée `Speed` de l'AI Trainer reçoivent chacune 2,946e21.
2. Le Smart GPU Manager distribue environ 73,6 EHz (Reinforcer) + 588 MHz (Text Generator) sur 2,95 ZHz reçus : **le reste n'est distribué à personne**.
3. Dans kuuk 3.1.x, Ratio, Demand et Graph n'envoient le surplus qu'aux cibles non bornées (`_set_storages`). Sans cible non bornée, il est perdu. ASM test23 a corrigé Demand seulement quand il n'y a aucune cible non bornée ; Ratio et Graph restent inchangés.
4. La demande count/s ne lit que le débit entrant (`production`). L'entrée `File` de l'AI Trainer contient **1,84e16** unités de texte en attente : la machine peut travailler bien plus vite que son débit entrant, ce que la demande ignore.
5. kuuk calcule le besoin avec `goal_obj.get_goal()` sans la conversion `/ speed.rate` qu'ASM test23 a ajoutée : selon la valeur de `rate`, l'estimation peut être fausse d'un facteur arbitraire.
6. Précision numérique : les valeurs (~1e21) restent très en deçà des limites des flottants 64 bits ; aucune perte significative n'a été trouvée.

Correction dans BRM : demande Auto avec stock en attente (4), et surplus rendu aux consommateurs finis (3). Le test `16 AI Trainer regression` reproduit la limitation avec les politiques d'origine et vérifie que le hub donne au moins 2,95 ZHz à l'AI Trainer. **Ce test ne mesure pas la production de neurones** : la formule interne du jeu n'est pas accessible. Le critère en jeu (≥ ~736 k neurones/s dans les mêmes conditions) reste à vérifier.

## Ports et sauvegarde

- Uid stable par port (`cpu_in_1`, `gpu_out_3`…), compteur par type qui ne décroît jamais, sauvegardé avec la disposition.
- Chemin du conteneur : `PanelContainer/MainContainer/<Cpu|Gpu>/<Inputs|Outputs>/<uid>/Port`. Le jeu enregistre `container_data` sous ce chemin : **ne jamais renommer ces nœuds sans migration**.
- Upload Labs applique les champs sauvegardés avant `_ready` (« set on load », confirmé par le code de kuuk). Le setter de `brm_layout` construit donc les ports immédiatement. Les clés étant triées à la relecture, `brm_layout` (b) précède `container_data` (c).
- Copie de secours par port : `brm_port_state` (`id`, `outputs_id`), réappliquée à la création du port. `export()` (copier/coller) ne la contient pas, pour qu'une copie obtienne de nouveaux identifiants.
- Garde-fou contre une sauvegarde corrompue : 256 ports par type au maximum. Ce n'est pas une limite de jeu ; l'interface suggère l'affichage compact dès 64 ports.

## Hub en aval d'un gestionnaire

Un hub déclare à l'amont, par ressource, sa demande finie (`get_resource_demand`) et s'il alimente des cibles non bornées (`get_resource_uncapped`). Un Smart Manager en Ratio/Demande/Graphe traite un hub sans demande finie mais avec des cibles non bornées comme une cible non bornée (il reçoit les restes). En Auto et dans un autre hub, la requête porte les deux informations. Sans aucune machine branchée sur ses sorties, un hub reçoit 0 d'un Smart Manager : c'est voulu.

## Une entrée, un câble

Une entrée native n'accepte qu'une connexion. Quand la dernière entrée libre d'une ressource est branchée, le hub en ajoute une automatiquement.

## Ports de réserve

Constat en jeu (alpha.3) : un port créé après la mise en place de la fenêtre est connectable et inscrit sur le bureau, mais ne reçoit rien du jeu avant un rechargement ; les ports qui existent dès la création fonctionnent. La cause exacte n'est pas encore identifiée (diagnostic comparatif dans le journal, préfixe `Input diff`).

Chaque hub crée donc avec la fenêtre `SPARE_INPUTS` = 8 entrées et `SPARE_OUTPUTS` = 4 sorties masquées par ressource (`spare: true` dans `brm_layout`). Ajouter un port révèle une réserve ; retirer un port créé avec la fenêtre le remet en réserve. Les réserves sont complétées avant `_ready` à chaque chargement. Un port créé en direct faute de réserve est marqué « après rechargement ». Les réserves ne sont transmises ni aux canaux ni à l'affichage.

## Ports ajoutés en cours de partie

Un port créé après `_ready` n'existait pas quand la fenêtre a collecté ses conteneurs. Le hub l'ajoute à `containers`, lui attribue un identifiant s'il n'en a pas, et l'inscrit dans `Globals.desktop.resources` s'il n'y est pas. Puis il vérifie l'inscription et affiche « port non reconnu » en cas d'échec, plutôt que de montrer un port qui ne serait pas connectable. **Ce chemin dépend d'API non publiques et doit être validé en jeu** (voir la sonde).

## Sonde d'exécution

Au premier hub de la session, `brm_runtime_probe.gd` écrit une seule fois, préfixé `[Probe]`, quels membres attendus existent réellement sur la fenêtre, les ports, le bureau et `Signals`. Rien n'est appelé ni modifié. C'est la source de vérité pour confirmer les hypothèses ci-dessous.

## Hypothèses sur l'API du jeu

Tirées du code public d'ASM, de kuuk, de BetterSplitters, de Where Should I Connect et du code source public de Mod Loader 7.0.1 ; aucun fichier du jeu n'a été décompilé.

| Hypothèse | Source | Statut |
|---|---|---|
| `filename` d'une fenêtre est relatif à `res://scenes/windows/` | sauvegarde, kuuk, BetterSplitters | confirmé (sauvegarde) |
| Champs sauvegardés appliqués avant `_ready` | commentaire et code de kuuk | probable |
| `container_data` indexé par chemin de nœud | sauvegarde | confirmé (sauvegarde) |
| `ResourceContainer.transfer`, `looping`, `input`, `outputs_id`, `input_id`, `update_connections()`, `tick()` | ASM, Where Should I Connect | confirmé par la sonde en jeu |
| `load()` renvoie l'entrée du cache même si un fichier existe au même chemin | moteur Godot 4.7.2, test de chargement, essai en jeu | confirmé (les 7 gestionnaires kuuk se chargent en BRM) |
| Mod Loader monte les ZIP désactivés | source ML 7.0.1 | confirmé (source) |
| Mod Loader n'applique pas `incompatibilities` | source ML 7.0.1 | confirmé (source) |
| Un port créé en cours de partie devient connectable | essai en jeu alpha.1 | confirmé (le jeu l'inscrit lui-même) |
| La racine d'une fenêtre est un `VBoxContainer` | sonde, alpha.1 | confirmé |
| Les conteneurs sont collectés avant le corps du `_ready` de la sous-classe | sonde, alpha.1 | confirmé : un nouveau hub crée ses ports dans `_enter_tree` |
| `DesktopButton` initialise son dessin dans `_ready` | erreurs `canvas_item` | probable ; ne jamais remplacer son `_ready` (réglages via `NOTIFICATION_READY`) |

## Limites confirmées

- Les réglages priorité/poids/min ne s'appliquent pas en mode Graph.
- Les machines non bornées (vendeurs, mineurs) reçoivent les restes avant que le surplus revienne aux consommateurs finis, comme à l'origine.
- La demande Auto est une estimation : une machine dont la conversion interne n'est pas lisible retombe sur son rôle (`STORAGE` si aucune matière consommée n'est détectée).
- Performance mesurée hors jeu (Godot 4.7.2 éditeur) : ~2 ms par itération pour 100 consommateurs en régime stable, ~4 ms en recalcul complet.

## Décisions techniques

| Date | Décision | Raison |
|---|---|---|
| 2026-11-02 | Alias de chemins en cache plutôt que migration de sauvegarde | aucune écriture de sauvegarde, retour arrière immédiat |
| 2026-11-02 | Gestionnaires : `filename` = chemin d'origine (`scene_file_path`) | une sauvegarde reste lisible par kuuk |
| 2026-11-02 | Auto des gestionnaires dans `brm_auto_mode`, `container_mode` inchangé | kuuk lit toujours un mode valide |
| 2026-11-02 | Ports dynamiques construits depuis la disposition sauvegardée | pas de limite fixe dans la scène ; restauration native par chemin |
| 2026-11-02 | Suppression d'un port seulement s'il est déconnecté | aucune API de suppression de connexion nécessaire |
| 2026-11-02 | Enregistrement des gestionnaires refusé si un mod concurrent est actif | ML 7.0.1 n'applique pas les incompatibilités |
| 2026-11-02 | Workflow de publication automatique d'ASM retiré | aucune publication sans validation explicite |
