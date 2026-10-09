extends Node3D
## SLING LEGACY — 3D 6v6 match: world, players (faceless), ball physics,
## possession, passing/shooting, tackling, team AI, goalkeepers, camera, HUD.

signal match_finished(stats: Dictionary)

const PITCH_L := 40.0
const PITCH_W := 26.0
const GOAL_W := 6.0
const GOAL_H := 2.4
const HALF_L := PITCH_L / 2.0
const HALF_W := PITCH_W / 2.0
const BALL_R := 0.16
const WALK := 5.4

# ------------------------------------------------------------------ input ----
class Joystick extends Control:
	var radius := 90.0
	var value := Vector2.ZERO
	var _tid := -1
	func _ready() -> void:
		custom_minimum_size = Vector2(radius * 2.0, radius * 2.0)
	func _draw() -> void:
		var c: Vector2 = size / 2.0
		draw_circle(c, radius, Color(1, 1, 1, 0.09))
		draw_arc(c, radius, 0, TAU, 40, Color(1, 1, 1, 0.30), 2.0)
		draw_circle(c + value * radius * 0.55, radius * 0.42, Color(1, 1, 1, 0.32))
	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventScreenTouch:
			if ev.pressed and _tid == -1:
				_tid = ev.index
				_update_value(ev.position)
				accept_event()
			elif not ev.pressed and ev.index == _tid:
				_tid = -1
				value = Vector2.ZERO
				queue_redraw()
				accept_event()
		elif ev is InputEventScreenDrag and ev.index == _tid:
			_update_value(ev.position)
			accept_event()
	func _update_value(pos: Vector2) -> void:
		var off: Vector2 = pos - size / 2.0
		value = off / radius
		if value.length() > 1.0:
			value = value.normalized()
		queue_redraw()

class MiniMap extends Control:
	var m: Node = null
	const PL := 40.0
	const PW := 26.0
	func _process(_d: float) -> void:
		queue_redraw()
	func _draw() -> void:
		if m == null or not is_instance_valid(m):
			return
		var w: float = size.x
		var h: float = size.y
		var sx: float = w / (PL + 8.0)
		var sz: float = h / (PW + 8.0)
		var ox: float = (w - PL * sx) / 2.0
		var oz: float = (h - PW * sz) / 2.0
		draw_rect(Rect2(ox, oz, PL * sx, PW * sz), Color(0.04, 0.22, 0.10, 0.85), true)
		draw_rect(Rect2(ox, oz, PL * sx, PW * sz), Color(1, 1, 1, 0.25), false, 1.5)
		for t in range(2):
			for s in range(6):
				var p: Node3D = m.pl[t][s]
				if p == null:
					continue
				var gp: Vector3 = p.global_position
				var pos := Vector2(ox + (gp.x + PL / 2.0) * sx, oz + (gp.z + PW / 2.0) * sz)
				var c: Color = Color("1fbf6b") if t == 0 else Color("d94545")
				if m._is_controlled(t, s):
					draw_circle(pos, 5.2, Color("d4af37"))
					draw_circle(pos, 3.4, c)
				else:
					draw_circle(pos, 3.2, c)
		var b: Node3D = m.ball
		if b != null:
			var gb: Vector3 = b.global_position
			draw_circle(Vector2(ox + (gb.x + PL / 2.0) * sx, oz + (gb.z + PW / 2.0) * sz), 2.6, Color.WHITE)

# ------------------------------------------------------------------ state ----
var cfg := {}

var human := [true, false]
var controlled := [1, 1]
var pl: Array = [[], []]          # CharacterBody3D per [team][slot]
var dat: Array = [[], []]         # data dict per [team][slot]
var vis: Array = [[], []]         # visual refs per [team][slot]
var ai_target: Array = [[], []]
var formation_slots := []
var rosters := []
var club := [{}, {}]

var ball: RigidBody3D
var ball_owner: Node3D = null
var last_touch: Node3D = null
var owner_grace := [0.0, 0.0]     # delay before AI acts on human team's ball

var state := "countdown"
var state_t := 0.0
var time_left := 240.0
var score := [0, 0]
var shots := [0, 0]
var touches := [0, 0]
var stamina := 100.0
var sprinting := false
var charge := -1.0                # shoot charge, <0 = not charging
var charge_team := 0
var switch_cd := [0.0, 0.0]
var tackle_cd := [0.0, 0.0]
var burst := [0.0, 0.0]
var gk_cd := [0.0, 0.0]
var ai_tick := 0.0
var carrier_tick := 0.0
var bounce_cd := 0.0

var your_goals := 0
var your_shots := 0
var your_touches := 0

var camera3d: Camera3D
var hud: CanvasLayer
var joy1: Joystick
var joy2: Joystick
var mini: MiniMap
var lb_score: Label
var lb_time: Label
var lb_center: Label
var lb_stamina: ProgressBar
var btn_act: Button
var paused := false
var tactical := false
var snd := {}

# ================================================================== ready ====
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	randomize()
	club[0] = DB.clubs[int(cfg.get("home", 0))]
	club[1] = DB.clubs[int(cfg.get("away", 1))]
	var fname := String(cfg.get("formation", "2-2-1"))
	formation_slots = DB.formation_slots(fname)
	var ai_formations := DB.formation_names()
	rosters = [DB.roster(int(cfg.get("home", 0))), DB.roster(int(cfg.get("away", 1)))]
	time_left = float(cfg.get("minutes", 4.0)) * 60.0
	human[1] = String(cfg.get("mode", "friendly")) == "2p"
	_build_world()
	_build_ball()
	_build_teams()
	_build_hud()
	_setup_kickoff(0)
	_play_snd("whistle")
	if DB.settings.get("vibration", false) and Input.has_method("vibrate_handheld"):
		Input.vibrate_handheld(80)

# ================================================================ world ======
func _mat(c: Color, tex: Texture2D = null) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if tex:
		m.albedo_texture = tex
		m.uv1_scale = Vector3(2.0, 1.4, 1.0)
	m.roughness = 0.95
	return m

func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

