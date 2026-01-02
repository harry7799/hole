extends Node

const CONFIG_SECTION := "gacha"

const SkinDataRes := preload("res://Scripts/SkinData.gd")

@export var single_cost_coins: int = 500
@export var ten_cost_coins: int = 4500
@export var ssr_pity_max: int = 30 # guarantee an SSR at this many rolls without SSR

var _ssr_pity_counter: int = 0
var _total_rolls: int = 0

var _rng := RandomNumberGenerator.new()
var _pool: Array = []


func _ready() -> void:
	_rng.randomize()
	_init_default_pool()


func _init_default_pool() -> void:
	_pool.clear()
	# NOTE: pool is referenced by skin_id which must exist in Main.gd's _skin_defs.
	# Keep classic out of gacha (it's the default skin).
	_pool.append(_make("vortex", "Vortex", "R", 45, 120))
	_pool.append(_make("neon", "Neon", "R", 45, 120))
	_pool.append(_make("ssr_eclipse", "SSR: Eclipse", "SSR", 5, 800))
	_pool.append(_make("ssr_singularity", "SSR: Singularity", "SSR", 5, 800))


func _make(id: String, display_name: String, rarity: String, weight: int, dup_refund: int) -> Resource:
	var s: Resource = SkinDataRes.new()
	s.id = id
	s.display_name = display_name
	s.rarity = rarity
	s.weight = maxi(0, weight)
	s.duplicate_refund_coins = maxi(0, dup_refund)
	return s


func load_from_config(cfg: ConfigFile) -> void:
	_ssr_pity_counter = int(cfg.get_value(CONFIG_SECTION, "ssr_pity", 0))
	_total_rolls = int(cfg.get_value(CONFIG_SECTION, "total_rolls", 0))
	_ssr_pity_counter = clampi(_ssr_pity_counter, 0, max(0, ssr_pity_max - 1))
	_total_rolls = maxi(0, _total_rolls)


func save_to_config(cfg: ConfigFile) -> void:
	cfg.set_value(CONFIG_SECTION, "ssr_pity", _ssr_pity_counter)
	cfg.set_value(CONFIG_SECTION, "total_rolls", _total_rolls)


func get_ssr_pity_counter() -> int:
	return _ssr_pity_counter


func get_total_rolls() -> int:
	return _total_rolls


func get_pool_snapshot() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in _pool:
		out.append({
			"id": s.id,
			"display_name": s.display_name,
			"rarity": s.rarity,
			"weight": s.weight,
			"duplicate_refund_coins": s.duplicate_refund_coins,
		})
	return out


func get_rarity_rate_map() -> Dictionary:
	# Returns e.g. {"R": 0.9, "SSR": 0.1}
	var totals: Dictionary = {}
	var all := 0
	for s in _pool:
		var w := maxi(0, int(s.weight))
		if w <= 0:
			continue
		all += w
		var r := String(s.rarity)
		totals[r] = int(totals.get(r, 0)) + w
	if all <= 0:
		return {}
	var out: Dictionary = {}
	for r in totals.keys():
		out[String(r)] = float(int(totals[r])) / float(all)
	return out


func roll(count: int, owned_skins: Dictionary) -> Dictionary:
	# Returns:
	# {
	#   results: Array[{skin_id, rarity, is_duplicate, refund_coins}],
	#   new_unlocks: Array[String],
	#   total_refund_coins: int,
	#   pity_before: int,
	#   pity_after: int,
	# }
	var safe_count := clampi(count, 1, 10)
	var pity_before := _ssr_pity_counter
	var results: Array[Dictionary] = []
	var new_unlocks: Array[String] = []
	var total_refund := 0

	for _i in range(safe_count):
		var force_ssr := (ssr_pity_max > 0 and _ssr_pity_counter >= ssr_pity_max - 1)
		var pick := _pick(force_ssr)
		if pick == null:
			continue

		var skin_id: String = String(pick.id)
		var rarity: String = String(pick.rarity)
		var is_dup := owned_skins.has(skin_id) and bool(owned_skins[skin_id])
		var refund := 0
		if is_dup:
			refund = pick.duplicate_refund_coins
			total_refund += refund
		else:
			new_unlocks.append(skin_id)

		results.append({
			"skin_id": skin_id,
			"rarity": rarity,
			"is_duplicate": is_dup,
			"refund_coins": refund,
		})

		_total_rolls += 1
		if rarity == "SSR":
			_ssr_pity_counter = 0
		else:
			_ssr_pity_counter = clampi(_ssr_pity_counter + 1, 0, max(0, ssr_pity_max - 1))

	return {
		"results": results,
		"new_unlocks": new_unlocks,
		"total_refund_coins": total_refund,
		"pity_before": pity_before,
		"pity_after": _ssr_pity_counter,
	}


func _pick(force_ssr: bool) -> Resource:
	if _pool.is_empty():
		return null

	var total_weight := 0
	for s in _pool:
		if force_ssr and s.rarity != "SSR":
			continue
		total_weight += maxi(0, s.weight)

	if total_weight <= 0:
		return null

	var r := _rng.randi_range(1, total_weight)
	var acc := 0
	for s in _pool:
		if force_ssr and s.rarity != "SSR":
			continue
		acc += maxi(0, s.weight)
		if r <= acc:
			return s
	return _pool[0]
