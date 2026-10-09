extends Control
## SLING LEGACY — screen manager & Arabic RTL UI.
## Builds every screen in code so the project stays light and inspectable.

signal ui_back

const NAVY := Color("0e1a2b")
const PANEL := Color("14263d")
const PANEL2 := Color("1a3050")
const EMER := Color("1fbf6b")
const GOLD := Color("d4af37")
const WHITE := Color("f5f7fa")
const GREY := Color("8fa3bd")
const RED := Color("c0392b")

const ATTR_LABELS := {
	"pace": "السرعة", "shoot": "التسديد", "pass": "التمرير",
	"dribble": "المراوغة", "defend": "الدفاع", "stamina": "التحمل",
}

var nav: Array = []
var current: Node = null
var current_match: Node = null
var flow := {"mode": "friendly", "home": 0, "away": 1, "formation": "2-2-1", "minutes": 4.0}
var font_bold: Font
var font_reg: Font
var tex_menu_bg: Texture2D
var tex_splash_bg: Texture2D

# ---------------------------------------------------------------- badges ----
class Badge extends Control:
	var color := Color.WHITE
	var color2 := Color.BLACK
	var letter := "؟"
	var _f: Font
	func _ready() -> void:
		custom_minimum_size = Vector2(64, 64)
		_f = ThemeDB.fallback_font
	func _draw() -> void:
		var r: float = min(size.x, size.y) / 2.0
		var c: Vector2 = size / 2.0
		draw_circle(c, r, color)
		draw_arc(c, r - 2, 0, TAU, 32, color2, 3.0)
		draw_arc(c, r * 0.62, 0, TAU, 32, color2, 2.0)
		draw_string(_f, c + Vector2(-r * 0.32, r * 0.36), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, int(r * 1.05), color2)

# ----------------------------------------------------------------- ready ----
func _ready() -> void:
	layout_direction = Control.LAYOUT_DIRECTION_RTL
	text_direction = Control.TEXT_DIRECTION_RTL
	font_bold = load("res://assets/fonts/NotoNaskhArabic-Bold.ttf")
	font_reg = load("res://assets/fonts/NotoSansArabicUI-Regular.ttf")
	tex_menu_bg = load("res://assets/textures/menu_bg.png")
	tex_splash_bg = load("res://assets/textures/splash_bg.png")
	_apply_theme()
	_ensure_input_map()
	nav.clear()
	go("splash")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if current_match:
			return  # match handles its own pause
		back()

func _apply_theme() -> void:
	var t := Theme.new()
	t.default_font = font_reg
	t.default_font_size = 24
	var sb_n := StyleBoxFlat.new()
	sb_n.bg_color = PANEL2
	sb_n.set_corner_radius_all(14)
	sb_n.content_margin_left = 18
	sb_n.content_margin_right = 18
	sb_n.content_margin_top = 8
	sb_n.content_margin_bottom = 8
	var sb_h := sb_n.duplicate() as StyleBoxFlat
	sb_h.bg_color = PANEL2.lightened(0.12)
	var sb_p := sb_n.duplicate() as StyleBoxFlat
	sb_p.bg_color = EMER.darkened(0.15)
	for st in ["normal", "hover", "pressed", "focus"]:
		match st:
			"normal": t.set_stylebox(st, "Button", sb_n)
			"hover": t.set_stylebox(st, "Button", sb_h)
			"pressed": t.set_stylebox(st, "Button", sb_p)
			"focus": t.set_stylebox(st, "Button", sb_n)
	t.set_color("font_color", "Button", WHITE)
	t.set_color("font_hover_color", "Button", WHITE)
	t.set_color("font_pressed_color", "Button", WHITE)
	t.set_color("font_disabled_color", "Button", GREY)
	var pnl := StyleBoxFlat.new()
	pnl.bg_color = PANEL
	pnl.set_corner_radius_all(20)
	pnl.content_margin_left = 24
	pnl.content_margin_right = 24
	pnl.content_margin_top = 20
	pnl.content_margin_bottom = 20
	t.set_stylebox("panel", "PanelContainer", pnl)
	theme = t

