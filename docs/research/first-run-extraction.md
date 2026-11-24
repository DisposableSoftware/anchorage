# First-run extraction: gamepad and unattended options (source-only research)

Sources were cloned at the release tags into `.../scratchpad/extract-research/` (soh, 2s2h, starship, kart; `lus-<sha>` worktrees for the pinned libultraship commits; `torch-<sha>`; `sdl2` = release-2.30.3). Nothing was built or run.

Pins: SoH 9.3.1 -> LUS da6daf1 (2026-10-12), Torch 2ab12fe. 2Ship 5.0.1 -> LUS 7cb1022 (2026-08-03). Starship v2.0.0 -> LUS 45c4f8d (2025-05-21), Torch f75facb. SpaghettiKart 1.0.0 -> LUS f40cfd3 (2026-02-04), Torch 2d474dd.

## 1. Do the prompts take a gamepad?

| Port | Prompt mechanism | Gamepad? |
|---|---|---|
| SoH, 2Ship | ImGui popups (`SohGui::RegisterPopup`, `BenGui::RegisterPopup`; soh `soh/soh/OTRGlobals.cpp:655` "No O2R Files ... Generate one now?", 2s2h `mm/2s2h/BenPort.cpp:487`) | Only if CVar `gControlNav` is 1. Default is 0 on Linux. |
| SpaghettiKart | "No O2R files found. Generate one now?" is `GameEngine::ShowYesNoBox` (`src/engine/mods/ModManager.cpp:55`, `src/port/Engine.cpp:319-343`) = `SDL_ShowMessageBox`, not ImGui | No. |
| Starship | `ShowYesNoBox` (`src/port/Engine.cpp:91`, 571-594) = `SDL_ShowMessageBox`; ROM picker is pfd (`src/port/extractor/GameExtractor.cpp:27`) | No. |

Evidence for SoH/2Ship:
- LUS `src/ship/window/gui/Gui.cpp:176-182` (`UpdateGamepadNavigation`, called every frame from `DrawMenu`, line 189) sets `ImGuiConfigFlags_NavEnableGamepad` only when `CVAR_IMGUI_CONTROLLER_NAV` is non-zero and a menu or any popup is open. Same code in 7cb1022. The comment names "boot prompts" as the case.
- `CVAR_IMGUI_CONTROLLER_NAV` is `gSettings.ControlNav` in SoH (`CMake/lus-cvars.cmake:7`) and `gControlNav` in the LUS default (`cmake/cvars.cmake:7`). Read with default 0. It is forced to 1 only under `__SWITCH__`/`__WIIU__` (`soh/Enhancements/bootcommands.c:13`, Starship `Engine.cpp:304`, Kart `Engine.cpp:352`). On Linux the user turns it on in the menu ("Menu Controller Navigation", `SohMenuSettings.cpp:143`), which needs a mouse or keyboard to open.
- So a fresh install on a Deck: A on "Yes" does nothing in SoH/2Ship unless the config already has the CVar. Pre-seeding is possible: CVars load from the `"CVars"` object of the JSON config (`ConsoleVariable.cpp:286`), so `{"CVars":{"gSettings":{"ControlNav":1}}}` in `shipofharkinian.json` / `2ship2harkinian.json` should enable it. UNVERIFIED: that nested form is what the port writes, and that it works before the first frame. Side effect: it blocks game input while a menu is open.
- Starship/Kart pins have no popup-aware nav (45c4f8d `Gui.cpp:145`, f40cfd3 `Gui.cpp:136`: menu-only), and their prompts are SDL boxes anyway.

