# Godot Black Hole Game — CEO Review (Gameplay, Logic, Systems)

Date: 2025-12-24
Engine: Godot 4.5 (Mobile renderer)
Workspace: `hole/`

## 1) Executive Summary
This is a 2D arcade “growth predator” game: the player pilots a black hole, consumes objects to grow/score, manages entropy (stability) decay, and survives escalating enemy pressure (Wanted system). The current codebase already contains a solid core loop plus meta-progression (coins, upgrades, skins, maps) with folder-driven extensibility.

## 1.1 Current Build — Feature Highlights (2025-12-24)
This build is tuned for **“immediately visible” feedback** (mobile-friendly) and includes several retention/scale hooks.

- **Shockwave (active skill)**: HUD button “重力衝擊波（雙擊或點此）” triggers cyan flash + expanding ring + screenshake + vibration; clears nearby enemy bullets and pushes/stuns enemies.
- **Wanted visualization**: at Wanted ≥ 3 (“DANGER: PURGE ACTIVE”) a **pulsing red overlay** appears (faint but visible).
- **EMP (rewarded action)**: “看廣告：啟動 EMP 衝擊波” button appears at Wanted ≥ 2.
- **Idle rewards (claimable)**: main menu “離線收益” shows accumulated coins and a **Claim** action; capped by `idle_coin_daily_cap`.
- **Projectile pooling**: Enemy projectiles are pooled/reused to reduce mobile hitches; hardened against freed-object references.
- **Projectile readability**: enemy bullets use **additive blend** for a cheap “glow” effect.
- **Infinite background stability**: repeat-region background is initialized immediately (works in main menu) and scaled to avoid edge gaps during long travel.

**What’s strong now**
- Clear core loop: move → pull → swallow → grow → survive against entropy/enemies.
- Mobile-first UX: portrait layout, simplified controls, and a single-screen HUD.
- Good systemic hooks: stability as a survival timer, wanted escalation, EMP, powerups.
- Content extensibility: `res://Maps` / `res://Skins` scanning means content can scale via assets.

**Primary gaps / risks**
- “Growth fantasy” clarity: multiple systems affect size/zoom/visuals, which can confuse player perception.
- Tuning: spawn density + scaling + stability decay + enemy bullet pressure needs iteration to feel fair.
- Some logic cohesion: camera control, growth visuals, and physics interaction are spread across scripts.

## 2) Current Game Loop (Player-facing)
**Minute-to-minute loop**
1. Player moves black hole toward targets.
2. Black hole gravity pulls nearby bodies.
3. When objects enter kill radius → they are swallowed.
4. Swallowing yields score + stability energy; contributes to growth points.
5. Stability decays continuously (entropy). Taking damage accelerates losing stability.
6. Wanted level rises with progression and increases enemy intensity.
7. Player uses EMP (rewarded action) and powerups (Magnet/Hourglass) to survive spikes.

**Win/Lose**
- Lose: stability reaches 0 OR time limit expires.
- Win condition is currently survival/time-based with score progression (not a final boss endpoint).

## 3) Systems Breakdown (What exists today)

### 3.1 Movement / Input
File: `Scenes/PlayerController.gd`
- Single-hand drag-to-move and desktop fallback.
- Boost (Shift) consumes stability via `apply_damage(cost)`.
- Double-tap gesture can also trigger Shockwave (as a backup to the HUD button).
- Safety measures implemented to avoid perceived teleport and UI-click movement.

Important UX note:
- `Scenes/Main.gd` contains a defensive `_input()` hit-test fallback for critical buttons (Start/Skins/Upgrades/MenuSettings/IdleRewards/EMP/Shockwave) to ensure taps still work even if GUI input is intercepted.

### 3.2 Black Hole Attraction + Swallowing
File: `Scripts/BlackHole.gd`
- Tracks nearby bodies via Area2D overlap and maintains `bodies_in_range`.
- Applies pull force in `_physics_process`.
- Swallowing logic:
  - If enemy: applies heavy stability damage and destroys enemy.
  - If normal: adds energy (stability), score, growth points.
  - If powerup: emits `powerup_collected` before freeing.

Added risk/reward:
- **Overload mode**: at high stability ratio (configurable), pull and score multipliers apply.

Active skill:
- **Shockwave** (`trigger_shockwave() -> bool`): consumes stability, emits `shockwave_triggered(intensity)`, pushes/stuns enemies, clears nearby bullets. Returns `false` if stability is insufficient so UI can show a toast instead of “no response”.

### 3.3 Stability (Entropy)
File: `Scripts/BlackHole.gd`
- `current_stability` decays each frame based on level penalty.
- Damage entry points: enemy melee collisions and projectiles.
- `stability_depleted` triggers game over.

### 3.4 Wanted / Enemy Escalation
File: `Scenes/Main.gd`
- Wanted influences enemy spawn rates and stage.
- Stages adjust:
  - enemy move speed
  - shoot interval
  - projectile speed/damage
  - burst/spread patterns

Added UX:
- **WantedOverlay**: pulsing red overlay appears at Wanted ≥ 3.