func _ensure_input_map() -> void:
	_add_key("mv_up", [KEY_W, KEY_UP])
	_add_key("mv_down", [KEY_S, KEY_DOWN])
	_add_key("mv_left", [KEY_A, KEY_LEFT])
	_add_key("mv_right", [KEY_D, KEY_RIGHT])
	_add_key("act_pass", [KEY_J])
	_add_key("act_shoot", [KEY_K])
	_add_key("act_sprint", [KEY_L])
	_add_key("act_switch", [KEY_SPACE])
	_add_key("act_move", [KEY_U])
	_add_key("act_pause", [KEY_ESCAPE, KEY_P])

func _add_key(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.keycode = k
		if not InputMap.action_has_event(action, ev):
			InputMap.action_add_event(action, ev)

# ------------------------------------------------------------- navigation ----
func _show(n: Node) -> void:
	if current and is_instance_valid(current):
		current.queue_free()
	current = n
	add_child(n)

func go(name: String, args := {}) -> void:
	nav.append({"name": name, "args": args})
	_open(name, args)

func back() -> void:
	if nav.size() > 1:
		nav.pop_back()
		var e: Dictionary = nav[nav.size() - 1]
		_open(e["name"], e["args"])
	else:
		nav.clear()
		go("menu")

func _open(name: String, args: Dictionary) -> void:
	match name:
		"splash": _show(_scr_splash())
		"menu": _show(_scr_menu())
		"playmode": _show(_scr_playmode())
		"friends": _show(_scr_friends())
		"teamsel": _show(_scr_teamsel(args))
		"formation": _show(_scr_formation())
		"teams": _show(_scr_teams())
		"career": _show(_scr_career())
		"training": _show(_scr_training())
		"stats": _show(_scr_stats())
		"settings": _show(_scr_settings())
		"about": _show(_scr_about())
		"results": _show(_scr_results(args))

# -------------------------------------------------------------- builders ----
func _lbl(text: String, size := 24, color := WHITE, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_font_override("font", font_bold)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.text_direction = Control.TEXT_DIRECTION_RTL
	return l

func _btn(text: String, cb: Callable, h := 62, w := 0, disabled := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, h)
	b.add_theme_font_size_override("font_size", 25)
	if bold_font_hack:
		b.add_theme_font_override("font", font_bold)
	b.disabled = disabled
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b

var bold_font_hack := true

func _bg(texture: Texture2D) -> TextureRect:
	var t := TextureRect.new()
	t.texture = texture
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	t.set_anchors_preset(Control.PRESET_FULL_RECT)
	return t

func _panel_root(inner: Control, darken := true) -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.layout_direction = Control.LAYOUT_DIRECTION_RTL
	root.text_direction = Control.TEXT_DIRECTION_RTL
	root.add_child(_bg(tex_menu_bg))
	if darken:
		var dim := ColorRect.new()
		dim.color = Color(0.02, 0.04, 0.08, 0.45)
		dim.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	root.add_child(margin)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	margin.add_child(panel)
	panel.add_child(inner)
	return root

var _cached_panel: StyleBoxFlat = null
func _panel_style() -> StyleBoxFlat:
	if _cached_panel == null:
		var p := StyleBoxFlat.new()
		p.bg_color = Color(PANEL, 0.94)
		p.set_corner_radius_all(22)
		p.content_margin_left = 28
		p.content_margin_right = 28
		p.content_margin_top = 24
		p.content_margin_bottom = 24
		_cached_panel = p
	return _cached_panel

func _back_bar(title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var b := _btn("→ رجوع", back, 46, 140)
	row.add_child(b)
	var l := _lbl(title, 34, WHITE, true)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	return row

# --------------------------------------------------------------- screens ----
func _scr_splash() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_bg(tex_splash_bg))
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 26)
	center.add_child(col)
	var logo := TextureRect.new()
	logo.texture = load("res://assets/textures/logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	logo.custom_minimum_size = Vector2(520, 240)
	col.add_child(logo)
	col.add_child(_lbl("A Real Football Career", 26, GREY))
	var p := ProgressBar.new()
	p.custom_minimum_size = Vector2(420, 18)
	p.show_percentage = false
	col.add_child(p)
	var st := _lbl("جاري التحميل...", 22, GREY)
	col.add_child(st)
	col.add_child(_lbl("v1.0 • تطوير: Maelainin Assari", 20, GREY))
	_splash_tick(p)
	return root

func _splash_tick(p: ProgressBar) -> void:
	for i in range(10):
		await get_tree().create_timer(0.14).timeout
		p.value = (i + 1) * 10
	if nav.size() == 1 and nav[0]["name"] == "splash":
		go("menu")

func _scr_menu() -> Control:
	var inner := VBoxContainer.new()
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.add_theme_constant_override("separation", 12)
	var logo := TextureRect.new()
	logo.texture = load("res://assets/textures/logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	logo.custom_minimum_size = Vector2(430, 190)
	inner.add_child(logo)
	inner.add_child(_lbl("6 ضد 6 • مسيرة كروية حقيقية", 24, GOLD, true))
	inner.add_child(_lbl("الملعب الكبير — دوار اللوح", 20, GREY))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	inner.add_child(spacer)
	var items := [
		["العب", _on_menu_play, false],
		["المسيرة المهنية", func(): go("career"), false],
		["اللعب مع الأصدقاء", func(): go("friends"), false],
		["الفرق", func(): go("teams"), false],
		["التدريب", func(): go("training"), DB.settings.get("graphics", "med") == "" and not DB.has_career()],
		["الإحصائيات", func(): go("stats"), false],
		["الإعدادات", func(): go("settings"), false],
		["عن اللعبة", func(): go("about"), false],
	]
	for it in items:
		var b := _btn(it[0], it[1], 58, 430, it[2])
		inner.add_child(b)
	var foot := _lbl("v1.0 • صنع بحب من طرف Maelainin Assari", 18, GREY)
	inner.add_child(foot)
	return _panel_root(inner)

func _on_menu_play() -> void:
	if DB.has_career():
		go("playmode")
	else:
		go("playmode")

func _scr_playmode() -> Control:
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 14)
	inner.add_child(_back_bar("اختر نمط اللعب"))
	var cb_friendly := func():
		flow["mode"] = "friendly"
		go("teamsel", {"step": "home"})
	var cb_career_match := func():
		if not DB.has_career():
			go("career")
		else:
			flow["mode"] = "career"
			flow["home"] = int(DB.career["club"])
			go("formation")
	var cb_2p := func():
		flow["mode"] = "2p"
		go("teamsel", {"step": "home"})
	inner.add_child(_btn("مباراة ودية — ضد الكمبيوتر", cb_friendly))
	inner.add_child(_btn("مباراة المسيرة — مع لاعبك", cb_career_match, 66))
	inner.add_child(_btn("ضد صديق — على نفس الجهاز", cb_2p, 66))
	inner.add_child(_lbl("نصيحة: فعّل التذكير قبل اللعب من الإعدادات.", 19, GREY))
	return _panel_root(inner)

func _scr_friends() -> Control:
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 14)
	inner.add_child(_back_bar("اللعب مع الأصدقاء"))
	inner.add_child(_lbl("عبر الإنترنت", 26, GOLD, true))
	var note := _lbl("اللعب عبر الإنترنت قادم في تحديث قادم. يتطلب خادماً مخصصاً وسيُنفذ دون إعادة كتابة اللعبة (بنية جاهزة للشبكة).", 20, GREY)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	note.custom_minimum_size = Vector2(560, 0)
	inner.add_child(note)
	var cb_room := func(): pass
	inner.add_child(_btn("إنشاء غرفة", cb_room, 58, 0, true))
	inner.add_child(_btn("الانضمام برمز", cb_room, 58, 0, true))
	inner.add_child(_lbl("محلياً", 26, GOLD, true))
	var cb_local := func():
		flow["mode"] = "2p"
		go("teamsel", {"step": "home"})
	inner.add_child(_btn("ضد صديق — نفس الجهاز (تجريبي)", cb_local, 62))
	return _panel_root(inner)

func _scr_teamsel(args: Dictionary) -> Control:
	var step := String(args.get("step", "home"))
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 12)
	inner.add_child(_back_bar("اختر فريقك" if step == "home" else "اختر الفريق المنافس"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	var cards: Array = []
	for i in range(DB.clubs.size()):
		var c: Dictionary = DB.clubs[i]
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(230, 150)
		var p := StyleBoxFlat.new()
		p.bg_color = PANEL2
		p.set_corner_radius_all(16)
		card.add_theme_stylebox_override("panel", p)
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", 4)
		var badge := Badge.new()
		badge.color = c["color"]
		badge.color2 = c["color2"]
		badge.letter = c["letter"]
		badge.custom_minimum_size = Vector2(56, 56)
		col.add_child(badge)
		col.add_child(_lbl(c["name"], 21, WHITE, true))
		col.add_child(_lbl("القوة: %d" % int(c["strength"]), 17, GREY))
		card.add_child(col)
		var idx := i
		var cb_card := func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_select_club(step, idx, cards)
		card.gui_input.connect(cb_card)
		grid.add_child(card)
		cards.append(card)
		# pre-select
		if (step == "home" and int(flow["home"]) == i) or (step == "away" and int(flow["away"]) == i):
			_highlight_card(card, true)
	inner.add_child(grid)
	if step == "away" or flow["mode"] == "2p":
		var cb_next := func():
			if flow["mode"] == "2p":
				flow["formation"] = "2-2-1"
				_with_reminder(_start_match)
			else:
				go("formation")
		inner.add_child(_btn("متابعة", cb_next, 60, 300))
	return _panel_root(inner)

func _select_club(step: String, idx: int, cards: Array) -> void:
	if step == "home":
		flow["home"] = idx
	else:
		flow["away"] = idx
	for i in range(cards.size()):
		_highlight_card(cards[i], i == idx)
	if step == "home" and flow["mode"] != "2p":
		go("teamsel", {"step": "away"})
	elif step == "home" and flow["mode"] == "2p":
		go("teamsel", {"step": "away"})

func _highlight_card(card: PanelContainer, on: bool) -> void:
	var p := StyleBoxFlat.new()
	p.bg_color = EMER.darkened(0.25) if on else PANEL2
	p.set_corner_radius_all(16)
	if on:
		p.border_color = EMER
		p.set_border_width_all(3)
	card.add_theme_stylebox_override("panel", p)

func _scr_formation() -> Control:
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 12)
	inner.add_child(_back_bar("اختر الخطة"))
	var names := DB.formation_names()
	var cards: Array = []
	for fn in names:
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(220, 130)
		var p := StyleBoxFlat.new()
		p.bg_color = PANEL2
		p.set_corner_radius_all(16)
		card.add_theme_stylebox_override("panel", p)
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_child(_lbl(fn, 30, WHITE, true))
		col.add_child(_lbl("5 لاعبين ميدانيين", 17, GREY))
		card.add_child(col)
		var cb_pick := func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				flow["formation"] = fn
				for k in range(cards.size()):
					_highlight_card(cards[k], k == cards.find(card))
		card.gui_input.connect(cb_pick)
		inner.add_child(card)
		cards.append(card)
		if flow["formation"] == fn:
			_highlight_card(card, true)
	inner.add_child(_lbl("مدة المباراة", 22, GOLD, true))
	var minutes := HBoxContainer.new()
	minutes.alignment = BoxContainer.ALIGNMENT_CENTER
	for m in [2, 4, 6]:
		var cb_min := func():
			flow["minutes"] = float(m)
			for k in range(minutes.get_child_count()):
				(minutes.get_child(k) as Button).add_theme_color_override("font_color", GOLD if k == [2, 4, 6].find(m) else WHITE)
		var mb := _btn("%d دقائق" % m, cb_min, 50, 150)
		if float(m) == float(flow["minutes"]):
			mb.add_theme_color_override("font_color", GOLD)
		minutes.add_child(mb)
	inner.add_child(minutes)
	inner.add_child(_btn("ابدأ المباراة", func(): _with_reminder(_start_match), 66, 320))
	return _panel_root(inner)

func _scr_teams() -> Control:
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	inner.add_child(_back_bar("الفرق"))
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(880, 430)
	tabs.add_theme_font_size_override("font_size", 20)
	for i in range(DB.clubs.size()):
		var c: Dictionary = DB.clubs[i]
		var sc := ScrollContainer.new()
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 4)
		var head := HBoxContainer.new()
		var badge := Badge.new()
		badge.color = c["color"]
		badge.color2 = c["color2"]
		badge.letter = c["letter"]
		badge.custom_minimum_size = Vector2(52, 52)
		head.add_child(badge)
		head.add_child(_lbl("%s — القوة %d" % [c["name"], int(c["strength"])], 24, WHITE, true))
		col.add_child(head)
		for p in DB.roster(i):
			var avg: int = _avg_attrs(p["attrs"])
			col.add_child(_lbl("#%d  %s  (%s) — متوسط %d" % [int(p["number"]), p["name"], _pos_name(p["pos"]), avg], 21))
		sc.add_child(col)
		tabs.add_child(sc)
		tabs.set_tab_title(i, c["short"])
	inner.add_child(tabs)
	return _panel_root(inner)