SDL message box on Linux (both use SDL 2.30.3, built in CI: Kart `.github/workflows/main.yml:201`, Starship `main.yml:134`):
- In 2.30.3 the bootstrap order tries X11 first (`src/video/SDL_video.c` bootstrap list, X11 before Wayland). The X11 box is drawn by SDL, takes mouse and keyboard only, no gamepad. It needs `DISPLAY`. Under gamescope (XWayland) it should appear, but a Deck user with the default gamepad layout cannot click it.
- The Wayland fallback (`src/video/wayland/SDL_waylandmessagebox.c:40-55`, 124) shells out to `zenity` only. This matches the zenity dialog seen in headless sway (Wayland only, no `DISPLAY`). No kdialog path for message boxes. If zenity is missing there, the call fails and the port treats the result as not Yes (`ret` is uninitialised on failure; the Yes check then likely fails and the port exits). UNVERIFIED at runtime.
- pfd (file picker, Starship always; Kart only when no valid ROM is auto-found) uses zenity or kdialog. `pfd::settings::available()` is checked in Kart (`GameExtractor.cpp:77`, returns false -> "No ROM selected" -> exit(1)). Starship has no such check. SteamOS base image: zenity absent, kdialog present only in desktop mode (as stated by the coordinator; not verified by me).

Fallback for any prompt: Steam Input layout with mouse emulation (trackpad click, or keyboard Enter/Esc: the SDL box binds Return=Yes, Esc=No). A Deck user can do this, but it is manual.

## 2. Flags, env vars, config keys that skip or automate

No port has an unattended-extract flag, env var, or config key. Greps for `--extract`, `no-gui`, `ShouldExtract`, `getenv` in the four trees found only `SHIP_HOME`/`APPIMAGE`/`XDG_DATA_HOME`/`HOME`/`TEMP` handling (soh `OTRGlobals.cpp:1520-1532`). The only automation path is ROM paths on argv (SoH, 2Ship).

SoH 9.3.1 and 2Ship 5.0.1, launching with `<rom>` as argv (the file must be a ROM, not zip):
- `soh/soh/OTRGlobals.cpp:498`: `extractStep = args.empty() ? ES_EXTRACT : ES_EXTRACT_ARGS` (2s2h `BenPort.cpp:352`). `ES_EXTRACT_ARGS` (line 595-640) runs `RunFileStandalone` then `CallTorch` on a thread with a progress popup. No Yes/No before it. Exception: if the archive already exists, "Confirm Re-extract" appears.
- After the extraction, args is empty and the "Run Ship of Harkinian: All files have been processed. Run SoH?" Yes/No popup shows (line 596; No = `exit(0)`). One prompt remains, after the work is done.
- Placing the ROM in the data dir with no argv (what `PORT-9` does now) gives two prompts: "Generate one now?" (line 655) then "ROMs found in application directory. Would you like to process them?" (line 673), then "Extract another?" (PS_SECOND, line ~700), all ImGui. Passing the ROM as argv is strictly fewer prompts.
- Idea (UNVERIFIED, not run): launch once with the ROM as argv, poll for `oot.o2r`/`oot-mq.o2r`/`mm.o2r` in the data dir, wait for size to settle, end that process, relaunch without args. This avoids every prompt. Risk: killing mid-write corrupts the archive; the settle check reduces but does not remove that. Torch writes the archive in the extraction thread; I did not check if it writes to a temp name first.

SpaghettiKart 1.0.0: `GameExtractor::SelectGameFromUI` (`src/port/GameExtractor.cpp:33-99`) scans cwd (`GetRoms`, line 121) for `*.z64`, hashes each, takes the first match (US SHA1 `579c48e2...`). The picker (zenity/kdialog) is reached only when none matches. So with the ROM in cwd the picker is avoided. The "Generate one now?" SDL box is not avoidable (`ModManager.cpp:55`, `GenerateAssetsMods`). Then "Found Mario Kart 64 (US) ... extraction will now begin" is another `SDL_ShowSimpleMessageBox` (`Engine.cpp:283`). So two SDL boxes, no gamepad.

