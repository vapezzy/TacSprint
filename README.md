# Tac Sprint

A fast tactical shooter made in Godot 4.7, by **luvx46**. Modes: training range,
team deathmatch against bots and Search & Destroy (up to 6 vs 6).

## Play on PC
Open the folder in Godot 4.7.2 and press Play, or run `spielen.bat`.

## iPhone / iPad (TrollStore)
Every push to `main` builds an unsigned `TacSprint.ipa` on GitHub Actions
(`.github/workflows/ios.yml`). Open the run under **Actions** and download
**TacSprint-ipa** from Artifacts, unzip it, and install the `.ipa` with TrollStore.
Push a tag such as `v1.0` and the build is attached to a release as well.

On touch screens: left thumb moves (push all the way forward to sprint), drag on
the right to look, and use the buttons for fire, aim, jump, crouch, reload, swap,
grenades and interact. The `II` button at the top pauses.

Textures: see `textures/CREDITS.txt`. Font: Rajdhani (SIL OFL, `fonts/OFL.txt`).

## License
MIT. See `LICENSE`.