func _pos_name(p: String) -> String:
	match p:
		"GK": return "حارس"
		"DF": return "مدافع"
		"MF": return "وسط"
		"FW": return "مهاجم"
	return p

func _avg_attrs(a: Dictionary) -> int:
	var s := 0
	for k in a.keys():
		s += int(a[k])
	return s / a.size()

# ---------------------------------------------------------------- career ----
func _scr_career() -> Control:
	if not DB.has_career():
		return _scr_career_new()
	var c: Dictionary = DB.career
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	inner.add_child(_back_bar("المسيرة المهنية"))
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 18)
	var badge := Badge.new()
	var club: Dictionary = DB.clubs[int(c["club"])]
	badge.color = club["color"]
	badge.color2 = club["color2"]
	badge.letter = club["letter"]
	badge.custom_minimum_size = Vector2(84, 84)
	top.add_child(badge)
	var info := VBoxContainer.new()
	info.add_child(_lbl(c["name"], 30, WHITE, true))
	info.add_child(_lbl("النادي: %s  •  المركز: %s  •  الرقم: %d" % [club["name"], c["position"], int(c["number"])], 21, GREY))
	info.add_child(_lbl("النقاط المتاحة للتدريب: %d  •  الخبرة: %d" % [int(c["points"]), int(c["xp"])], 21, GOLD))
	top.add_child(info)
	inner.add_child(top)
	var s: Dictionary = c["stats"]
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 30)
	for kv in [["المباريات", s["apps"]], ["الأهداف", s["goals"]], ["صناعة الأهداف", s["assists"]], ["التقييم", "%.1f" % DB.career_avg_rating()], ["فوز", s["wins"]], ["تعادل", s["draws"]], ["خسارة", s["losses"]], ["أفضل تقييم", "%.1f" % float(s["best_rating"])] ]:
		var cell := VBoxContainer.new()
		cell.add_child(_lbl(str(kv[1]), 30, EMER, true))
		cell.add_child(_lbl(str(kv[0]), 18, GREY))
		grid.add_child(cell)
	inner.add_child(grid)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	var cb_play := func():
		flow["mode"] = "career"
		flow["home"] = int(c["club"])
		go("formation")
	var cb_train := func(): go("training")
	var cb_del := func():
		_confirm("هل أنت متأكد من حذف المسيرة؟ لا يمكن التراجع.", func():
			DB.career = {}
			DB.save_career()
			back()
		)
	row.add_child(_btn("لعب مباراة مسيرة", cb_play, 58, 250))
	row.add_child(_btn("التدريبات", cb_train, 58, 200))
	row.add_child(_btn("حذف المسيرة", cb_del, 58, 200))
	inner.add_child(row)
	return _panel_root(inner)