Starship v2.0.0: always the "Please provide a Starfox 64 ROM" Yes/No SDL box (`Engine.cpp:91`), then a pfd picker (`GameExtractor.cpp:27`; `"."` start dir, no scan, no path argument), then an info box, then "Extract another?" box (line 99). Four dialogs, two modal types. The only non-desktop code path (`GetPathRelativeToAppDirectory("baserom.us.rev1.z64")`, line 35) is `#else` for iOS/Android/Switch, not Linux.

## 3. Can Anchorage run Torch itself?

- Torch has a standalone CLI: `torch o2r <baserom.z64>` (`src/main.cpp:38-46` at f75facb; `USE_STANDALONE` default ON, `CMakeLists.txt:9`). It reads `config.yml` and the `assets/` yaml tree from the cwd (`Companion.cpp:958-964`) and writes the output named in config.yml (relative to cwd; Starship's gives `sf64.o2r`). Exits 0 with no GUI.
- Not shipped as a usable release: the only GitHub release is `v1.0.0` (2024-04-08) with a 16 MB Linux `torch` plus CMake build junk (build.ninja, CMakeCache.txt). Too old for current configs. The ports' releases do not contain a torch binary (Torch is linked in as a library). Anchorage would have to build Torch itself per port pin (different Torch commits per port: SoH 2ab12fe, Kart 2d474dd, Starship f75facb) and host the binaries. 2Ship uses OTRExporter/ZAPDTR, not Torch, so no CLI exists for it in the same form.
- SoH calls Torch via `Extractor::CallTorch` (needs `installPath/assets`, inside the AppImage), so reusing the port's own AppImage binary to run Torch is not exposed by any flag.
- Estimate: a static torch is roughly 16 MB (the old binary); I did not build one. Building it for 3 pins and keeping it maintained is real work. Not recommended for the MVP.

## Recommendation for the MVP

1. SoH and 2Ship: pass the ROM as argv (instead of, or besides, placing it in the data dir). This removes "Generate now?" and "Process them?". The one remaining prompt ("Run SoH?") comes after extraction. Anchorage can either (a) tell the user to press nothing and relaunch from the card once the archive exists, or (b) watch the archive appear and end and relaunch the process (verify on a Deck first).
2. Optionally pre-seed the ControlNav CVar in the port's config JSON so ImGui popups answer to A (verify on a Deck).
3. SpaghettiKart and Starship: SDL message boxes cannot take a gamepad. A controller-only user has no path without a Steam Input layout that emits mouse clicks or Enter. For Kart the ROM in cwd avoids the picker; for Starship nothing avoids it. Starship and Kart should be marked "needs a one-time desktop-mode (or mouse/keyboard) setup" in the MVP.
4. Card text in the meantime, for all four: "First launch makes the game files from your ROM. This needs a keyboard or mouse once. In Game Mode, switch the controller layout to 'Keyboard + Mouse' (or use the trackpad as a mouse) and click Yes. Later launches need nothing." For SoH/2Ship once argv launch is in place: "First launch creates the game files, then press Play again."
5. Alternative worth a spec line: offer a "Prepare in Desktop Mode" action that launches the port with the ROM so extraction can be done once with a mouse; later game-mode launches skip it. Needs zenity or kdialog in desktop mode for Starship/Kart pickers (kdialog is there per the coordinator).

## Could not verify

- Nothing was built or run; all behaviour is from source at the tags above.
- Whether `{"CVars":{"gSettings":{"ControlNav":1}}}` is the exact JSON form and takes effect at boot.
- Whether the X11 SDL box opens under gamescope (XWayland present) and what it does with no zenity and no `DISPLAY`; uninitialised-`ret` behaviour on failure.
- That the Deck's default Steam Input layout for a non-Steam game sends gamepad only (assumed).
- Whether killing SoH/2Ship after the archive appears is safe (temp-file behaviour of Torch's O2R writer not checked).
- Which SDL the AppImages actually bundle (CI builds 2.30.3 and copies to `/lib`; the AppImage may bundle it or use the system one).
- Starship HEAD (past v2.0.0) and SoH/2Ship HEAD may differ; only the release tags were checked (LUS pins and port sources).