func _build_world() -> void:
	# environment: night stadium
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("0b1526")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("8899bb")
	e.ambient_light_energy = 0.55
	e.fog_enabled = true
	e.fog_light_color = Color("101c30")
	e.fog_density = 0.004
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -30, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = DB.settings.get("graphics", "med") == "med"
	sun.shadow_bias = 0.02
	add_child(sun)

	# ground
	var ground := StaticBody3D.new()
	var gcol := CollisionShape3D.new()
	var gbox := BoxShape3D.new()
	gbox.size = Vector3(60, 1, 44)
	gcol.shape = gbox
	gcol.position.y = -0.5
	ground.add_child(gcol)
	var gmesh := MeshInstance3D.new()
	var pmesh := PlaneMesh.new()
	pmesh.size = Vector2(60, 44)
	gmesh.mesh = pmesh
	gmesh.material_override = _mat(Color.WHITE, load("res://assets/textures/grass.png"))
	ground.add_child(gmesh)
	add_child(ground)

	var line := _mat(Color(0.93, 0.95, 0.97))
	var y := 0.015
	# boundary + halfway
	_box(Vector3(PITCH_L, 0.02, 0.12), Vector3(0, y, -HALF_W), line, self)
	_box(Vector3(PITCH_L, 0.02, 0.12), Vector3(0, y, HALF_W), line, self)
	_box(Vector3(0.12, 0.02, PITCH_W), Vector3(-HALF_L, y, 0), line, self)
	_box(Vector3(0.12, 0.02, PITCH_W), Vector3(HALF_L, y, 0), line, self)
	_box(Vector3(0.12, 0.02, PITCH_W), Vector3(0, y, 0), line, self)
	# center circle
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 3.55
	tm.outer_radius = 3.7
	ring.mesh = tm
	ring.material_override = line
	ring.rotation_degrees.x = 90
	ring.position.y = y
	add_child(ring)
	# penalty areas (9 x 5.5m boxes at each end)
	for sx in [-1, 1]:
		_box(Vector3(0.12, 0.02, 11), Vector3(sx * (HALF_L - 5.5), y, -5.5), line, self)
		_box(Vector3(0.12, 0.02, 11), Vector3(sx * (HALF_L - 5.5), y, 5.5), line, self)
		_box(Vector3(5.5, 0.02, 0.12), Vector3(sx * (HALF_L - 2.75), y, -5.5), line, self)
		_box(Vector3(5.5, 0.02, 0.12), Vector3(sx * (HALF_L - 2.75), y, 5.5), line, self)

	_goals()
	_stands()

func _goals() -> void:
	var white := _mat(Color(0.95, 0.96, 0.98))
	var netm := StandardMaterial3D.new()
	netm.albedo_color = Color(1, 1, 1, 0.16)
	netm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for sx in [-1, 1]:
		var g := Node3D.new()
		g.position.x = sx * HALF_L
		add_child(g)
		for sz in [-1, 1]:
			var post := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.07
			cm.bottom_radius = 0.07
			cm.height = GOAL_H
			post.mesh = cm
			post.material_override = white
			post.position = Vector3(0, GOAL_H / 2.0, sz * GOAL_W / 2.0)
			g.add_child(post)
		var bar := MeshInstance3D.new()
		var bm2 := CylinderMesh.new()
		bm2.top_radius = 0.07
		bm2.bottom_radius = 0.07
		bm2.height = GOAL_W
		bar.mesh = bm2
		bar.material_override = white
		bar.rotation_degrees.x = 90
		bar.position = Vector3(0, GOAL_H, 0)
		g.add_child(bar)
		# net shell: back + top + sides (visual) and a static body to stop the ball
		var net := StaticBody3D.new()
		var ncol := CollisionShape3D.new()
		var nbox := BoxShape3D.new()
		nbox.size = Vector3(1.6, GOAL_H + 0.3, GOAL_W + 0.3)
		ncol.shape = nbox
		ncol.position = Vector3(sx * 0.85, (GOAL_H + 0.3) / 2.0, 0)
		net.add_child(ncol)
		var nmesh := MeshInstance3D.new()
		var nb := BoxMesh.new()
		nb.size = nbox.size
		nmesh.mesh = nb
		nmesh.material_override = netm
		nmesh.position = ncol.position
		net.add_child(nmesh)
		g.add_child(net)

func _stands() -> void:
	var wall := _mat(Color("1a2438"))
	_box(Vector3(PITCH_L + 26, 5, 1), Vector3(0, 2.5, -HALF_W - 9), wall, self)
	_box(Vector3(PITCH_L + 26, 5, 1), Vector3(0, 2.5, HALF_W + 9), wall, self)
	_box(Vector3(1, 5, PITCH_W + 20), Vector3(-HALF_L - 11, 2.5, 0), wall, self)
	_box(Vector3(1, 5, PITCH_W + 20), Vector3(HALF_L + 11, 2.5, 0), wall, self)
	if DB.settings.get("graphics", "med") == "low":
		return
	# low-cost crowd: small colored boxes on the stands
	var palette := [Color("c9d4e8"), Color("7fa8e0"), Color("e0c97f"), Color("8fd0a8"), Color("d98f8f"), Color("9a8fd9")]
	for side in range(4):
		for i in range(42):
			var c: Color = palette[randi() % palette.size()]
			var b := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.42, 0.6, 0.3)
			b.mesh = bm
			b.material_override = _mat(c)
			if side == 0:
				b.position = Vector3(-HALF_L - 12 + i * 1.05, 5.4 + randf() * 0.7, -HALF_W - 8.4)
			elif side == 1:
				b.position = Vector3(-HALF_L - 12 + i * 1.05, 5.4 + randf() * 0.7, HALF_W + 8.4)
			elif side == 2:
				b.position = Vector3(-HALF_L - 10.4, 5.4 + randf() * 0.7, -HALF_W - 9 + i * 0.85)
			else:
				b.position = Vector3(HALF_L + 10.4, 5.4 + randf() * 0.7, -HALF_W - 9 + i * 0.85)
			add_child(b)

# ================================================================ players ====
func _build_teams() -> void:
	for t in range(2):
		for s in range(6):
			var pd: Dictionary = rosters[t][s]
			var attrs: Dictionary = (pd["attrs"] as Dictionary).duplicate()
			var is_you := false
			if t == 0 and cfg.has("career") and s == 5:
				var c: Dictionary = cfg["career"]
				pd = {"name": c["name"], "number": c["number"], "pos": "FW", "attrs": c["attrs"]}
				attrs = (c["attrs"] as Dictionary).duplicate()
				for k in attrs.keys():
					attrs[k] = clampi(int(attrs[k]), 40, 96)
				is_you = true
			var node := _build_player_node(t, s, pd, is_you)
			pl[t].append(node)
			dat[t].append({"attrs": attrs, "num": int(pd["number"]), "name": pd["name"], "role": pd["pos"], "is_you": is_you})
			ai_target[t].append(Vector3.ZERO)
			add_child(node)

