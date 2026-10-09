extends Node

# إعلان الإشارات الخاصة بالمشروع
signal career_changed
signal settings_changed

const SAVE_VERSION := 1
const SETTINGS_PATH := "user://settings.json"
const CAREER_PATH := "user://career.json"
const XP_PER_POINT := 50

var clubs := [
	{"name": "نجوم دوار اللوح", "short": "NDL", "color": Color("18a957"), "color2": Color("0d5c2e"), "letter": "ن", "strength": 70},
	{"name": "أطلس غرناطة", "short": "ATL", "color": Color("2456c9"), "color2": Color("122a66"), "letter": "أ", "strength": 74},
	{"name": "صقور الريف", "short": "SOQ", "color": Color("c92f2f"), "color2": Color("661616"), "letter": "ص", "strength": 72}
]

var settings := {
	"sfx": true,
	"music": true,
	"rtl": true
}

var career := {}

func _ready() -> void:
	load_settings()
	load_career()

func save_settings() -> void:
	var file = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(settings))

func load_settings() -> void:
	if FileAccess.file_exists(SETTINGS_PATH):
		var file = FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		if file:
			var json = JSON.new()
			if json.parse(file.get_as_text()) == OK:
				var data = json.get_data()
				if typeof(data) == TYPE_DICTIONARY:
					settings = data

func save_career() -> void:
	var file = FileAccess.open(CAREER_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(career))

func load_career() -> void:
	if FileAccess.file_exists(CAREER_PATH):
		var file = FileAccess.open(CAREER_PATH, FileAccess.READ)
		if file:
			var json = JSON.new()
			if json.parse(file.get_as_text()) == OK:
				var data = json.get_data()
				if typeof(data) == TYPE_DICTIONARY:
					career = data
