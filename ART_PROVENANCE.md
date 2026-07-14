# Art asset provenance

Last updated: 2026-07-15

These five production prey sprites were generated with Codex's built-in image-generation workflow, reviewed in chat, and approved by the project owner before replacement. No third-party image was supplied as a reference or composited into this batch.

## Approved source batch

Creation-workstation batch directory:

`%USERPROFILE%/.codex/generated_images/019f6193-5e2f-74a2-a5bd-2dc2fa54d55f`

| Runtime asset | Generated source | Source SHA-256 | Final SHA-256 |
| --- | --- | --- | --- |
| `Art/Prey/prey_photon_mote.png` | `exec-09dca9c8-9a11-4ae7-9581-0cad116f21fe.png` | `837072CAAC8363FAB48ADAF3E9D5588DB4CCFE61F83363883388BE0477F7F821` | `545878A2B7F76CD2C93C6719B263403C291A74570FF16B3DDC0CCA01E6AC0711` |
| `Art/Prey/prey_plasma_seed.png` | `exec-b5dcd067-810d-4173-bc0f-98b5a2fa9b81.png` | `F92DC0643E575C5578061FCD2A3175C19CD5AB63616CD1157B1954289C5468E1` | `1732AAB155BEB9F42140F6FFD849A1A41B9E213F41ABCDBCEDC46F17F720F688` |
| `Art/Prey/prey_nebula_prism.png` | `exec-298070d2-4d21-4aeb-9c1d-cd7855130951.png` | `874F398F6C7033186B01344145571072722A46D0C6FAAA264EFC617D8EFACF9B` | `F53EB12D0435581BB980C1DD69BE46E1D8355475AA5B46A235A910F48E2C3E43` |
| `Art/Prey/prey_pulsar_core.png` | `exec-eedbca6e-2e88-4f53-bbc0-a395f3b6282e.png` | `8625885608F26DD7DEC25E90FED220D04BF4D7742C34FB973CEB2122B0AD0A94` | `9ADE3709A5B3EAF4CD756F233FC3B9C1AF42F8FDD70DD22EA37F78E57EEE9811` |
| `Art/Prey/prey_quantum_relic.png` | `exec-884899d7-80e6-424b-9408-fb866b439d1d.png` | `E22B67D0DECC4A2DA075BE612FC7885877194755872CE56E7ADDDBAD58B43D16` | `206BE3A2DE04CB943FB8291237C9ADCB50233E6A85F7912A8E7A4F6CD8304190` |

## Prompt-intent record

Five compact cosmic energy artifacts—photon mote, plasma seed, nebula prism, pulsar core, and quantum relic—with distinct silhouettes, restrained cyan/gold/coral/violet accents, polished pseudo-3D materials, and strong readability during fast mobile play. Each transparent source used a uniform chroma-key backdrop with no scene, floor, shadow, text, logo, or watermark.

## Deterministic processing

`tools/process_prey_art.py` uses the installed imagegen chroma-key helper with a soft matte and despill, then normalizes every subject to a centered 256 x 256 transparent RGBA canvas with a maximum 208 x 208 visible footprint. Validation checks dimensions, transparent corners, centered alpha bounds, and residual green fringe pixels.

Rebuild after installing Pillow:

```powershell
python tools/process_prey_art.py --source-dir "$env:USERPROFILE/.codex/generated_images/019f6193-5e2f-74a2-a5bd-2dc2fa54d55f"
```

Validate the committed runtime assets without the generated source batch:

```powershell
python tools/process_prey_art.py --validate-only
```
