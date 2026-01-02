# Godot Black Hole Game — 邏輯 / 架構報告（2025-12-23，更新至 2025-12-25）

> 目的：整理目前所有代碼邏輯與系統結構，方便你規劃更好玩的內容與美術配置。

---

## 0. 近期更新摘要（2025-12-25）

這段時間的改動重點在「可玩性與可用性」：讓 UI/設定不再卡死、讓傷害判定穩定、讓 Fever Mode 可辨識、並修掉相機移動時背景露灰邊。

### 0.1 玩家可感知的變更

- **HUD 重新整理**
  - 右上「核心等級」資訊區塊移除，避免遮擋。
  - 左上原「黑洞等級」改為顯示 **核心等級**。
  - 右上只保留設定按鈕，且改成 **TextureButton 圖示**（可替換成齒輪/板手）。

- **設定視窗可用性修復（主選單/遊戲中）**
  - 設定視窗改為真正可互動的 modal（不再被 overlay 吃掉點擊）。
  - 遊戲中開啟設定會暫停，關閉後恢復（避免凍結/卡死）。

- **音量與音樂選擇**
  - 音量拆成「音樂」與「音效」，會保存到 `user://meta.cfg`。
  - 新增「背景音樂」下拉：預設 + 已解鎖地圖的專屬音樂（若有對應檔案）。

- **地圖商店（Upgrades → Maps）UI 修復/改良**
  - 預覽圖置中且不裁切。
  - 支援左/右箭頭與滑動切換地圖。
  - 解鎖提示文字：**「解鎖地圖與地圖限定專屬音樂」**。

- **Fever Mode（連吞）與辨識度**
  - Fever 期間對敵人/子彈交互更一致（包含重疊情況的補吸收）。
  - Fever 有明顯的視覺提示（外圈光暈/粒子 aura），不遮住黑洞本體。

- **傷害判定穩定化（不再“偶爾才扣血”）**
  - 傷害改成以黑洞「核心傷害半徑」判定，不再依賴大型吸引區的進入事件。
  - 子彈會先追蹤命中目標，接近核心半徑才結算傷害；Fever 期間會被吸收。

- **背景露灰邊修復（相機跟隨時）**
  - 無限背景改為 repeat-region sprite 並且每幀「固定置中鏡頭 + 滾動 region_rect 做視差」，避免任何方向跑出灰底。

### 0.2 技術性改動（給工程/策劃參考）

- **UI 互動層級/輸入阻擋問題修復**
  - 多個全螢幕/遮罩類 Control 設為 `mouse_filter = IGNORE`，避免吞掉點擊。
  - 設定/確認視窗放到高 layer 的 CanvasLayer（SettingsLayer）上。

- **持久化資料擴充（meta.cfg）**
  - 新增/擴充：音量（music/sfx）、BGM 選擇、地圖解鎖與選用。

- **地圖綁定音樂規則（現在版本）**
  - 若地圖圖片為 `res://Maps/xxx.png`，同資料夾放 `res://Maps/xxx.mp3` 或 `.ogg/.wav`，
    則在玩家解鎖該地圖後，該音樂會出現在設定的「背景音樂」下拉選單中。

### 0.3 主要更動檔案清單

- `Scenes/MainScene.tscn`：HUD 結構、右上設定 TextureButton、移除右上等級區塊。
- `Scenes/Main.gd`：設定視窗/對話框層級與互動修復、音量保存、BGM 下拉、Maps 商店 UI、背景無限平鋪修復、Fever UI 等。
- `Scripts/BlackHole.gd`：Fever Mode、傷害半徑 API、Fever 視覺提示（aura）。
- `Enemy.gd`：敵人介面（is_enemy/get_score_value）、核心半徑傷害判定。
- `EnemyProjectile.gd`：核心半徑命中判定、Fever 吸收。
- `Scenes/FullScreenEffect.tscn`：避免遮罩吃輸入（mouse_filter）。

### 0.4 已知限制 / 注意事項

- 本機環境無法直接以 CLI 執行 `godot --version`（不影響在 Godot Editor 內執行/測試）。
- 地圖專屬音樂採「同名檔案」約定，後續若要更完整的資料驅動（每張地圖有名稱/價格/音樂/特效），建議改成 Resource/JSON 定義。

---

## 1. 專案總覽