func _build_player_node(t: int, s: int, pd: Dictionary, is_you: bool) -> CharacterBody3D:
	var p := CharacterBody3D.new()
	p.set_script(null)
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.34
	cap.height = 1.7
	col.shape = cap
	col.position.y = 0.95
	p.add_child(col)

	var shirt_c: Color = club[t]["color"] if s != 0 else club[t]["color2"]
	if is_you:
		shirt_c = Color("f0c040")
	var shirt := _mat(shirt_c)
	var dark := _mat(Color("1c2330"))
	var skin := _mat(Color("c8996c"))

	var v := Node3D.new()
	v.name = "vis"
	p.add_child(v)

	var torso := MeshInstance3D.new()
	var tcm := CapsuleMesh.new()
	tcm.radius = 0.30
	tcm.height = 0.72
	torso.mesh = tcm
	torso.material_override = shirt
	torso.position.y = 1.02
	v.add_child(torso)

	var shorts := MeshInstance3D.new()
	var shm := BoxMesh.new()
	shm.size = Vector3(0.52, 0.28, 0.38)
	shorts.mesh = shm
	shorts.material_override = dark
	shorts.position.y = 0.60
	v.add_child(shorts)

	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.24
	hm.height = 0.48
	head.mesh = hm
	head.material_override = skin
	head.position.y = 1.70
	v.add_child(head)

	var legL := MeshInstance3D.new()
	var llm := BoxMesh.new()
	llm.size = Vector3(0.15, 0.48, 0.15)
	legL.mesh = llm
	legL.material_override = dark
	legL.position = Vector3(-0.12, 0.26, 0)
	v.add_child(legL)
	var legR := MeshInstance3D.new()
	legR.mesh = llm
	legR.material_override = dark
	legR.position = Vector3(0.12, 0.26, 0)
	v.add_child(legR)

	# shirt number above the head (helps distinguish players; no faces anywhere)
	var num := Sprite3D.new()
	var nt: Texture2D = load("res://assets/textures/num_%d.png" % clampi(int(pd["number"]), 1, 15))
	num.texture = nt
	num.pixel_size = 0.011
	num.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	num.position = Vector3(0, 2.18, 0)
	if is_you:
		num.modulate = Color("ffd766")
	v.add_child(num)

	# controlled-player ring on the ground
	var ringm := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = 0.44
	rm.outer_radius = 0.56
	ringm.mesh = rm
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color("1fbf6b")
	rmat.emission_enabled = true
	rmat.emission = Color("1fbf6b")
	rmat.emission_energy_multiplier = 0.8
	ringm.material_override = rmat
	ringm.rotation_degrees.x = 90
	ringm.position.y = 0.05
	ringm.visible = false
	v.add_child(ringm)

	vis[t].append({"legL": legL, "legR": legR, "ring": ringm, "vis": v})
	return p

# ================================================================== HUD ======
func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(hud)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.layout_direction = Control.LAYOUT_DIRECTION_RTL
	root.text_direction = Control.TEXT_DIRECTION_RTL
	hud.add_child(root)

	# top bar
	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.position = Vector2(-240, 8)
	top.custom_minimum_size = Vector2(480, 52)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.05, 0.10, 0.18, 0.75)
	ps.set_corner_radius_all(14)
	top.add_theme_stylebox_override("panel", ps)
	var tr := HBoxContainer.new()
	tr.alignment = BoxContainer.ALIGNMENT_CENTER
	tr.add_theme_constant_override("separation", 18)
	lb_score = _hud_lbl("", 26)
	lb_time = _hud_lbl("", 22)
	tr.add_child(lb_score)
	tr.add_child(lb_time)
	top.add_child(tr)
	root.add_child(top)

	# pause + tactical buttons
	var bp := _hud_btn("❚❚", func(): _toggle_pause(), 52, 52)
	bp.position = Vector2(1216, 10)
	root.add_child(bp)
	var bt := _hud_btn("عرض", func(): tactical = not tactical, 52, 52)
	bt.position = Vector2(1156, 10)
	root.add_child(bt)

	# center banner / countdown
	lb_center = _hud_lbl("", 64)
	lb_center.set_anchors_preset(Control.PRESET_CENTER)
	lb_center.position = Vector2(-320, -160)
	lb_center.size = Vector2(640, 120)
	lb_center.add_theme_color_override("font_color", Color("ffd766"))
	lb_center.add_theme_font_override("font", load("res://assets/fonts/NotoNaskhArabic-Bold.ttf"))
	root.add_child(lb_center)

	# joystick P1
	joy1 = Joystick.new()
	joy1.radius = 88.0
	joy1.position = Vector2(56, 500)
	root.add_child(joy1)

	# sprint + stamina
	var bs := _hud_btn("ركض", func(): pass, 60, 96)
	bs.position = Vector2(110, 428)
	bs.button_down.connect(func(): sprinting = true)
	bs.button_up.connect(func(): sprinting = false)
	root.add_child(bs)
	lb_stamina = ProgressBar.new()
	lb_stamina.max_value = 100
	lb_stamina.show_percentage = false
	lb_stamina.custom_minimum_size = Vector2(150, 10)
	lb_stamina.position = Vector2(90, 492)
	root.add_child(lb_stamina)

	# action buttons P1
	var bshoot := _hud_btn("تسديد", func(): pass, 92, 92)
	bshoot.position = Vector2(1146, 500)
	bshoot.button_down.connect(func(): _start_charge(0))
	bshoot.button_up.connect(func(): _release_charge(0))
	root.add_child(bshoot)
	var bpass := _hud_btn("تمرير", func(): _do_pass(0), 82, 82)
	bpass.position = Vector2(1036, 610)
	root.add_child(bpass)
	btn_act = _hud_btn("تدخل", func(): _do_act(0), 76, 76)
	btn_act.position = Vector2(1186, 636)
	root.add_child(btn_act)
	var bsw := _hud_btn("تبديل", func(): _manual_switch(0), 66, 66)
	bsw.position = Vector2(952, 566)
	root.add_child(bsw)

	# minimap
	mini = MiniMap.new()
	mini.m = self
	mini.custom_minimum_size = Vector2(210, 136)
	mini.position = Vector2(520, 574)
	root.add_child(mini)

	# P2 controls (same-device)
	if human[1]:
		joy2 = Joystick.new()
		joy2.radius = 66.0
		joy2.position = Vector2(1000, 268)
		root.add_child(joy2)
		var bpass2 := _hud_btn("تمرير", func(): _do_pass(1), 64, 64)
		bpass2.position = Vector2(880, 180)
		root.add_child(bpass2)
		var bshoot2 := _hud_btn("تسديد", func(): _do_shoot(1, 0.7), 72, 72)
		bshoot2.position = Vector2(1000, 130)
		root.add_child(bshoot2)
		var bsw2 := _hud_btn("تبديل", func(): _manual_switch(1), 56, 56)
		bsw2.position = Vector2(820, 260)
		root.add_child(bsw2)

	# pause panel
	_pause_panel = _build_pause_panel(root)

	# sounds
	for nm in ["kick", "whistle", "bounce", "cheer"]:
		var ap := AudioStreamPlayer.new()
		ap.stream = load("res://assets/audio/%s.wav" % nm)
		ap.volume_db = -6.0
		add_child(ap)
		snd[nm] = ap

	# camera
	camera3d = Camera3D.new()
	camera3d.current = true
	camera3d.position = Vector3(-10, 7, 0)
	add_child(camera3d)