### 3.5 Enemies + Projectiles
Files:
- `Enemy.gd`
- `EnemyProjectile.gd`
- Enemies chase the black hole and shoot projectiles.
- Enemies can show a short pre-fire telegraph line (stage threshold lowered so it appears earlier).
- Projectiles self-timeout based on viewport+camera zoom.

Performance:
- **Object pooling** for `EnemyProjectile` (spawn/recycle) reduces runtime allocations.

Readability:
- Projectile sprite uses additive blending (“glow”) to increase visibility against bright backgrounds.

### 3.6 Powerups
Files:
- `Scenes/MagnetItem.gd` (MAGNET)
- `Scenes/HourglassItem.gd` (HOURGLASS)
- Magnet effect: applies pull-to-blackhole forces to prey inside visible area.
- Hourglass effect: freezes enemies/projectiles temporarily.

### 3.7 Background / Camera / Visual FX
Files:
- `Scenes/Main.gd` (camera follow, zoom, infinite background)
- `Shaders/BlackHoleShader.gdshader` (local distortion, circular correctness)
- `Shaders/FullScreenDistort.gdshader` (global ripple)

Notable implementation details:
- Infinite background via a repeating region Sprite2D that is:
  - initialized with a non-zero `region_rect` immediately (so it renders in the main menu)
  - dynamically resized during gameplay based on viewport/zoom
  - scaled and buffered to prevent grey edge gaps during long-distance travel
- Camera zoom driven primarily by black hole level.
- Fullscreen ripple can be disabled via settings.

### 3.8 Meta Progression & Store
File: `Scenes/Main.gd`
- Persisted storage: `user://meta.cfg` via `ConfigFile`.
- Meta includes:
  - coins
  - pending idle rewards (claimable)
  - upgrades (gravity/speed/magnet)
  - skins selection/unlocks
  - maps selection/unlocks
  - separate menu background selection

Retention hooks:
- **Idle rewards** are accumulated into `pending_idle_reward_coins` and claimed from the main menu (not auto-granted), capped daily.
- **Try-before-buy**: random chance to apply a trial skin for a run (does not unlock).

Monetization hooks (stubbed / simulated):
- Rewarded EMP action.
- Rewarded revive prompt on death.

### 3.9 Content Extensibility
Folders:
- `Maps/` (drop images; they appear in the Maps UI)
- `Skins/` (drop images; they appear in the Skins UI)

## 4) Architectural Notes (How it’s wired)

### 4.1 Scene Layout
- Main scene: `Scenes/MainScene.tscn` with `Main.gd` root script.
- Player: `BlackHole` (Area2D) + `PlayerController` (movement).
- UI: HUD + MainMenu in a CanvasLayer.

### 4.2 Signal Flow
- BlackHole emits:
  - `object_swallowed(score_gain)`
  - `level_up(new_level)`
  - `stability_changed(current, max)`
  - `stability_depleted()`
  - `powerup_collected(type)`
- Main listens and updates UI/spawn pacing.

### 4.3 Group Conventions
- `Enemies` for EMP clears.
- `EnemyProjectiles` for freeze/limits.
- `Prey` / `Swallowables` for prey limit + magnet.
- `PowerUps` for excluding from gravity pull.

## 5) Known Pain Points / Product Risks

### 5.1 Player perception (size vs camera)
If the camera zoom changes at the same time as growth visuals, players may misinterpret object sizes and movement. This impacts “feel” more than correctness.

### 5.2 Difficulty spikes
Enemy projectile bursts + stability decay + aggressive spawn can stack into sudden failures. Consider:
- clearer telegraphing
- controllable escape tools
- smoothing escalation curves

### 5.3 Content readability on mobile
Tiny objects can become hard to see; the game needs consistent visual hierarchy:
- prey small but readable
- enemies clearly larger
- bullets clearly smaller than enemies

## 6) Opportunities: More Playability / Retention (CEO brainstorming)

### 6.1 Make growth meaningful
- Give discrete unlock effects at specific levels (e.g., stronger pull pattern, temporary shield, larger kill radius).
- Add “shape evolution” skins that convey power.

### 6.2 Add run goals
- Missions: swallow X of type, survive Y seconds at wanted Z.
- Risk-reward zones: areas with higher prey density + higher enemy aggression.

### 6.3 Enemy variety
- Sniper enemy (low rate, high accuracy)
- Swarm enemy (many, fragile)
- Shielded enemy (needs sustained pull)
- Boss at time checkpoints

### 6.4 Progression economy
- Coins per run scale with performance + missions.
- Add meaningful upgrade caps and “prestige” loops.

### 6.5 Moment-to-moment juice
- Combo multiplier for consecutive swallows.
- Near-miss bullet dodge bonus.

## 7) Engineering Recommendations (to scale iteration speed)

### 7.1 Centralize tuning
Move key parameters into a single tuning resource (or `ConfigFile`) to iterate without code edits:
- prey size
- spawn rates
- enemy stage tables
- stability decay curve

### 7.2 Add debug HUD toggles (dev-only)
- show FPS
- show counts: prey/enemies/projectiles
- show black hole level/stability decay