func _scr_career_new() -> Control:
	var inner := VBoxContainer.new()
	inner.custom_minimum_size = Vector2(560, 0)
	inner.add_theme_constant_override("separation", 12)
	inner.add_child(_back_bar("إنشاء مسيرة جديدة"))
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "اسم اللاعب"
	name_edit.custom_minimum_size = Vector2(0, 54)
	name_edit.add_theme_font_size_override("font_size", 24)
	inner.add_child(name_edit)
	var row := HBoxContainer.new()
	var num := SpinBox.new()
	num.min_value = 1
	num.max_value = 99
	num.value = 9
	num.custom_minimum_size = Vector2(120, 54)
	num.add_theme_font_size_override("font_size", 24)
	row.add_child(_lbl("الرقم:", 22))
	row.add_child(num)
	var pos := OptionButton.new()
	for p in DB.POSITIONS:
		pos.add_item(p)
	pos.custom_minimum_size = Vector2(190, 54)
	pos.add_theme_font_size_override("font_size", 22)
	row.add_child(_lbl("المركز:", 22))
	row.add_child(pos)
	row.add_child(_lbl("النادي:", 22))
	inner.add_child(row)
	var club_sel := OptionButton.new()
	for cl in DB.clubs:
		club_sel.add_item(cl["name"])
	club_sel.custom_minimum_size = Vector2(0, 54)
	club_sel.add_theme_font_size_override("font_size", 22)
	inner.add_child(club_sel)
	var cb_create := func():
		var nm: String = name_edit.text.strip_edges()
		if nm.is_empty():
			nm = "لاعب دوار اللوح"
		DB.create_career(nm, int(num.value), DB.POSITIONS[pos.selected], club_sel.selected)
		back()
	inner.add_child(_btn("إنشاء المسيرة", cb_create, 62))
	return _panel_root(inner)

