extends SceneTree
## Headless smoke test. Run with:
##   godot --headless -s tests/smoke_test.gd
## Verifies data integrity, save/load roundtrips and script loading.

var failures := 0

func _init() -> void:
	print("== SLING LEGACY smoke test ==")
	var db = load("res://scripts/data.gd").new()
	root.add_child(db)
	check(db.clubs.size() >= 4, "at least 4 fictional clubs exist")
	check(db.clubs.size() == 6, "6 clubs defined")
	for i in range(db.clubs.size()):
		var r: Array = db.roster(i)
		check(r.size() == 6, "club %d has a 6-player roster" % i)
		check(int(r[0]["number"]) == 1 and r[0]["pos"] == "GK", "club %d roster starts with a goalkeeper" % i)
	check(db.formation_names().size() >= 3, "at least 3 formations available")
	for fn in db.formation_names():
		check(db.formation_slots(fn).size() == 5, "formation %s has 5 outfield slots" % fn)
	# career roundtrip (memory)
	db.create_career("اختبار", 9, "مهاجم", 0)
	db.apply_career_match({"result": "W", "your_goals": 2, "your_shots": 4, "rating": 8.0})
	check(int(db.career["stats"]["goals"]) == 2, "career goals are tracked")
	check(int(db.career["stats"]["apps"]) == 1, "career appearances are tracked")
	check(int(db.career["xp"]) > 0, "career XP is granted")
	# training
	var before: int = int(db.career["attrs"]["shoot"])
	var trained: bool = db.train_attribute("shoot")
	check((not trained) or int(db.career["attrs"]["shoot"]) == before + 1, "training raises an attribute")
	# settings roundtrip (disk)
	db.save_settings()
	var db2 = load("res://scripts/data.gd").new()
	root.add_child(db2)
	db2.load_settings()
	check(db2.settings.has("sound") and db2.settings.has("reminder"), "settings persist and load")
	# scripts load
	check(load("res://scripts/match.gd") != null, "match.gd loads")
	check(load("res://scripts/main.gd") != null, "main.gd loads")
	if failures == 0:
		print("SMOKE TEST: ALL PASSED")
		quit(0)
	else:
		print("SMOKE TEST: %d FAILURE(S)" % failures)
		quit(1)

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS: " + msg)
	else:
		print("  FAIL: " + msg)
		failures += 1