var _pause_panel: Control = null

func _hud_lbl(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.text_direction = Control.TEXT_DIRECTION_RTL
	l.add_theme_font_override("font", load("res://assets/fonts/NotoNaskhArabic-Bold.ttf"))
	return l

func _hud_btn(text: String, cb: Callable, h: float, w: float) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, h)
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_font_override("font", load("res://assets/fonts/NotoSansArabicUI-Regular.ttf"))
	b.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.45, 0.26, 0.75)
	sb.set_corner_radius_all(int(min(h, w) / 2.0))
	sb.border_color = Color(1, 1, 1, 0.35)
	sb.set_border_width_all(2)
	b.add_theme_stylebox_override("normal", sb)
	var sbp := sb.duplicate() as StyleBoxFlat
	sbp.bg_color = Color(0.16, 0.62, 0.36, 0.9)
	b.add_theme_stylebox_override("pressed", sbp)
	b.pressed.connect(cb)
	return b

func _build_pause_panel(root: Control) -> Control:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.visible = false
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.visible = false
	root.add_child(center)
	var panel := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color("14263d")
	ps.set_corner_radius_all(20)
	panel.add_theme_stylebox_override("panel", ps)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.add_child(_hud_lbl("إيقاف مؤقت", 32))
	var cb_resume := func(): _toggle_pause()
	var cb_restart := func():
		get_tree().paused = false
		paused = false
		_pause_panel.visible = false
		(_pause_panel.get_meta("center") as Control).visible = false
		match_finished.emit({"quit": true, "restart": true, "scored": score[0], "conceded": score[1], "rows": []})
	var cb_quit := func():
		get_tree().paused = false
		_end_match(true)
	var mk := func(txt: String, f: Callable) -> void:
		var b := _hud_btn(txt, f, 56, 300)
		col.add_child(b)
	mk.call("استئناف", cb_resume)
	mk.call("إعادة المباراة", cb_restart)
	mk.call("الخروج إلى القائمة", cb_quit)
	panel.add_child(col)
	center.add_child(panel)
	dim.set_meta("center", center)
	return dim

func _toggle_pause() -> void:
	paused = not paused
	get_tree().paused = paused
	if _pause_panel:
		_pause_panel.visible = paused
		(_pause_panel.get_meta("center") as Control).visible = paused

# ================================================================= sounds ====
func _play_snd(nm: String) -> void:
	if not DB.settings.get("sound", true):
		return
	if snd.has(nm) and snd[nm] != null:
		(snd[nm] as AudioStreamPlayer).play()

# ============================================================== main loop ====
func _physics_process(delta: float) -> void:
	if paused:
		return
	match state:
		"countdown":
			state_t -= delta
			lb_center.text = str(maxi(1, int(ceil(state_t))))
			if state_t <= 0.0:
				state = "playing"
				lb_center.text = ""
		"playing":
			_update_timer(delta)
			_update_teams(delta)
			_update_ball(delta)
			_ai_update(delta)
			_hud_update(delta)
		"goal":
			state_t -= delta
			if state_t <= 0.0:
				_setup_kickoff(_kickoff_team)
		"out":
			state_t -= delta
			if state_t <= 0.0:
				state = "playing"

var _kickoff_team := 0

func _process(delta: float) -> void:
	if paused or state == "ended":
		return
	_camera_update(delta)
	lb_score.text = "%s  %d - %d  %s" % [club[0]["short"], score[0], score[1], club[1]["short"]]
	lb_stamina.value = stamina
	if charge >= 0.0:
		charge += delta * 1.1
	_keyboard_actions()
	# leg animation + rings
	for t in range(2):
		for s in range(6):
			var p: CharacterBody3D = pl[t][s]
			if p == null:
				continue
			var v: Dictionary = vis[t][s]
			var sp: float = Vector2(p.velocity.x, p.velocity.z).length()
			var ang: float = sin(Time.get_ticks_msec() / 90.0 + s) * clampf(sp / 6.0, 0.0, 1.0) * 0.7
			(v["legL"] as MeshInstance3D).rotation.x = ang
			(v["legR"] as MeshInstance3D).rotation.x = -ang
			(v["ring"] as MeshInstance3D).visible = _is_controlled(t, s)

func _update_timer(delta: float) -> void:
	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		_end_match(false)
		return
	var mm := int(time_left) / 60
	var ss := int(time_left) % 60
	lb_time.text = "%02d:%02d" % [mm, ss]

# ================================================================ players ====
func _is_controlled(t: int, s: int) -> bool:
	return human[t] and controlled[t] == s

func _team_of(p: Node3D) -> int:
	return 0 if pl[0].has(p) else 1

func _slot_of(p: Node3D) -> int:
	return pl[_team_of(p)].find(p)

func _max_speed(d: Dictionary, spr: bool) -> float:
	var v: float = WALK * (0.72 + float(d["attrs"]["pace"]) / 100.0 * 0.55)
	if spr:
		v *= 1.55
	return v

func _input_move(t: int) -> Vector3:
	var v := Vector2.ZERO
	if t == 0:
		v = joy1.value
		var kx := Input.get_action_strength("mv_right") - Input.get_action_strength("mv_left")
		var ky := Input.get_action_strength("mv_down") - Input.get_action_strength("mv_up")
		if absf(kx) > 0.01 or absf(ky) > 0.01:
			v = Vector2(kx, ky)
	elif joy2 != null:
		v = joy2.value
	if v.length() < 0.12:
		return Vector3.ZERO
	var fwd := -camera3d.global_transform.basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var right := camera3d.global_transform.basis.x
	right.y = 0
	right = right.normalized()
	return (right * v.x + fwd * (-v.y)).normalized()

