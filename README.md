# SLING LEGACY — A Real Football Career (v1.0)

لعبة كرة قدم 6 ضد 6 ثلاثية الأبعاد للأندرويد، بمسيرة مهنية دون اتصال، وواجهة عربية RTL.

**Development:** Maelainin Assari — **Stadium:** الملعب الكبير — دوار اللوح

> لا تلهك الألعاب عن الصلاة وذكر الله.

---

## 1. Requirements / المتطلبات

- **Godot 4.2.x** with the **Compatibility** renderer (GLES3) — chosen for old hardware and medium Android phones.
- Honest note: the Godot 4 editor officially requires **Windows 10+**, so it will most likely **not run on a Windows 7 laptop** (not verified — it is an official requirement). The APK is built in the cloud via GitHub Actions, so a local editor is optional.
- For local export: Android SDK + JDK 17. For cloud builds: nothing but a GitHub account.

## 2. Run the project / التشغيل

1. Open the project in Godot 4.2.2 (`Project > Import`, select the project folder).
2. Press F5. Keyboard debug controls: `WASD` move, `J` pass, `K` shoot (hold to charge), `U` tackle/dribble, `Space` switch player, `L` sprint, `Esc` pause.

## 3. Build the APK with GitHub Actions (recommended) / بناء APK

1. Create a new GitHub repository and upload the project files (`project.godot` must stay at the repository root).
2. Open **Actions > "Android Debug APK" > Run workflow**.
3. When it finishes, download the APK from **Artifacts**, copy it to your phone and install it (allow unknown sources).
4. For a signed release later: create a keystore with `keytool`, store it in GitHub Secrets (`ANDROID_KEYSTORE_BASE64`, `KEY_ALIAS`, `KEYSTORE_PASSWORD`, `KEY_PASSWORD`) and use `--export-release`.

The workflow downloads the official Godot 4.2.2 Linux editor + export templates, installs the Android SDK, creates a debug keystore, imports assets, exports `build/SLING-LEGACY-v1.0-debug.apk` and uploads it as an artifact. No secrets are needed for debug builds.

## 4. Testing / الاختبار

```
godot --headless -s tests/smoke_test.gd
```

Manual checklist: player movement & auto/manual switching, passing/shooting/goals, goalkeeper saves, pause/resume, career & settings save/load, reminder before play, Android export, performance on the phone (low/medium graphics).

## 5. Project layout / بنية المشروع

```
SLING-LEGACY/
  project.godot            Godot 4.2 config (Compatibility, landscape 1280x720)
  icon.png                 original app icon (SL monogram + ball + crown)
  export_presets.cfg       Android debug preset (com.maelainin.slinglegacy)
  scenes/Main.tscn         root scene (all screens/match built in code)
  scripts/data.gd          autoload DB: 6 fictional clubs, rosters, career, saves
  scripts/main.gd          Arabic RTL UI: menu, career, training, settings...
  scripts/match.gd         3D 6v6 match: world, faceless players, ball, AI, HUD
  assets/fonts|textures|audio|icons
  tests/smoke_test.gd
  .github/workflows/android.yml
```

## 6. Implemented features / الميزات

- Real-time 3D 6v6 match (5 + goalkeeper per side) — physically play, pass, shoot and score.
- Virtual joystick + pass / shoot (hold to charge) / contextual tackle-dribble / switch / sprint buttons; stamina bar; minimap; scoreboard & timer; pause menu; result screen.
- Smart player switching (nearest when defending, receiver after a pass, manual override, goalkeeper handling on goal kicks) with a green ring highlight.
- Team AI: support runs, pressing, marking, carrier decisions (shoot/pass/dribble), goalkeeper positioning & dives; throw-ins/corners/goal kicks handled as quick restarts.
- 6 original fictional clubs with badges, rosters and attributes; 3 formations; match length 2/4/6 minutes.
- Offline career: create a player (name, number, position, club), track apps/goals/shots/W-D-L/ratings, XP and attribute training; progress saved locally (`user://`).
- Islamic reminder before every match (can be disabled in settings); no music, no ads, no purchases, no gambling content.
- **No faces anywhere:** player models have blank heads — numbers, kits and a ring distinguish players.
- Same-device 2-player mode (experimental); online multiplayer is honestly marked "coming soon" with disabled buttons.
- Low/medium graphics setting, sound effects toggle, vibration toggle, camera sensitivity, data reset with confirmation.

## 7. Known limitations / القيود

- Online multiplayer is **not implemented** in v1.0 (buttons disabled and labelled).
- No fouls/penalties/red cards (kept out deliberately to avoid a broken referee system).
- Restarts (throw-in/corner/goal kick) are simplified quick restarts.
- No separate training mini-games (training is attribute-point based).
- **Build/test status:** the smoke test, Godot export and GitHub Actions build were **not executed** in the generation environment (no Godot available there). First run on your machine may require minor fixes — please report what you see.

## 8. License

MIT License — Copyright (c) 2026 Maelainin Assari. All clubs, logos, players and assets are original and fictional.
