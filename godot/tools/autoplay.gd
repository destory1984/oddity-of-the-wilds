# Autoplay tests: drive the real game with injected input and check the outcome.
# Run with `-- --test=all` (or one name). Each test prints one line:
#   TEST name PASS|FAIL detail
# and the run ends with `TESTS n passed, m failed` and exit code m.
extends Node

const MARSH := preload("res://marsh.gd")
var main: Node
var only := "all"
var results: Array = []

const TESTS := ["start_click", "story_opens", "story_closes", "opening", "meet_bori", "boss_opens_cave", "save_load", "cave_enter", "cave_layout", "archer_telegraph", "key_door", "rival_scene", "cave_save_load", "unstick", "mole_charge", "mole_grants_skip", "cave_faint", "cave_exit", "water_skip", "water_skip_letgo", "village_enter", "village_layout", "simji_talk", "lamp_cost_night", "lamp_cost_day", "lamp_no_pips", "pip_rest", "errand_done", "kongal_errand", "doran_errand", "mulgyeol_errand", "lantern_night", "folk_again", "lake", "forest", "hill", "garden_end", "village_exit", "marsh_scraps", "forest_grove", "firefly_errand", "grotto", "cloud", "castle", "shrine", "journal", "wolf", "trial", "squirrels", "crystals", "race", "vault", "save_tonight", "fishing", "bat", "moonflowers", "houses", "feats", "start_key", "bridges", "shop_buy", "shop_click", "footsteps", "boss_survive", "faint_resets",
	"flash_dodge", "late_dodge", "flash_guard", "guard_block", "guard_back", "momentum", "level_moves", "skill_cost", "goblin_telegraph", "boss_phase2"]

func _ready() -> void:
	run.call_deferred()

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func check(name: String, ok: bool, detail := "") -> void:
	results.append(ok)
	print("TEST %s %s %s" % [name, "PASS" if ok else "FAIL", detail])

func click() -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = get_viewport().get_visible_rect().size / 2.0
	Input.parse_input_event(e)
	var up := e.duplicate()
	up.pressed = false
	Input.parse_input_event(up)

func tap(key: int) -> void:
	var e := InputEventKey.new()
	e.keycode = key
	e.physical_keycode = key
	e.pressed = true
	Input.parse_input_event(e)
	var up := e.duplicate()
	up.pressed = false
	Input.parse_input_event(up)

# hold a direction given in world x/z: pick the screen keys that move that way
func hold_world(dir: Vector2) -> void:
	var fwd := Vector2(-sin(main.cam_yaw), -cos(main.cam_yaw))
	var right := Vector2(cos(main.cam_yaw), -sin(main.cam_yaw))
	main.fake_keys.clear()
	var f := dir.dot(fwd)
	var r := dir.dot(right)
	if f > 0.38: main.fake_keys[KEY_W] = true
	if f < -0.38: main.fake_keys[KEY_S] = true
	if r > 0.38: main.fake_keys[KEY_D] = true
	if r < -0.38: main.fake_keys[KEY_A] = true

func release() -> void:
	main.fake_keys.clear()

func reset_to(p: Vector2) -> void:
	main.player.x = p.x
	main.player.z = p.y
	main.player.hp = float(main.player.max_hp)
	main.player.inv = 0.0
	main.ground_y = main.height_at(p.x, p.y)

func calm_enemies(on: bool) -> void:
	for e in main.enemies:
		if not e.get("boss", false) and not e.get("mole", false) and not e.get("prop", false) and is_instance_valid(e.node):
			e.node.visible = not on
			if on:
				e.x = 2.0 # parked in the corner water, out of the way
				e.z = 2.0

