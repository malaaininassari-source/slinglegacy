extends Node

func _ready() -> void:
	if DB.has_signal("career_changed"):
		DB.career_changed.connect(_on_career_changed)
	if DB.has_signal("settings_changed"):
		DB.settings_changed.connect(_on_settings_changed)

func _on_career_changed() -> void:
	pass

func _on_settings_changed() -> void:
	pass
