# 🕳️ 黑洞核心 (Black Hole Core)

一款以 **Godot 4.5** 開發的 2D 物理街機遊戲。玩家操控黑洞吞噬物體成長，對抗熵值衰減，擊退不斷升級的敵人威脅。

![Godot](https://img.shields.io/badge/Godot-4.5-blue?logo=godotengine)
![Platform](https://img.shields.io/badge/Platform-Mobile-green)
![Renderer](https://img.shields.io/badge/Renderer-GL%20Compatibility-orange)

---

## 🎮 核心玩法

- **引力吞噬**：黑洞自動吸引範圍內物體，靠近核心即被吞噬得分
- **成長系統**：吞噬越多，引力範圍與視覺大小指數增長
- **穩定度（熵值）**：穩定度持續衰減，被敵人攻擊加速消耗，歸零即遊戲結束
- **通緝系統**：等級越高通緝越高（0-5 級），敵人生成速度從 5 秒加速至 0.1 秒
- **重力衝擊波**：主動技能，清除彈幕並擊退敵人
- **EMP 衝擊波**：通緝 ≥ 2 時可使用，全場清敵

## 🧩 遊戲系統

### Roguelike 升級
每次升級可從 3 張隨機卡片中選擇增益效果，提升引力、穩定度、攻擊等屬性。

### 多角色選擇
6 種可解鎖角色，各有不同起始屬性與被動能力。

### 遊戲模式
| 模式 | 說明 |
|------|------|
| **關卡制** | 限時 180 秒，達成目標過關 |
| **無盡模式** | 無時間限制，挑戰最高分 |
| **Roguelike 無盡挑戰** | 帶升級選擇的無盡模式 |

### 每日任務
設定視窗內可查看每日 / 局內任務，完成獲得金幣獎勵。

### 抽獎系統（轉蛋）
消耗金幣抽取造型，含 R / SSR 稀有度、保底機制、彩虹粒子演出。

### 離線收益
離線時間自動累積金幣，回到遊戲可領取。

## 🏗️ 技術架構

### 場景結構
```
MainScene.tscn
├── CanvasLayer (HUD + MainMenu)
├── Camera2D（跟隨黑洞 + 動態縮放）
├── PlayerController（觸控/鍵盤輸入）
├── BlackHole（引力、吞噬、穩定度）
└── FullScreenEffect（全螢幕引力漣漪 Shader）
```

### Autoload 系統
| 名稱 | 功能 |
|------|------|
| `GameConfig` | 全局常數與平衡參數 |
| `MetaManager` | 存檔 / 讀檔 / 局外成長 |
| `Events` | 全局信號中介 |
| `GachaManager` | 抽獎邏輯與保底計算 |
| `MissionManager` | 每日 / 局內任務追蹤 |
| `RoguelikeUpgradeManager` | Roguelike 升級池管理 |

### Shader 效果
- **BlackHoleShader** — 黑洞本體扭曲效果（Screen Texture）
- **FullScreenDistort** — 全螢幕引力漣漪波紋

### 物理與引力
- `Area2D` 追蹤進入範圍的物體
- `_physics_process` 中根據距離衰減施加 `apply_central_force()`
- 進入 `kill_radius` 觸發吞噬

## 📁 專案結構

```
hole/
├── Scenes/          # 場景檔 (.tscn) 與對應腳本
│   ├── Main.gd      # 遊戲主控制器（UI、生成、計分、通緝）
│   ├── MainScene.tscn
│   ├── GachaScene.gd # 抽獎演出
│   └── ...
├── Scripts/         # 獨立系統腳本
│   ├── BlackHole.gd  # 黑洞核心機制
│   ├── CharacterSelectUI.gd
│   ├── UpgradeSelectionUI.gd
│   ├── SpawnManager.gd
│   └── ...
├── Shaders/         # Shader 與素材
├── Skins/           # 造型定義（資料夾掃描自動載入）
├── Maps/            # 地圖背景與音樂（資料夾掃描自動載入）
├── Fonts/           # NotoSansCJK 中文字型
└── Audio/           # 音效檔案
```

## 🚀 開始開發

### 環境需求
- [Godot 4.5](https://godotengine.org/) 以上
- Mobile 渲染方式（GL Compatibility）

### 執行
1. 用 Godot 編輯器開啟專案資料夾
2. 按 **F5** 執行主場景
3. 或命令列：`godot --path . res://Scenes/MainScene.tscn`

### 擴充內容
- **新增地圖**：將背景圖 + 音樂放入 `Maps/` 資料夾，自動掃描載入
- **新增造型**：在 `Skins/` 資料夾新增素材，按既有格式定義
- **新增敵人**：繼承 `Area2D`，實作 `set_target()`、`is_enemy()`、`get_score_value()`，加入 `"Enemies"` 群組

## 📱 平台支援

- **目標平台**：手機（Android / iOS）
- **螢幕方向**：直式（Portrait）
- **視口大小**：720 × 1280
- **渲染器**：GL Compatibility（適配低端裝置）

## 📄 License

Private project.