func run() -> void:
	var want := func(n): return only == "all" or only == n
	if only == "title_space": # the user's web save, then Space at the title, twice
		var f := FileAccess.open(main.SAVE_PATH, FileAccess.WRITE)
		f.store_string('{"atk":37,"boss_dead":true,"chests":[true,true,true,true,true],"day":3,"door_open":false,"gold":786,"has_key":false,"hour":2.13,"hp":208.0,"in_cave":false,"lv":10,"max_hp":208,"pots":7,"saw_painting":false,"story":5,"x":14.65,"z":20.15}')
		f.close()
		main.load_game()
		print("intro before=", main.intro)
		tap(KEY_SPACE)
		await wait(1.0)
		print("after 1st space intro=", main.intro, " story_open=", main.story_open, " title valid=", is_instance_valid(main.ui.title))
		tap(KEY_SPACE)
		await wait(1.0)
		print("after 2nd space intro=", main.intro, " pos=", main.player.x, ",", main.player.z, " in_cave=", main.in_cave)
		get_tree().quit(0)
		return
	if want.call("start_click"):
		await wait(1.0) # let the title orbit drift the camera first
		click()
		await wait(0.3)
		check("start_click", not main.intro and absf(main.cam_yaw - main.CAM_YAW) < 0.001, "title closes on a mouse click, camera back to the fixed angle (yaw %.3f)" % main.cam_yaw)
		check("story_opens", main.story_open, "opening illustration shows after the title")
		for k in 30:
			if not main.story_open:
				break
			click()
			await wait(0.05)
		await wait(0.7)
		check("story_closes", not main.story_open and not main.ui.story.visible, "two clicks page through and close it")
	if main.intro:
		main.start_game(false)
	if main.story_open:
		main.close_story()
		await wait(0.6)
	if want.call("start_key"):
		# the intro is over by now, so check that keys still reach the game: H toggles help
		var before: bool = main.ui.help.visible
		tap(KEY_H)
		await wait(0.2)
		check("start_key", main.ui.help.visible != before, "keys reach the game after the title")
		tap(KEY_H)
	calm_enemies(true)
	if want.call("bridges"):
		for b in main.bridges:
			var z: float = b.z + 0.5
			reset_to(Vector2(b.a - 2.0, z))
			hold_world(Vector2(1, 0))
			var t := 0.0
			var goal: float = b.b + 2.0
			while t < 8.0 and main.player.x < goal:
				# steer back onto the deck's centre line
				hold_world(Vector2(1, clampf((z - main.player.z) * 2.0, -1, 1)).normalized())
				await wait(0.1)
				t += 0.1
			release()
			check("bridges", main.player.x >= goal, "bridge at z=%d: reached x=%.1f of %.1f" % [b.z, main.player.x, goal])
	if want.call("shop_buy"):
		reset_to(Vector2(main.shop_pos.x, main.shop_pos.z))
		main.story_step = 3
		main.player.gold = 100
		var pots: int = main.player.pots
		tap(KEY_SPACE)
		await wait(0.2)
		var opened: bool = main.shop_open
		var h0: float = main.hour
		await wait(1.0)
		var frozen: bool = main.hour == h0
		tap(KEY_1)
		await wait(0.2)
		tap(KEY_ESCAPE)
		await wait(0.2)
		check("shop_buy", frozen and opened and main.player.pots == pots + 1 and main.player.gold == 70 and not main.shop_open,
			"clock frozen=%s opened=%s pots %d->%d gold 100->%d closed=%s" % [frozen, opened, pots, main.player.pots, main.player.gold, not main.shop_open])
	if want.call("shop_click"):
		reset_to(Vector2(main.shop_pos.x, main.shop_pos.z))
		main.story_step = 3
		main.player.gold = 100
		var p0: int = main.player.pots
		main.toggle_shop(true)
		await wait(0.3)
		var btn: Button = main.ui.shop_btns[0]
		var at: Vector2 = btn.get_parent().get_global_rect().get_center()
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.position = at
		e.global_position = at
		e.pressed = true
		Input.parse_input_event(e)
		var u := e.duplicate()
		u.pressed = false
		Input.parse_input_event(u)
		await wait(0.3)
		check("shop_click", main.player.pots == p0 + 1, "clicking the first card's button buys it: pots %d->%d, button at %s disabled=%s" % [p0, main.player.pots, at, btn.disabled])
		main.toggle_shop(false)
		await wait(0.2)
	if want.call("footsteps"):
		reset_to(main.START)
		main.sfx_log.clear()
		hold_world(Vector2(0, 1))
		await wait(1.5)
		release()
		var steps: int = main.sfx_log.filter(func(k): return k.begins_with("step") or k.begins_with("triangle:1")).size()
		check("footsteps", steps >= 3, "%d steps in 1.5 s of walking" % steps)
	if want.call("boss_survive"):
		var boss = main.enemies.filter(func(e): return e.get("boss", false))
		if boss.is_empty() or boss[0].dead:
			check("boss_survive", false, "no boss on the map")
		else:
			var b0: Dictionary = boss[0]
			calm_enemies(true) # the boss alone: a marsh archer that happens to stand nearby would add its own hits
			reset_to(Vector2(b0.x, b0.z + 2.0))
			main.player.max_hp = 100
			main.player.hp = 100.0
			var faints := [0]
			var start: Vector2 = main.START
			for i in 120: # 12 s standing next to the awake boss, doing nothing
				await wait(0.1)
				if Vector2(main.player.x, main.player.z).distance_to(start) < 0.5:
					faints[0] += 1
					break
			calm_enemies(false)
			check("boss_survive", faints[0] == 0, "level 1 Sora standing still beside the boss for 12 s: hp %d" % int(main.player.hp))
	if want.call("faint_resets"):
		var boss = main.enemies.filter(func(e): return e.get("boss", false) and not e.dead)
		if not boss.is_empty():
			boss[0].hp = 100.0
		reset_to(Vector2(30, 30))
		main.faint()
		await wait(0.2)
		var at_start: bool = Vector2(main.player.x, main.player.z).distance_to(main.START) < 0.1
		var boss_full: bool = boss.is_empty() or boss[0].hp == boss[0].max_hp
		check("faint_resets", at_start and boss_full and main.ui.banner.modulate.a > 0.5,
			"at start=%s boss healed=%s banner shown=%s" % [at_start, boss_full, main.ui.banner.modulate.a > 0.5])
	# ---- story: the first minute and the first cottage visit
	if want.call("opening"):
		calm_enemies(true)
		reset_to(main.START)
		main.story_step = 0
		main.begin_opening()
		var lamp: OmniLight3D = main.dark_lamp
		var asked: bool = main.ui.quest.visible and main.ui.quest.text.contains("E")
		var n_before: int = main.enemies.size()
		tap(KEY_E)
		await wait(0.2)
		var lit: bool = main.dark_lamp == null
		await wait(1.2)
		var g: Dictionary = main.enemies[main.enemies.size() - 1]
		var near: bool = lamp != null and Vector2(g.x, g.z).distance_to(Vector2(lamp.position.x, lamp.position.z)) < 3.0 # it rises at 1.4 tiles, then walks toward Sora
		check("opening", asked and lit and main.enemies.size() == n_before + 1 and near and main.story_step == 2,
			"prompt=%s lamp lit=%s goblin rose beside it=%s step=%d (goblin %.1f,%.1f lamp %.1f,%.1f n %d->%d)" % [asked, lit, near, main.story_step, g.x, g.z, lamp.position.x, lamp.position.z, n_before, main.enemies.size()])
		g.x = 2.0
		g.z = 2.0
		g.node.visible = false
		check("lantern_scene", main.story_open, "touching the crown shows the lantern scene")
		main.close_story()
		await wait(0.6)
	if want.call("meet_bori"):
		reset_to(Vector2(main.shop_pos.x, main.shop_pos.z))
		main.story_step = 2
		tap(KEY_SPACE)
		await wait(0.2)
		var talking: bool = main.story_open and not main.shop_open
		for k in 40:
			if not main.story_open:
				break
			tap(KEY_SPACE)
			await wait(0.05)
		await wait(0.6)
		tap(KEY_SPACE)
		await wait(0.2)
		check("meet_bori", talking and main.story_step == 3 and main.shop_open,
			"first visit talks first=%s then the shop opens=%s" % [talking, main.shop_open])
		tap(KEY_ESCAPE)
		await wait(0.2)

	# ---- Ys-style combat (DESIGN.md milestone 1)
	var dummy := {}
	if want.call("flash_dodge"):
		reset_to(Vector2(30, 30))
		main.flash_cd = 0.0
		main.player.mp = 0.0
		main.dodge()
		var r: String = main.player_hit(10, Vector2(main.player.x + 1, main.player.z), dummy)
		check("flash_dodge", r == "flash_dodge" and main.player.hp == main.player.max_hp and main.slowmo > 1.5 and main.player.mp == 20.0,
			"result=%s hp=%d slowmo=%.1f momentum=%d" % [r, int(main.player.hp), main.slowmo, int(main.player.mp)])
		await wait(2.2)
	if want.call("late_dodge"):
		reset_to(Vector2(30, 30))
		main.flash_cd = 0.0
		main.dodge()
		await wait(0.25) # past the 0.15 s window but still rolling: i-frames, no slow-mo
		var r: String = main.player_hit(10, Vector2(main.player.x + 1, main.player.z), dummy)
		check("late_dodge", r == "none" and main.slowmo <= 0.0, "result=%s" % r)
		await wait(0.5)
	if want.call("flash_guard"):
		reset_to(Vector2(30, 30))
		main.player.face = Vector2(1, 0)
		var foe := {"stun": 0.0}
		main.fake_keys[KEY_L] = true
		await wait(0.05)
		var r: String = main.player_hit(10, Vector2(main.player.x + 1, main.player.z), foe)
		release()
		check("flash_guard", r == "flash_guard" and main.player.hp == main.player.max_hp and main.counter_t > 1.0 and foe.stun == 1.0,
			"result=%s hp=%d counter=%.1f stun=%.1f" % [r, int(main.player.hp), main.counter_t, foe.stun])
		await wait(0.2)
	if want.call("guard_block"):
		reset_to(Vector2(30, 30))
		main.player.face = Vector2(1, 0)
		main.player.sp = 100.0
		main.fake_keys[KEY_L] = true
		await wait(0.4) # held too long for a flash guard: a plain block
		var r: String = main.player_hit(10, Vector2(main.player.x + 1, main.player.z), dummy)
		release()
		check("guard_block", r == "guard" and main.player.hp == main.player.max_hp - 3 and main.player.sp <= 85.5,
			"result=%s hp lost %d (want 3) stamina %d" % [r, int(main.player.max_hp - main.player.hp), int(main.player.sp)])
		await wait(1.0)
	if want.call("guard_back"):
		reset_to(Vector2(30, 30))
		main.player.face = Vector2(1, 0)
		main.fake_keys[KEY_L] = true
		await wait(0.4)
		var r: String = main.player_hit(10, Vector2(main.player.x - 1, main.player.z), dummy)
		release()
		check("guard_back", r == "hit", "attack from behind is not blocked: %s" % r)
		await wait(1.0)
	if want.call("momentum"):
		calm_enemies(false)
		var gob = main.enemies.filter(func(e): return not e.get("boss", false) and not e.get("prop", false) and not e.dead)[0]
		calm_enemies(true)
		gob.node.visible = true
		reset_to(Vector2(30, 30))
		gob.x = 31.0
		gob.z = 30.0
		gob.atk_cd = 9.0
		main.player.mp = 0.0
		main.player.atk_cd = 0.0
		main.player.face = Vector2(1, 0)
		main.attack()
		await wait(0.3)
		check("momentum", main.player.mp >= 4.9, "one slash on one goblin: momentum %.1f (want 5)" % main.player.mp)
		gob.x = 2.0
		gob.z = 2.0
		gob.node.visible = false
	if want.call("level_moves"):
		calm_enemies(false)
		var gob = main.enemies.filter(func(e): return not e.get("boss", false) and not e.get("prop", false) and not e.dead and e.x < 50.0)[0]
		calm_enemies(true)
		gob.node.visible = true
		var lv0: int = main.player.lv
		var ghp0: float = gob.hp
		main.player.combo_t = 0.0
		# five-hit chain at Lv6: the fifth swing is the slam
		main.player.lv = 6
		reset_to(Vector2(30, 30))
		gob.x = 31.0
		gob.z = 30.0
		gob.hp = 99999.0
		gob.atk_cd = 99.0
		var combos: Array = []
		for k in 5:
			main.player.atk_cd = 0.0
			main.player.face = Vector2(1, 0)
			main.attack()
			combos.append(main.player.combo)
			await wait(0.1)
		var chain: bool = combos == [0, 1, 2, 3, 4]
		# dash slash at Lv3: running with Shift
		main.player.lv = 3
		reset_to(Vector2(26, 30))
		gob.x = 27.5
		gob.z = 30.0
		var hp1: float = gob.hp
		main.player.sp = 100.0
		main.player.face = Vector2(1, 0)
		main.player.vx = 6.0
		main.player.vz = 0.0
		main.player.atk_cd = 0.0
		main.fake_keys[KEY_SHIFT] = true
		main.attack()
		main.fake_keys.clear()
		var dashed: bool = main.player.x > 27.5 and gob.hp < hp1
		# charged slash at Lv4: guard a second, then J
		main.player.lv = 4
		reset_to(Vector2(30, 30))
		gob.x = 31.2
		gob.z = 30.0
		main.player.face = Vector2(1, 0)
		main.fake_keys[KEY_L] = true
		await wait(1.15)
		var hp2: float = gob.hp
		main.player.atk_cd = 0.0
		main.attack()
		main.fake_keys.clear()
		var charged: bool = hp2 - gob.hp >= main.player.atk * 2.5
		check("level_moves", chain and dashed and charged, "5-hit chain=%s %s dash moved and hit=%s charged cut=%.0f" % [chain, str(combos), dashed, hp2 - gob.hp])
		main.player.lv = lv0
		gob.hp = ghp0
		gob.atk_cd = 1.0
		gob.stun = 0.0
		gob.wind = 0.0
		gob.kx = 0.0
		gob.kz = 0.0
		gob.x = 2.0
		gob.z = 2.0
		gob.node.visible = false
	if want.call("skill_cost"):
		main.player.mp = 20.0
		main.player.cds = [0.0, 0.0, 0.0, 0.0]
		main.use_skill(0)
		var spent_none: bool = main.player.mp == 20.0
		main.player.mp = 40.0
		main.use_skill(0)
		check("skill_cost", spent_none and main.player.mp == 10.0, "whirl needs 30 momentum: at 20 nothing, at 40 left %d" % int(main.player.mp))
	if want.call("goblin_telegraph"):
		main.mate_cd = 9.0 # companions (from the lake and forest tests) would hit it and cut the wind-up short
		main.mate2_cd = 9.0
		calm_enemies(false)
		var gob = main.enemies.filter(func(e): return not e.get("boss", false) and not e.get("prop", false) and not e.dead)[0]
		calm_enemies(true)
		gob.node.visible = true
		reset_to(Vector2(30, 30))
		gob.x = 30.8
		gob.z = 30.0
		gob.hurt = 0.0
		gob.kx = 0.0
		gob.kz = 0.0
		gob.atk_cd = 0.0
		gob.wind = 0.0
		await wait(0.25)
		var during: float = main.player.hp
		var winding: bool = gob.get("wind", 0.0) > 0.0
		await wait(0.6)
		check("goblin_telegraph", winding and during == main.player.max_hp and main.player.hp < main.player.max_hp,
			"winding=%s hp during wind-up %d, after %d" % [winding, int(during), int(main.player.hp)])
		gob.x = 2.0
		gob.z = 2.0
		gob.node.visible = false
	if want.call("boss_phase2"):
		var boss = main.enemies.filter(func(e): return e.get("boss", false) and not e.dead)
		if boss.is_empty():
			check("boss_phase2", false, "no boss")
		else:
			var b0: Dictionary = boss[0]
			b0.hp = float(b0.max_hp) * 0.5 + 1.0
			reset_to(Vector2(b0.x, b0.z + 3.0))
			main.player.inv = 5.0
			main.damage_enemy(b0, 10.0, Vector2(main.player.x, main.player.z))
			await wait(0.3)
			var hp_now: float = b0.hp
			main.damage_enemy(b0, 50.0, Vector2(main.player.x, main.player.z))
			check("boss_phase2", b0.phase == 2 and b0.roar > 0.0 and b0.hp == hp_now,
				"phase=%d roaring=%s, hit during roar ignored=%s" % [b0.phase, b0.roar > 0.0, b0.hp == hp_now])
	if want.call("boss_opens_cave"):
		var boss = main.enemies.filter(func(e): return e.get("boss", false) and not e.dead)
		if boss.is_empty():
			check("boss_opens_cave", false, "no boss")
		else:
			boss[0].hp = 1.0
			boss[0].roar = 0.0
			boss[0].phase = 2
			main.damage_enemy(boss[0], 50.0, Vector2(main.player.x, main.player.z))
			await wait(2.0)
			var ok: bool = main.story_step == 5 and main.story_open and main.cave_pos.x > 0
			main.close_story()
			await wait(0.6)
			check("boss_opens_cave", ok, "boss down -> story step %d, cave at %s" % [main.story_step, main.cave_pos])

	if want.call("save_load"):
		main.player.lv = 4
		main.player.xp = 33
		main.player.gold = 77
		main.story_step = 3
		main.save_game()
		main.player.lv = 1
		main.player.xp = 0
		main.player.gold = 0
		main.story_step = 0
		main.load_game()
		check("save_load", main.player.lv == 4 and main.player.xp == 33 and main.player.gold == 77 and main.story_step == 3,
			"after reload: lv %d xp %d gold %d story %d" % [main.player.lv, main.player.xp, main.player.gold, main.story_step])
	if want.call("cave_enter"):
		main.story_step = 5
		if main.cave_pos.x < 0:
			main.cave_pos = Vector2(16, 3)
		reset_to(main.cave_pos + Vector2(0, 0.5))
		await wait(1.2)
		check("cave_enter", main.in_cave and main.story_step == 6 and main.walkable(main.player.x, main.player.z),
			"stepping on the cave mouth: in cave=%s step=%d at %.1f,%.1f" % [main.in_cave, main.story_step, main.player.x, main.player.z])
	if want.call("cave_layout"):
		var ok: bool = main.cave_marks.size() == 9 and not main.walkable(main.cave_marks.D.x, main.cave_marks.D.y) and main.walkable(main.cave_marks.K.x, main.cave_marks.K.y)
		check("cave_layout", ok, "marks %s, locked door blocks, key spot open" % [main.cave_marks.keys()])
	if want.call("archer_telegraph"):
		var ar = main.enemies.filter(func(e): return e.get("archer", false) and not e.dead)
		if ar.is_empty():
			check("archer_telegraph", false, "no archers in the cave")
		else:
			var a0: Dictionary = ar[0]
			reset_to(Vector2(a0.x - 4.5, a0.z))
			a0.atk_cd = 0.0
			a0.wind = 0.0
			await wait(0.3)
			var winding: bool = a0.get("wind", 0.0) > 0.0
			var hp0: float = main.player.hp
			await wait(2.0)
			check("archer_telegraph", winding and main.player.hp < hp0, "winds up=%s, brick hit for %d" % [winding, int(hp0 - main.player.hp)])
	if want.call("key_door"):
		reset_to(main.cave_marks.D + Vector2(-1.0, 0))
		tap(KEY_SPACE)
		await wait(0.2)
		var locked: bool = not main.cave_door_open
		reset_to(main.cave_marks.K)
		tap(KEY_SPACE)
		await wait(0.2)
		reset_to(main.cave_marks.D + Vector2(-1.0, 0))
		tap(KEY_SPACE)
		await wait(0.2)
		check("key_door", locked and main.has_key and main.cave_door_open and main.walkable(main.cave_marks.D.x, main.cave_marks.D.y),
			"locked first=%s key=%s open=%s" % [locked, main.has_key, main.cave_door_open])
	if want.call("rival_scene"):
		reset_to(main.cave_marks.P + Vector2(0, 0.5))
		await wait(0.3)
		var shown: bool = main.story_open
		main.close_story()
		await wait(0.6)
		check("rival_scene", shown and main.saw_painting, "painting scene with the rival shows once=%s" % shown)
	if want.call("cave_save_load"):
		main.in_cave = true
		reset_to(main.cave_marks.S + Vector2(3, 0))
		main.save_game()
		main.in_cave = false
		main.player.x = 15.0
		main.load_game()
		await wait(0.3)
		check("cave_save_load", main.in_cave and main.player.x > 100.0 and main.hero.visible and main.cave_door_open,
			"reloaded underground: in cave=%s x=%.1f sora visible=%s door stays open=%s" % [main.in_cave, main.player.x, main.hero.visible, main.cave_door_open])
	if want.call("unstick"):
		main.in_cave = true
		main.player.x = main.cave_marks.S.x - 1.4 # inside the wall left of the start
		main.player.z = main.cave_marks.S.y + 2.0
		await wait(0.3)
		var x0: float = main.player.x
		hold_world(Vector2(1, 0))
		await wait(0.6)
		release()
		check("unstick", main.player_can(main.player.x, main.player.z) and main.player.x > x0, "freed from the wall and walking: x %.1f -> %.1f" % [x0, main.player.x])
	if want.call("mole_charge"):
		var mo = main.enemies.filter(func(e): return e.get("mole", false) and not e.dead)
		if mo.is_empty():
			check("mole_charge", false, "no mole in the cave")
		else:
			var m0: Dictionary = mo[0]
			m0.x = main.cave_marks.B.x
			m0.z = main.cave_marks.B.y
			main.player.max_hp = 200
			reset_to(main.cave_marks.B - Vector2(3.0, 0))
			main.player.hp = 200.0
			m0.atk_cd = 0.0
			m0.next = "charge"
			m0.dash = 0.0
			m0.stun = 0.0
			m0.wind = 0.0
			calm_enemies(true)
			await wait(0.4)
			var winding: bool = m0.wind > 0.0
			var hp_wind: float = main.player.hp
			await wait(1.5)
			check("mole_charge", winding and hp_wind == 200.0 and main.player.hp < 200.0,
				"winds up=%s, no damage during wind-up=%s, charge hit for %d" % [winding, hp_wind == 200.0, int(200.0 - main.player.hp)])
	if want.call("mole_grants_skip"):
		var mo = main.enemies.filter(func(e): return e.get("mole", false) and not e.dead)
		if not mo.is_empty():
			mo[0].hp = 1.0
			mo[0].stun = 0.0
			main.damage_enemy(mo[0], 50.0, Vector2(main.player.x, main.player.z))
		await wait(1.6)
		var shown: bool = main.story_open
		main.close_story()
		await wait(0.6)
		check("mole_grants_skip", main.has_skip and shown, "mole down -> water skip=%s, scene shown=%s" % [main.has_skip, shown])
	if want.call("cave_faint"):
		main.in_cave = true
		reset_to(main.cave_marks.B - Vector2(3, 0))
		main.faint()
		await wait(0.3)
		check("cave_faint", not main.in_cave and main.ui.zone_name.text == "갈대늪" and main.player.x < 100.0,
			"fainting underground wakes outside with outside state: in cave=%s zone=%s" % [main.in_cave, main.ui.zone_name.text])
	if want.call("cave_exit"):
		main.has_skip = true
		main.cave_exit_seen = false
		main.in_cave = true
		reset_to(main.cave_marks.E + Vector2(-0.5, 0))
		await wait(1.2)
		var talk: bool = main.story_open
		main.close_story()
		await wait(0.6)
		check("cave_exit", talk and not main.in_cave and main.story_step == 7, "exit -> outside=%s step=%d" % [not main.in_cave, main.story_step])
	if want.call("water_skip"):
		main.in_cave = false
		main.has_skip = true
		reset_to(Vector2(19.0, 15.0)) # west bank of the river
		main.player.sp = 100.0
		main.fake_keys[KEY_SHIFT] = true
		hold_world(Vector2(1, 0))
		main.fake_keys[KEY_SHIFT] = true
		await wait(1.6)
		release()
		await wait(0.2)
		check("water_skip", main.player.x > 27.0, "with Shift held Sora runs across the river: x 19.0 -> %.1f" % main.player.x)
	if want.call("water_skip_letgo"):
		main.has_skip = true
		reset_to(Vector2(19.0, 15.0))
		main.player.sp = 15.0 # nearly out of stamina
		hold_world(Vector2(1, 0))
		main.fake_keys[KEY_SHIFT] = true
		await wait(0.5)
		main.fake_keys.erase(KEY_SHIFT) # lets go of Shift for a moment mid-river
		await wait(0.3)
		main.fake_keys[KEY_SHIFT] = true
		await wait(1.2)
		release()
		await wait(0.2)
		check("water_skip_letgo", main.player.x > 27.0, "low stamina and a short Shift let-go still cross: x 19.0 -> %.1f" % main.player.x)
	# ---- village (story step 8)
	if want.call("village_enter"):
		main.in_cave = false
		main.in_village = false
		main.story_step = 7
		main.errand = 0
		main.has_skip = true
		reset_to(Vector2(43.0, 20.0)) # east shore, then skip over the edge water with Shift
		main.player.sp = 100.0
		hold_world(Vector2(1, 0))
		main.fake_keys[KEY_SHIFT] = true
		await wait(1.6)
		release()
		await wait(0.6)
		var talk: bool = main.story_open
		main.close_story()
		await wait(0.6)
		check("village_enter", main.in_village and main.story_step == 8 and talk, "east edge -> village=%s step=%d arrival talk=%s" % [main.in_village, main.story_step, talk])
	if want.call("village_layout"):
		var lamps: int = main.village_lamps().size()
		check("village_layout", lamps == 12 and main.village.dark.size() == 3 and main.walkable(main.village.marks.M.x - 1.5, main.village.marks.M.y),
			"12 lanterns (%d), 3 dark (%d), square walkable" % [lamps, main.village.dark.size()])
	if want.call("simji_talk"):
		main.in_village = true
		main.errand = 0
		reset_to(main.village.marks.M + Vector2(-1.2, 0))
		tap(KEY_E)
		await wait(0.3)
		var talk: bool = main.story_open
		main.close_story()
		await wait(0.6)
		check("simji_talk", talk and main.errand == 1 and main.ui.quest.text.contains("0/3"), "talk=%s errand=%d quest=%s" % [talk, main.errand, main.ui.quest.text])
	if want.call("lamp_cost_night"):
		main.hour = 23.0
		main.crown_pips = 7
		var d0: Dictionary = main.village.dark[0]
		var n0: int = main.enemies.size()
		reset_to(d0.pos + Vector2(-1.0, 0))
		tap(KEY_E)
		await wait(1.3)
		check("lamp_cost_night", d0.lit and main.crown_pips == 6 and main.enemies.size() == n0 + 1, "lit=%s pips 7->%d goblin woke=%s" % [d0.lit, main.crown_pips, main.enemies.size() == n0 + 1])
	if want.call("lamp_cost_day"):
		main.hour = 13.0
		main.crown_pips = 6
		var d1: Dictionary = main.village.dark[1]
		reset_to(d1.pos + Vector2(-1.0, 0))
		tap(KEY_E)
		await wait(0.3)
		check("lamp_cost_day", d1.lit and main.crown_pips == 4, "by day a lantern costs 2: pips 6->%d" % main.crown_pips)
	if want.call("lamp_no_pips"):
		main.crown_pips = 0
		var d2: Dictionary = main.village.dark[2]
		reset_to(d2.pos + Vector2(-1.0, 0))
		tap(KEY_E)
		await wait(0.3)
		check("lamp_no_pips", not d2.lit and main.crown_pips == 0, "with no pips the lantern stays dark=%s" % (not d2.lit))
	if want.call("pip_rest"):
		calm_enemies(true)
		for e in main.enemies:
			if e.get("cave", false) and not e.get("mole", false):
				e.x = 2.0
				e.z = 2.0
		main.hour = 23.0
		main.crown_pips = 0
		var lit_lamp = main.lanterns.filter(func(l): return l.position.x > 130.0 and not l.get_meta("dark", false))[0]
		reset_to(Vector2(lit_lamp.position.x + 0.4, lit_lamp.position.z + 1.0))
		await wait(21.0)
		check("pip_rest", main.crown_pips == 2, "21 s resting by a lit lantern at night: pips 0->%d" % main.crown_pips)
	if want.call("errand_done"):
		main.crown_pips = 3
		main.hour = 23.0
		var d2: Dictionary = main.village.dark[2]
		reset_to(d2.pos + Vector2(-1.0, 0))
		tap(KEY_E)
		await wait(0.3)
		var g0: int = main.player.gold
		var p0: int = main.player.pots
		reset_to(main.village.marks.M + Vector2(-1.2, 0))
		tap(KEY_E)
		await wait(0.3)
		main.close_story()
		await wait(0.6)
		check("errand_done", main.errand == 3 and main.crown_pips == 8 and main.player.gold == g0 + 60 and main.player.pots == p0 + 1,
			"errand=%d pips=%d gold +%d pots +%d" % [main.errand, main.crown_pips, main.player.gold - g0, main.player.pots - p0])
	if want.call("kongal_errand"):
		main.errand = 3
		main.kid_q = 0
		var kp: Vector2 = main.village.folk_pos.kongal
		reset_to(kp + Vector2(1.0, 0))
		tap(KEY_E)
		await wait(0.3)
		main.close_story()
		var guards: Array = main.enemies.filter(func(e): return not e.dead and e.x > 130.0)
		var asked: bool = main.kid_q == 1 and guards.size() >= 3
		var kid: Vector3 = main.kid_node.position
		reset_to(Vector2(kid.x + 0.6, kid.z))
		main.player.inv = 5.0
		await wait(0.3)
		var held: bool = main.kid_q == 1 # guards still up: the kid stays
		for e in guards:
			e.dead = true
			e.node.visible = false
		await wait(0.3)
		var freed: bool = main.kid_q == 2
		reset_to(kp + Vector2(1.0, 0))
		await wait(2.5) # the kid trots after her at 5 m/s
		var follows: bool = main.kid_node.position.distance_to(Vector3(main.player.x, 0, main.player.z)) < 1.6
		var g0: int = main.player.gold
		var p0: int = main.player.pots
		tap(KEY_E)
		await wait(0.3)
		main.close_story()
		check("kongal_errand", asked and held and freed and follows and main.kid_q == 3 and main.player.gold == g0 + 40 and main.player.pots == p0 + 1,
			"asked=%s guards=%d held=%s freed=%s follows=%s kid_q=%d gold +%d pots +%d" % [asked, guards.size(), held, freed, follows, main.kid_q, main.player.gold - g0, main.player.pots - p0])
	if want.call("doran_errand"):
		main.kid_q = 3
		main.doran_q = 0
		main.hour = 23.0
		main.crown_pips = 8
		var dp: Vector2 = main.village.folk_pos.doran
		reset_to(dp + Vector2(1.0, 0))
		tap(KEY_E)
		await wait(0.3)
		main.close_story()
		var asked: bool = main.doran_q == 1
		tap(KEY_E)
		await wait(0.3)
		main.close_story()
		var read: bool = main.doran_q == 2 and main.crown_pips == 7
		main.in_village = false
		reset_to(Vector2(main.shop_pos.x, main.shop_pos.z))
		var hp0: int = main.player.max_hp
		main.crown_pips = 2
		tap(KEY_SPACE)
		await wait(0.3)
		var no_shop: bool = not main.shop_open
		main.close_story()
		check("doran_errand", asked and read and no_shop and main.doran_q == 3 and main.crown_pips == 8 and main.player.max_hp == hp0 + 10,
			"asked=%s read=%s delivered(no shop)=%s doran_q=%d pips=%d max_hp +%d" % [asked, read, no_shop, main.doran_q, main.crown_pips, main.player.max_hp - hp0])
		main.in_village = true
		reset_to(main.village.marks.M + Vector2(-1.2, 0))
	if want.call("mulgyeol_errand"):
		main.doran_q = 3
		main.mul_q = 0
		var mp: Vector2 = main.village.folk_pos.mulgyeol
		reset_to(mp + Vector2(-1.0, 0))
		tap(KEY_E)
		await wait(0.3)
		main.close_story()
		var asked: bool = main.mul_q == 1 and main.oar_node != null
		main.in_village = false
		main.has_skip = true
		reset_to(Vector2(13.6, 12.0)) # east shore of the pond: run west over the water to the oar
		main.player.inv = 5.0
		main.player.sp = 100.0
		hold_world(Vector2(-1, 0))
		main.fake_keys[KEY_SHIFT] = true
		await wait(1.0)
		release()
		await wait(0.4)
		var got: bool = main.mul_q == 2 and not main.oar_node.visible
		main.in_village = true
		reset_to(mp + Vector2(-1.0, 0))
		var g0: int = main.player.gold
		tap(KEY_E)
		await wait(0.3)
		main.close_story()
		check("mulgyeol_errand", asked and got and main.mul_q == 3 and main.player.gold == g0 + 50,
			"asked=%s got oar=%s mul_q=%d gold +%d cave=%s" % [asked, got, main.mul_q, main.player.gold - g0, main.in_cave])
		for e in main.enemies.filter(func(e): return not e.dead and e.x < 20.0 and e.z < 20.0):
			e.dead = true
			e.node.visible = false
	if want.call("lantern_night"):
		main.mul_q = 3
		main.night_q = 0
		main.hour = 22.0
		reset_to(main.village.marks.M + Vector2(-1.2, 0))
		await wait(0.3)
		var dark: int = main.village_lamps().filter(func(l): return not l.visible).size()
		var started: bool = main.night_q == 1 and dark == main.village_lamps().size()
		main.close_story()
		await wait(0.2)
		for i in 80: # stay just behind Noeul until he turns at the end of his path
			if main.night_q != 1:
				break
			var np: Vector3 = main.noeul_node.position
			reset_to(Vector2(np.x - 1.2, np.z))
			main.player.inv = 5.0
			await wait(0.1)
		var fell: bool = main.night_q == 2
		main.close_story()
		await wait(0.3)
		var lit: int = main.village_lamps().filter(func(l): return l.visible).size()
		var rose: bool = main.night_q == 3 and lit == main.village_lamps().size()
		main.close_story()
		await wait(0.3)
		var duel: Array = main.enemies.filter(func(e): return e.get("noeul", false) and not e.dead)
		var spawned: bool = duel.size() == 1
		if spawned:
			var e: Dictionary = duel[0]
			reset_to(Vector2(e.x - 1.5, e.z))
			main.player.inv = 9.0
			await wait(0.5)
			main.damage_enemy(e, 10000.0, Vector2(main.player.x, main.player.z))
			await wait(1.4)
		main.close_story()
		check("lantern_night", started and fell and rose and spawned and main.night_q == 4 and main.has_unbrick,
			"started=%s (dark %d) fell=%s rose=%s (lit %d) duel=%s night_q=%d unbrick=%s" % [started, dark, fell, rose, lit, spawned, main.night_q, main.has_unbrick])
		main.hour = 12.0
	if want.call("folk_again"):
		main.met["doran"] = true
		main.doran_q = 3
		reset_to(main.village.folk_pos.doran + Vector2(1.0, 0))
		tap(KEY_E)
		await wait(0.3)
		var said: String = main.ui.story_text.text
		main.close_story()
		check("folk_again", said.contains("배달을 마쳤"), "Doran after the letter: %s" % said.left(30))
	if want.call("lake"):
		main.night_q = 4
		main.lake_q = 0
		main.hour = 22.0
		reset_to(main.village.marks.K + Vector2(0, -0.3))
		await wait(1.5)
		var entered: bool = main.in_lake and main.lake_q == 1
		main.close_story()
		main.crown_pips = 8
		reset_to(main.lake.marks.D + Vector2(1.0, 0))
		tap(KEY_E)
		await wait(0.2)
		var thawed: bool = main.lake_q == 2 and main.lake.thawed and main.crown_pips == 6
		main.close_story()
		reset_to(Vector2(main.lake_npc.position.x - 1.0, main.lake_npc.position.z))
		tap(KEY_E)
		await wait(1.5)
		var rowed: bool = main.lake_q == 3 and main.mate != null and main.player.z > 13.0
		main.close_story()
		await wait(0.3)
		var turtle: Array = main.enemies.filter(func(e): return e.get("turtle", false) and not e.dead)
		if turtle.size() == 1:
			main.player.inv = 9.0
			main.damage_enemy(turtle[0], 10000.0, Vector2(main.player.x, main.player.z))
			await wait(1.4)
		var joined: bool = main.lake_q == 4
		main.close_story()
		reset_to(main.lake.marks.Q + Vector2(0, 1.0))
		tap(KEY_E)
		await wait(1.5)
		var back: bool = main.player.z < 5.0
		check("lake", entered and thawed and rowed and turtle.size() == 1 and joined and back,
			"entered=%s thawed=%s rowed=%s turtle=%d joined=%s rowed back=%s" % [entered, thawed, rowed, turtle.size(), joined, back])
		reset_to(main.lake.marks.S + Vector2(0, 0.3))
		await wait(1.5)
	if want.call("forest"):
		main.night_q = 4
		main.lake_q = 4
		main.forest_q = 0
		main.hour = 22.0
		reset_to(main.village.marks.F + Vector2(-0.3, 0))
		await wait(1.5)
		var entered: bool = main.in_forest and main.forest_q == 1
		main.close_story()
		await wait(0.2)
		var w0: Dictionary = main.forest.walls[0]
		var shut: bool = not main.walkable(w0.pos.x, w0.pos.y)
		main.crown_pips = 8
		reset_to(w0.pos + Vector2(-1.0, 0))
		main.player.inv = 9.0
		tap(KEY_E)
		await wait(0.2)
		var opened: bool = w0.open and main.walkable(w0.pos.x, w0.pos.y) and main.crown_pips == 6
		reset_to(main.forest.marks.N + Vector2(-4.0, 0))
		main.player.inv = 9.0
		await wait(0.3)
		var met: bool = main.forest_q == 2
		main.close_story()
		await wait(0.3)
		var duel: Array = main.enemies.filter(func(e): return e.get("second", false) and not e.dead)
		if duel.size() == 1:
			main.damage_enemy(duel[0], 10000.0, Vector2(main.player.x, main.player.z))
			await wait(1.4)
		main.close_story()
		check("forest", entered and shut and opened and met and duel.size() == 1 and main.forest_q == 3,
			"entered=%s wall shut=%s opened=%s met Noeul=%s duel=%d forest_q=%d" % [entered, shut, opened, met, duel.size(), main.forest_q])
		for e in main.enemies.filter(func(e): return not e.dead and e.x > 170.0):
			e.dead = true
			e.node.visible = false
		reset_to(main.forest.marks.S + Vector2(0.3, 0))
		await wait(1.5)
		main.hour = 12.0
		main.in_village = true
		reset_to(main.village.marks.M + Vector2(-1.2, 0))
	if want.call("hill"):
		main.forest_q = 3
		main.hill_q = 0
		main.in_village = false
		main.in_forest = true
		main.hour = 22.0
		reset_to(main.forest.marks.E + Vector2(-0.3, 0))
		await wait(1.5)
		var shields: Array = main.enemies.filter(func(e): return not e.dead and e.get("shield", 0) > 0)
		var entered: bool = main.in_hill and main.hill_q == 1 and shields.size() == 3 and main.mate2 != null
		main.close_story()
		var sg: Dictionary = shields[0] if shields.size() > 0 else {}
		var hp0: float = sg.get("hp", 0.0)
		if not sg.is_empty():
			main.damage_enemy(sg, 50.0, Vector2(sg.x - 1.0, sg.z))
		var blocked: bool = not sg.is_empty() and sg.shield == 2 and sg.hp == hp0
		main.crown_pips = 8
		for mill in main.hill.mills:
			reset_to(mill.pos + Vector2(1.3, 0))
			main.player.inv = 9.0
			tap(KEY_E)
			await wait(0.2)
		var bridged: bool = main.hill_q == 2 and main.hill.bridged and main.walkable(main.hill.HILL_X + 20, 12) and main.crown_pips == 5
		main.close_story()
		reset_to(main.hill.marks.B + Vector2(-4.5, 0))
		main.player.inv = 30.0
		await wait(0.3)
		main.close_story()
		await wait(0.3)
		var hawk: Array = main.enemies.filter(func(e): return e.get("hawk", false) and not e.dead)
		var out_of_reach := false
		if hawk.size() == 1:
			var h0: float = hawk[0].hp
			main.damage_enemy(hawk[0], 100.0, Vector2(main.player.x, main.player.z))
			out_of_reach = hawk[0].hp == h0
			hawk[0].air = false
			main.damage_enemy(hawk[0], 10000.0, Vector2(main.player.x, main.player.z))
			await wait(1.4)
		main.close_story()
		check("hill", entered and blocked and bridged and hawk.size() == 1 and out_of_reach and main.hill_q == 3,
			"entered=%s shield blocked=%s bridge=%s hawk=%d air-proof=%s hill_q=%d" % [entered, blocked, bridged, hawk.size(), out_of_reach, main.hill_q])
		for e in main.enemies.filter(func(e): return not e.dead and e.x > 300.0):
			e.dead = true
			e.node.visible = false
		reset_to(main.hill.marks.S + Vector2(0.3, 0))
		await wait(1.5)
		main.in_forest = false
		main.in_village = true
		main.hour = 12.0
	if want.call("garden_end"):
		main.forest_q = 3
		main.hill_q = 3
		main.garden_q = 0
		main.in_village = false
		main.in_hill = true
		main.castle_q = 3
		reset_to(main.castle.marks.E + Vector2(-0.3, 0))
		await wait(1.5)
		var entered: bool = main.in_garden and main.garden_q == 1
		main.close_story()
		reset_to(main.garden.marks.C + Vector2(-6.0, 0))
		main.player.inv = 30.0
		await wait(0.3)
		var mold: Array = main.enemies.filter(func(e): return e.get("mold", false) and not e.dead)
		var fought: bool = main.garden_q == 2 and mold.size() == 1
		if fought:
			mold[0].hp = mold[0].max_hp * 0.13
			main.damage_enemy(mold[0], 30.0, Vector2(main.player.x, main.player.z))
			await wait(0.3)
		var locked: bool = main.garden_q == 3 and mold.size() == 1 and mold[0].locked and main.crown_pips == 0
		main.close_story()
		await wait(0.2)
		var shards_came: bool = main.enemies.any(func(e): return e.get("shard", false) and not e.dead)
		var snuffed := false
		if shards_came: # let one pair reach its post once: the post must start over
			var sh: Array = main.enemies.filter(func(e): return e.get("shard", false) and not e.dead)
			sh[0].x = sh[0].post.x
			sh[0].z = sh[0].post.y
			await wait(0.1)
			snuffed = main.ring_k == 0 and main.enemies.filter(func(e): return e.get("shard", false) and not e.dead).size() == 2
		for i in 80: # then cut the shards down as they come
			if main.garden_q == 4:
				break
			for e in main.enemies.filter(func(e): return e.get("shard", false) and not e.dead):
				main.damage_enemy(e, 999.0, Vector2(main.player.x, main.player.z))
			await wait(0.3)
		var ready: bool = main.garden_q == 4 and main.crown_pips == 8 and shards_came and snuffed
		tap(KEY_E)
		await wait(0.3)
		main.close_story()
		await wait(0.4)
		var ended: bool = main.story_step == 12 and main.garden_q == 5 and mold[0].dead
		main.close_story()
		check("garden_end", entered and fought and locked and ready and ended,
			"entered=%s fought=%s locked at 12%%=%s lights filled=%s ended=%s step=%d" % [entered, fought, locked, ready, ended, main.story_step])
		reset_to(main.garden.marks.S + Vector2(0.3, 0))
		await wait(1.5)
		main.in_hill = false
		main.in_forest = false
		main.in_village = true
		reset_to(main.village.marks.M + Vector2(-1.2, 0))
	if want.call("village_exit"):
		reset_to(main.village.marks.G + Vector2(0.6, 0))
		main.player.x = main.village.marks.G.x + 0.3
		await wait(1.2)
		check("village_exit", not main.in_village and main.player.x < 48.0, "west gate -> outside=%s x=%.1f" % [not main.in_village, main.player.x])
	if want.call("marsh_scraps"):
		main.in_village = false
		main.in_forest = false
		main.in_lake = false
		main.in_hill = false
		main.in_garden = false
		calm_enemies(true)
		var walk_ok := true
		for p in MARSH.SCRAPS + [MARSH.CHEST_AT]:
			walk_ok = walk_ok and main.player_can(p.x, p.y)
		for i in 3:
			reset_to(MARSH.SCRAPS[i])
			await wait(0.2)
			main.close_story()
		var whole: bool = main.marsh.count() == 3 and main.marsh.chest.visible
		var atk0: int = main.player.atk
		var hp0: int = main.player.max_hp
		reset_to(MARSH.CHEST_AT + Vector2(0.8, 0))
		tap(KEY_SPACE)
		await wait(0.2)
		main.close_story()
		var opened: bool = main.marsh.chest_open and main.player.atk == atk0 + 4 and main.player.max_hp == hp0 + 20
		main.save_game()
		main.marsh.found = [false, false, false]
		main.marsh.chest_open = false
		var sd = JSON.parse_string(FileAccess.get_file_as_string(main.SAVE_PATH))
		main.marsh.restore(sd.get("scraps", []), bool(sd.get("moon_chest", false)))
		var kept: bool = main.marsh.count() == 3 and main.marsh.chest_open and not main.marsh.nodes[0].visible
		calm_enemies(false)
		check("marsh_scraps", walk_ok and whole and opened and kept, "spots walkable=%s whole map=%s opened=%s (atk +%d) kept after load=%s" % [walk_ok, whole, opened, main.player.atk - atk0, kept])
	if want.call("forest_grove"):
		main.in_village = false
		main.in_lake = false
		main.in_hill = false
		main.in_garden = false
		main.in_forest = true
		calm_enemies(true)
		var fx0: int = main.FOREST.FOREST_X
		var shut: bool = not main.player_can(main.forest.marks.V.x, main.forest.marks.V.y)
		reset_to(Vector2(fx0 + 2, 5)) # by the tablet
		tap(KEY_E)
		await wait(0.2)
		var read: bool = main.story_open
		main.close_story()
		for k in 4:
			var st: Dictionary = main.forest.stones[k]
			reset_to(st.pos + Vector2(-1.0 if k == 0 else 0.0, 0.0 if k == 0 else 1.0))
			for n in (3 - k - st.phase + 8) % 4:
				tap(KEY_E)
				await wait(0.15)
		await wait(0.2)
		main.close_story()
		var solved: bool = main.forest.solved and main.player_can(main.forest.marks.V.x, main.forest.marks.V.y)
		var hp0: int = main.player.max_hp
		reset_to(main.forest.marks.c + Vector2(-1.0, 0))
		tap(KEY_E)
		await wait(0.2)
		main.close_story()
		var opened: bool = main.forest.chest_open and main.player.max_hp == hp0 + 15
		main.in_forest = false
		calm_enemies(false)
		check("forest_grove", shut and read and solved and opened, "wall shut=%s tablet read=%s solved=%s phases=%s chest=%s" % [shut, read, solved, main.forest.stones.map(func(s): return s.phase), opened])
	if want.call("firefly_errand"):
		main.errand = 3
		main.kid_q = 3
		main.doran_q = 3
		main.fly_q = 0
		main.met["kongal"] = true
		main.in_village = true
		main.in_forest = false
		calm_enemies(true)
		var kp: Vector2 = main.village.folk_pos.kongal
		reset_to(kp + Vector2(-1.0, 0))
		tap(KEY_E)
		await wait(0.3)
		main.close_story()
		var asked: bool = main.fly_q == 1
		main.in_village = false
		main.hour = 13.0
		await wait(0.2)
		var hidden_by_day: bool = not main.marsh.flies[0].node.visible
		main.hour = 22.0
		await wait(0.2)
		var walk_ok := true
		for f in main.marsh.flies:
			walk_ok = walk_ok and main.player_can(f.home.x, f.home.y)
		for i in 5:
			var n: Node3D = main.marsh.flies[i].node
			reset_to(Vector2(n.position.x, n.position.z))
			await wait(0.15)
		var full: bool = main.fly_q == 2
		main.in_village = true
		var g0: int = main.player.gold
		reset_to(kp + Vector2(-1.0, 0))
		tap(KEY_E)
		await wait(0.3)
		main.close_story()
		var lent: bool = main.fly_q == 3 and main.jar_node != null and main.player.gold == g0 + 30
		main.in_village = false
		calm_enemies(false)
		check("firefly_errand", asked and hidden_by_day and walk_ok and full and lent, "asked=%s hidden by day=%s spots walkable=%s caught=%d lent jar=%s" % [asked, hidden_by_day, walk_ok, main.marsh.caught(), lent])
	if want.call("grotto"):
		main.in_village = false
		main.in_forest = false
		main.in_hill = false
		main.in_garden = false
		main.in_lake = true
		main.lake_q = 4
		main.grotto_q = 0
		main.story_step = maxi(main.story_step, 10)
		main.has_skip = true
		var gx: float = main.GROTTO.GROTTO_X
		reset_to(main.lake.marks.G + Vector2(0, -0.3))
		await wait(1.0)
		var entered: bool = main.in_grotto() and main.grotto_q == 1
		main.close_story()
		await wait(0.1)
		calm_enemies(true)
		reset_to(Vector2(gx + 7.6, 4))
		hold_world(Vector2(1, 0))
		await wait(1.0)
		release()
		var no_skip: bool = main.player.x < gx + 9.0
		reset_to(Vector2(gx + 7.6, 4))
		main.player.sp = 100.0
		hold_world(Vector2(1, 0))
		main.fake_keys[KEY_SHIFT] = true
		await wait(1.0)
		release()
		var crossed: bool = main.player.x > gx + 12.0
		reset_to(Vector2(gx + 16, 9.5))
		main.player.sp = 100.0
		hold_world(Vector2(0, 1))
		main.fake_keys[KEY_SHIFT] = true
		await wait(1.0)
		release()
		await wait(0.2)
		var met_crab: bool = main.grotto_q == 2
		main.close_story()
		await wait(0.2)
		var crabs: Array = main.enemies.filter(func(e): return e.get("crab", false) and not e.dead)
		var spat := false
		if crabs.size() == 1:
			var c: Dictionary = crabs[0]
			main.player.inv = 99.0
			for i in 40:
				reset_to(Vector2(c.x + 6.0, c.z)) # keep backing off: from afar the crab spits
				main.player.inv = 99.0
				await wait(0.1)
				if main.enemy_shots.size() >= 3:
					spat = true
					break
			main.player.inv = 0.0
			c.hp = 1.0
			main.damage_enemy(c, 50.0, Vector2(c.x, c.z - 1.0))
		await wait(1.3)
		main.close_story()
		var beaten: bool = main.grotto_q == 3 and main.grotto.chest.visible
		reset_to(main.grotto.marks.c + Vector2(-1.0, 0))
		tap(KEY_E)
		await wait(0.2)
		main.close_story()
		var pearl: bool = main.has_pearl and main.grotto_q == 4
		var g0: int = main.player.gold
		reset_to(main.grotto.marks.p + Vector2(0, 1.0))
		tap(KEY_SPACE)
		await wait(0.2)
		var side: bool = main.grotto_side and main.player.gold == g0 + 60
		main.in_lake = false
		calm_enemies(false)
		check("grotto", entered and no_skip and crossed and met_crab and spat and beaten and pearl and side,
			"entered=%s walk stops at water=%s skip crossed=%s crab woke=%s spat bricks=%s beaten=%s pearl=%s side chest=%s" % [entered, no_skip, crossed, met_crab, spat, beaten, pearl, side])
	if want.call("cloud"):
		main.in_village = false
		main.in_forest = false
		main.in_lake = false
		main.in_garden = false
		main.in_hill = true
		main.hill_q = 3
		main.cloud_q = 0
		main.story_step = maxi(main.story_step, 10)
		var cx: float = main.CLOUD.CLOUD_X
		reset_to(main.hill.marks.U + Vector2(0, 0.3))
		await wait(1.0)
		var entered: bool = main.in_cloud() and main.cloud_q == 1
		main.close_story()
		await wait(0.1)
		calm_enemies(true)
		var hops := []
		for leg in [[Vector2(cx + 3.6, 10), Vector2(1, 0)], [Vector2(cx + 12, 8.4), Vector2(0, -1)]]:
			reset_to(leg[0])
			hold_world(leg[1])
			await wait(1.4)
			release()
			await wait(0.1)
			hops.append(Vector2(main.player.x - cx, main.player.z))
		var flew: bool = hops[0].x > 10.2 and hops[0].x < 13.0 and hops[1].y < 3.5 and hops[1].y > 0.5 and main.gust_dir == Vector2.ZERO
		reset_to(main.cloud.marks.c + Vector2(-1.0, 0))
		tap(KEY_E)
		await wait(0.2)
		var chest: bool = main.cloud_chest
		reset_to(Vector2(cx + 13.6, 10))
		hold_world(Vector2(1, 0))
		await wait(1.4)
		release()
		await wait(0.2)
		var woke: bool = main.cloud_q == 2 and main.player.x > cx + 20.0
		main.close_story()
		await wait(0.2)
		var foes: Array = main.enemies.filter(func(e): return e.get("scare", false) and not e.dead)
		var flung := false
		if foes.size() == 1:
			var k: Dictionary = foes[0]
			for i in 40:
				reset_to(Vector2(cx + 20.5, 14.0)) # stay off to the side: from afar it flings bricks four ways
				main.player.inv = 99.0
				await wait(0.1)
				if main.enemy_shots.size() >= 4:
					flung = true
					break
			main.player.inv = 0.0
			k.hp = 1.0
			main.damage_enemy(k, 50.0, Vector2(k.x, k.z - 1.0))
		await wait(1.3)
		main.close_story()
		main.player.sp = 100.0
		main.player.dodge = 0.0
		tap(KEY_K)
		await wait(0.05)
		var cheap_roll: bool = main.has_feather and main.player.sp > 80.0
		main.in_hill = false
		calm_enemies(false)
		check("cloud", entered and flew and chest and woke and flung and cheap_roll,
			"entered=%s hops=%s chest=%s scarecrow woke=%s flung bricks=%s feather roll=%s (sp %.0f)" % [entered, hops, chest, woke, flung, cheap_roll, main.player.sp])
	if want.call("castle"):
		main.in_village = false
		main.in_forest = false
		main.in_lake = false
		main.in_garden = false
		main.in_hill = true
		main.hill_q = 3
		main.castle_q = 0
		main.has_unbrick = true
		main.has_skip = true
		main.crown_pips = 8
		main.hour = 22.0
		main.story_step = maxi(main.story_step, 10)
		var cx: float = main.CASTLE.CASTLE_X
		reset_to(main.hill.marks.X + Vector2(-0.3, 0))
		await wait(1.0)
		var entered: bool = main.in_castle() and main.castle_q == 1
		main.close_story()
		await wait(0.1)
		calm_enemies(true)
		var shut: bool = not main.player_can(cx + 9, 13)
		reset_to(Vector2(cx + 7.8, 13.5))
		tap(KEY_E)
		await wait(0.2)
		var gate: bool = main.castle.gate_open and main.player_can(cx + 9, 13)
		reset_to(Vector2(cx + 11.6, 13.5))
		main.player.sp = 100.0
		hold_world(Vector2(1, 0))
		main.fake_keys[KEY_SHIFT] = true
		await wait(1.0)
		release()
		var skipped: bool = main.player.x > cx + 16.0
		reset_to(Vector2(cx + 21.6, 13))
		hold_world(Vector2(1, 0))
		await wait(1.4)
		release()
		await wait(0.1)
		var vented: bool = main.player.x > cx + 27.0 and main.gust_dir == Vector2.ZERO
		var shut_door: bool = not main.player_can(cx + 31, 13)
		for pg in main.castle.pages:
			reset_to(pg.pos + Vector2(1.0, 0))
			tap(KEY_E)
			await wait(0.2)
			main.close_story()
			await wait(0.1)
		var door: bool = main.castle.pages_read() == 3 and main.castle.door_open and main.player_can(cx + 31, 13)
		reset_to(main.castle.marks.K + Vector2(-4.0, 0))
		await wait(0.3)
		var woke: bool = main.castle_q == 2
		main.close_story()
		await wait(0.2)
		var ks: Array = main.enemies.filter(func(e): return e.get("knight", false) and not e.dead)
		var shield := false
		var flank := false
		var guard_opens := false
		if ks.size() == 1:
			var k: Dictionary = ks[0]
			k.atk_cd = 99.0
			var front: Vector2 = Vector2(k.x, k.z) + k.face * 1.5
			var hp0: float = k.hp
			main.damage_enemy(k, 40.0, front)
			shield = k.hp == hp0
			main.damage_enemy(k, 40.0, Vector2(k.x, k.z) - k.face * 1.5)
			flank = k.hp < hp0
			reset_to(front)
			main.player.face = -k.face
			main.guarding = true
			main.guard_since = main.t
			var res: String = main.player_hit(10, Vector2(k.x, k.z), k)
			main.guarding = false
			var hp1: float = k.hp
			main.damage_enemy(k, 40.0, front)
			guard_opens = res == "flash_guard" and k.hp < hp1
			k.hp = 1.0
			k.stun = 1.0
			main.damage_enemy(k, 40.0, front)
		await wait(1.3)
		main.close_story()
		var beaten: bool = main.castle_q == 3
		reset_to(main.castle.marks.E + Vector2(-0.3, 0))
		await wait(1.5)
		var to_garden: bool = main.in_garden
		main.close_story()
		reset_to(main.garden.marks.S + Vector2(0.3, 0))
		await wait(1.5)
		var back: bool = main.in_castle()
		main.in_hill = false
		calm_enemies(false)
		check("castle", entered and shut and gate and skipped and vented and shut_door and door and woke and shield and flank and guard_opens and beaten and to_garden and back,
			"entered=%s gate shut/open=%s/%s skip=%s vent=%s door shut=%s pages open door=%s knight woke=%s front blocked=%s flank hits=%s flash guard opens=%s beaten=%s to garden=%s back=%s" % [entered, shut, gate, skipped, vented, shut_door, door, woke, shield, flank, guard_opens, beaten, to_garden, back])
	if want.call("shrine"):
		main.in_village = false
		main.in_forest = false
		main.in_lake = false
		main.in_garden = false
		main.in_hill = false
		main.skill_up = -1
		main.shrine_seen = false
		main.story_step = maxi(main.story_step, 6)
		main.enter_cave()
		main.close_story()
		await wait(0.1)
		calm_enemies(true)
		var cx: float = main.CAVE_X
		var reach: bool = main.player_can(cx + 4, 17) and main.player_can(cx + 4, 19)
		reset_to(Vector2(cx + 4, 18.5))
		await wait(0.3)
		var seen: bool = main.shrine_seen and main.story_open
		main.close_story()
		reset_to(main.cave_marks["1"] + Vector2(0, -1.0))
		tap(KEY_E)
		await wait(0.2)
		main.close_story()
		var whirl: bool = main.skill_up == 0
		reset_to(main.cave_marks["3"] + Vector2(0, -1.0))
		tap(KEY_SPACE)
		await wait(0.2)
		main.close_story()
		var nova: bool = main.skill_up == 2 and main.skill_cost(2) == 45
		main.player.hp = 50.0
		main.player.mp = 100.0
		main.player.cds[2] = 0.0
		tap(KEY_O)
		await wait(0.1)
		var healed: bool = main.player.hp > 50.0 and main.player.mp < 60.0 # 45 spent, a little drained by idling
		main.leave_cave()
		await wait(0.2)
		calm_enemies(false)
		check("shrine", reach and seen and whirl and nova and healed, "room reachable=%s shrine scene=%s whirl woke=%s nova woke (cost 45)=%s nova heals=%s (hp %.0f, mp %.0f)" % [reach, seen, whirl, nova, healed, main.player.hp, main.player.mp])
	if want.call("journal"):
		if main.intro:
			main.start_game(false)
		main.close_story()
		await wait(0.1)
		main.story_step = maxi(main.story_step, 6)
		tap(KEY_Q)
		await wait(0.1)
		var shown: bool = main.ui.journal.visible
		var txt: String = main.ui.journal_text.text + main.ui.journal_text2.text
		var has: bool = "지금 할 일" in txt and "늪의 옛 지도 조각" in txt and "곁이야기" in txt and "지닌 것" in txt
		tap(KEY_H)
		await wait(0.1)
		var swapped: bool = main.ui.help.visible and not main.ui.journal.visible
		main.toggle_help(false)
		check("journal", shown and has and swapped, "opens with Q=%s lists quest, side stories, keepsakes=%s help swaps it out=%s" % [shown, has, swapped])
	if want.call("wolf"):
		if main.intro:
			main.start_game(false)
		main.close_story()
		calm_enemies(true)
		reset_to(Vector2(20, 30))
		main.spawn_wolf(Vector2(24, 30))
		var w: Dictionary = main.enemies[main.enemies.size() - 1]
		w.atk_cd = 2.0
		w.hp = 99999.0 # companions join in during the full run; keep it alive long enough to watch
		var hp0: float = main.player.hp
		var circled := false
		var lunged := false
		var start_ang := atan2(w.z - 30.0, w.x - 20.0)
		for i in 60:
			reset_to(Vector2(20, 30))
			main.player.hp = hp0
			await wait(0.1)
			if absf(wrapf(atan2(w.z - 30.0, w.x - 20.0) - start_ang, -PI, PI)) > 0.4:
				circled = true
			if w.dash > 0.0:
				lunged = true
		var spawned_forest: bool = main.forest.wolves.size() == 3
		if not w.dead:
			w.dead = true
			w.node.queue_free()
			w.shadow.queue_free()
		calm_enemies(false)
		check("wolf", circled and lunged and spawned_forest, "circles=%s lunges=%s forest pack=%d" % [circled, lunged, main.forest.wolves.size()])
	if want.call("trial"):
		if main.intro:
			main.start_game(false)
		main.close_story()
		main.in_village = true
		main.in_forest = false
		main.in_hill = false
		main.in_lake = false
		main.in_garden = false
		main.night_q = 4
		main.trial_best = 0.0
		calm_enemies(true)
		reset_to(main.village.marks.R + Vector2(0, 1.0))
		tap(KEY_E)
		await wait(0.2)
		var began: bool = main.trial_wave == 1
		main.close_story()
		var g0: int = main.player.gold
		var lv0: int = main.player.lv
		var hp0: int = main.player.max_hp
		var waves := 0
		for i in 120:
			main.player.inv = 9.0
			var foes: Array = main.trial_foes()
			if not foes.is_empty():
				waves = maxi(waves, main.trial_wave)
				for e in foes:
					main.damage_enemy(e, 99999.0, Vector2(main.player.x, main.player.z))
			if main.trial_wave == 0:
				break
			await wait(0.3)
		main.close_story()
		var cleared: bool = main.trial_best > 0.0 and main.player.gold >= g0 + 300 and main.player.max_hp == hp0 + 20 + 12 * (main.player.lv - lv0) # kills level her up too
		calm_enemies(false)
		check("trial", began and waves == 5 and cleared, "began=%s waves seen=%d cleared=%s best %.1f s" % [began, waves, cleared, main.trial_best])
	if want.call("squirrels"):
		if main.intro:
			main.start_game(false)
		main.close_story()
		main.in_village = false
		main.in_forest = true
		main.forest_q = maxi(main.forest_q, 1)
		main.forest.freed = [false, false, false, false, false]
		main.has_acorn = false
		main.cages_spawned = false
		main.spawn_cages()
		var cages: Array = main.enemies.filter(func(e): return e.has("cage") and not e.dead)
		var spots := true
		for c in cages:
			spots = spots and main.walkable(c.x + 1.0, c.z) or main.walkable(c.x - 1.0, c.z) or main.walkable(c.x, c.z + 1.0)
		var first: Dictionary = cages[0] if cages.size() > 0 else {}
		var two_hits := false
		if not first.is_empty():
			main.damage_enemy(first, 10.0, Vector2(first.x - 1.0, first.z))
			main.damage_enemy(first, 10.0, Vector2(first.x - 1.0, first.z))
			two_hits = not first.dead
		for c in cages:
			for k in 3:
				main.damage_enemy(c, 10.0, Vector2(c.x - 1.0, c.z))
		await wait(0.2)
		main.close_story()
		main.player.hp = 10.0
		main.player.pots = 1
		main.player.cds[3] = 0.0
		tap(KEY_4)
		await wait(0.1)
		var acorn: bool = main.has_acorn and main.player.hp >= 75.0 - 0.5
		main.in_forest = false
		check("squirrels", cages.size() == 5 and spots and two_hits and acorn, "cages=%d reachable=%s still shut after 2 hits=%s acorn heals 65=%s (hp %.0f)" % [cages.size(), spots, two_hits, acorn, main.player.hp])
	if want.call("crystals"):
		main.story_step = maxi(main.story_step, 6)
		if main.intro:
			main.start_game(false)
		main.close_story()
		await wait(0.1)
		var cr: Array = main.crystals
		main.crystal_done = false
		main.crystal_run = 0
		main.has_ring = false
		var by_rank := {}
		for e in cr:
			by_rank[main.CRYSTAL_NOTE[int(e.crystal)]] = e
		var ring := func(rank: int):
			var e: Dictionary = by_rank[rank]
			e.hurt = 0.0
			main.crystal_hit(e)
		var low: Dictionary = by_rank[0]
		main.in_cave = true
		reset_to(Vector2(low.x - 1.0, low.z))
		main.player.face = Vector2(1, 0)
		main.player.atk_cd = 0.0
		main.attack() # a real sword swing rings the lowest crystal
		var sword_rings: bool = main.crystal_run == 1
		main.in_cave = false
		main.crystal_run = 0
		await wait(0.3)
		ring.call(0)
		ring.call(2) # wrong: back to the start
		var reset: bool = main.crystal_run == 0
		for k in 4:
			ring.call(k)
		var done: bool = main.crystal_done and main.crystal_chest.visible
		var reach: bool = main.walkable(main.crystal_chest.position.x - 1.0, main.crystal_chest.position.z)
		main.in_cave = true
		reset_to(Vector2(main.crystal_chest.position.x - 1.0, main.crystal_chest.position.z))
		tap(KEY_SPACE)
		await wait(0.2)
		main.close_story()
		main.in_cave = false
		check("crystals", cr.size() == 4 and sword_rings and reset and done and reach and main.has_ring, "crystals=%d sword rings=%s wrong note resets=%s solved=%s chest reachable=%s ring=%s" % [cr.size(), sword_rings, reset, done, reach, main.has_ring])
	if want.call("race"):
		main.story_step = maxi(main.story_step, 10)
		if main.intro:
			main.start_game(false)
		main.close_story()
		main.in_village = false
		main.in_hill = true
		main.hill_q = maxi(main.hill_q, 1)
		main.has_shoes = false
		main.race_best = 0.0
		calm_enemies(true)
		await wait(0.2)
		main.close_story()
		var hx: float = main.HILL.HILL_X
		var spots := true
		for p in main.RACE_WHEELS + [main.RACE_POST + Vector2(1, 0)]:
			spots = spots and main.walkable(hx + p.x, p.y)
		reset_to(Vector2(hx + main.RACE_POST.x + 1.0, main.RACE_POST.y))
		tap(KEY_E)
		await wait(0.1)
		var started: bool = main.race_on
		for p in main.RACE_WHEELS:
			reset_to(Vector2(hx + p.x, p.y))
			await wait(0.1)
		await wait(0.2)
		main.close_story()
		var won: bool = not main.race_on and main.has_shoes and main.race_best > 0.0
		reset_to(Vector2(hx + main.RACE_POST.x + 1.0, main.RACE_POST.y))
		tap(KEY_E)
		await wait(0.1)
		main.race_left = 0.05
		await wait(0.2)
		var timed_out: bool = not main.race_on
		main.in_hill = false
		calm_enemies(false)
		check("race", spots and started and won and timed_out, "spots walkable=%s started=%s won shoes=%s (best %.1f s) runs out of time=%s" % [spots, started, won, main.race_best, timed_out])
	if want.call("vault"):
		main.story_step = maxi(main.story_step, 10)
		if main.intro:
			main.start_game(false)
		await wait(0.2)
		main.close_story()
		main.in_village = false
		main.in_hill = true
		main.has_armour = false
		var cx: float = main.CASTLE.CASTLE_X
		var shut: bool = not main.player_can(cx + 22, 23)
		for i in [0, 1, 2]: # all three: gates 1 and 3 open, gate 2 flipped twice
			reset_to(main.castle.levers[i].pos + Vector2(0, 1.0))
			tap(KEY_E)
			await wait(0.1)
		var wrong: bool = not main.castle.vault_solved()
		reset_to(main.castle.levers[1].pos + Vector2(0, 1.0))
		tap(KEY_E) # back off the middle lever: levers 1 and 3 alone open everything
		await wait(0.1)
		var solved: bool = main.castle.vault_solved() and main.player_can(cx + 22, 23)
		reset_to(Vector2(cx + 27, 23))
		tap(KEY_E)
		await wait(0.2)
		main.close_story()
		var hp0: float = main.player.hp
		main.player.inv = 0.0
		main.hurt_player(20, 0.0)
		var less: bool = main.has_armour and absf((hp0 - main.player.hp) - 17.0) < 0.01
		main.player.hp = float(main.player.max_hp)
		main.in_hill = false
		check("vault", shut and wrong and solved and less, "gates shut=%s all three levers wrong=%s levers 1+3 open=%s armour takes 20 as 17=%s" % [shut, wrong, solved, less])
	if want.call("save_tonight"):
		main.in_village = false
		main.in_forest = false
		main.in_hill = false
		main.in_lake = false
		main.in_garden = false
		main.in_cave = false
		reset_to(Vector2(20, 30))
		main.marsh.found = [true, true, true]
		main.marsh.chest_open = true
		main.fly_q = 3
		main.has_pearl = true
		main.grotto_q = 4
		main.cloud_q = 3
		main.has_feather = true
		main.skill_up = 1
		main.crystal_done = true
		main.has_ring = true
		main.trial_best = 77.0
		main.race_best = 12.5
		main.has_shoes = true
		main.forest.freed = [true, true, true, true, true]
		main.has_acorn = true
		main.has_armour = true
		main.castle_q = 3
		main.save_game()
		for k in ["has_pearl", "has_feather", "has_ring", "has_shoes", "has_acorn", "has_armour", "crystal_done"]:
			main.set(k, false)
		main.fly_q = 0
		main.grotto_q = 0
		main.cloud_q = 0
		main.skill_up = -1
		main.trial_best = 0.0
		main.race_best = 0.0
		main.castle_q = 0
		main.load_game()
		var ok: bool = main.has_pearl and main.has_feather and main.has_ring and main.has_shoes and main.has_acorn and main.has_armour 			and main.crystal_done and main.fly_q == 3 and main.grotto_q == 4 and main.cloud_q == 3 and main.skill_up == 1 			and main.trial_best == 77.0 and main.race_best == 12.5 and main.castle_q == 3 and main.marsh.chest_open and main.forest.freed.count(true) == 5
		check("save_tonight", ok, "keepsakes, side stories and records survive save and load=%s" % ok)
	if want.call("fishing"):
		main.story_step = maxi(main.story_step, 10)
		if main.intro:
			main.start_game(false)
		await wait(0.2)
		main.close_story()
		main.in_village = false
		main.in_hill = false
		main.in_lake = true
		main.lake_q = maxi(main.lake_q, 2)
		main.fish_kinds = [false, false, false, false, false]
		reset_to(main.lake.marks.f)
		var reach: bool = main.walkable(main.lake.marks.f.x, main.lake.marks.f.y)
		tap(KEY_E)
		await wait(0.1)
		var cast: bool = main.fish_state == "wait"
		tap(KEY_E) # too early
		await wait(0.1)
		var early: bool = main.fish_state == ""
		var landed := 0
		for i in 40:
			if main.fish_kinds.count(true) == 5:
				break
			tap(KEY_E)
			await wait(0.05)
			main.fish_t = 0.0
			await wait(0.05)
			if main.fish_state == "bite":
				tap(KEY_E)
				await wait(0.05)
				landed += 1
			main.close_story()
		main.in_lake = false
		check("fishing", reach and cast and early and landed > 0, "spot reachable=%s cast=%s early pull loses it=%s landed=%d kinds=%d" % [reach, cast, early, landed, main.fish_kinds.count(true)])
	if want.call("bat"):
		var ok_spots := true
		for b in main.BAT_SPOTS:
			ok_spots = ok_spots and main.walkable(b.x, b.y)
		calm_enemies(true)
		reset_to(Vector2(20, 30))
		main.spawn_bat(Vector2(23, 30))
		var b0: Dictionary = main.enemies[main.enemies.size() - 1]
		b0.hp = 99999.0
		b0.atk_cd = 1.0
		var swooped := false
		var hp0: float = main.player.hp
		for i in 50:
			reset_to(Vector2(20, 30))
			main.player.hp = hp0
			await wait(0.1)
			if b0.dash > 0.0:
				swooped = true
		var flies: bool = b0.node.position.y > 0.5
		if not b0.dead:
			b0.dead = true
			b0.node.queue_free()
			b0.shadow.queue_free()
		calm_enemies(false)
		check("bat", ok_spots and swooped and flies, "spots open=%s swoops=%s flies above ground=%s" % [ok_spots, swooped, flies])
	if want.call("moonflowers"):
		main.story_step = maxi(main.story_step, 6)
		if main.intro:
			main.start_game(false)
		await wait(0.2)
		main.close_story()
		main.in_village = false
		main.in_hill = false
		main.in_lake = false
		main.in_forest = false
		main.in_cave = false
		main.in_garden = false
		main.marsh.picked = [false, false, false]
		main.has_tea = false
		calm_enemies(true)
		var spots := true
		for p in main.MARSH.FLOWERS:
			spots = spots and main.player_can(p.x, p.y)
		main.hour = 22.0
		main.day = 0 # new moon: closed
		await wait(0.2)
		var shut: bool = not main.marsh.flowers[0].visible
		main.day = 4 # full moon
		await wait(0.2)
		var open_: bool = main.marsh.flowers[0].visible
		for p in main.MARSH.FLOWERS:
			reset_to(p)
			await wait(0.15)
		var three: bool = main.marsh.picked_count() == 3
		reset_to(Vector2(main.shop_pos.x, main.shop_pos.z))
		tap(KEY_SPACE)
		await wait(0.2)
		main.close_story()
		if main.shop_open:
			main.toggle_shop(false)
		main.hour = 12.0
		calm_enemies(false)
		check("moonflowers", spots and shut and open_ and three and main.has_tea, "spots=%s closed at new moon=%s open at full moon=%s picked 3=%s tea=%s" % [spots, shut, open_, three, main.has_tea])
	if want.call("houses"):
		main.story_step = maxi(main.story_step, 8)
		if main.intro:
			main.start_game(false)
		await wait(0.2)
		main.close_story()
		main.in_village = true
		main.in_hill = false
		main.in_lake = false
		main.in_forest = false
		main.house_seen = [false, false, false, false, false]
		calm_enemies(true)
		var doors_ok: bool = main.village.doors.size() == 5
		for d in main.village.doors:
			doors_ok = doors_ok and main.walkable(d.x, d.y)
		reset_to(main.village.doors[4])
		tap(KEY_SPACE)
		await wait(1.0)
		var inside: bool = main.in_house == 4 and main.player.x >= main.HOUSE_X
		reset_to(Vector2(main.cupboard.position.x, main.cupboard.position.z + 1.0))
		tap(KEY_SPACE)
		await wait(0.2)
		var picture: bool = main.story_open and main.house_seen[4]
		main.close_story()
		reset_to(Vector2(main.HOUSE_X + 4, 6))
		await wait(1.0)
		var out: bool = main.in_house == -1 and main.player.x < main.HOUSE_X and main.in_village
		calm_enemies(false)
		check("houses", doors_ok and inside and picture and out, "5 doors reachable=%s went in=%s picture in the last house=%s came out=%s" % [doors_ok, inside, picture, out])
	if want.call("feats"):
		main.feats_done = [false, false, false, false, false, false]
		var g0: int = main.player.gold
		main.stats.crits = 49
		main.player.inv = 0.0
		calm_enemies(true)
		reset_to(Vector2(20, 30))
		main.spawn_enemy(Vector2(21, 30))
		var e: Dictionary = main.enemies[main.enemies.size() - 1]
		var k0: int = main.stats.kills
		main.damage_enemy(e, 99999.0, Vector2(20, 30), 4.0, true)
		main.stats.crits = maxi(main.stats.crits, 50)
		main.check_feats()
		var done: bool = main.feats_done[2] and main.stats.kills == k0 + 1 and main.player.gold >= g0 + 50
		var listed: bool = "도전 과제" in "\n".join(main.journal_lines())
		calm_enemies(false)
		check("feats", done and listed, "crit feat at 50=%s kill counted, journal lists feats=%s" % [done, listed])
	calm_enemies(false)
	var failed := results.count(false)
	print("TESTS %d passed, %d failed" % [results.size() - failed, failed])
	get_tree().quit(failed)