- 類型：2D 物理吞噬（黑洞成長）+ 熵值衰減（穩定度）+ 通緝壓力（敵人/子彈）
- 引擎：Godot 4.x
- 主場景：`Scenes/MainScene.tscn`

### 1.1 核心檔案地圖

- 遊戲主控：`Scenes/Main.gd`
- 黑洞核心：`Scripts/BlackHole.gd`
- 玩家輸入：`Scenes/PlayerController.gd`
- 敵人：`Enemy.gd` + `Scenes/Enemy.tscn`
- 子彈：`EnemyProjectile.gd` + `EnemyProjectile.tscn`
- 獵物/可吞物：`Scenes/SwallowableObject.gd` + `Scenes/SwallowableObject.tscn`
- 道具：`Scenes/MagnetItem.gd`、`Scenes/HourglassItem.gd`
- 全螢幕效果：`Scenes/FullScreenEffect.tscn`
- Shader：`Shaders/BlackHoleShader.gdshader`、`Shaders/FullScreenDistort.gdshader`

---

## 2. 場景結構（MainScene）

主場景 `Scenes/MainScene.tscn` 的核心結構（概念層級）：

- World（Node2D）
  - `BlackHole`（Area2D）：黑洞本體，包含碰撞/吸引/吞噬/穩定度
  - `PlayerController`（Node2D）：輸入與移動
  - `Camera2D`：鏡頭跟隨黑洞、動態 zoom
  - `StarBackground`（Sprite2D）：背景貼圖（repeat/region）
- UI（CanvasLayer）
  - `HUD`（Control）：時間、穩定度條、等級、分數、通緝、EMP、設定
  - `MainMenu`（Control）：主選單（按開始才開局）
  - `FullScreenEffect`（Node2D）：全螢幕漣漪（ColorRect + ShaderMaterial）

---

## 3. 系統與責任分工

### 3.1 `Main.gd`（遊戲導演 / Game Loop）

**責任**
- 遊戲狀態：開始前（主選單）/ 進行中 / 結束 / 復活提示
- 生成節奏：獵物、敵人、道具
- UI 更新：分數、等級、時間、通緝、穩定度
- 特殊系統：Wanted、EMP、沙漏凍結、磁鐵吸引

**關鍵狀態**
- `game_started`：進入先顯示主選單；按「開始遊戲」才正式開局
- `is_game_over`：結束或復活選擇期間凍結
- `time_left`：180 秒倒數（沙漏啟動時暫停倒數）
- `wanted_level`：0~5 通緝等級（依黑洞等級推進）

### 3.2 `BlackHole.gd`（核心玩法）

**責任**
- 引力吸引（對範圍內 rigid bodies 施力）
- 吞噬（進入 kill radius 則吞噬）
- 成長/升級（吞噬累積→level_up）
- 穩定度（熵值）衰減 + 受傷統一入口 `apply_damage()`
- 視覺：黑洞自身 shader + 全螢幕漣漪 shader 參數更新

**對外訊號（Main.gd 會接）**
- `object_swallowed(score_gain: int)`
- `level_up(new_level: int)`
- `reached_max_level()`
- `stability_changed(current, max_val)`
- `stability_depleted()`
- `powerup_collected(powerup_type: StringName)`

### 3.3 `PlayerController.gd`（輸入/手感）

**責任**
- 移動輸入（方向鍵/觸控方向）
- 加速（Shift）消耗穩定度當燃料：`black_hole.apply_damage(cost)`

> 這支腳本是你未來做「手感升級」最安全的集中改動點。

### 3.4 `Enemy.gd`（壓力來源：追擊 + 射擊 + 近戰）

**責任**
- 追蹤目標（BlackHole）：直線朝目標移動，並旋轉朝向
- 射擊：Timer 週期 instantiate `EnemyProjectile.tscn`
- 碰撞近戰：撞到黑洞就造成傷害，並觸發「蒸發/縮小」懲罰（若黑洞提供介面）

**群組**
- `Enemies`：用於 EMP 清場、沙漏凍結

### 3.5 `EnemyProjectile.gd`（遠程傷害）

**責任**
- 依 `velocity` 移動
- 命中黑洞：呼叫 `apply_damage(damage)`，然後自毀
- 存活時間：用 `LifetimeTimer`（依 viewport/zoom 估算，避免太短）

**群組**
- `EnemyProjectiles`：沙漏凍結、清理