func _update_teams(delta: float) -> void:
	switch_cd[0] = maxf(0.0, switch_cd[0] - delta)
	switch_cd[1] = maxf(0.0, switch_cd[1] - delta)
	tackle_cd[0] = maxf(0.0, tackle_cd[0] - delta)
	tackle_cd[1] = maxf(0.0, tackle_cd[1] - delta)
	burst[0] = maxf(0.0, burst[0] - delta)
	burst[1] = maxf(0.0, burst[1] - delta)
	gk_cd[0] = maxf(0.0, gk_cd[0] - delta)
	gk_cd[1] = maxf(0.0, gk_cd[1] - delta)
	owner_grace[0] = maxf(0.0, owner_grace[0] - delta)
	owner_grace[1] = maxf(0.0, owner_grace[1] - delta)

	# stamina for P1
	if sprinting and stamina > 0.0:
		stamina = maxf(0.0, stamina - 16.0 * delta)
	else:
		stamina = minf(100.0, stamina + 9.0 * delta)

	for t in range(2):
		for s in range(6):
			var p: CharacterBody3D = pl[t][s]
			var d: Dictionary = dat[t][s]
			var desired := Vector3.ZERO
			if _is_controlled(t, s):
				var mv := _input_move(t)
				var spr := sprinting and t == 0 and stamina > 0.0
				if Input.is_action_pressed("act_sprint") and t == 0:
					spr = true
				desired = mv * _max_speed(d, spr)
				if burst[t] > 0.0:
					desired *= 1.5
			else:
				var tgt: Vector3 = ai_target[t][s]
				var to: Vector3 = tgt - p.global_position
				to.y = 0
				if to.length() > 0.45:
					var sp: float = _max_speed(d, false) * (0.8 if s == 0 else 1.0)
					if state == "playing" and ball_owner == p and burst[t] > 0.0:
						sp *= 1.4
					desired = to.normalized() * sp
			var cur: Vector3 = p.velocity
			var accel := 16.0 if desired.length() > Vector2(cur.x, cur.z).length() else 22.0
			var nv := cur.move_toward(desired, accel * delta)
			var vy: float = cur.y - 22.0 * delta
			if p.is_on_floor() and vy < 0.0:
				vy = -0.1
			p.velocity = Vector3(nv.x, vy, nv.z)
			p.move_and_slide()
			# keep inside the stadium (height clamp only below ground)
			if p.global_position.y < 0.0:
				p.global_position.y = 0.0
			p.global_position.x = clampf(p.global_position.x, -HALF_L - 3.0, HALF_L + 3.0)
			p.global_position.z = clampf(p.global_position.z, -HALF_W - 3.0, HALF_W + 3.0)
			# face movement
			var hv := Vector2(p.velocity.x, p.velocity.z)
			if hv.length() > 0.6:
				p.rotation.y = lerp_angle(p.rotation.y, atan2(hv.x, hv.y), 12.0 * delta)

	# AI defenders attempt tackles
	for t in range(2):
		if ball_owner != null and _team_of(ball_owner) != t and tackle_cd[t] <= 0.0 and state == "playing":
			var presser_s := _nearest_slot(t, true)
			var presser: Node3D = pl[t][presser_s]
			if _is_controlled(t, presser_s):
				continue
			if presser.global_position.distance_to(ball_owner.global_position) < 1.25:
				_attempt_tackle(presser, ball_owner)

# ================================================================== ball =====
func _build_ball() -> void:
	ball = RigidBody3D.new()
	ball.mass = 0.43
	ball.linear_damp = 0.45
	ball.angular_damp = 1.2
	ball.collision_layer = 2
	ball.collision_mask = 1 | 2
	var col := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = BALL_R
	col.shape = sh
	ball.add_child(col)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = BALL_R
	sm.height = BALL_R * 2.0
	mi.mesh = sm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.96, 0.96, 0.97)
	mi.material_override = wm
	ball.add_child(mi)
	add_child(ball)

func _update_ball(delta: float) -> void:
	bounce_cd = maxf(0.0, bounce_cd - delta)
	if ball_owner != null and is_instance_valid(ball_owner):
		# dribble: keep the ball glued at the owner's feet
		var fwd: Vector3 = -ball_owner.global_transform.basis.z
		var flat := Vector3(fwd.x, 0, fwd.z).normalized()
		ball.global_position = ball_owner.global_position + flat * 0.55 + Vector3(0, BALL_R, 0)
		ball.linear_velocity = Vector3(ball_owner.velocity.x, 0, ball_owner.velocity.z)
		ball.angular_velocity = Vector3.ZERO
		return
	# gain possession
	if state == "playing":
		var best: Node3D = null
		var bd := 1.25
		for t in range(2):
			for s in range(6):
				var p: Node3D = pl[t][s]
				var dd: float = Vector2(p.global_position.x - ball.global_position.x, p.global_position.z - ball.global_position.z).length()
				if dd < bd and ball.linear_velocity.length() < 11.0:
					bd = dd
					best = p
		if best != null:
			_set_owner(best)
	# last touch tracking (for restarts)
	if ball_owner == null:
		for t in range(2):
			for s in range(6):
				var p: Node3D = pl[t][s]
				if p.global_position.distance_to(ball.global_position) < 1.0:
					last_touch = p
	# bounce sound
	if ball.global_position.y < 0.22 and ball.linear_velocity.y < -3.0 and bounce_cd <= 0.0:
		bounce_cd = 0.25
		_play_snd("bounce")
	_goals_and_out()

func _set_owner(p: Node3D) -> void:
	ball_owner = p
	last_touch = p
	ball.freeze = true
	ball.collision_layer = 0
	var t: int = _team_of(p)
	touches[t] += 1
	if dat[t][_slot_of(p)].get("is_you", false):
		your_touches += 1
	if human[t]:
		owner_grace[t] = 0.9
		var s: int = _slot_of(p)
		controlled[t] = s if s != 0 else _nearest_slot(t, true)
		_after_switch(t)

func _clear_owner() -> void:
	ball_owner = null
	ball.freeze = false
	ball.collision_layer = 2