func _scr_training() -> Control:
	var inner := VBoxContainer.new()
	inner.custom_minimum_size = Vector2(600, 0)
	inner.add_theme_constant_override("separation", 10)
	inner.add_child(_back_bar("التدريب"))
	if not DB.has_career():
		inner.add_child(_lbl("أنشئ مسيرة مهنية أولاً من قائمة المسيرة.", 22, GREY))
		inner.add_child(_btn("إنشاء مسيرة", func(): go("career"), 56, 260))
		return _panel_root(inner)
	var c: Dictionary = DB.career
	inner.add_child(_lbl("%s — النقاط المتاحة: %d" % [c["name"], int(c["points"])], 24, GOLD, true))
	for key in ATTR_LABELS.keys():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.add_child(_lbl(ATTR_LABELS[key], 22))
		var bar := ProgressBar.new()
		bar.max_value = 99
		bar.value = int(c["attrs"][key])
		bar.show_percentage = false
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(bar)
		row.add_child(_lbl(str(int(c["attrs"][key])), 22, EMER, true))
		var cb_plus := func():
			if DB.train_attribute(key):
				_refresh_current()
		var plus := _btn("+", cb_plus, 46, 52, int(c["points"]) < 1 or int(c["attrs"][key]) >= 99)
		row.add_child(plus)
		inner.add_child(row)
	inner.add_child(_lbl("كل نقطة تدريب تكلف %d نقطة خبرة (تُكسب من المباريات)." % DB.XP_PER_POINT, 18, GREY))
	return _panel_root(inner)