### 7.3 Automated smoke checks
- minimal play loop test: start run → spawn prey → swallow works → game over triggers.

## 8) File Index (starting points for new engineers)
- Gameplay loop & UI/meta: `Scenes/Main.gd`
- Black hole core mechanics: `Scripts/BlackHole.gd`
- Input/movement: `Scenes/PlayerController.gd`
- Prey behavior: `Scenes/SwallowableObject.gd`
- Enemy AI & projectiles: `Enemy.gd`, `EnemyProjectile.gd`
- Visual FX: `Shaders/BlackHoleShader.gdshader`, `Shaders/FullScreenDistort.gdshader`

## 9) Proposed Next Steps (CEO Roadmap)
The following proposals are designed to move the experience from “eat → grow → dodge → die” into a loop with **counterplay, peaks, and short-term goals**, while also aligning monetization and retention with HCG best practices.

### 9.1 Gameplay: Make It Fun (爽感 + 策略)

#### A) Fever Mode (狂熱模式 / 暴走狀態)
Goal: introduce a high-contrast **power fantasy spike** (careful survival → manic domination).

- **Trigger**: a hidden “combo meter” fills when the player swallows continuously; example requirement: swallow 10 objects within a short time window.
- **Duration**: 5–8 seconds.
- **Effects**
  - **Invincible**: ignore enemy bullets and collisions.
  - **Full consume**: can swallow enemies and bullets (normally damaging).
  - **Burst pull**: gravity range ×2.
  - **Speed boost**: movement speed +50%.
- **Presentation**
  - Black hole becomes gold/rainbow; more intense particles.
  - BGM speeds up.

Why it matters:
- A “Fever spike” is a core HCG retention driver—players replay to hit the high.

#### B) Rare Prey: Loot Goblin (寶藏哥布林)
Goal: break linear pathing and create greed-driven risk.

- **Spawn**: rare special object with a halo (e.g., “gold apple” / “mini UFO”).
- **Behavior**: not attracted by gravity; when it notices the player, it **runs away**.
- **Reward options**
  - large coin drop
  - full stability refill
  - free powerup drop

Why it matters:
- Forces players to chase into danger, creating a deliberate risk decision.

#### C) In-game Missions (短期任務)
Goal: provide goals other than “don’t die” to reduce “chore feeling”.

- **UI**: a small icon + progress bar at the top (e.g., “swallow 5 red objects”).
- **Reward ideas**
  - instant full-screen Shockwave
  - temporary score multiplier

### 9.2 Monetization: Smart Ads (把廣告變玩家幫手)
Principle: ads should be **emergency** (save me) or **greed** (give me more), never annoying.

#### A) Ad placements table

| Placement | Trigger | Copy / Incentive | Psychology |
|---|---|---|---|
| Revive (1/run) | At death | “Continue + 5s invincibility!” | Loss aversion |
| Headstart buff | Main menu (pre-run) | “Start at Lv.3 + Magnet” | Greed / speedrun |
| EMP charge (panic button) | Wanted ≥ 3 | “Charged (watch ad)” | Fear / emergency |
| End-of-run multiplier | Results screen | “Coins ×3” | Accumulation / conversion |
| Skin trial | Main menu | “Try Legendary skin for 1 run” | Experience marketing |

#### B) Interstitial (forced ad) best timing
- **Never** during gameplay.
- Only after Game Over when the player clicks “Main menu / Retry”.
- Add `min_play_time` gate (e.g., 60s): if the player died in 10s, **do not show** an interstitial.

### 9.3 Retention: Make Players Return Tomorrow

#### A) Visual progression tiers (階級進化)
Goal: address “growth fantasy clarity” beyond just scaling.

- Lv 1–5: classic black.
- Lv 6–10: purple rim glow; longer particle trails.
- Lv 11+: add an accretion disk (Interstellar-style) for screenshot-worthy evolution.

#### B) Daily + Idle (每日簽到與離線收益)
Goal: strengthen the existing idle rewards loop.

- Replace “just a claim button” with a themed screen (e.g., “Galaxy Bank”) showing coins visibly accumulating.
- Claim feedback: “coins fly into wallet” animation.
- Push notification when cap reached (future mobile feature): “Your black hole swallowed a galaxy—come claim rewards.”

### 9.4 Technical Polish / Tuning

#### A) Mobile haptics (震動回饋分級)
Goal: increase “impact feel” with low cost.

- Small swallow: no vibration.
- Medium swallow: light vibration.
- Large swallow / enemy: heavy vibration.

#### B) Edge-safe UI (防誤觸)
Goal: reduce OS gesture/menu accidental triggers.

- Keep key buttons (EMP, pause/settings) at least 50–80px from screen edges.

#### C) Pacing: wave-based difficulty (波浪式難度)
Goal: avoid a purely linear pressure curve.

- Pressure wave (many enemies) → release wave (fewer enemies, more prey) → bigger pressure.
- The “release” moments are where players feel power and satisfaction, improving replay.

---
If you want, I can also produce a second MD focused only on “tuning sheet” (all numeric constants grouped with recommended ranges) for fast balancing sessions.
