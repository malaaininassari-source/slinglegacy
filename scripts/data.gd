extends Node
## SLING LEGACY — data layer: fictional clubs, players, career, settings, saves.
## Autoloaded as "DB".

signal career_changed
signal settings_changed

const SAVE_VERSION := 1
const SETTINGS_PATH := "user://settings.json"
const CAREER_PATH := "user://career.json"
const XP_PER_POINT := 50

# ------------------------------------------------------------------ clubs ----
var clubs := [
	{"name": "نجوم دوار اللوح", "short": "NDL", "color": Color("18a957"), "color2": Color("0d5c2e"), "letter": "ن", "strength": 78},
	{"name": "أطلس غرناطة", "short": "ATL", "color": Color("2456c9"), "color2": Color("122a66"), "letter": "أ", "strength": 74},
	{"name": "صقور الريف", "short": "SOQ", "color": Color("c92f2f"), "color2": Color("661616"), "letter": "ص", "strength": 72},
	{"name": "أسود سوس", "short": "ASD", "color": Color("22262e"), "color2": Color("d4af37"), "letter": "س", "strength": 75},
	{"name": "فارس المحيط", "short": "FAM", "color": Color("0f8f8f"), "color2": Color("084848"), "letter": "ف", "strength": 70},
	{"name": "شعلة الأطلس", "short": "CHA", "color": Color("e07b1f"), "color2": Color("7a4411"), "letter": "ش", "strength": 71},
]

var formations := {
	"2-2-1": [Vector2(-7, -6), Vector2(-7, 6), Vector2(-1, -5), Vector2(-1, 5), Vector2(5, 0)],
	"2-1-2": [Vector2(-7, -6), Vector2(-7, 6), Vector2(-2, 0), Vector2(3, -5), Vector2(3, 5)],
	"3-1-1": [Vector2(-8, -7), Vector2(-8, 0), Vector2(-8, 7), Vector2(-2, 0), Vector2(5, 0)],
}

const FIRST_NAMES := ["أمين", "يوسف", "إلياس", "حمزة", "بدر", "زكرياء", "أنس", "وليد", "سفيان", "رشيد", "عادل", "هشام", "طارق", "نبيل", "فارس", "أيوب", "مهدي", "ياسين", "أكرم", "سليم", "رضا", "خليل", "مروان", "سامر"]
const LAST_NAMES := ["التازي", "العلوي", "الحسني", "البركاني", "الفاسي", "المراكشي", "أمزيان", "الزياني", "بوشتى", "الرامي", "بلقاضي", "السرغيني"]

const POSITIONS := ["حارس المرمى", "مدافع", "وسط ميدان", "مهاجم"]

# --------------------------------------------------------------- settings ----
var settings := {
	"sound": true,
	"music": false,          # no music exists in v1.0; option kept for completeness
	"graphics": "med",       # "low" | "med"
	"cam_sens": 1.0,
	"vibration": true,
	"reminder": true,        # Islamic reminder before gameplay
	"language": "ar",
}

# ---------------------------------------------------------------- career ----
var career: Dictionary = {}   # empty = no career yet

# ----------------------------------------------------------------- saves ----
func load_settings() -> void:
	var d = _read_json(SETTINGS_PATH)
	if d is Dictionary:
		for k in settings.keys():
			if d.has(k):
				settings[k] = d[k]
	emit_signal("settings_changed")

func save_settings() -> void:
	_write_json(SETTINGS_PATH, settings)
	emit_signal("settings_changed")

func reset_all_data() -> void:
	career = {}
	save_career()
	settings = {"sound": true, "music": false, "graphics": "med", "cam_sens": 1.0, "vibration": true, "reminder": true, "language": "ar"}
	save_settings()

func load_career() -> void:
	var d = _read_json(CAREER_PATH)
	if d is Dictionary and int(d.get("version", 0)) == SAVE_VERSION:
		career = d
	else:
		career = {}

func save_career() -> void:
	if career.is_empty():
		_delete_file(CAREER_PATH)
		return
	career["version"] = SAVE_VERSION
	_write_json(CAREER_PATH, career)
	emit_signal("career_changed")

func has_career() -> bool:
	return not career.is_empty()