### 3.6 `SwallowableObject.gd`（獵物 / 分數來源）

**責任**
- 隨機貼圖（textures 池）
- 隨機 scale / 角速度
- 提供 `get_score_value()`（能量值）

**群組**
- `Prey`、`Swallowables`

### 3.7 道具（Magnet/Hourglass）

**共同介面**
- `get_score_value()`：吞噬得分
- `get_powerup_type()`：回傳 `MAGNET` 或 `HOURGLASS`

**效果由 Main.gd 實作**
- Magnet：期間內對畫面內獵物施加額外拉力
- Hourglass：凍結敵人與子彈（暫停 combat），並暫停倒數

---

## 4. 訊號與資料流（重點）

### 4.1 黑洞 → Main.gd

- 吞噬：`object_swallowed(score_gain)`
  - Main：`current_score += score_gain` → 更新分數 UI
- 升級：`level_up(new_level)`
  - Main：更新等級 UI、調整生成速率（spawn_rate 變快）、更新 Wanted
- 穩定度更新：`stability_changed(current, max)`
  - Main：更新 `ProgressBar` 值與顏色
- 穩定度耗盡：`stability_depleted()`
  - Main：提供一次性復活 → 否則 game over
- 道具：`powerup_collected(type)`
  - Main：啟動 Magnet 或 Hourglass

### 4.2 Main.gd → 生成

- `spawn_timer.timeout` → `_spawn_object()`：生成獵物（依等級增加同波數量）
- `enemy_spawn_timer.timeout` → `_spawn_enemy()`：生成敵人（依 wanted 增加同波數量）
- `_powerup_spawn_timer.timeout` → `_spawn_powerup()`：生成磁鐵/沙漏

---

## 5. 節奏設計：時間、Wanted、生成曲線

### 5.1 時間
- `game_duration = 180s`
- 倒數在 `_process(delta)` 每幀扣 `time_left -= delta`
- 沙漏啟動時暫停倒數（等沙漏結束再繼續扣）

### 5.2 Wanted（通緝）
- Wanted 由黑洞等級推進：0~5
- Wanted 影響：
  - UI 文案/顏色
  - 敵人生成速度（`enemy_spawn_timer.wait_time`）
  - 同波敵人數量（wanted 越高一次生成更多）
  - wanted ≥ 2 顯示 EMP 按鈕

### 5.3 生成位置
- `_get_spawn_position()` 會依 `Camera2D.zoom` 計算世界可視範圍，把生成點推到螢幕邊緣附近

---

## 6. 戰鬥與生存系統

### 6.1 傷害入口統一：`apply_damage(amount)`
- 敵人近戰撞擊：`Enemy.gd` → 黑洞 `apply_damage(damage)`
- 子彈命中：`EnemyProjectile.gd` → 黑洞 `apply_damage(damage)`
- 加速燃料：`PlayerController.gd` → 黑洞 `apply_damage(cost)`

**重要更新（2025-12-25）**
- 傷害判定改成「接近黑洞核心傷害半徑」才結算，避免因為吸引區域太大導致傷害偶發。
- 黑洞提供 `get_damage_radius()` 供敵人/子彈查詢。

### 6.2 蒸發/縮小懲罰：`shrink_and_eject(amount, eject_count)`
- 由敵人近戰觸發（若黑洞提供該方法）
- 效果：減少吞噬計數代理、縮小 pull radius、噴出獵物（視覺與節奏懲罰）

### 6.3 復活
- `stability_depleted()` → `Main._on_entropy_death()`
- 第一次死亡彈出 `ConfirmationDialog` 讓玩家復活一次
- 復活時：清敵人/子彈、回復一定比例穩定度、恢復計時器與控制

---

## 7. UI / 視窗系統

### 7.1 主選單（MainMenu）
- 進入場景先顯示
- 點「開始遊戲」才會：開計時器、啟用玩家控制、啟用黑洞 process

**關卡制入口（2025-12-25 追加）**
- 主選單新增第二顆按鈕：**「開始遊戲（關卡制）」**，與原本自由無盡模式並存。
- 現階段僅做「模式分流」與入口，關卡內容（勝利條件/專屬機制）會逐步加到 `Main.gd` 的遊戲流程中。

---

## 13. 關卡制提案：Level 2「黃金奇點」(The Golden Singularity)

