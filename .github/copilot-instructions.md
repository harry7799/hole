# Godot Black Hole Game - AI Coding Instructions

## Project Overview
A 2D physics-based arcade game built in **Godot 4.5** (Mobile rendering method). The player controls a black hole that grows by consuming objects while fighting entropy decay and evading enemies.

## Architecture & Core Systems

### Scene Hierarchy
- **MainScene.tscn** - Root container with UI, Camera2D, PlayerController, BlackHole, and FullScreenEffect
- **BlackHole** (Scripts/BlackHole.gd) - Core gameplay mechanics (gravity, swallowing, stability)
- **PlayerController** (Scenes/PlayerController.gd) - Dedicated input handler for black hole movement
- **Main.gd** - Game loop, spawning, scoring, wanted system, and background parallax

### Critical Signal Flow
```
BlackHole → Main.gd:
  - object_swallowed(score_gain) → updates score, spawns faster
  - level_up(new_level) → adjusts camera zoom, spawn rate
  - stability_changed(current, max) → updates progress bar color
  - stability_depleted() → triggers game over

Main.gd → Scene:
  - Dynamically spawns SwallowableObject and Enemy instances
  - Updates UI labels (score, level, time, wanted, stability)
```

### Physics & Attraction System
- **Attraction**: BlackHole uses `Area2D.body_entered/exited` to track bodies in `bodies_in_range` array
- **Gravity Application**: In `_physics_process`, iterate tracked bodies and apply `apply_central_force()` based on distance falloff
- **Swallowing**: Objects within `kill_radius` trigger `_swallow_body()` which emits `object_swallowed` signal
- **Growth**: `max_pull_radius` and visual scale increase with each swallow using exponential formula

## Key Conventions

### Node References
- **Always use Unique Names (`%`) for cross-scene references**: `%BlackHole`, `%Camera2D`, `%ScoreLabel`, `%FullScreenEffect`
- **Onready pattern**: `@onready var camera = %Camera2D` in Main.gd
- **Export for scene assets**: `@export var enemy_scene: PackedScene` to assign in editor

### GDScript Patterns
1. **Signal-based communication** (never direct child access across scenes)
2. **Groups for collective operations**: Enemies use `add_to_group("Enemies")` for batch clearing with EMP
3. **Method queries before calling**: `if body.has_method("apply_damage"): body.apply_damage(damage)`
4. **Tween lifecycle management**: Store tweens in instance variables (`emp_button_tween`) and check `is_valid()` before creating new ones

### Shader Integration
- **BlackHoleShader.gdshader**: Local distortion effect on black hole sprite using `SCREEN_TEXTURE`
  - Updates `center` uniform via `_update_shader_position()` every frame
  - Aspect ratio correction required for circular distortion: `diff_corrected.y *= aspect_ratio`
- **FullScreenDistort.gdshader**: Global ripple effect starting at level 1
  - Main.gd → BlackHole → FullScreenEffect/ColorRect/ShaderMaterial
  - Updates `center_uv`, `distort_radius`, `distort_strength`, `distort_speed` in `_process()`
  - **Critical**: Set ColorRect.color to pure white `(1,1,1,1)` to avoid color tinting

## Gameplay Systems

### Stability (Entropy) System
- **BlackHole.gd**: `current_stability` starts at 100, decays at `base_decay_rate * (1.0 + level * 0.15) * delta`
- **Damage sources**: Enemy collision (`Enemy.damage`), projectiles (`EnemyProjectile.damage`)
- **Unified damage interface**: `apply_damage(amount)` method on BlackHole
- **Death**: Emits `stability_depleted()` when stability ≤ 0

### Wanted Level System (Main.gd)
- **Levels 0-5**: Threshold based on `BlackHole.current_level` (3→Wanted1, 7→Wanted2, etc.)
- **Enemy spawn rate**: Scales from 5.0s (wanted 1) to 0.1s (wanted 5) in `_update_enemy_spawning()`
- **EMP Button**: Shows at wanted ≥ 2, uses looping Tween for flashing effect
  - **Bug prevention**: Check `emp_button_tween.is_valid()` before creating new tween
  - Call `emp_button_tween.kill()` when hiding button

### Camera & Visual Feedback
- **Camera follows black hole** with lerp smoothing: `camera.global_position.lerp(black_hole.global_position, 0.3)`
- **Dynamic zoom**: Decreases with level: `1.0 / (1.0 + level * 0.08)`, clamped to [0.3, 1.0]
- **Background parallax**: 
  - Uses `parallax_strength` (0.35) to offset background relative to camera movement
  - For tiled backgrounds: Creates 3x3 grid of duplicates, uses modulo wrapping for infinite scrolling

## Development Workflows

### Running the Game
- Main scene: `uid://dmlxku3cybh56` (MainScene.tscn)
- Press F5 in Godot editor or run `godot --path . res://Scenes/MainScene.tscn`

### Adding New Enemy Types
1. Inherit from `Area2D`, set `move_speed` and `damage` exports
2. Add `set_target(t)` method for Main.gd to pass BlackHole reference
3. In `_ready()`: Call `add_to_group("Enemies")` for EMP compatibility
4. Implement `is_enemy() -> bool` and `get_score_value() -> float` for BlackHole interaction
5. Connect `body_entered` signal to handle collision with BlackHole (call `apply_damage()`)

### Adding UI Elements
- Create node in MainScene.tscn, enable Unique Name (%)
- Reference in Main.gd: `@onready var new_label = %NewLabel`
- Update in relevant signal handler or `_process()`

### Shader Parameter Updates
Always use `set_shader_parameter()` in GDScript:
```gdscript
shader_material.set_shader_parameter("center_uv", screen_pos / viewport_size)
```
Never modify shader uniforms directly - they're read-only from GDScript.

## Common Pitfalls
1. **Tween errors**: Always store tweens in variables and check `is_valid()` before creating new ones
2. **Integer division warnings**: Use `int(total_seconds / 60.0)` instead of `total_seconds / 60`
3. **Shader color tinting**: Ensure ColorRect using screen-space shaders has `color = Color.WHITE`
4. **Missing Unique Names**: If `%NodeName` returns null, check node has Unique Name enabled in scene tree
5. **Aspect ratio in shaders**: Always correct for viewport aspect when calculating circular distances

## File Organization
- `/Scenes/` - Scene files (.tscn) and their companion scripts
- `/Scripts/` - Standalone scripts like BlackHole.gd
- `/Shaders/` - .gdshader files and texture imports
- Root level - Enemy/Projectile scripts that may be reused

## Notes
- Game uses Chinese text for UI labels - preserve encoding when editing
- Mobile renderer targets lower-end devices - avoid complex post-processing stacks
- Time limit: 180 seconds (see `game_duration` in Main.gd)