func create_career(p_name: String, number: int, position: String, club_idx: int) -> void:
	var base := 62
	var attrs := {
		"pace": base + 8, "shoot": base + 8, "pass": base + 8,
		"dribble": base + 8, "defend": base + 4, "stamina": base + 10,
	}
	match position:
		"حارس المرمى":
			attrs = {"pace": 55, "shoot": 40, "pass": 55, "dribble": 45, "defend": 75, "stamina": 60}
		"مدافع":
			attrs["defend"] = base + 14; attrs["shoot"] = base + 2
		"وسط ميدان":
			attrs["pass"] = base + 14; attrs["dribble"] = base + 10
		"مهاجم":
			attrs["shoot"] = base + 14; attrs["pace"] = base + 12
	career = {
		"version": SAVE_VERSION,
		"name": p_name.strip_edges(),
		"number": clampi(number, 1, 99),
		"position": position,
		"club": club_idx,
		"attrs": attrs,
		"xp": 0,
		"points": 0,
		"stats": {"apps": 0, "goals": 0, "assists": 0, "wins": 0, "losses": 0, "draws": 0, "rating_sum": 0.0, "best_rating": 0.0, "shots": 0},
	}
	save_career()

## stats: {result: "W"|"D"|"L", your_goals, your_shots, rating, scored, conceded}
func apply_career_match(stats: Dictionary) -> void:
	if career.is_empty():
		return
	var s: Dictionary = career["stats"]
	s["apps"] += 1
	s["goals"] += int(stats.get("your_goals", 0))
	s["shots"] += int(stats.get("your_shots", 0))
	s["rating_sum"] += float(stats.get("rating", 6.0))
	s["best_rating"] = maxf(float(s["best_rating"]), float(stats.get("rating", 6.0)))
	match String(stats.get("result", "D")):
		"W": s["wins"] += 1
		"L": s["losses"] += 1
		_: s["draws"] += 1
	var gained: int = int(15 + float(stats.get("rating", 6.0)) * 6 + int(stats.get("your_goals", 0)) * 12)
	career["xp"] = int(career["xp"]) + gained
	var new_points: int = int(career["xp"]) / XP_PER_POINT
	if new_points > int(career["points"]):
		career["points"] = new_points
	save_career()

func train_attribute(key: String) -> bool:
	if career.is_empty() or int(career["points"]) < 1:
		return false
	var attrs: Dictionary = career["attrs"]
	if int(attrs.get(key, 99)) >= 99:
		return false
	attrs[key] = int(attrs[key]) + 1
	career["points"] = int(career["points"]) - 1
	save_career()
	return true

func career_avg_rating() -> float:
	if career.is_empty():
		return 0.0
	var s: Dictionary = career["stats"]
	if int(s["apps"]) == 0:
		return 0.0
	return float(s["rating_sum"]) / float(s["apps"])

# ------------------------------------------------------------- utilities ----
func roster(club_idx: int) -> Array:
	## Returns 6 players: GK + 5 outfield, generated deterministic-ish per club.
	var c: Dictionary = clubs[club_idx]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + club_idx * 77
	var names: Array[String] = []
	var out: Array = []
	var strength: float = float(c["strength"])
	# goalkeeper
	var gk := {
		"name": FIRST_NAMES[rng.randi_range(0, FIRST_NAMES.size() - 1)] + " " + LAST_NAMES[rng.randi_range(0, LAST_NAMES.size() - 1)],
		"number": 1, "pos": "GK", "attrs": _mk_attrs(rng, strength, true),
	}
	out.append(gk)
	var nums := [2, 3, 4, 5, 6, 7, 8, 10, 11, 14]
	nums.shuffle()
	var poses := ["DF", "DF", "MF", "MF", "FW"]
	for i in range(5):
		var nm: String
		while true:
			nm = FIRST_NAMES[rng.randi_range(0, FIRST_NAMES.size() - 1)] + " " + LAST_NAMES[rng.randi_range(0, LAST_NAMES.size() - 1)]
			if not names.has(nm):
				break
		names.append(nm)
		out.append({
			"name": nm, "number": nums[i],
			"pos": poses[i], "attrs": _mk_attrs(rng, strength, false),
		})
	return out

func _mk_attrs(rng: RandomNumberGenerator, strength: float, gk: bool) -> Dictionary:
	var j := func() -> int: return int(clampf(strength + rng.randf_range(-12, 12), 35, 93))
	var a := {"pace": j.call(), "shoot": j.call(), "pass": j.call(), "dribble": j.call(), "defend": j.call(), "stamina": int(clampf(strength + rng.randf_range(-5, 18), 45, 96))}
	if gk:
		a["defend"] = int(clampf(strength + 10, 50, 95)); a["shoot"] = 40
	return a

func formation_names() -> Array:
	return formations.keys()

func formation_slots(name: String) -> Array:
	return formations.get(name, formations["2-2-1"])

# ------------------------------------------------------------ file utils ----
func _read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed

func _write_json(path: String, data) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("SLING LEGACY: cannot write " + path)
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()

func _delete_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

func _ready() -> void:
	load_settings()
	load_career()