# Writes each named sound to DIR/name.wav and prints its shape:
#   SOUND name dur=0.06s peak=0.31 rms=0.09 zcr=0.21
# zcr is zero crossings per sample: higher means brighter / more hiss (a pure 100 Hz tone is about 0.009).
static func sound_report(m: Node, dir: String) -> void:
	var sounds := {
		"step_grass": [100.0, 0.06, "noise", 0.12, 0.0],
		"step_bridge": [150.0, 0.07, "triangle", 0.22, -60.0],
		"hit": [300.0, 0.08, "square", 0.2, -200.0],
		"hurt": [320.0, 0.09, "triangle", 0.13, -140.0],
		"hurt_body": [160.0, 0.12, "step", 0.08, 0.0],
		"hurt_old": [90.0, 0.15, "square", 0.25, -40.0],
		"swing": [180.0, 0.07, "sawtooth", 0.12, 300.0],
		"stomp": [55.0, 0.5, "square", 0.35, -30.0],
		"buy": [880.0, 0.08, "square", 0.15, 0.0],
	}
	if dir != "":
		DirAccess.make_dir_recursive_absolute(dir)
	for name in sounds:
		var a: Array = sounds[name]
		var st: AudioStreamWAV = m.sfx_stream(a[0], a[1], a[2], a[3], a[4])
		var d := st.data
		var n := d.size() / 2
		var peak := 0.0
		var sum := 0.0
		var cross := 0
		var prev := 0.0
		for i in n:
			var v := d.decode_s16(i * 2) / 32768.0
			peak = maxf(peak, absf(v))
			sum += v * v
			if i > 0 and signf(v) != signf(prev):
				cross += 1
			prev = v
		if dir != "":
			st.save_to_wav(dir.path_join(name + ".wav"))
		print("SOUND %s dur=%.2fs peak=%.2f rms=%.3f zcr=%.3f" % [name, float(n) / st.mix_rate, peak, sqrt(sum / maxi(1, n)), float(cross) / maxi(1, n)])
