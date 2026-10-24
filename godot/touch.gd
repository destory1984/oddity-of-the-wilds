# On-screen touch controls for phones in landscape (the user asked for phone play, 2026-10-24).
# Every finger is read on its own (InputEventScreenTouch/Drag by index), so Sora can walk with the left thumb while
# the right one swings or dodges. A finger on the left of the screen grabs a stick that appears under it; pushed to
# the rim she runs. The keys call the same functions as the keyboard; guard and run are held through main.touch_keys.
# The keys are drawn here, not made of Buttons: the mouse the browser makes out of a touch follows one finger only.
extends Control

var main: Node
var pad_idx := -1          # the finger on the stick, -1 for none
var pad_origin := Vector2.ZERO
var pad_at := Vector2.ZERO
var held := {}             # finger index -> key name, for the keys that act while held (guard)
const PAD_R := 80.0        # how far the knob goes
const RUN_AT := 0.92       # pushed this far the stick runs

var tex := {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	for n in ["attack", "dodge", "guard", "crown", "open", "stick_base", "stick_knob", "zoom_in", "zoom_out"]:
		tex[n] = load("res://art/ui/touch_%s.png" % n)

# where each key sits (centre, radius) for the screen as it is now; the skills are the HUD's own icons
func keys() -> Dictionary:
	var vs := get_viewport_rect().size
	var k := {
		"attack": [Vector2(vs.x - 80, vs.y - 196), 58.0],
		"dodge": [Vector2(vs.x - 196, vs.y - 158), 42.0],
		"guard": [Vector2(vs.x - 176, vs.y - 270), 42.0],
		"crown": [Vector2(vs.x - 64, vs.y - 300), 38.0],
		"open": [Vector2(vs.x - 290, vs.y - 226), 38.0],
		# a column left of the menu keys, level with their two rows: clear of the boss bar and the quest line under them
		"zoom_in": [Vector2(vs.x - 358, 36), 26.0],
		"zoom_out": [Vector2(vs.x - 358, 100), 26.0],
	}
	for i in 4: # the skill icons hud.gd draws (U I O and the potion)
		k["skill%d" % i] = [Vector2(vs.x - 264 + i * 74, vs.y - 59), 36.0]
	return k

# the keys are for play only: a story, the shop, a sheet or the settings take taps as clicks
func playing() -> bool:
	return not main.intro and not main.story_open and not main.shop_open and not main.settings_open \
		and not main.ui.journal.visible and not main.ui.help.visible and not main.way_open and main.down_t <= 0.0

func key_at(p: Vector2) -> String:
	var k := keys()
	for n in k:
		if p.distance_to(k[n][0]) <= k[n][1] + 6.0:
			return n
	return ""

var asked_full := false

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and not asked_full and OS.has_feature("web_android"):
			asked_full = true # Android browsers go full screen on a touch (iOS Safari cannot)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		if event.pressed:
			if not playing():
				return
			var n := key_at(event.position)
			if n != "":
				press(n, event.index)
				get_viewport().set_input_as_handled()
			elif event.position.x < get_viewport_rect().size.x * 0.45 and pad_idx < 0:
				pad_idx = event.index
				pad_origin = event.position
				pad_at = event.position
				get_viewport().set_input_as_handled()
		else:
			if event.index == pad_idx:
				pad_idx = -1
				main.touch_move = Vector2.ZERO
				main.touch_keys.erase(KEY_SHIFT)
			if held.has(event.index):
				main.touch_keys.erase(KEY_L)
				held.erase(event.index)
	elif event is InputEventScreenDrag and event.index == pad_idx:
		pad_at = event.position
		var v: Vector2 = (pad_at - pad_origin) / PAD_R
		if v.length() > 1.0:
			pad_origin = pad_at - v.normalized() * PAD_R # the stick follows a thumb that slides past the rim
			v = v.normalized()
		main.touch_move = v if v.length() > 0.15 else Vector2.ZERO
		if v.length() >= RUN_AT:
			main.touch_keys[KEY_SHIFT] = true
		else:
			main.touch_keys.erase(KEY_SHIFT)
		get_viewport().set_input_as_handled()

func press(n: String, idx: int) -> void:
	match n:
		"attack": main.attack()
		"dodge": main.dodge()
		"guard":
			main.touch_keys[KEY_L] = true
			held[idx] = n
		"crown": main.crown_key()
		"open": main.interact()
		"zoom_in": main.cam_dist = clampf(main.cam_dist - 2.4, 8, 26)
		"zoom_out": main.cam_dist = clampf(main.cam_dist + 2.4, 8, 26)
		"skill0", "skill1", "skill2": main.use_skill(int(n.right(1)))
		"skill3": main.drink_potion()

# the menu keys and the minimap step aside while a story, the shop, a sheet or the settings are up
func step_aside() -> void:
	var up: bool = main.intro or main.story_open or main.shop_open or main.settings_open or main.ui.journal.visible or main.ui.help.visible
	for c in [main.ui.hint, main.ui.sound_btn, main.ui.journal_btn, main.ui.settings_btn, main.ui.mini.get_parent()]:
		c.visible = not up

func _process(_dt: float) -> void:
	step_aside()
	if not playing() and pad_idx >= 0: # a story or a sheet opened under the thumb: let go of everything
		pad_idx = -1
		main.touch_move = Vector2.ZERO
		main.touch_keys.clear()
		held.clear()
	queue_redraw()

func _draw() -> void:
	var vs := get_viewport_rect().size
	if vs.y > vs.x: # held upright: ask for landscape
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.02, 0.04, 0.09, 0.92))
		var msg: String = tr("가로로 돌려 주세요")
		var f: Font = main.ui_font
		var w := f.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
		draw_string(f, Vector2((vs.x - w) / 2.0, vs.y / 2.0), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color("#eef3ff"))
		return
	if not playing():
		return
	# the stick: under the thumb while held, a faint one at rest where the left thumb usually lies
	var base := pad_origin if pad_idx >= 0 else Vector2(150, vs.y - 160)
	var knob := pad_at if pad_idx >= 0 else base
	var a := 0.95 if pad_idx >= 0 else 0.45
	draw_texture_rect(tex.stick_base, Rect2(base - Vector2(96, 96), Vector2(192, 192)), false, Color(1, 1, 1, a))
	draw_texture_rect(tex.stick_knob, Rect2(knob - Vector2(40, 40), Vector2(80, 80)), false, Color(1, 1, 1, a))
	var k := keys()
	for n in ["attack", "dodge", "guard", "crown", "open", "zoom_in", "zoom_out"]:
		var c: Vector2 = k[n][0]
		var r: float = k[n][1]
		var lit := held.values().has(n)
		draw_texture_rect(tex[n], Rect2(c - Vector2(r, r) * 1.1, Vector2(r, r) * 2.2), false, Color(1.2, 1.2, 1.2) if lit else Color(1, 1, 1, 0.9))
