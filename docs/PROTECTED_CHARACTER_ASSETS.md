# Protected character assets

Character outfits are encrypted before packaging. The APK contains only
`.aarpack` and `.aarpreview` ciphertext files. Raw Spine and preview files are
kept locally and are excluded from Git.

## Local source layout

For every outfit named `<assetName>`, provide:

```text
assets/character/ryza/<assetName>/<assetName>.atlas
assets/character/ryza/<assetName>/<assetName>.png
assets/character/ryza/<assetName>/<assetName>.skel
assets/character/ryza/<assetName>/<assetName>_gesture.json
assets/images/skins/<assetName>.png  # optional independent preview
```

If the preview is missing or is byte-identical to the Spine atlas texture, the
packer skips it. Mark that appearance with `hasPreview: false`; the picker then
shows an empty preview area instead of exposing the atlas sheet.

## Build

Do not use `flutter build` directly. The wrapper generates or reuses the local
key, refreshes every encrypted pack, injects the key at compile time, and then
builds Flutter:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\build_protected.ps1 -Target apk -Mode debug
powershell -ExecutionPolicy Bypass -File .\tool\build_protected.ps1 -Target apk -Mode debug -Install
powershell -ExecutionPolicy Bypass -File .\tool\build_protected.ps1 -Target appbundle -Mode release
powershell -ExecutionPolicy Bypass -File .\tool\build_protected.ps1 -Target windows -Mode release
```

For development on an emulator:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\run_protected.ps1 -Device emulator-5554
```

The key is stored at `.asset_protection/character_assets.key`. Back it up
privately if installed builds must continue using the same encrypted packs.
Never commit the key, raw resources, generated packs, APKs, or symbol files.

This protection prevents direct APK extraction of usable character files. It
does not claim to prevent runtime memory inspection or a determined reverse
engineer.
