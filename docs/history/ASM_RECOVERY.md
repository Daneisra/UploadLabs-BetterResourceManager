# Original test20 source recovery

Recovered September 11, 2026 on branch `recovery/test20-installed`, based on `327181e6b57fea5267c4d36662069340cd0d110e`. This source recovery does not publish a new release or replace the existing test20 artifact.

The original user-tested archive is `guardipee14-AdaptiveSmartManager-v0.1.0-test20.zip`, 31,556 bytes, SHA-256 `b3b8aad369e28ce19874dee6bceec0e07d84de9c3914ac05ed708f7fe66c7dfc`.

The [existing GitHub release](https://github.com/guardipee14/Adaptive-Smart-Manager/releases/tag/v0.1.0-test20) instead serves a 26,581-byte ZIP with SHA-256 `5465c63b1c3609899191ea720af53d900f194ba1b2fac372e43ffa6863175ee8` (checked September 12). Its notes contain a third, inconsistent checksum. Neither the filename nor the manifest version identifies the original tested build unambiguously.

## Restored gameplay files

- `data/asm_data.json`
- `scenes/windows/window_adaptive_smart_manager.gd`
- `scripts/global/distribution_modes.gd`
- `scripts/global/smart_window_data.gd`
- `scripts/global/window_graph.gd`
- `scripts/smart_resource_container.gd`

All gameplay GDScript, scenes and JSON now match the original archive apart from whitespace normalization. Repository documentation and the manifest's valid website URL were retained. The original archive also includes `translations/AdaptiveSmartManager.en.translation`; its complete extraction is preserved separately under `C:\Dev\UploadLabsRecovery\ASM-test20`. That compiled translation was not restored into this source checkout. The current packaging script copies translations as-is; it does not regenerate that binary. This checkout is therefore recovered gameplay source, not a claim of a byte-identical or newly runtime-tested rebuilt package.

## Integration evidence and next release

The original installed package passed the three targeted AAC v0.1.15-test7 integration checks on September 11: Thread scoring, Analyzer Accept/Undo and finite GPU scoring in Demand mode (Thread count/s, GPU count). See the sibling AAC repository's `tests/RUNTIME_TEST7.md` for evidence and coverage limits. These checks do not revalidate every ASM mode, allocation path or rebuilt package.

Preserve the original archive and existing public tag. The recovery branch is for source review; use a distinct new build label for any reconstructed ASM candidate, reconcile translation/package contents and validate that artifact before making a public pairing claim. Do not overwrite test20 or change `.github/release-request.json` merely to save the recovery.

## Test21 reconstruction

The original compiled translation was recovered and tested against its CSV in Godot 4.6.1. Fourteen messages matched; the original compiled `window_sgm_desc` was stale ("clock-consumers" rather than the CSV's "GPU-speed consumers"). Test21 therefore regenerates the compiled translation from the unchanged CSV and verifies all 15 message values; it does not claim a byte-identical test20 binary. The original remains preserved separately with SHA-256 `88075c94157ee690b2be39d33c152517724db911742e45e8a7a4289661ef72e3`; the rebuilt translation is `997f9b755bdfade7e23a8d47ee45520f2cd1ac4fe0a3e3adad49898a13a17b61`.

The current candidate includes that compiled file, explicit test21 startup/manifest identity and README packaging. No allocation logic, scene behavior, resource contract or CSV text is changed from the recovered original. `tools/Test-Package.ps1` enforces the permitted difference set against the original archive. See `tests/README.md` for build and verification commands. A fresh test21 load/UI/AAC smoke test remains pending; this reconstruction does not publish a release or replace test20.