# =============================================================== kicking =====
func _do_pass(t: int) -> void:
	if state != "playing":
		return
	var p: Node3D = pl[t][controlled[t]]
	if ball_owner != p:
		return
	var mv := _input_move(t)
	if mv.length() < 0.1:
		mv = -p.global_transform.basis.z
	var target := _best_pass_target(t, mv)
	if target == null:
		return
	_clear_owner()
	var from: Vector3 = ball.global_position
	var to: Vector3 = target.global_position + Vector3(0, 0.4, 0)
	var dir: Vector3 = (to - from)
	var dist := Vector2(dir.x, dir.z).length()
	dir = dir.normalized()
	ball.linear_velocity = Vector3(dir.x, 0, dir.z) * clampf(dist * 1.8, 9.0, 21.0) + Vector3(0, dist * 0.10, 0)
	_play_snd("kick")
	# switch to the intended receiver
	if human[t]:
		controlled[t] = _slot_of(target)
		_after_switch(t)

func _best_pass_target(t: int, dir: Vector3) -> Node3D:
	var best: Node3D = null
	var bs := -999.0
	var me: Node3D = pl[t][controlled[t]]
	for s in range(6):
		if s == controlled[t]:
			continue
		var cnd: Node3D = pl[t][s]
		var to: Vector3 = cnd.global_position - me.global_position
		var d := Vector2(to.x, to.z).length()
		if d < 1.0:
			continue
		var dot: float = Vector2(to.x, to.z).normalized().dot(Vector2(dir.x, dir.z).normalized())
		var sc: float = dot * 2.2 - absf(d - 11.0) * 0.06 + (1.0 if s != 0 else -0.4)
		if sc > bs:
			bs = sc
			best = cnd
	return best

func _start_charge(t: int) -> void:
	if state != "playing":
		return
	if ball_owner == pl[t][controlled[t]]:
		charge = 0.0
		charge_team = t

func _release_charge(t: int) -> void:
	if charge < 0.0:
		return
	var pw: float = clampf(charge, 0.15, 1.0)
	charge = -1.0
	_do_shoot(t, pw)

func _do_shoot(t: int, power: float) -> void:
	if state != "playing":
		return
	var p: Node3D = pl[t][controlled[t]]
	if ball_owner != p:
		return
	_clear_owner()
	var gx: float = HALF_L if t == 0 else -HALF_L
	var aim := Vector3(gx, 1.1, randf_range(-GOAL_W * 0.32, GOAL_W * 0.32))
	var mv := _input_move(t)
	if mv.length() > 0.1:
		aim.z = clampf(aim.z + (-mv.z) * 3.0, -GOAL_W * 0.45, GOAL_W * 0.45)
	var d: Dictionary = dat[t][controlled[t]]
	aim.z += randf_range(-1.0, 1.0) * (1.0 - float(d["attrs"]["shoot"]) / 110.0) * 4.0
	var dir: Vector3 = (aim - ball.global_position).normalized()
	ball.linear_velocity = dir * (15.0 + 12.0 * power) + Vector3(0, 2.4 + 2.2 * power, 0)
	shots[t] += 1
	if d.get("is_you", false):
		your_shots += 1
	_play_snd("kick")

func _do_act(t: int) -> void:
	if state != "playing":
		return
	var p: Node3D = pl[t][controlled[t]]
	if ball_owner == p:
		# knock-on burst (dribble move)
		burst[t] = 0.45
		_play_snd("kick")
	elif ball_owner != null and _team_of(ball_owner) != t and tackle_cd[t] <= 0.0:
		if p.global_position.distance_to(ball_owner.global_position) < 1.8:
			_attempt_tackle(p, ball_owner)
			tackle_cd[t] = 0.8

func _attempt_tackle(tackler: Node3D, carrier: Node3D) -> void:
	var tt := _team_of(tackler)
	tackle_cd[tt] = 0.8
	var ta := float(dat[tt][_slot_of(tackler)]["attrs"]["defend"])
	var ca := float(dat[_team_of(carrier)][_slot_of(carrier)]["attrs"]["dribble"])
	if randf() < 0.45 + (ta - ca) * 0.005:
		# won: ball pops loose toward the tackler's side
		_clear_owner()
		var dir: Vector3 = (ball.global_position - carrier.global_position).normalized()
		ball.linear_velocity = Vector3(dir.x, 0.35, dir.z) * 6.5
		_play_snd("kick")
	else:
		# missed: tackler stumbles
		tackler.velocity *= 0.15

func _manual_switch(t: int) -> void:
	if not human[t]:
		return
	var cur := controlled[t]
	var best := -1
	var bd := 999.0
	for s in range(1, 6):
		if s == cur:
			continue
		var d: float = pl[t][s].global_position.distance_to(ball.global_position)
		if d < bd:
			bd = d
			best = s
	if best > 0:
		controlled[t] = best
		switch_cd[t] = 0.6
		_after_switch(t)

func _after_switch(t: int) -> void:
	for s in range(6):
		(vis[t][s]["ring"] as MeshInstance3D).visible = _is_controlled(t, s)

func _nearest_slot(t: int, outfield: bool) -> int:
	var best := 1
	var bd := 999.0
	for s in range(6):
		if outfield and s == 0:
			continue
		var d: float = pl[t][s].global_position.distance_to(ball.global_position)
		if d < bd:
			bd = d
			best = s
	return best

func _defensive_auto_switch(t: int) -> void:
	if not human[t] or switch_cd[t] > 0.0:
		return
	var cand := _nearest_slot(t, true)
	if cand == controlled[t]:
		return
	var dc: float = pl[t][controlled[t]].global_position.distance_to(ball.global_position)
	var dn: float = pl[t][cand].global_position.distance_to(ball.global_position)
	if dc - dn > 1.6:
		controlled[t] = cand
		switch_cd[t] = 0.7
		_after_switch(t)

# ================================================================== AI =======
func _ai_update(delta: float) -> void:
	ai_tick -= delta
	carrier_tick -= delta
	# human teams: auto-switch to the best defensive option when we don't have the ball
	if state == "playing":
		if ball_owner == null or _team_of(ball_owner) != 0:
			_defensive_auto_switch(0)
		if human[1] and (ball_owner == null or _team_of(ball_owner) != 1):
			_defensive_auto_switch(1)
	if ai_tick <= 0.0:
		ai_tick = 0.16
		_think_positions()
	if carrier_tick <= 0.0:
		carrier_tick = 0.4
		_think_carrier()