func _refresh_current() -> void:
	if nav.is_empty():
		return
	var e: Dictionary = nav[nav.size() - 1]
	_open(e["name"], e["args"])

func _scr_stats() -> Control:
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	inner.add_child(_back_bar("الإحصائيات"))
	if not DB.has_career():
		inner.add_child(_lbl("لا توجد إحصائيات بعد. أنشئ مسيرة وابدأ اللعب.", 22, GREY))
	else:
		var c: Dictionary = DB.career
		var s: Dictionary = c["stats"]
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 40)
		for kv in [["المباريات", s["apps"]], ["الأهداف", s["goals"]], ["التسديدات", s["shots"]], ["الفوز", s["wins"]], ["التعادل", s["draws"]], ["الخسارة", s["losses"]], ["متوسط التقييم", "%.2f" % DB.career_avg_rating()], ["الخبرة", c["xp"]], ["نقاط التدريب", c["points"]]]:
			var cell := VBoxContainer.new()
			cell.add_child(_lbl(str(kv[1]), 32, EMER, true))
			cell.add_child(_lbl(str(kv[0]), 19, GREY))
			grid.add_child(cell)
		inner.add_child(grid)
	return _panel_root(inner)

func _scr_settings() -> Control:
	var inner := VBoxContainer.new()
	inner.custom_minimum_size = Vector2(620, 0)
	inner.add_theme_constant_override("separation", 10)
	inner.add_child(_back_bar("الإعدادات"))
	var s: Dictionary = DB.settings
	inner.add_child(_check("تفعيل التذكير قبل اللعب («لا تلهك الألعاب عن الصلاة وذكر الله»)", s["reminder"], func(v): s["reminder"] = v; DB.save_settings()))
	inner.add_child(_check("المؤثرات الصوتية", s["sound"], func(v): s["sound"] = v; DB.save_settings()))
	inner.add_child(_check("الاهتزاز", s["vibration"], func(v): s["vibration"] = v; DB.save_settings()))
	var cb_mus := func(_v):
		s["music"] = false
		DB.save_settings()
	var mus := _check("الموسيقى (غير متوفرة في هذا الإصدار)", s["music"], cb_mus)
	mus.disabled = true
	inner.add_child(mus)
	var g := OptionButton.new()
	g.add_item("منخفضة")
	g.add_item("متوسطة")
	g.selected = 1 if s["graphics"] == "med" else 0
	g.add_theme_font_size_override("font_size", 22)
	g.item_selected.connect(func(i): s["graphics"] = "med" if i == 1 else "low"; DB.save_settings())
	var grow := HBoxContainer.new()
	grow.add_child(_lbl("الرسومات:", 22))
	grow.add_child(g)
	inner.add_child(grow)
	var sens := HSlider.new()
	sens.min_value = 0.4
	sens.max_value = 2.0
	sens.step = 0.1
	sens.value = float(s["cam_sens"])
	sens.custom_minimum_size = Vector2(260, 40)
	sens.value_changed.connect(func(v): s["cam_sens"] = v; DB.save_settings())
	var srow := HBoxContainer.new()
	srow.add_child(_lbl("حساسية الكاميرا:", 22))
	srow.add_child(sens)
	inner.add_child(srow)
	var lang := HBoxContainer.new()
	lang.add_child(_lbl("اللغة: العربية (افتراضي)", 22))
	inner.add_child(lang)
	var cb_do_reset := func():
		DB.reset_all_data()
		_refresh_current()
	var cb_reset := func():
		_confirm("سيتم حذف المسيرة والإعدادات نهائياً. متابعة؟", cb_do_reset)
	inner.add_child(_btn("إعادة تعيين كل البيانات", cb_reset, 56, 320))
	return _panel_root(inner)