> 目標：把既有「吞噬成長」玩法轉成一個有明確勝利條件的關卡，並用環境力場 + 核心守衛敵人，逼玩家改變走位與節奏。

### 13.1 勝利 / 失敗條件

- **勝利條件**：在關卡時間內達到 **核心等級 Lv.10**，解鎖「吞核心」能力後，吞噬地圖中央的 **黃金核心（Golden Core）**。
- **失敗條件**（任一成立即失敗）：
  - 黑洞穩定度耗盡（沿用現有 `stability_depleted()`）。
  - 倒數結束且尚未吞噬黃金核心。
  - （可選、簡化版先不做）黃金核心完整度歸零。

### 13.2 地圖機制：全域漩渦流（Vortex Current）

- 地圖存在一個「向心漩渦流」：對場上物體（獵物/敵人/子彈/隕石）施加切向 + 向心力。
- 玩家黑洞也會感受到力場（但係數可較小），形成「越靠近中心越難控制」的張力。
- 目的：讓玩家不能只靠直線追獵物，必須利用流場做軌道式走位。

**最小可行實作方式（不重寫架構）**
- 在 `Main.gd` 內新增一個「關卡環境力場」更新：每個 `_physics_process` 對特定 group（例如 `Prey`/`Enemies`/`EnemyProjectiles`/`Swallowables`）的 `RigidBody2D` 施加 `apply_central_force()`。
- 力的方向：
  - 向心：朝中心 `to_center.normalized()`
  - 切向：`to_center.orthogonal().normalized()`
  - 強度：距離越近越強（例如 `1/(r+offset)` 類 falloff）

### 13.3 場景物件：黃金核心（Golden Core）

- 位置：地圖中心附近，視覺上明顯可辨。
- 行為：
  - Lv < 10 時：不可被吞噬（或吞噬失敗彈開）。
  - Lv >= 10 時：進入黑洞 kill radius 觸發「吞核心勝利」。

**MVP 建議**
- 先做成 `Area2D` + `CollisionShape2D`，提供 `is_core_objective() -> bool` / `get_score_value()`（可為 0）供黑洞辨識；真正的勝利判定放在 `Main.gd` 接收到「吞噬核心」事件時結束關卡。

### 13.4 危險源：軌道隕石（Orbiting Meteors）

- 生成：固定在 2~3 條軌道半徑上刷出（或從外圈進入後被漩渦流捕獲）。
- 特性：
  - 碰到黑洞造成較高傷害或強制縮小懲罰（用現有 `apply_damage()` / `shrink_and_eject()` 介面）。
  - 可被吞噬，但需要更高等級/更接近核心半徑（避免早期亂吞太賺）。

### 13.5 黃金化敵人（3 種，對策差異明顯）

- **Guardian（守護者）**：靠近中心繞行，優先阻擋玩家接近黃金核心；近戰傷害高。
- **Sniper（狙擊者）**：在外圈繞行，低頻高傷的遠程射擊，逼玩家不能只貼中心。
- **Leech（吸收者/補給者）**：會試圖接觸黃金核心（或中心區），成功後提升敵人強度/加速生成（MVP 可先做：接觸中心就自爆並生成 1 波敵人）。

### 13.6 節奏（洋蔥式四階段）

- **Phase A（0%~25%）**：讓玩家理解流場；敵人少、隕石少；目標是穩定升級。
- **Phase B（25%~55%）**：加入狙擊者與第一條隕石軌道；逼玩家學會外圈繞行吃獵物。
- **Phase C（55%~80%）**：守護者成群，中心區壓力上升；吞噬節奏要求更高。
- **Phase D（80%~100% / Lv.10）**：解鎖吞核心；敵人刷出最密集但時間不長，做「衝刺到中心」的高潮。

### 13.7 與現有程式架構的對接點

- 入口：主選單新增按鈕 → `Main.gd` 設定 `game_mode = CAMPAIGN` 與 `campaign_level_id`，再走現有 `_start_game()`。
- 差異化：在 `Main.gd` 的生成/勝利判定加入 `if game_mode == CAMPAIGN` 分支。
- 黑洞不需重寫：關卡的「環境力場」「核心目標」「敵人組合」由 `Main.gd` 控制即可。

### 7.2 HUD
- 時間、穩定度條、Wanted、等級、分數、EMP、設定
- 現在採用 PanelContainer 包住資訊區塊，提高可讀性