func _think_positions() -> void:
	for t in range(2):
		var has_ball: bool = ball_owner != null and _team_of(ball_owner) == t
		var opp_has: bool = ball_owner != null and _team_of(ball_owner) != t
		# distance ranking
		var dists := []
		for s in range(1, 6):
			dists.append([s, pl[t][s].global_position.distance_to(ball.global_position)])
		dists.sort_custom(func(a, b): return a[1] < b[1])
		for s in range(6):
			if _is_controlled(t, s):
				continue
			if s == 0:
				ai_target[t][0] = _gk_target(t)
				continue
			var home: Vector2 = formation_slots[s - 1]
			var spot: Vector3 = Vector3(home.x, 0, home.y) if t == 0 else Vector3(-home.x, 0, -home.y)
			if has_ball:
				spot.x += 4.0 if t == 0 else -4.0
				spot.z = lerpf(spot.z, ball.global_position.z, 0.35)
				if s == dists[0][0]:
					spot = ball.global_position + Vector3((4.5 if t == 0 else -4.5), 0, (spot.z - ball.global_position.z) * 0.35)
			elif opp_has:
				spot.x += -2.5 if t == 0 else 2.5
				spot.z = lerpf(spot.z, ball.global_position.z * 0.7, 0.5)
				if s == dists[0][0]:
					spot = ball.global_position + (pl[t][0].global_position - ball.global_position).normalized() * 0.8
				elif s == dists[1][0]:
					spot = ball.global_position + (pl[t][0].global_position - ball.global_position) * 0.35
			else:
				if s == dists[0][0] or s == dists[1][0]:
					spot = ball.global_position
				else:
					spot.x = lerpf(spot.x, ball.global_position.x, 0.25)
					spot.z = lerpf(spot.z, ball.global_position.z, 0.25)
			spot.x = clampf(spot.x, -HALF_L + 0.5, HALF_L - 0.5)
			spot.z = clampf(spot.z, -HALF_W + 0.5, HALF_W - 0.5)
			ai_target[t][s] = spot

func _gk_target(t: int) -> Vector3:
	var gx: float = (-HALF_L + 1.0) if t == 0 else (HALF_L - 1.0)
	var advance: float = clampf((absf(ball.global_position.x) - 12.0) * 0.08, 0.0, 1.3)
	var x: float = gx + (advance if t == 0 else -advance)
	var z: float = clampf(ball.global_position.z * 0.35, -GOAL_W / 2.0, GOAL_W / 2.0)
	return Vector3(x, 0, z)

func _think_carrier() -> void:
	if ball_owner == null or state != "playing":
		return
	var t := _team_of(ball_owner)
	var s := _slot_of(ball_owner)
	if human[t] and (s == controlled[t] or owner_grace[t] > 0.0):
		return
	var d: Dictionary = dat[t][s]
	# shoot?
	var gx: float = (HALF_L - 0.5) if t == 0 else (-HALF_L + 0.5)
	var dgoal: float = Vector2(ball.global_position.x - gx, ball.global_position.z).length()
	if dgoal < 12.5 and absf(ball.global_position.z) < 10.0:
		if randf() < 0.4 + float(d["attrs"]["shoot"]) / 220.0:
			controlled[t] = s  # ensure aim uses the carrier
			_do_shoot(t, randf_range(0.55, 1.0))
			return
	# pass?
	if randf() < 0.55:
		var best: Node3D = null
		var bs := -999.0
		for os in range(1, 6):
			if os == s:
				continue
			var cnd: Node3D = pl[t][os]
			var fwd: float = (cnd.global_position.x - ball.global_position.x) * (1.0 if t == 0 else -1.0)
			var sc: float = fwd * 0.2 - cnd.global_position.distance_to(ball.global_position) * 0.08 + randf() * 0.6
			if sc > bs:
				bs = sc
				best = cnd
		if best != null:
			controlled[t] = s
			_do_pass(t)
			return
	# dribble toward goal, avoiding opponents
	var dir := Vector3((1.0 if t == 0 else -1.0), 0, clampf(-ball.global_position.z * 0.08, -0.5, 0.5))
	for os in range(6):
		var opp: Node3D = pl[1 - t][os]
		var away: Vector3 = ball.global_position - opp.global_position
		var dd := Vector2(away.x, away.z).length()
		if dd < 3.0:
			dir += Vector3(away.x, 0, away.z).normalized() * (3.0 - dd) * 0.5
	ai_target[t][s] = ball.global_position + dir.normalized() * 4.0

func _gk_dives() -> void:
	for t in range(2):
		if gk_cd[t] > 0.0:
			continue
		var gk: CharacterBody3D = pl[t][0]
		var gx: float = -HALF_L if t == 0 else HALF_L
		var incoming: bool = (ball.linear_velocity.x < -4.5 and t == 0) or (ball.linear_velocity.x > 4.5 and t == 1)
		if incoming and absf(ball.global_position.x - gx) < 6.5 and ball.global_position.y < 2.2:
			var tt: float = (gx - ball.global_position.x) / ball.linear_velocity.x
			if tt > 0.0 and tt < 1.2:
				var zpred: float = ball.global_position.z + ball.linear_velocity.z * tt
				if absf(zpred) < GOAL_W / 2.0 + 1.4:
					gk_cd[t] = 1.6
					var to: Vector3 = Vector3(gx + (0.4 if t == 0 else -0.4), 0.9, zpred) - gk.global_position
					gk.velocity = to.normalized() * 11.0
					gk.velocity.y = 4.0

# ====================================================== goals & restarts =====
func _goals_and_out() -> void:
	if state != "playing":
		return
	var bx: float = ball.global_position.x
	var bz: float = ball.global_position.z
	var by: float = ball.global_position.y
	# goal?
	if absf(bx) > HALF_L + 0.15:
		if absf(bz) < GOAL_W / 2.0 and by < GOAL_H + 0.15:
			var scoring_team := 0 if bx > 0.0 else 1
			_on_goal(scoring_team)
			return
		# behind the line: corner or goal kick
		var attacker := _team_of(last_touch) if last_touch != null else (0 if bx > 0.0 else 1)
		# ball crossed on bx side; if attacker == team that attacks that side -> goal kick for the other
		var side_team := 0 if bx > 0.0 else 1   # team that attacks this side
		if attacker == side_team:
			# corner for the attacking team
			_restart(Vector3(signf(bx) * (HALF_L - 0.8), 0, signf(bz) * (HALF_W - 0.8)), attacker)
		else:
			# goal kick: give to the defending team's GK
			var def_team := 1 - attacker
			_restart(Vector3(signf(bx) * (HALF_L - 4.0), 0, 0.0), def_team, true)
		return
	# touchline
	if absf(bz) > HALF_W + 0.6:
		var throw_team := 1 - (_team_of(last_touch) if last_touch != null else 0)
		_restart(Vector3(clampf(bx, -HALF_L + 1.0, HALF_L - 1.0), 0, signf(bz) * (HALF_W - 0.6)), throw_team)

