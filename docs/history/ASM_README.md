# Adaptive Smart Manager

Adaptive Smart Manager (ASM) is a unified replacement for **Smart Thread Manager** and **Smart GPU Manager** for Upload Labs.

It keeps the familiar player-facing manager workflow while sharing one implementation underneath, fixing allocation/runtime issues found during testing, and exposing a read-only compatibility surface for Adaptive Auto Connector (AAC).

> **Current source build:** `v0.1.0-test23` — Upload Labs 3.0 compatibility prerelease candidate. See [GitHub Releases](https://github.com/guardipee14/Adaptive-Smart-Manager/releases) for downloadable packages.

**Reconstructed candidate:** `v0.1.0-test21` (not released; fresh in-game validation pending). It preserves the original test20 manager logic, restores a compiled English translation generated from the CSV, and corrects the stale GPU description in the original binary. GitHub's test20 download differs from the original tested archive; see [recovery provenance](RECOVERY.md).

**Local compatibility hotfix:** `v0.1.0-test22` follows the installed game's ordinary Thread/GPU Manager unlock requirements for both smart nodes and their guides. In Upload Labs 3.0, Thread Manager uses `research.thread_manager`, not the former `perk.thread_manager`. Older games retain their original perk requirement. This does not grant research, alter saves, replace existing nodes, or change resource allocation. Full 3.0 gameplay compatibility is not implied by this focused fix.

**Local demand hotfix:** `v0.1.0-test23` additionally reads 3.0's `Process` component for finite processing demand instead of classifying every modern machine as uncapped. It uses consumed input quantities and the current goal/speed conversion, refreshes changing requirements, and preserves legacy `get_goal()` support. Truly uncapped sellers/miners remain uncapped. Ratio/Demand/Graph allocation policies, manager ids, saved modes and Base settings are unchanged; no save migration or node replacement is required.

Test23 includes both hotfixes and the test21 translation recovery. Earlier public test20 artifacts are preserved; see [recovery provenance](RECOVERY.md) before comparing their checksums or gameplay.

## What it keeps

- Smart Thread Manager window id: `smart_thread_manager`
- Smart GPU Manager window id: `smart_gpu_manager`
- CPU resource: `clock_speed`
- GPU resource: `gpu_speed`
- Ratio, Demand, and Graph modes
- Manager chaining
- Base `count` / `count/s` toggle
- Existing CPU/GPU unlock requirements and categories
- Existing save-facing manager ids so saved manager windows can migrate

## What ASM improves

- One shared Thread/GPU manager implementation instead of duplicated code.
- Demand-mode shortage handling no longer creates a GHz → MHz → kHz → Hz starvation ladder across later consumers.
- Demand mode can redistribute surplus supply after calculated finite demand is satisfied, so available CPU/GPU does not sit unused when finite targets can accept more.
- Compact Need/Supply presentation using a common promoted Upload Labs unit.
- Thread and GPU managers use the same compact visual language.
- Uncapped GPU targets remain visible in Demand mode without hiding the actual Supply value.
- Graph filters and signal subscriptions are cleaned up when topology/mode ownership changes.
- Defensive handling for transient topology and zero-value states.
- Registration/version handling and compatibility metadata are more robust.
- Read-only `window_binds` / `get_aac_manager_snapshot()` compatibility surface for AAC.

## Current validation

- Upload Labs `3.0.9` live startup: test23 resource preflight and both manager registrations passed; the CPU manager correctly identified 24 finite consumers and one genuinely uncapped target, rather than 25 uncapped targets. GPU speed-only consumers remained uncapped.
- CPU/GPU Demand and saved Base settings loaded unchanged. The startup allocation sample conserved available CPU/GPU supply without over-allocation.
- Isolated demand regression suite: 138 checks passed on Godot `4.7.2` and `4.6.1`. The same suite reproduces 43 behavioral failures against pre-fix test22.
- Isolated unlock suite: 158 checks passed. English translation: all 15 messages verified. Package verification checks every runtime file against source.
- Coverage is focused unlock/demand compatibility, not exhaustive 3.0 gameplay or a new full AAC integration certification. See [verification instructions](tests/README.md).

### Historical test20 evidence

`v0.1.0-test20` has been runtime-tested with:

- Upload Labs `2.2.12`
- Mod Loader `7.0.1`
- Godot `4.6.1`
- 59 finite Smart Thread Manager consumers
- Smart GPU Manager finite + uncapped consumers
- Ratio / Demand / Graph mode switching
- Base `count` / `count/s` switching
- large topology changes while AAC graph validation remained structurally clean

The original test20 package also passed AAC test7's targeted integration checks on September 11, 2026. Those results do not establish that the different GitHub test20 download or reconstructed test21 package has passed a fresh game run. See [test21 verification and build instructions](tests/README.md).

## Installation

1. Remove/disable the original `kuuk-SmartThreadManager` and `kuuk-SmartGPUManager` mods. ASM registers the same window ids and must not run alongside them.
2. Save and close Upload Labs, and back up your save and existing ASM ZIP before replacing it.
3. Use `guardipee14-AdaptiveSmartManager-v0.1.0-test23.zip` from its matching [GitHub prerelease](https://github.com/guardipee14/Adaptive-Smart-Manager/releases), or build it from a clean source checkout with `tools/New-Release.ps1 -ReleaseLabel 0.1.0-test23`. Verify the downloaded ZIP against its accompanying `.sha256` file; rebuilt ZIP hashes can differ because of timestamps/line endings.
4. Move the previous ASM ZIP outside the game's `mods` folder, then place the new ZIP there without extracting it. Do not leave two ASM versions installed together.
5. Start Upload Labs and verify both managers in your existing save. Test23 does not require replacing placed nodes, changing connections or switching Mode/Base choices. A genuine uncapped Processing Seller can still appear as `∞ ×1`; ordinary processing machines should contribute finite demand.

Public-test notes and feedback thread: [Issue #1](https://github.com/guardipee14/Adaptive-Smart-Manager/issues/1).

For the default Steam location used during development, the mod folder was:

```text
E:\SteamLibrary\steamapps\common\Upload Labs\mods
```

Your Steam library path may be different.

## Adaptive Auto Connector compatibility

ASM preserves the manager ids/resources AAC expects and exposes a read-only manager snapshot. AAC does **not** receive ownership of manager distribution or automatic connection mutation through this interface.

AAC `v0.1.15-test7` explicitly detects ASM. Its three targeted game checks passed with the original test20 archive in Demand mode (Thread count/s, GPU count). Test23 keeps the same read-only interface and was observed starting alongside AAC with corrected live demand, but those historical Accept/Undo and scoring checks were not repeated for test23.

## Attribution

Adaptive Smart Manager combines and modifies the Smart Thread Manager / Smart GPU Manager work originally published by **kuuk / Omisse** in [`Omisse/ul-stmmod`](https://github.com/Omisse/ul-stmmod).

The original project is MIT licensed. See [`LICENSE`](LICENSE) and [`NOTICE.md`](NOTICE.md).

## Status

ASM is currently a **release-candidate test build**, not the final `v0.1.0` release. Bug reports should include the Godot log and, when relevant, a screenshot showing the affected manager and connected nodes.