func _check(text: String, val: bool, cb: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = val
	c.add_theme_font_size_override("font_size", 21)
	c.toggled.connect(cb)
	return c

func _scr_about() -> Control:
	var inner := VBoxContainer.new()
	inner.custom_minimum_size = Vector2(620, 0)
	inner.add_theme_constant_override("separation", 10)
	inner.add_child(_back_bar("عن اللعبة"))
	var logo := TextureRect.new()
	logo.texture = load("res://assets/textures/logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	logo.custom_minimum_size = Vector2(340, 150)
	inner.add_child(logo)
	for line in [
		"SLING LEGACY — A Real Football Career",
		"الإصدار 1.0",
		"التطوير: Maelainin Assari",
		"المحرك: Godot Engine 4.2 (وضع التوافق للأجهزة الضعيفة)",
		"الملعب الرئيسي: الملعب الكبير — دوار اللوح",
		"جميع الأندية والشعارات واللاعبين خياليون بالكامل.",
		"لا توجد إعلانات ولا مشتريات ولا موسيقى.",
		"الترخيص: MIT — رخصة مفتوحة المصدر.",
	]:
		inner.add_child(_lbl(line, 21, WHITE if line.find("Maelainin") == -1 else GOLD))
	inner.add_child(_lbl("لا تلهك الألعاب عن الصلاة وذكر الله.", 22, EMER, true))
	return _panel_root(inner)

func _scr_results(args: Dictionary) -> Control:
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 12)
	inner.add_child(_lbl("نتيجة المباراة", 32, WHITE, true))
	var home: Dictionary = DB.clubs[int(flow["home"])]
	var away: Dictionary = DB.clubs[int(flow["away"])]
	inner.add_child(_lbl("%s   %d - %d   %s" % [home["short"], int(args.get("scored", 0)), int(args.get("conceded", 0)), away["short"]], 44, EMER, true))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 60)
	for kv in args.get("rows", []):
		grid.add_child(_lbl(str(kv[0]), 21, GREY))
		grid.add_child(_lbl(str(kv[1]), 22, WHITE, true))
	inner.add_child(grid)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	var cb_re := func(): _with_reminder(_start_match)
	var cb_menu := func():
		nav.clear()
		go("menu")
	row.add_child(_btn("إعادة المباراة", cb_re, 58, 220))
	row.add_child(_btn("القائمة الرئيسية", cb_menu, 58, 220))
	inner.add_child(row)
	return _panel_root(inner)