func _restart(pos: Vector3, team: int, gk_ball := false) -> void:
	state = "out"
	state_t = 1.0
	_clear_owner()
	ball.global_position = pos + Vector3(0, BALL_R + 0.05, 0)
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	# give the ball to the nearest suitable player of `team`
	var s := 0 if gk_ball else _nearest_slot_of(team, pos)
	var p: Node3D = pl[team][s]
	p.global_position = pos + Vector3(0, 0, -signf(pos.z) * 0.8 if absf(pos.z) > 1.0 else 0.8)
	if human[team]:
		controlled[team] = s
		_after_switch(team)
	_set_owner(p)

func _nearest_slot_of(t: int, pos: Vector3) -> int:
	var best := 1
	var bd := 999.0
	for s in range(1, 6):
		var d: float = pl[t][s].global_position.distance_to(pos)
		if d < bd:
			bd = d
			best = s
	return best

func _on_goal(team: int) -> void:
	score[team] += 1
	if last_touch != null and dat[_team_of(last_touch)][_slot_of(last_touch)].get("is_you", false) and _team_of(last_touch) == team:
		your_goals += 1
	state = "goal"
	state_t = 2.6
	_kickoff_team = 1 - team
	_clear_owner()
	ball.linear_velocity = Vector3.ZERO
	var scorer := ""
	if last_touch != null and _team_of(last_touch) == team:
		scorer = " — " + dat[team][_slot_of(last_touch)]["name"]
	lb_center.text = "هدف!" + scorer
	_play_snd("whistle")
	_play_snd("cheer")
	if DB.settings.get("vibration", false) and Input.has_method("vibrate_handheld"):
		Input.vibrate_handheld(180)

func _setup_kickoff(possess_team: int) -> void:
	state = "countdown"
	state_t = 2.2
	lb_center.text = ""
	for t in range(2):
		for s in range(6):
			var pos: Vector3
			if s == 0:
				pos = Vector3(-HALF_L + 1.2, 0, 0) if t == 0 else Vector3(HALF_L - 1.2, 0, 0)
			else:
				var home: Vector2 = formation_slots[s - 1]
				pos = Vector3(home.x, 0, home.y) if t == 0 else Vector3(-home.x, 0, -home.y)
				if t == possess_team:
					pos.x *= 0.35
			pl[t][s].global_position = pos
			pl[t][s].velocity = Vector3.ZERO
			pl[t][s].rotation.y = atan2(-pos.x, -pos.z) if pos.length() > 0.1 else 0.0
	_clear_owner()
	ball.global_position = Vector3(0, BALL_R + 0.1, 0)
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	var st := 5 if possess_team == 0 else 4
	controlled[0] = st
	controlled[1] = 5 if possess_team == 1 else 4
	_set_owner(pl[possess_team][st if possess_team == 0 else 5])
	_after_switch(0)
	_after_switch(1)

# =============================================================== camera ======
func _camera_update(delta: float) -> void:
	var sens: float = float(DB.settings.get("cam_sens", 1.0))
	if tactical:
		var tpos := Vector3(clampf(ball.global_position.x * 0.35, -10, 10), 27.0, 13.0)
		camera3d.global_position = camera3d.global_position.lerp(tpos, 3.0 * delta * sens)
		camera3d.look_at(Vector3(ball.global_position.x * 0.4, 0, 0), Vector3.UP)
	else:
		var p: Node3D = pl[0][controlled[0]]
		var look: Vector3 = p.global_position * 0.65 + ball.global_position * 0.35
		var desired: Vector3 = p.global_position + Vector3(-8.6, 6.6, 0)
		desired.z = clampf(desired.z * 0.4 + ball.global_position.z * 0.12, -9.0, 9.0)
		camera3d.global_position = camera3d.global_position.lerp(desired, 4.5 * delta * sens)
		camera3d.look_at(look + Vector3(0, 1.0, 0), Vector3.UP)

func _keyboard_actions() -> void:
	if state != "playing" or not human[0]:
		return
	if Input.is_action_just_pressed("act_pass"):
		_do_pass(0)
	if Input.is_action_just_pressed("act_shoot"):
		_start_charge(0)
	if Input.is_action_just_released("act_shoot"):
		_release_charge(0)
	if Input.is_action_just_pressed("act_move"):
		_do_act(0)
	if Input.is_action_just_pressed("act_switch"):
		_manual_switch(0)
	if Input.is_action_just_pressed("act_pause"):
		_toggle_pause()

func _hud_update(_delta: float) -> void:
	# contextual action label
	var p: Node3D = pl[0][controlled[0]]
	if ball_owner != null and _team_of(ball_owner) == 1 and p.global_position.distance_to(ball_owner.global_position) < 1.9:
		btn_act.text = "تدخل"
	elif ball_owner == p:
		btn_act.text = "مراوغة"
	else:
		btn_act.text = "ضغط"
	# GK dives
	_gk_dives()

# =============================================================== match end ====
func _end_match(quit: bool) -> void:
	if state == "ended":
		return
	state = "ended"
	var result := "D"
	if score[0] > score[1]:
		result = "W"
	elif score[0] < score[1]:
		result = "L"
	var poss := 50.0
	if touches[0] + touches[1] > 0:
		poss = 100.0 * float(touches[0]) / float(touches[0] + touches[1])
	var rating := 6.0 + float(your_goals) * 1.2 + minf(0.9, float(your_touches) * 0.012)
	match result:
		"W": rating += 1.0
		"L": rating -= 0.6
		"D": rating += 0.3
	rating = clampf(rating, 3.0, 10.0)
	var rows := [
		["التسديدات", "%d - %d" % [shots[0], shots[1]]],
		["الاستحواذ", "%d%% - %d%%" % [int(poss), 100 - int(poss)]],
	]
	if bool(cfg.get("mode", "friendly")) == "career" and cfg.has("career"):
		rows.append(["أهدافك", str(your_goals)])
		rows.append(["تسديداتك", str(your_shots)])
		rows.append(["تقييمك", "%.1f" % rating])
	match_finished.emit({
		"scored": score[0],
		"conceded": score[1],
		"result": result,
		"rating": rating,
		"your_goals": your_goals,
		"your_shots": your_shots,
		"career": String(cfg.get("mode", "friendly")) == "career",
		"quit": quit,
		"rows": rows,
	})