**重要更新（2025-12-25）**
- 右上等級資訊區塊移除；左上等級統一顯示「核心等級」。
- 右上設定按鈕改為 TextureButton 圖示，方便替換齒輪/板手。

### 7.3 設定（AcceptDialog）
- 音樂音量滑桿 + 百分比顯示
- 音效音量滑桿 + 百分比顯示
- 背景音樂下拉：預設 + 已解鎖地圖專屬音樂（若存在同名音檔）
- 設定視窗已修正為可在主選單/遊戲中正常互動（避免卡死/點不到）

### 7.4 EMP（AcceptDialog）
- 「清場」或「延長時間」二選一

---

## 12. 下一步建議（給 CEO/策劃）

若要往「更好玩/可營運」推進，最建議的下一步：

1) **把“地圖/音樂/價格/解鎖條件”資料化**
  - 目前是以資料夾掃描 + 同名音檔約定。
  - 建議改成 `res://Data/maps.tres`（Resource）或 JSON，讓每張地圖可定義：展示名、價格、音樂、主題特效、稀有度、是否可做活動。

2) **Meta Loop 強化（留存）**
  - 既然已有金幣/地圖/skins/upgrades，下一步可引入每日任務/離線收益節奏與“地圖主題事件”。

3) **Fever Mode 轉成可被設計的系統**
  - 把 Fever 觸發條件、持續時間、倍率、可吃子彈/敵人的規則與視覺強度抽成常數/表格，方便設計調參。

4) **敵人多樣化（對策導向）**
  - 現有基礎敵人已可用；下一步做 2~3 種明顯差異（狙擊/衝撞/召喚/護盾）即可讓節奏大幅提升。

---

## 8. 視覺與美術掛點（建議你規劃美術時對齊的層）

1) **背景層**：`StarBackground` + Main.gd 的 repeat/視差
2) **世界層**：獵物（textures 池）/ 敵人貼圖 / 子彈貼圖
3) **核心層**：黑洞 `Visuals` 的 ShaderMaterial（局部扭曲/色差）
4) **全螢幕層**：`FullScreenEffect` 的 ColorRect Shader（漣漪/扭曲）
5) **UI 層**：HUD/選單/對話框

> 美術替換最穩定的策略：先替換世界層貼圖（獵物/敵人/子彈），再調整 Shader 強度與 UI 對比度。

---

## 9. 擴充點清單（做「更好玩」最推薦下刀位置）

### 9.1 新敵人類型
- 規格：
  - `set_target(t)`
  - `is_enemy() -> bool`
  - `add_to_group("Enemies")`
  - 傷害走 `apply_damage()`
- 可延伸方向：
  - 狙擊型（長射程低頻高傷）
  - 召喚型（呼叫小怪）
  - 干擾型（降低穩定度回復、反向磁鐵）

### 9.2 新道具
- 只要提供 `get_powerup_type()`，Main.gd match 分支即可
- 例：護盾、時間回溯、分數倍率、短暫擴大 kill radius、EMP 改成能量蓄力技

### 9.3 手感升級
- 聚焦 `PlayerController.gd`
- 例：慣性/阻尼、衝刺冷卻、觸控搖桿、吸附式瞄準

### 9.4 節奏曲線
- Wanted 門檻 / wait_time 曲線 / 同波數量
- 獵物 spawn_count 與移動初速（避免玩家「站著就吃」）

---

## 10. 附：系統流程（文字版）

1. 進入場景 → 顯示主選單（game_started=false）
2. 點開始 → 初始化本局數值 → 開始倒數 → 開始生成 → 啟用控制
3. 玩家移動 → 吞噬獵物/道具 → 分數+成長 → 可能升級
4. 升級 → Wanted 上升 → 敵人更頻繁、更密集
5. 敵人/子彈命中 → 穩定度下降 → 觸發更強視覺警示
6. 穩定度歸零 → 復活一次（可選） → 否則結束
7. 時間歸零 → 結束

---

## 11. 建議下一步（如果你要我協助）

- 我可以把「節奏曲線」抽成可調參（例如 JSON/Resource 或統一常數區塊），讓你後面改難度/關卡更快。
- 或者先做一個「美術配置清單」：列出每個貼圖/材質在場景中的節點掛點與替換規格（尺寸、pivot、shader 參數）。