# ------------------------------------------------------------- reminder -----
func _with_reminder(cb: Callable) -> void:
	if not DB.settings.get("reminder", true):
		cb.call()
		return
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	panel.add_theme_stylebox_override("panel", _panel_style())
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.add_child(_lbl("تذكير", 28, GOLD, true))
	col.add_child(_lbl("✦", 26, GOLD))
	var msg := _lbl("لا تلهك الألعاب عن الصلاة وذكر الله.", 26, WHITE, true)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD
	msg.custom_minimum_size = Vector2(440, 0)
	col.add_child(msg)
	var chk := CheckBox.new()
	chk.text = "تفعيل التذكير قبل اللعب"
	chk.button_pressed = true
	chk.add_theme_font_size_override("font_size", 20)
	col.add_child(chk)
	var cb_ok := func():
		DB.settings["reminder"] = chk.button_pressed
		DB.save_settings()
		layer.queue_free()
		cb.call()
	col.add_child(_btn("حسناً", cb_ok, 56, 200))
	panel.add_child(col)
	center.add_child(panel)
	add_child(layer)

func _confirm(text: String, cb: Callable) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "تأكيد"
	dlg.ok_button_text = "نعم"
	dlg.cancel_button_text = "إلغاء"
	dlg.add_theme_font_size_override("font_size", 22)
	var l := _lbl(text, 22)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size = Vector2(420, 0)
	dlg.add_child(l)
	dlg.confirmed.connect(func():
		dlg.queue_free()
		cb.call()
	)
	dlg.canceled.connect(func(): dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered()

# ----------------------------------------------------------------- match ----
func _start_match() -> void:
	if flow["mode"] == "career" and DB.has_career():
		var others: Array = []
		for i in range(DB.clubs.size()):
			if i != int(DB.career["club"]):
				others.append(i)
		others.shuffle()
		flow["away"] = others[0]
		flow["career"] = DB.career.duplicate(true)
	else:
		flow.erase("career")
	if flow["home"] == flow["away"]:
		flow["away"] = (int(flow["home"]) + 1) % DB.clubs.size()
	var m = preload("res://scripts/match.gd").new()
	m.cfg = flow.duplicate(true)
	m.match_finished.connect(_on_match_finished)
	if current and is_instance_valid(current):
		current.queue_free()
	current = m
	current_match = m
	add_child(m)

func _on_match_finished(stats: Dictionary) -> void:
	if is_instance_valid(current_match):
		current_match.queue_free()
	current_match = null
	current = null
	if bool(stats.get("restart", false)):
		_with_reminder(_start_match)
		return
	if bool(stats.get("career", false)) and not bool(stats.get("quit", false)):
		DB.apply_career_match(stats)
	nav.clear()
	go("results", stats)
