# The Crown Oddity: Godot 4 port of the browser demo.
# Everything (world, actors, HUD) is built from code so the scene file stays tiny.
extends Node3D

const N := 48
const WATER := 0
const GRASS := 1
const SAND := 2
const BRIDGE := 3
const START := Vector2(15, 20)
const CAM_ROTATE := false # camera rotation (Q/E) is switched off for now

var rng := RandomNumberGenerator.new()
var map := PackedByteArray()
var hgt := PackedFloat32Array()
var rocks: Array = []        # blockers: {x, z, r}
var bridges: Array = []

var player := {}
var enemies: Array = []
var chests: Array = []
var projectiles: Array = []
var fx: Array = []           # {node, life, t, update: Callable}

const CAM_YAW := 0.55
var cam_yaw := CAM_YAW
var cam_dist := 18.0
var shake := 0.0
var intro := true
var raining := false
var t := 0.0
var ground_y := 0.0         # smoothed ground height under the player, so 0.18 steps don't jolt the camera
var muted := false
# Ys-style combat feel: hit-stop, flash dodge (slow-mo), guard and flash guard (counter)
var hitstop := 0.0          # seconds the whole game stays frozen after a hit
var slowmo := 0.0           # seconds enemies run at SLOWMO speed after a flash dodge
const SLOWMO := 0.25
var flash_cd := 0.0
var dodge_start := -9.0
var guarding := false
var guard_since := -9.0
var counter_t := 0.0        # first slash in this window is a guaranteed x2.5 critical
var last_hit_t := -9.0      # last time a slash connected; momentum drains after 4 s without one
var fake_keys := {}           # keys held down by the autoplay tests

func key_down(k: int) -> bool:
	return fake_keys.has(k) or Input.is_key_pressed(k)

var camera: Camera3D
var sun: DirectionalLight3D
var env: Environment
var hero: Sprite3D
var hero_shadow: MeshInstance3D
var hero_tex := {}           # name -> [texture, row]
var rain: CPUParticles3D
var motes: CPUParticles3D

var ui_font: Font
var title_font: SystemFont
var hud: CanvasLayer
var ui := {}
var toast_t := 0.0
var banner_t := 0.0

# ---------------------------------------------------------------- helpers
func rnd(a := 0.0, b := 1.0) -> float:
	return rng.randf_range(a, b)

func idx(x: int, z: int) -> int:
	return x + z * N

# ---------------------------------------------------------------- cave (story steps 6 and 7)
# The underground cave is a 32x24 grid built far east of the marsh (x >= CAVE_X).
const CAVE_X := 100
const CAVE_W := 32
const CAVE_H := 24
const CAVE_ROWS := """################################
#......###........###..........#
#......###...P....###..........#
#.S............................#
#......###........###.......K..#
#......###........###..........#
#......###........###..........#
###.############################
###.############################
###.############################
#........###........##.........#
#........###........##.........#
#........###..wwww..##.........#
#.......................D......#
#........###..wwww..##.........#
#........###........##....B....#
#........###........##.........#
####.#################.........#
#.............########.........E
#.............########.........#
#...1...2...3.########.........#
#.............##################
################################
################################"""
var cave_grid: Array = []   # rows of characters
var in_cave := false
var cave_door_open := false
var cave_marks := {}        # letter -> world Vector2 (S, P, K, D, B, E; 1 2 3 the shrine's stones)

func cave_char(x: float, z: float) -> String:
	var tx := int(round(x)) - CAVE_X
	var tz := int(round(z))
	if tx < 0 or tz < 0 or tx >= CAVE_W or tz >= CAVE_H:
		return "#"
	var c: String = cave_grid[tz][tx]
	if c == "D" and cave_door_open:
		return "."
	return c

func tile_at(x: float, z: float) -> int:
	if x >= HOUSE_X - 0.5:
		return WATER if house_char(x, z) == "#" else GRASS
	if x >= CASTLE.CASTLE_X - 0.5:
		return WATER if castle.blocked(x, z) else GRASS
	if x >= CLOUD.CLOUD_X - 0.5:
		return WATER if cloud.blocked(x, z) else GRASS
	if x >= GROTTO.GROTTO_X - 0.5:
		return WATER if grotto.blocked(x, z) else GRASS
	if x >= HILL.HILL_X - 0.5:
		return WATER if hill.blocked(x, z) else (SAND if hill.char_at(x, z) == "=" else GRASS)
	if x >= LAKE.LAKE_X - 0.5:
		return WATER if lake.blocked(x, z) else (SAND if lake.char_at(x, z) in "=PQ" else GRASS)
	if x >= GARDEN.GARDEN_X - 0.5:
		return WATER if garden.blocked(x, z) else (SAND if garden.char_at(x, z) == "=" else GRASS)
	if x >= FOREST.FOREST_X - 0.5:
		return WATER if forest.blocked(x, z) else (SAND if forest.char_at(x, z) == "=" else GRASS)
	if x >= VILLAGE.VILLAGE_X - 0.5:
		return WATER if village.blocked(x, z) else (SAND if village.char_at(x, z) == "=" else GRASS)
	if x >= CAVE_X - 0.5:
		var c := cave_char(x, z)
		return WATER if c == "#" or c == "D" else (SAND if c == "w" else GRASS)
	var tx := int(round(x))
	var tz := int(round(z))
	if tx < 0 or tz < 0 or tx >= N or tz >= N:
		return WATER
	return map[idx(tx, tz)]

func height_at(x: float, z: float) -> float:
	if x >= CAVE_X - 0.5:
		return 0.0
	var tx := int(round(x))
	var tz := int(round(z))
	if tx < 0 or tz < 0 or tx >= N or tz >= N:
		return -1.0
	return hgt[idx(tx, tz)]

func walkable(x: float, z: float) -> bool:
	if tile_at(x, z) == WATER:
		return false
	for r in rocks:
		if Vector2(r.x - x, r.z - z).length() < r.r:
			return false
	return true

func unstick() -> void:
	var best := Vector2(player.x, player.z)
	var found := false
	for r in range(1, 12):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c := Vector2(round(player.x) + dx, round(player.z) + dz)
				if player_can(c.x, c.y):
					if not found or c.distance_to(Vector2(player.x, player.z)) < best.distance_to(Vector2(player.x, player.z)):
						best = c
						found = true
		if found:
			break
	player.x = best.x
	player.z = best.y

# Sora keeps a little room from cave walls so her sprite never sinks into one
var has_skip := false   # 물수제비 걸음 (story step 7 ability)
var skipping := false
var skip_grace := 0.0   # a short let-go of Shift or the arrows mid-river does not drop Sora in

# water the water skip can run over: the marsh rivers and ponds, and the deep runs in the grotto
func skip_water(x: float, z: float) -> bool:
	if x >= CASTLE.CASTLE_X - 0.5:
		return castle.char_at(x, z) == "~"
	if x >= GROTTO.GROTTO_X - 0.5:
		return grotto.char_at(x, z) == "~"
	return x < CAVE_X - 0.5 and tile_at(x, z) == WATER and x > 1.0 and z > 1.0 and z < N - 2.0 and (x < N - 2.0 or (z > 17.5 and z < 23.5))

func player_can(x: float, z: float) -> bool:
	if not walkable(x, z):
		return skipping and skip_water(x, z)
	if x >= CAVE_X - 0.5:
		for d in [Vector2(0.35, 0), Vector2(-0.35, 0), Vector2(0, 0.35), Vector2(0, -0.35)]:
			if not walkable(x + d.x, z + d.y) and not (skipping and skip_water(x + d.x, z + d.y)):
				return false
	return true

func make_tex(w: int, h: int, draw: Callable) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	draw.call(img)
	return ImageTexture.create_from_image(img)

func px(img: Image, x: float, y: float, w: float, h: float, c: Color) -> void:
	var x0 := int(round(x))
	var y0 := int(round(y))
	for yy in range(y0, y0 + int(round(h))):
		for xx in range(x0, x0 + int(round(w))):
			if xx >= 0 and yy >= 0 and xx < img.get_width() and yy < img.get_height():
				img.set_pixel(xx, yy, c)

func mat_color(c: Color, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m

func glow_mat(c: Color, energy := 3.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m

# ---------------------------------------------------------------- setup
func _ready() -> void:
	if "--pseudo" in OS.get_cmdline_user_args():
		TranslationServer.pseudolocalization_enabled = true # shows which text goes through the translation table
	get_viewport().size_changed.connect(func(): if ui.has("story_cap"): fit_story())
	rng.seed = 7
	if not Array(OS.get_cmdline_user_args()).any(func(x): return x.begins_with("--test") or x.begins_with("--scene")):
		load_settings() # tests and screenshots always run with the default settings
	# Pretendard ships as unicode-range pieces; chain them as fallbacks so web builds (no system fonts) get Hangul
	var sys := SystemFont.new()
	sys.font_names = PackedStringArray(["Pretendard", "Malgun Gothic", "Noto Sans KR", "Apple SD Gothic Neo", "sans-serif"])
	var pieces: Array[Font] = []
	for f in ResourceLoader.list_directory("res://fonts/pretendard"):
		if f.ends_with(".woff2"):
			pieces.append(load("res://fonts/pretendard/" + f))
	if pieces.is_empty():
		ui_font = sys
	else:
		ui_font = pieces[0]
		var rest: Array[Font] = pieces.slice(1)
		rest.append(sys)
		ui_font.fallbacks = rest
	title_font = SystemFont.new()
	title_font.font_names = PackedStringArray(["Cinzel", "Georgia", "Times New Roman", "serif"])
	title_font.fallbacks = [ui_font]
	title_font.font_weight = 700
	build_environment()
	build_map()
	build_terrain()
	build_vegetation()
	build_props()
	build_lights()
	build_cottage()
	darken_first_lamp()
	build_cave()
	build_shrine()
	spawn_crystals()
	build_crystal_chest()
	village.build(self)
	forest.build(self)
	garden.build(self)
	lake.build(self)
	hill.build(self)
	grotto.build(self)
	grotto_steps()
	cloud.build(self)
	cloud.build_updraft(self, hill.marks.U)
	castle.build(self)
	build_trial()
	build_ways()
	build_house_room()
	build_race()
	build_player()
	for i in 9:
		spawn_enemy(Vector2(-1, -1), i >= 6) # the last three are brick archers
	enemies[0].x = 12.0
	enemies[0].z = 24.0
	enemies[1].x = 30.0
	enemies[1].z = 22.0
	build_chests()
	marsh.build(self)
	village_sign()
	spawn_boss()
	build_particles()
	build_hud()
	for l in [ui.story_text, ui.story_who, ui.journal_text, ui.journal_text2, ui.ways_text]:
		scale_text(l)
	build_mate_hud(ui.root)
	apply_settings()
	update_daylight(0.0)
	var targs := OS.get_cmdline_user_args()
	if targs.is_empty():
		load_game()
	else: # tests and shots use their own save file and always start fresh
		SAVE_PATH = "user://test_save.json"
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	apply_test_args(targs)

# ---------------------------------------------------------------- test scenes
# Fixed starting states for screenshots and checks, picked with `-- --scene=NAME`.
# Extra flags: --hour=H --day=D --shot=PATH (save a PNG after --wait seconds, default 4, then quit).
const SCENES := {
	"title": {},
	"start": {"play": true},
	"night": {"play": true, "hour": 23.0, "day": 4},
	"dusk": {"play": true, "hour": 19.5},
	"noon": {"play": true, "hour": 13.0},
	"cottage": {"play": true, "at": "cottage"},
	"shop": {"play": true, "at": "shop", "gold": 120, "shop": true},
	"boss": {"play": true, "at": Vector2(16, 11)},
	"bridge": {"play": true, "at": Vector2(19, 26)},
	"faint": {"play": true, "faint": 2.5},
	"opening": {"play": true, "opening": true},
	"cave": {"play": true, "cave": true},
	"cave_in": {"play": true, "cave_in": true},
	"talk": {"play": true, "talk": true},
	"mole": {"play": true, "mole": true},
	"scene": {"play": true, "scene": true},
	"village": {"play": true, "village": true},
	"village_night": {"play": true, "village": true, "hour": 22.0},
	"forest": {"play": true, "village": true, "forest": true, "hour": 16.0},
	"forest_night": {"play": true, "village": true, "forest": true, "hour": 22.0},
	"mold": {"play": true, "village": true, "mold": true, "hour": 21.0},
	"turtle": {"play": true, "village": true, "turtle": true, "hour": 15.0},
	"hill": {"play": true, "village": true, "hill": true, "hour": 10.0},
	"kid": {"play": true, "village": true, "kid": true, "hour": 20.5},
	"grove": {"play": true, "village": true, "forest": true, "grove": true, "hour": 15.0},
	"flies": {"play": true, "at": Vector2(8, 23), "hour": 22.5, "flies": true},
	"crab": {"play": true, "village": true, "crab": true, "hour": 14.0},
	"grotto_in": {"play": true, "village": true, "crab": true, "grotto_in": true, "hour": 21.0},
	"grotto_steps": {"play": true, "village": true, "turtle": true, "steps": true, "hour": 15.0},
	"cloud": {"play": true, "village": true, "cloud": true, "hour": 11.0},
	"scarecrow": {"play": true, "village": true, "cloud": true, "scare": true, "hour": 16.0},
	"castle": {"play": true, "village": true, "castle": true, "hour": 15.0},
	"knight": {"play": true, "village": true, "castle": true, "knight": true, "hour": 15.0},
	"shrine": {"play": true, "shrine": true},
	"journal": {"play": true, "journal": true},
	"wolves": {"play": true, "village": true, "forest": true, "wolves": true, "hour": 16.5},
	"trial": {"play": true, "village": true, "trial": true, "hour": 21.0},
	"cage": {"play": true, "village": true, "forest": true, "cage": true, "hour": 14.0},
	"race": {"play": true, "village": true, "hill": true, "race": true, "hour": 10.0},
	"moonflower": {"play": true, "at": Vector2(37.0, 24.5), "hour": 22.5, "day": 4},
	"house": {"play": true, "village": true, "house": true, "hour": 15.0},
	"festival": {"play": true, "village": true, "festival": true, "hour": 22.0, "day": 4},
	"cloudpath": {"play": true, "village": true, "cloud": true, "path": true, "hour": 11.0},
	"ways": {"play": true, "ways": true, "hour": 16.0},
	"walk_dr": {"play": true, "walk_dr": true, "at": Vector2(12, 14), "hour": 12.0},
	"settings": {"play": true, "settings": true},
	"east": {"play": true, "at": Vector2(42.0, 21.5), "hour": 12.0},
	"fall": {"play": true, "fall": 2.5, "at": Vector2(20, 22)},
	"chat": {"play": true, "chat": true, "at": Vector2(20, 22), "hour": 13.0},
	"scrap": {"play": true, "at": Vector2(42.5, 5.5), "hour": 17.0},
}

func apply_test_args(args: PackedStringArray) -> void:
	var opt := {}
	for a in args:
		if a.begins_with("--") and "=" in a:
			opt[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
		elif a.begins_with("--"):
			opt[a.substr(2)] = ""
	if not opt.has("scene") and not opt.has("test") and not opt.has("sounds"):
		return
	var scene_name: String = opt.get("scene", "title")
	var sc: Dictionary = SCENES.get(scene_name, {})
	if sc.is_empty() and scene_name != "title":
		push_error("unknown scene: %s (known: %s)" % [scene_name, ", ".join(SCENES.keys())])
	if sc.get("play", false):
		start_game(false)
	var at = sc.get("at", null)
	if at is String and at == "cottage":
		at = Vector2(shop_pos.x + 1.5, shop_pos.z + 2.5)
	elif at is String and at == "shop":
		at = Vector2(shop_pos.x, shop_pos.z)
	if at is Vector2:
		player.x = at.x
		player.z = at.y
		ground_y = height_at(at.x, at.y)
	if sc.has("flies"): # night fireflies over the marsh, and the lent jar already glowing
		fly_q = 1
		marsh.flies_on = true
		build_jar()
	if sc.has("gold"):
		player.gold = sc.gold
	if sc.get("shop", false):
		story_step = 3
		toggle_shop(true)
	if sc.get("village", false):
		story_step = 7
		errand = 1
		enter_village()
		player.x = village.marks.M.x - 2.0
		player.z = village.marks.M.y + 1.0
		if sc.get("forest", false): # the hardened forest, first wall ahead
			night_q = 4
			forest_q = 1
			enter_forest()
			player.x = forest.walls[0].pos.x - 2.5
			player.z = forest.walls[0].pos.y
			if sc.has("wolves"):
				player.x = FOREST.FOREST_X + 25.0
				player.z = 18.0
				close_story()
				spawn_wolf(Vector2(player.x + 2.5, player.z + 0.5))
				spawn_wolf(Vector2(player.x + 1.0, player.z + 2.0))
			if sc.has("cage"):
				player.x = FOREST.FOREST_X + 13.5
				player.z = 5.0
				close_story()
			if sc.has("grove"):
				player.x = forest.marks.t.x + 2.0
				player.z = forest.marks.t.y
				close_story()
		if sc.get("mold", false): # the last boss in the heart of the garden
			night_q = 4
			forest_q = 3
			garden_q = 1
			enter_garden()
			garden_q = 2
			spawn_mold()
			player.x = garden.marks.C.x - 4.5
			player.z = garden.marks.C.y + 1.5
		if sc.get("turtle", false): # Sora and Mulgyeol against the brick turtle on the island
			night_q = 4
			lake_q = 1
			enter_lake()
			lake.thaw()
			lake_q = 2
			row_to_island()
			close_story()
			spawn_turtle()
			player.x = lake.marks.T.x + 2.5
			player.z = lake.marks.T.y + 1.0
			snap_mate()
			if sc.has("steps"):
				for e in enemies:
					if e.get("turtle", false):
						e.dead = true
						e.node.visible = false
						e.shadow.visible = false
				ui.boss.visible = false
				player.x = lake.marks.G.x + 1.5
				player.z = lake.marks.G.y - 1.5
		if sc.get("crab", false): # the brick crab in the grotto under the island, Mulgyeol along
			night_q = 4
			lake_q = 4
			enter_lake()
			lake.thaw()
			join_mate()
			has_skip = true
			enter_grotto()
			close_story()
			grotto_q = 2
			spawn_crab()
			player.x = grotto.marks.C.x + 4.0
			player.z = grotto.marks.C.y + 1.5
			if sc.has("grotto_in"): # the entry room, at night, by the steps up
				for e in enemies:
					if e.get("crab", false):
						e.dead = true
						e.node.visible = false
						e.shadow.visible = false
				ui.boss.visible = false
				player.x = grotto.marks.S.x + 2.0
				player.z = grotto.marks.S.y + 1.0
			snap_mate()
		if sc.get("hill", false): # the wind hills, one mill turning, Mulgyeol and Noeul along
			night_q = 4
			lake_q = 4
			forest_q = 3
			join_mate()
			join_noeul()
			enter_hill()
			close_story()
			hill.wind_mill(hill.mills[0], self)
			player.x = hill.mills[0].pos.x + 2.5
			player.z = hill.mills[0].pos.y + 2.0
			snap_mates()
			if sc.has("race"):
				player.x = HILL.HILL_X + RACE_POST.x + 1.0
				player.z = RACE_POST.y
				race_key()
				player.x = HILL.HILL_X + 6.0
				player.z = 16.5
				snap_mates()
		if sc.get("cloud", false): # the cloud mound above the hill, mates along; with "scare" the scarecrow is up
			night_q = 4
			lake_q = 4
			forest_q = 3
			hill_q = 3
			join_mate()
			join_noeul()
			enter_hill()
			close_story()
			enter_cloud()
			close_story()
			player.x = CLOUD.CLOUD_X + 3.0
			player.z = 10.0
			if sc.has("path"):
				player.z = 12.0
				cloud.reveal_t = 30.0
				cloud.reveal(true)
			if sc.has("scare"):
				cloud_q = 2
				spawn_scarecrow()
				player.x = cloud.marks.K.x - 3.0
				player.z = cloud.marks.K.y + 1.5
			snap_mates()
		if sc.get("castle", false): # the sunken castle's great hall; with "knight" the throne room fight
			night_q = 4
			lake_q = 4
			forest_q = 3
			hill_q = 3
			has_skip = true
			join_mate()
			join_noeul()
			enter_castle()
			close_story()
			castle.open_gate()
			player.x = CASTLE.CASTLE_X + 18.0
			player.z = 12.0
			if sc.has("knight"):
				for pg in castle.pages:
					pg.read = true
				castle.open_door()
				castle_q = 2
				spawn_knight()
				player.x = castle.marks.K.x - 3.5
				player.z = castle.marks.K.y + 1.0
			set_quest(castle_quest())
			snap_mates()
		if sc.get("trial", false): # the moon trial's third wave, wolves around the stone ring
			night_q = 4
			player.x = village.marks.R.x + 1.5
			player.z = village.marks.R.y - 0.5
			trial_wave = 3
			trial_start = t
			spawn_trial_wave()
		if sc.get("house", false): # inside the last village house
			enter_house(4)
			player.x = HOUSE_X + 5.5
			player.z = 2.5
		if sc.get("festival", false): # the lantern festival on a full-moon night
			mail_got = [true, true, true]
			errand = 3
		if sc.get("kid", false): # Kongal's kid goblin trotting after Sora in the south field
			errand = 3
			player.x = VILLAGE.VILLAGE_X + 9.0
			player.z = 19.0
			kid_q = 2
			place_kid()
	if sc.get("scene", false):
		show_story("res://art/story/06_cave_rival.jpg", STORY.PAINTING)
		for k in 6:
			next_story()
	if sc.get("mole", false):
		story_step = 5
		enter_cave()
		player.x = cave_marks.B.x - 4.0
		player.z = cave_marks.B.y
	if sc.get("talk", false):
		story_step = 3
		show_story("", STORY.BORI)
		for k in 4:
			next_story()
			next_story()
	if sc.get("cave_in", false):
		story_step = 5
		enter_cave()
		player.x += 2.0
	if sc.get("cave", false):
		for e in enemies:
			if e.get("boss", false):
				e.dead = true
				e.node.queue_free()
				e.shadow.queue_free()
				ui.boss.visible = false
				open_cave(Vector2(e.x, e.z))
				player.x = e.x
				player.z = e.z + 3.5
		close_story()
	if sc.get("shrine", false): # the shrine of three stones under the cave, the whirl woken
		enter_cave()
		close_story()
		shrine_seen = true
		skill_up = 0
		player.x = CAVE_X + 8.0
		player.z = 18.6
	if sc.get("journal", false): # the journal mid-game: two map scraps, the firefly errand on, the whirl woken
		story_step = 8
		errand = 3
		kid_q = 3
		doran_q = 3
		fly_q = 1
		has_skip = true
		shrine_seen = true
		skill_up = 0
		marsh.found = [true, false, true]
		set_quest("마을 심부름을 모두 마쳤다. 밤이 되면 마을에서 쉬자")
		toggle_journal(true)
	if sc.get("ways", false): # the waystone list by Bori's cottage
		story_step = 9
		lake_q = 1
		var w0 := way_spot(0)
		player.x = w0.x + 0.8
		player.z = w0.y + 1.4
		toggle_ways(true)
	if sc.get("walk_dr", false): # walking toward the bottom right of the screen (5 o'clock)
		fake_keys[KEY_S] = true
		fake_keys[KEY_D] = true
	if sc.get("settings", false):
		toggle_settings(true)
	if sc.get("opening", false):
		begin_opening()
	if sc.has("fall"):
		get_tree().create_timer(sc.fall).timeout.connect(func(): player.inv = 0.0; hurt_player(9999, ground_y))
	if sc.has("chat"): # companions trading a line in balloons
		join_mate()
		join_noeul()
		snap_mates()
		get_tree().create_timer(1.0).timeout.connect(func(): say_bubble(mate, "다리 아파. 좀 쉬었다 가자."); say_bubble(mate2, "……뭘 봐. 그냥 쉬는 거야."))
	if sc.has("faint"):
		get_tree().create_timer(sc.faint).timeout.connect(faint)
	hour = float(opt.get("hour", sc.get("hour", hour)))
	day = int(opt.get("day", sc.get("day", day)))
	if opt.has("test"):
		var runner := Node.new()
		runner.set_script(load("res://tools/autoplay.gd"))
		runner.main = self
		runner.only = opt.test
		add_child(runner)
	if opt.has("sounds"):
		load("res://tools/autoplay.gd").sound_report(self, opt.sounds)
		get_tree().quit()
	if opt.has("shot"):
		var path: String = opt.shot if opt.shot != "" else "res://shot.png"
		get_tree().create_timer(float(opt.get("wait", "4"))).timeout.connect(func():
			get_viewport().get_texture().get_image().save_png(path)
			print("SHOT ", path)
			get_tree().quit())

func build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#e8c98a")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#fff0d0")
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.9
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 0.9
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color("#e8c98a")
	env.fog_depth_begin = 18.0
	env.fog_depth_end = 46.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.light_color = Color("#ffc06a")
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)

	camera = Camera3D.new()
	camera.fov = 32.0
	camera.far = 200.0
	add_child(camera)

	# tilt-shift + grade as a full-screen pass under the HUD
	var post := CanvasLayer.new()
	post.layer = 0
	add_child(post)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/tiltshift.gdshader")
	rect.material = sm
	post.add_child(rect)
	tilt_rect = rect

# layout: a winding river from the north feeds a southern lake with an island;
# a raised meadow in the north-east, a small pond in the north-west
func build_map() -> void:
	map.resize(N * N)
	hgt.resize(N * N)
	for z in N:
		for x in N:
			var lake := Vector2((x - 24) * 0.8, z - 39).length() < 6.5 and Vector2(x - 24, z - 39).length() > 2.2
			var river := z < 35 and absf(x - (24.0 + sin(z * 0.18) * 5.0)) < 2.2
			var pond := Vector2(x - 9, z - 11).length() < 3.2
			var w := lake or river or pond or x < 2 or z < 2 or x > N - 3 or z > N - 3
			var plateau := x > 31 and z < 17
			map[idx(x, z)] = WATER if w else GRASS
			hgt[idx(x, z)] = -0.45 if w else (0.6 if plateau else (0.18 if rng.randf() < 0.12 else 0.0))
	# sand banks next to water
	for z in range(1, N - 1):
		for x in range(1, N - 1):
			if map[idx(x, z)] != GRASS:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if map[idx(x + d.x, z + d.y)] == WATER and rng.randf() < 0.55:
					map[idx(x, z)] = SAND
					hgt[idx(x, z)] = -0.12
					break
	bridge_line(12, 36, 9)
	bridge_line(10, 34, 25)
	bridge_line(12, 36, 39)

func bridge_line(x0: int, x1: int, z: int) -> void:
	var run = null
	for i in range(x0, x1 + 1):
		if map[idx(i, z)] == WATER:
			map[idx(i, z)] = BRIDGE
			hgt[idx(i, z)] = 0.08
			if map[idx(i, z + 1)] == WATER:
				map[idx(i, z + 1)] = BRIDGE
				hgt[idx(i, z + 1)] = 0.08
			if run == null:
				run = {"a": i, "z": z}
			run.b = i
		elif run != null:
			bridges.append(run)
			run = null
	# the deck is two tiles wide and overhangs each end; any water left under it
	# (e.g. the lower row at a bank) would be an invisible wall, so pave it all
	for b in bridges:
		if b.z != z:
			continue
		for i in range(b.a - 1, b.b + 2):
			for zz in [z, z + 1]:
				if map[idx(i, zz)] == WATER:
					map[idx(i, zz)] = BRIDGE
					hgt[idx(i, zz)] = 0.08

# ---------------------------------------------------------------- terrain
func noise_tex(cols: Array) -> ImageTexture:
	return make_tex(16, 16, func(img: Image):
		for y in 16:
			for x in 16:
				var v := rng.randf()
				var c: Color = cols[0]
				for k in range(1, cols.size()):
					if v > float(k) / cols.size():
						c = cols[k]
				img.set_pixel(x, y, c))

func block_layer(type: int, tex: Texture2D, tint: Callable) -> void:
	var list: Array = []
	for z in N:
		for x in N:
			if map[idx(x, z)] == type:
				list.append(Vector2i(x, z))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = BoxMesh.new()
	mm.instance_count = list.size()
	for i in list.size():
		var p: Vector2i = list[i]
		var h := hgt[idx(p.x, p.y)]
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(1, 1.2, 1)), Vector3(p.x, h - 0.6, p.y)))
		mm.set_instance_color(i, (tint.call() as Color).srgb_to_linear())
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/block.gdshader")
	sm.set_shader_parameter("top_tex", tex)
	mmi.material_override = sm
	add_child(mmi)

func build_terrain() -> void:
	var grass_top := noise_tex([Color("#5e8f30"), Color("#6b9c36"), Color("#6b9c36"), Color("#7dab3e")])
	var sand_top := noise_tex([Color("#c99a62"), Color("#ddb479"), Color("#ddb479"), Color("#efcf97")])
	block_layer(GRASS, grass_top, func(): return Color.from_hsv(0.24 + rnd(-0.02, 0.02), 0.25, rnd(0.82, 1.0)))
	block_layer(SAND, sand_top, func(): return Color(1, 1, 1) * rnd(0.9, 1.05))

	var bed := MeshInstance3D.new()
	var bp := PlaneMesh.new()
	bp.size = Vector2(N, N)
	bed.mesh = bp
	bed.material_override = mat_color(Color("#29475e"))
	bed.position = Vector3(N / 2.0 - 0.5, -0.7, N / 2.0 - 0.5)
	add_child(bed)

	var water_tex := make_tex(32, 32, func(img: Image):
		img.fill(Color("#3d6f9a"))
		for i in 40:
			px(img, rnd(0, 32), rnd(0, 32), rnd(2, 6), 1, Color("#5f93bf") if rng.randf() < 0.5 else Color("#2f5c86"))
		for i in 6:
			px(img, rnd(0, 32), rnd(0, 32), 2, 1, Color("#cfe8ff")))
	var water := MeshInstance3D.new()
	var wp := PlaneMesh.new()
	wp.size = Vector2(N, N)
	water.mesh = wp
	var wm := ShaderMaterial.new()
	wm.shader = load("res://shaders/water.gdshader")
	wm.set_shader_parameter("tex", water_tex)
	water.material_override = wm
	water.position = Vector3(N / 2.0 - 0.5, -0.22, N / 2.0 - 0.5)
	add_child(water)

	# bridges: planks and rails
	var plank_tex := make_tex(16, 16, func(img: Image):
		var cols := [Color("#8a5a32"), Color("#9d6a3c"), Color("#7d4f2b"), Color("#a87443")]
		for k in 4:
			px(img, k * 4, 0, 4, 16, cols[k])
			px(img, k * 4 + 3, 0, 1, 16, Color("#3d2614")))
	var plank_mat := StandardMaterial3D.new()
	plank_mat.albedo_texture = plank_tex
	plank_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	plank_mat.uv1_scale = Vector3(4, 1, 1)
	var post_mat := mat_color(Color("#3b2a1e"))
	for b in bridges:
		lego_deck(b.a, b.b, b.z)

# a bridge of toy bricks: a deck of staggered 2x2-stud bricks in red, yellow, blue and green,
# and a low brick wall along each side with gaps every third brick
const LEGO_COLS := [Color("#c8322a"), Color("#e8b018"), Color("#2f5fb8"), Color("#3f8a3a")]
var lego_mats: Array = []
var stud_mesh: CylinderMesh

func lego_brick(g: Node3D, size: Vector3, pos: Vector3, ci: int) -> void:
	if lego_mats.is_empty():
		for c in LEGO_COLS:
			var m := StandardMaterial3D.new()
			m.albedo_color = c
			m.roughness = 0.3
			lego_mats.append(m)
		stud_mesh = CylinderMesh.new()
		stud_mesh.top_radius = 0.11
		stud_mesh.bottom_radius = 0.11
		stud_mesh.height = 0.07
		stud_mesh.radial_segments = 10
	var mat: Material = lego_mats[ci % lego_mats.size()]
	var b := box(size - Vector3(0.03, 0, 0.03), mat) # a hair narrower, so the seams between bricks show
	b.position = pos
	g.add_child(b)
	for i in 2:
		for k in 2:
			var st := MeshInstance3D.new()
			st.mesh = stud_mesh
			st.material_override = mat
			st.position = pos + Vector3((i - 0.5) * size.x * 0.5, size.y / 2.0 + 0.035, (k - 0.5) * size.z * 0.5)
			g.add_child(st)

func lego_deck(a: int, b_: int, z: int) -> void:
	var length := b_ - a + 3
	var g := Node3D.new()
	var n := 0
	for row in 2: # two rows of bricks across the deck, the second shifted half a brick
		var x := -length / 2.0 + (0.5 if row == 1 else 0.0)
		while x < length / 2.0 - 0.01:
			var w := minf(1.0, length / 2.0 - x)
			lego_brick(g, Vector3(w, 0.2, 0.86), Vector3(x + w / 2.0, 0.02, -0.44 + row * 0.88), n)
			x += w
			n += 1
	for side in [-0.95, 0.95]: # the side walls
		var k := 0
		var x2 := -length / 2.0
		while x2 < length / 2.0 - 0.01:
			if k % 3 != 2:
				lego_brick(g, Vector3(0.9, 0.36, 0.22), Vector3(x2 + 0.45, 0.3, side), k + 1)
			x2 += 1.0
			k += 1
	g.position = Vector3((a + b_) / 2.0, 0, z + 0.5)
	add_child(g)

func box(size: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	return mi

# ---------------------------------------------------------------- vegetation
func cross_mesh(w: float, h: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ang in [0.0, PI / 2.0, PI / 4.0]:
		var d := Vector3(cos(ang), 0, sin(ang)) * (w / 2.0)
		var v := [-d, d, d + Vector3(0, h, 0), -d + Vector3(0, h, 0)]
		var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.set_uv(uv[k])
			st.add_vertex(v[k])
	return st.commit()

func vegetation(tex: Texture2D, w: float, h: float, spots: Array, strength: float) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = cross_mesh(w, h)
	mm.instance_count = spots.size()
	for i in spots.size():
		var s: Vector4 = spots[i]
		var b := Basis(Vector3.UP, rnd(0, PI)).scaled(Vector3(s.w, s.w * rnd(0.8, 1.2), s.w))
		mm.set_instance_transform(i, Transform3D(b, Vector3(s.x, s.y, s.z)))
		mm.set_instance_color(i, Color.from_hsv(0.22, 0.06, rnd(0.88, 1.0)).srgb_to_linear())
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	veg_meshes.append(mm)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/grass.gdshader")
	sm.set_shader_parameter("tex", tex)
	sm.set_shader_parameter("strength", strength)
	mmi.material_override = sm
	add_child(mmi)

func build_vegetation() -> void:
	# tapered blades: light roots, sunlit tips, leaning in a shared breeze
	var tuft := make_tex(48, 48, func(img: Image):
		var ramp := ["#5e9a34", "#68a636", "#6eaa36", "#82ba3e", "#9ccb48", "#b8dc62", "#d8ee90"]
		for i in 46:
			var x := 6.0 + rng.randf() * 36.0
			var h := 14.0 + rng.randf() * 32.0
			var lean := (rng.randf() - 0.3) * 0.5
			for y in int(h):
				var k := y / h
				var ci := mini(ramp.size() - 1, int(floor(k * (ramp.size() - 0.2) + rng.randf() * 0.6)))
				px(img, x, 47 - y, 2 if k < 0.55 else 1, 1, Color(ramp[ci]))
				x += lean * (0.4 + k)
		for i in 4:
			var x := 6.0 + rng.randf() * 34.0
			var y := 10.0 + rng.randf() * 18.0
			var c := Color([("#fff6d8"), ("#ffd24a"), ("#8f9cff"), ("#ffb0cc")][rng.randi() % 4])
			px(img, x - 1, y, 3, 1, c)
			px(img, x, y - 1, 1, 3, c)
			px(img, x, y, 1, 1, Color("#ffb030")))
	var cattail := make_tex(16, 32, func(img: Image):
		for i in 5:
			var x := 2 + i * 3 + rng.randi() % 2
			var h := 18.0 + rng.randf() * 12.0
			px(img, x, 32 - h, 1, h, Color("#7aa63a") if i % 2 else Color("#a2b850"))
			# a slim dark-brown seed head (cattails are brown, not red) with a pale tip
			px(img, x - 1, 32 - h, 2, 5, Color("#5a4630"))
			px(img, x - 1, 32 - h, 1, 5, Color("#76603f"))
			px(img, x, 32 - h - 2, 1, 2, Color("#d8cf9a"))
		for i in 6:
			px(img, rng.randf() * 15, 20 + rng.randf() * 10, 1, 12, Color("#5d8a2a")))
	var grass_spots: Array = []
	var cattail_spots: Array = []
	for z in N:
		for x in N:
			var ty := map[idx(x, z)]
			var h := hgt[idx(x, z)]
			if ty == GRASS:
				for k in 8:
					grass_spots.append(Vector4(x + rnd(-0.5, 0.5), h, z + rnd(-0.5, 0.5), rnd(0.7, 1.15)))
			if ty == SAND and rng.randf() < 0.8:
				for k in 3:
					cattail_spots.append(Vector4(x + rnd(-0.5, 0.5), h, z + rnd(-0.5, 0.5), rnd(0.8, 1.2)))
			if ty == WATER and rng.randf() < 0.07:
				cattail_spots.append(Vector4(x + rnd(-0.4, 0.4), -0.3, z + rnd(-0.4, 0.4), rnd(0.9, 1.2)))
	vegetation(tuft, 0.8, 0.55, grass_spots, 0.12)
	vegetation(cattail, 0.8, 1.7, cattail_spots, 0.07)

# ---------------------------------------------------------------- props
func build_props() -> void:
	var rock_mat := mat_color(Color("#6c6f78"))
	for i in 40:
		var x := rnd(3, N - 3)
		var z := rnd(3, N - 3)
		if tile_at(x, z) == GRASS or tile_at(x, z) == SAND:
			var r := rnd(0.12, 0.3)
			var m := box(Vector3(r * 1.6, r, r * 1.4), rock_mat)
			m.position = Vector3(x, height_at(x, z) + r * 0.4, z)
			m.rotation = Vector3(rnd(0, 0.4), rnd(0, 3), 0)
			add_child(m)
	# bushes and voxel trees share one MultiMesh of tinted cubes
	var cubes: Array = [] # [Transform3D, Color]
	for i in 30:
		var x := rnd(3, N - 3)
		var z := rnd(3, N - 3)
		if tile_at(x, z) != GRASS or Vector2(x, z).distance_to(START) < 4:
			continue
		for k in 7:
			var s := rnd(0.35, 0.6)
			cubes.append([Transform3D(Basis().scaled(Vector3.ONE * s), Vector3(x + rnd(-0.4, 0.4), height_at(x, z) + rnd(0.2, 0.7), z + rnd(-0.4, 0.4))),
				Color.from_hsv(0.25 + rnd(-0.03, 0.03), 0.55, rnd(0.58, 0.72))])
		rocks.append({"x": x, "z": z, "r": 0.6})
	var trunks: Array = []
	for i in 180:
		var x := rnd(3, N - 3)
		var z := rnd(3, N - 3)
		var forest := (x > 34 and z > 18) or (x < 13 and z > 28)
		if tile_at(x, z) != GRASS or Vector2(x, z).distance_to(START) < 5 or (not forest and rng.randf() < 0.8):
			continue
		var blocked := false
		for r in rocks:
			if Vector2(r.x - x, r.z - z).length() < 1.6:
				blocked = true
		if blocked:
			continue
		var v := rng.randf()
		var kind := "pine" if v < 0.4 else ("autumn" if v < 0.55 else "leafy")
		voxel_tree(x, z, kind, cubes, trunks)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = BoxMesh.new()
	mm.instance_count = cubes.size()
	for i in cubes.size():
		mm.set_instance_transform(i, cubes[i][0])
		mm.set_instance_color(i, (cubes[i][1] as Color).srgb_to_linear())
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var cm := StandardMaterial3D.new()
	cm.vertex_color_use_as_albedo = true
	cm.roughness = 0.9
	mmi.material_override = cm
	add_child(mmi)
	for tr in trunks:
		add_child(tr)

func voxel_tree(x: float, z: float, kind: String, cubes: Array, trunks: Array) -> void:
	var y0 := height_at(x, z)
	var sc := rnd(0.85, 1.15)
	var trunk_h := 1.0 if kind == "pine" else rnd(1.4, 2.0)
	var birch := kind == "leafy" and rng.randf() < 0.3
	var trunk := box(Vector3(0.32, trunk_h, 0.32) * sc, mat_color(Color("#e8e4d8") if birch else Color("#5a3a22")))
	trunk.position = Vector3(x, y0 + trunk_h * sc / 2.0, z)
	trunks.append(trunk)
	var hue := Vector2(0.06, 0.09) if kind == "autumn" else (Vector2(0.33, 0.37) if kind == "pine" else Vector2(0.22, 0.28))
	var add := func(s: float, p: Vector3):
		var c := Color.from_hsv(rnd(hue.x, hue.y), 0.85 if kind == "autumn" else 0.6, rnd(0.42, 0.55) if kind == "pine" else rnd(0.62, 0.85))
		cubes.append([Transform3D(Basis().scaled(Vector3.ONE * s * sc), Vector3(x, y0, z) + p * sc), c])
	if kind == "pine":
		for l in 5:
			var r := 1.3 - l * 0.25
			for k in 8:
				var a := k / 8.0 * TAU
				add.call(0.5, Vector3(cos(a) * r * 0.7, 1.0 + l * 0.6, sin(a) * r * 0.7))
		add.call(0.4, Vector3(0, 4.1, 0))
	else:
		for k in 26:
			var a := rnd(0, TAU)
			var r := rnd(0, 1.3)
			var h := rnd(-0.6, 0.8)
			add.call(rnd(0.45, 0.8), Vector3(cos(a) * r, trunk_h + 0.8 + h * (1.0 - r * 0.3), sin(a) * r))
	rocks.append({"x": x, "z": z, "r": 0.45})

# ---------------------------------------------------------------- lights
var shop_pos := Vector3.ZERO  # in front of the cottage door
var shop_open := false
var lanterns: Array = []     # OmniLight3D, brighter after dusk
var sunbeams: Array = []     # additive light shafts, strongest at golden hour

# one MultiMesh of coloured boxes ([Transform3D, Color] pairs), lit by vertex colour
func multimesh_of(list: Array) -> MultiMeshInstance3D:
	var cm := StandardMaterial3D.new()
	cm.vertex_color_use_as_albedo = true
	cm.roughness = 0.9
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = BoxMesh.new()
	mm.instance_count = list.size()
	for i in list.size():
		mm.set_instance_transform(i, list[i][0])
		mm.set_instance_color(i, (list[i][1] as Color).srgb_to_linear())
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = cm
	add_child(mmi)
	return mmi

# the same, split into 6x6 chunks so each sees only nearby lights (the web renderer lights a mesh with at most 8)
func add_chunks(blocks: Array, origin_x: int) -> void:
	var chunks := {}
	for bl in blocks:
		var o: Vector3 = bl[0].origin
		var key := Vector2i(int(o.x - origin_x) / 6, int(o.z) / 6)
		if not chunks.has(key):
			chunks[key] = []
		chunks[key].append(bl)
	for key in chunks:
		multimesh_of(chunks[key])

func folk_sprite(id: String) -> Sprite3D:
	var spr := Sprite3D.new()
	spr.texture = load("res://art/folk/%s.png" % id)
	spr.hframes = 2
	spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	spr.scale = Vector3(1, 1.0 / cos(0.78), 1)
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	spr.shaded = false
	spr.pixel_size = 1.75 / 170.0
	spr.offset = Vector2(0, 85)
	return spr

func lantern(x: float, z: float, post_mat: Material, glass: Material) -> void:
	var y := height_at(x, z)
	var pole := box(Vector3(0.12, 1.5, 0.12), post_mat)
	pole.position = Vector3(x, y + 0.75, z)
	add_child(pole)
	var arm := box(Vector3(0.4, 0.08, 0.08), post_mat)
	arm.position = Vector3(x + 0.15, y + 1.48, z)
	add_child(arm)
	var lamp := box(Vector3(0.22, 0.28, 0.22), glass)
	lamp.position = Vector3(x + 0.3, y + 1.3, z)
	add_child(lamp)
	var l := OmniLight3D.new()
	l.light_color = Color("#ffb45a")
	l.omni_range = 5.0
	l.omni_attenuation = 1.6
	l.position = lamp.position
	add_child(l)
	l.set_meta("glass", lamp)
	lanterns.append(l)

# a small cottage west of the start: plaster walls, shingled gable roof,
# stone chimney, wooden door, a warm window and a lantern by the door
func build_cottage() -> void:
	var spot := Vector2(8, 17)
	for tries in 30:
		if walkable(spot.x, spot.y) and walkable(spot.x - 1.5, spot.y) and walkable(spot.x + 1.5, spot.y) 				and spot.distance_to(START) > 5.0:
			break
		spot = Vector2(rnd(5, 10), rnd(14, 22))
	var g := Node3D.new()
	g.position = Vector3(spot.x, height_at(spot.x, spot.y), spot.y)
	g.rotation.y = 0.2
	add_child(g)
	var wall := mat_color(Color("#e4dccc"))
	var trim := mat_color(Color("#4a3428"))
	var add := func(size: Vector3, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
		var b := box(size, m)
		b.position = pos
		b.rotation = rot
		g.add_child(b)
		return b
	add.call(Vector3(3.0, 1.8, 2.4), Vector3(0, 0.9, 0), wall)                 # walls
	add.call(Vector3(3.1, 0.12, 2.5), Vector3(0, 0.06, 0), trim)               # sill beam
	for x in [-1.5, 1.5]:
		add.call(Vector3(0.12, 1.8, 0.12), Vector3(x, 0.9, 1.2), trim)         # corner posts
	# gable ends: stacked shrinking plaster slabs
	for k in 5:
		add.call(Vector3(3.0, 0.2, 2.4 - k * 0.48), Vector3(0, 1.9 + k * 0.2, 0), wall)
	# roof: two slopes of shingle rows, alternating shades
	for side in [-1.0, 1.0]:
		for r in 6:
			var shade := Color("#3a3846") if r % 2 == 0 else Color("#2e2c38")
			add.call(Vector3(3.5, 0.1, 0.32), Vector3(0, 1.85 + r * 0.2, side * (1.45 - r * 0.24)), mat_color(shade), Vector3(side * 0.7, 0, 0))
	add.call(Vector3(3.6, 0.14, 0.2), Vector3(0, 3.05, 0), mat_color(Color("#24222c")))  # ridge
	var stone := mat_color(Color("#4a4e5e"))
	add.call(Vector3(0.45, 1.1, 0.45), Vector3(0.9, 3.0, -0.5), stone)      # chimney
	add.call(Vector3(0.55, 0.12, 0.55), Vector3(0.9, 3.58, -0.5), mat_color(Color("#2e3240")))
	# front: door, window with warm light, lantern
	add.call(Vector3(0.7, 1.25, 0.08), Vector3(-0.6, 0.65, 1.22), mat_color(Color("#5a3a26")))
	add.call(Vector3(0.08, 0.08, 0.1), Vector3(-0.35, 0.65, 1.28), mat_color(Color("#d9b04a")))
	add.call(Vector3(0.8, 0.7, 0.1), Vector3(0.65, 1.0, 1.22), trim)
	var pane := glow_mat(Color("#ffc46a"), 2.0)
	pane.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	pane.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	add.call(Vector3(0.62, 0.52, 0.1), Vector3(0.65, 1.0, 1.25), pane)
	add.call(Vector3(0.04, 0.52, 0.12), Vector3(0.65, 1.0, 1.27), trim)
	add.call(Vector3(0.62, 0.04, 0.12), Vector3(0.65, 1.0, 1.27), trim)
	var glass := glow_mat(Color("#ffc46a"), 4.0)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	glass.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	add.call(Vector3(0.2, 0.26, 0.2), Vector3(-0.05, 1.4, 1.38), glass)
	add.call(Vector3(0.06, 0.06, 0.25), Vector3(-0.05, 1.58, 1.3), trim)
	var l := OmniLight3D.new()
	l.light_color = Color("#ffb45a")
	l.omni_range = 5.0
	l.omni_attenuation = 1.6
	l.position = Vector3(-0.05, 1.4, 1.6)
	g.add_child(l)
	lanterns.append(l)
	# chimney smoke
	var smoke := CPUParticles3D.new()
	smoke.amount = 14
	smoke.lifetime = 3.0
	smoke.direction = Vector3(0.3, 1, 0)
	smoke.spread = 12.0
	smoke.initial_velocity_min = 0.4
	smoke.initial_velocity_max = 0.7
	smoke.gravity = Vector3(0.15, 0.05, 0)
	smoke.scale_amount_min = 0.8
	smoke.scale_amount_max = 1.6
	var sq := QuadMesh.new()
	sq.size = Vector2(0.35, 0.35)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = Color(0.85, 0.85, 0.9, 0.35)
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sq.material = sm
	smoke.mesh = sq
	smoke.position = Vector3(0.9, 3.7, -0.5)
	g.add_child(smoke)
	shop_pos = g.transform * Vector3(-0.6, 0, 1.9)
	# hanging sign over the door
	add.call(Vector3(0.7, 0.32, 0.06), Vector3(-0.6, 1.55, 1.32), mat_color(Color("#8a5a32")))
	var sign := Label3D.new()
	sign.text = "상점"
	sign.font = ui_font_for_sign()
	sign.font_size = 48
	sign.pixel_size = 0.005
	sign.modulate = Color("#ffe6a0")
	sign.outline_size = 8
	sign.position = Vector3(-0.6, 1.55, 1.37)
	g.add_child(sign)
	# block the footprint
	for dx in [-1.0, 0.0, 1.0]:
		for dz in [-0.6, 0.6]:
			var w := g.transform * Vector3(dx, 0, dz)
			rocks.append({"x": w.x, "z": w.z, "r": 0.9})

func ui_font_for_sign() -> Font:
	return ui_font

# ---------------------------------------------------------------- shop
const SHOP := [
	{"name": "회복약", "desc": "체력 45 회복", "price": 30},
	{"name": "기세 사탕", "desc": "기세 +50", "price": 20},
	{"name": "벼린 칼날", "desc": "공격력 +3", "price": 80},
	{"name": "튼튼한 갑옷", "desc": "최대 체력 +15", "price": 80},
]

func near_shop() -> bool:
	return Vector2(player.x - shop_pos.x, player.z - shop_pos.z).length() < 1.6

const SHOP_GREET := ["어서 오렴. 천천히 골라 보거라.", "오늘은 뭐가 필요하니?", "늪이 험하지? 약은 넉넉히 챙기렴.", "늪 구석구석에 달지기들의 옛 지도 조각이 흩어져 있다더구나."]

# Bori has heard what Sora has been up to: a line for each keepsake or deed, mixed in with her usual greetings
func bori_news() -> Array:
	var out: Array = []
	if marsh.chest_open: out.append("지도 조각을 다 맞췄다며? 달지기들 솜씨는 여전하구나.")
	if fly_q >= 3: out.append("반딧불 병이구나. 밤길이 덜 무섭겠어.")
	if has_pearl: out.append("물빛 진주라니. 물결네 할아버지가 아끼던 거란다.")
	if has_feather: out.append("바람 깃털을 지녔구나. 걸음이 한결 가벼워 보인다.")
	if has_acorn: out.append("다람쥐들이 고맙다고 도토리를 줬다고? 귀엽기도 하지.")
	if has_ring: out.append("그 반지 소리가 맑구나. 동굴 수정이지?")
	if castle.pages_read() >= 3: out.append("한결의 일기를 읽었다고…… 그 녀석, 끝까지 혼자 짊어졌구나.")
	if trial_best > 0.0: out.append("심지가 그러던데, 달빛 시련을 마쳤다며? 대단하구나.")
	if has_armour: out.append("달지기 갑옷이 잘 어울리는구나. 이제야 마음이 놓인다.")
	if not has_tea and marsh.picked_count() == 0 and story_step >= 5: out.append("달이 반 넘게 찬 밤이면 늪에 달꽃이 핀단다. 세 송이만 가져오면 차를 끓여 주마.")
	return out

func toggle_shop(open: bool) -> void:
	if open and story_step < 3:
		meet_bori()
		return
	shop_open = open
	ui.shop.visible = open
	if open:
		var lines: Array = SHOP_GREET.duplicate()
		lines.append_array(bori_news())
		ui.shop_say.text = lines[rng.randi() % lines.size()]
		ui.shop_keeper.texture = load("res://art/portrait/bori.png")
		refresh_shop()
		sfx(660, 0.12, "triangle", 0.2)

# the blade and the armour cost 40 more each time one is bought (80, 120, 160, ...)
var shop_bought := [0, 0, 0, 0]

func shop_price(i: int) -> int:
	return SHOP[i].price + (40 * shop_bought[i] if i >= 2 else 0)

func refresh_shop() -> void:
	ui.shop_gold.text = "◆ %d" % player.gold
	for i in SHOP.size():
		ui.shop_btns[i].disabled = player.gold < shop_price(i)
		ui.shop_btns[i].text = tr("◆ %d  사기") % shop_price(i)

func buy(i: int) -> void:
	var it: Dictionary = SHOP[i]
	if player.gold < shop_price(i):
		ui.shop_say.text = "금화가 조금 모자라구나. 늪을 한 바퀴 더 돌고 오렴."
		ui.shop_keeper.texture = load("res://art/portrait/bori_serious.png")
		return
	player.gold -= shop_price(i)
	shop_bought[i] += 1
	match i:
		0: player.pots += 1
		1: player.mp = minf(player.max_mp, player.mp + 50.0)
		2: player.atk += 3
		3:
			player.max_hp += 15
			player.hp += 15
	ui.shop_say.text = ["몸조심하렴. 아플 땐 아끼지 말고 마시고.", "달콤하지? 기운이 날 게다.", "날이 잘 섰다. 손 베이지 않게 조심해.", "든든할 게다. 이제 좀 마음이 놓이는구나."][i]
	ui.shop_keeper.texture = load("res://art/portrait/bori.png")
	sfx(880, 0.08, "square", 0.15)
	get_tree().create_timer(0.07).timeout.connect(func(): sfx(1320, 0.12, "square", 0.15))
	refresh_shop()

func build_lights() -> void:
	var post_mat := mat_color(Color("#3b2a1e"))
	var glass := glow_mat(Color("#ffc46a"), 4.0)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	glass.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	# a lantern post at both ends of every bridge
	for br in bridges:
		for x in [br.a - 1.6, br.b + 1.6]:
			lantern(x, br.z - 0.6, post_mat, glass)
	# and a few more along the meadow: by the start, the lakeshore, the high meadow, the forest edges
	for p in [Vector2(13, 17), Vector2(18, 24), Vector2(17, 33), Vector2(31, 36), Vector2(33, 13),
			Vector2(39, 9), Vector2(34, 22), Vector2(9, 27)]:
		var spot: Vector2 = p
		for tries in 12: # nudge off water, bushes and trees
			if walkable(spot.x, spot.y) and tile_at(spot.x, spot.y) == GRASS:
				break
			spot = p + Vector2(rnd(-2, 2), rnd(-2, 2))
		if walkable(spot.x, spot.y):
			lantern(spot.x, spot.y, post_mat, glass)
			rocks.append({"x": spot.x, "z": spot.y, "r": 0.25})
	# slanted sun shafts: long additive quads in a loose ring around the play area
	var shaft := make_tex(16, 64, func(img: Image):
		for y in 64:
			for x in 16:
				var a := sin(PI * x / 15.0) * (1.0 - y / 64.0)
				img.set_pixel(x, y, Color(1, 0.9, 0.65, a * 0.5)))
	for i in 14:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(rnd(1.2, 2.4), 14.0)
		q.mesh = qm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_texture = shaft
		m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		m.no_depth_test = false
		q.material_override = m
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		q.position = Vector3(rnd(4, N - 4), 6.0, rnd(4, N - 4))
		q.rotation.z = 0.5 # lean with the sun
		add_child(q)
		sunbeams.append([q, m, rnd(0, TAU)])

func update_lights() -> void:
	for l in lanterns:
		if l == dark_lamp or l.get_meta("dark", false):
			l.light_energy = 0.0
			continue
		l.light_energy = (0.6 + night * 2.4) * (1.0 + sin(t * 9.0 + l.position.x) * 0.05)
	for b in sunbeams:
		b[1].albedo_color = Color(1, 1, 1, beams * (0.55 + 0.45 * sin(t * 0.5 + b[2])))

# ---------------------------------------------------------------- player
func blob(r: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = Vector2(r, r * 0.7)
	m.mesh = q
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = make_tex(16, 16, func(img: Image):
		for y in 16:
			for x in 16:
				var d := Vector2(x - 7.5, y - 7.5).length() / 8.0
				img.set_pixel(x, y, Color(0, 0, 0, clampf(0.55 * (1.0 - d), 0.0, 1.0))))
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	return m

func build_player() -> void:
	player = {
		"x": START.x, "z": START.y, "vx": 0.0, "vz": 0.0, "face": Vector2(0, 1), "dir": "down", "anim": 0.0,
		"lv": 1, "xp": 0, "hp": 100.0, "max_hp": 100, "mp": 0.0, "max_mp": 100, "sp": 100.0, "atk": 10, "gold": 0, "pots": 3,
		"atk_cd": 0.0, "combo": 0, "combo_t": 0.0, "dodge": 0.0, "dvx": 0.0, "dvz": 0.0, "inv": 0.0, "cds": [0.0, 0.0, 0.0, 0.0], "hurt_t": 0.0,
	}
	# Sora walk sheets: 4 frames per row; straight rows front, left, right, away; diagonal rows dl, dr, ul, ur
	var straight: Texture2D = load("res://art/sora/sora-v3-walk.png")
	var diag: Texture2D = load("res://art/sora/sora-v3-diag.png")
	for d in [["down", 0], ["left", 1], ["side", 2], ["up", 3]]:
		hero_tex[d[0]] = [straight, d[1]]
	for d in [["downleft", 0], ["downright", 1], ["upleft", 2], ["upright", 3]]:
		hero_tex[d[0]] = [diag, d[1]]
	hero = Sprite3D.new()
	hero.texture = straight
	hero.region_enabled = true
	# stand upright (a fully camera-facing quad leans back and sinks its feet into the ground and grass)
	# and stretch it by 1/cos(camera pitch) so it still reads at its true proportions
	hero.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	hero.scale = Vector3(1, 1.0 / cos(0.78), 1)
	hero.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	hero.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	hero.shaded = false
	# 192x256 cells like the idle sprites; she stands about 244 px tall with her feet 7 px above the cell bottom
	hero.pixel_size = 1.58 / 244.0
	hero.offset = Vector2(0, 121)
	walk_px = hero.pixel_size
	walk_off = hero.offset
	add_child(hero)
	# a faint see-through copy drawn over everything, so Sora stays readable behind roofs and trees
	hero_ghost = Sprite3D.new()
	hero_ghost.region_enabled = true
	hero_ghost.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	hero_ghost.shaded = false
	hero_ghost.no_depth_test = true
	hero_ghost.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	hero_ghost.modulate = Color(0.75, 0.82, 1.0, 0.35)
	hero_ghost.render_priority = -1
	hero_ghost.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	hero.add_child(hero_ghost)
	hero_shadow = blob(0.9)
	set_hero_frame("down", 0)

var hero_ghost: Sprite3D

func sync_ghost() -> void:
	hero_ghost.texture = hero.texture
	hero_ghost.region_rect = hero.region_rect
	hero_ghost.pixel_size = hero.pixel_size
	hero_ghost.offset = hero.offset
	hero_ghost.flip_h = hero.flip_h

func set_hero_frame(dir: String, frame: int) -> void:
	hero.flip_h = false
	var e: Array = hero_tex[dir]
	var tex: Texture2D = e[0]
	var cw := tex.get_width() / 4.0
	var ch := tex.get_height() / 4.0
	hero.texture = tex
	hero.region_rect = Rect2(frame * cw, e[1] * ch, cw, ch)
	hero.pixel_size = walk_px
	hero.offset = walk_off

# ---- standing still: Sora turns to the viewer, breathes, and now and then does something of her own
# (front-facing 4-frame loops from the Space Oddity sprites, 192x256 cells, art/sora/idle/<name>.png)
const IDLE_ACTS := [
	"cheer-big", "hot-wipe", "rest-bubble", "rest-cheer", "rest-clap", "rest-comb", "rest-count", "rest-crane",
	"rest-draw", "rest-float", "rest-gum", "rest-hop", "rest-juggle", "rest-knit", "rest-letter", "rest-look",
	"rest-map", "rest-music", "rest-nod", "rest-note", "rest-photo", "rest-pinwheel", "rest-plush", "rest-ribbon",
	"rest-rope", "rest-scope", "rest-sit", "rest-sleep", "rest-snack", "rest-socks", "rest-spin", "rest-star",
	"rest-stretch", "rest-string", "rest-sway", "rest-tea", "rest-tilt", "rest-umbrella", "rest-water",
	"rest-wave", "rest-wave2", "rest-yawn", "rest-yoyo", "see-aurora", "see-hush", "see-point", "see-snap",
	"see-up", "see-wow"
]
const IDLE_LONG := ["rest-snack", "rest-tea", "rest-water", "rest-nod", "rest-sleep", "rest-yoyo", "rest-juggle", "rest-knit", "rest-draw", "rest-music", "rest-string"] # these play twice as long
var walk_px := 0.0
var walk_off := Vector2.ZERO
var idle_t := 0.0
var idle_name := ""
var idle_k := 0.0
var idle_left := 0.0
var idle_tex := {}
var last_input_t := 0.0  # rest actions start only after 10 s without a key or click

func set_hero_idle(name: String, frame: int) -> void:
	if not idle_tex.has(name):
		idle_tex[name] = load("res://art/sora/idle/%s.png" % name)
	hero.texture = idle_tex[name]
	hero.flip_h = false
	hero.region_rect = Rect2(frame * 192, 0, 192, 256)
	hero.pixel_size = walk_px # same cell size and scale as the walk sheets
	hero.offset = walk_off

func update_idle(dt: float) -> void:
	if idle_name == "": # just stopped: breathe, facing the viewer
		idle_name = "idle"
		idle_k = 0.0
		idle_left = rnd(3.0, 6.0)
	idle_k += dt * (1.4 if idle_name == "idle" else 1.8) # slow, calm frames: breathing 1.4 per second, actions 1.8
	idle_left -= dt
	if idle_left <= 0.0:
		var calm: bool = nearest_enemy(7.0) == null
		if idle_name == "idle" and calm and t - last_input_t >= 10.0:
			idle_name = IDLE_ACTS.pick_random()
			idle_left = 8.9 if idle_name in IDLE_LONG else 4.45 # two or four loops of four frames
		else:
			idle_name = "idle"
			idle_left = rnd(2.0, 4.0)
		idle_k = 0.0
	set_hero_idle(idle_name, int(idle_k) % 4)

# ---------------------------------------------------------------- enemies
# LEGO-style brick goblin: plastic boxes with studs on top faces
func brick(g: Node3D, mats: Array, size: Vector3, pos: Vector3, color: Color, studs := true, glow := false) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.32
	if glow:
		m.emission_enabled = true
		m.emission = Color("#ff9a1a")
		m.emission_energy_multiplier = 3.0
	else:
		mats.append(m)
	var b := box(size, m)
	b.position = pos
	g.add_child(b)
	if studs:
		var nx := maxi(1, int(round(size.x / 0.2)))
		var nz := maxi(1, int(round(size.z / 0.2)))
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.075
		cyl.bottom_radius = 0.075
		cyl.height = 0.06
		cyl.radial_segments = 12
		for i in nx:
			for k in nz:
				var st := MeshInstance3D.new()
				st.mesh = cyl
				st.material_override = m
				st.position = pos + Vector3(-size.x / 2.0 + (i + 0.5) * size.x / nx, size.y / 2.0 + 0.03, -size.z / 2.0 + (k + 0.5) * size.z / nz)
				g.add_child(st)

func make_monster(boss := false) -> Node3D:
	var root := Node3D.new()
	var g := Node3D.new()
	root.add_child(g)
	var mats: Array = []
	var body := Color("#5a2a8a") if boss else Color("#b4231e")
	var dark := Color("#2e2a30")
	var head := Color("#1e1e2a") if boss else Color("#2f5fb8")
	brick(g, mats, Vector3(0.14, 0.16, 0.16), Vector3(-0.13, 0.08, 0), dark, false)
	brick(g, mats, Vector3(0.14, 0.16, 0.16), Vector3(0.13, 0.08, 0), dark, false)
	brick(g, mats, Vector3(0.5, 0.3, 0.36), Vector3(0, 0.31, 0), body)
	brick(g, mats, Vector3(0.12, 0.2, 0.14), Vector3(-0.32, 0.34, 0), body, false)
	brick(g, mats, Vector3(0.12, 0.2, 0.14), Vector3(0.32, 0.34, 0), body, false)
	brick(g, mats, Vector3(0.42, 0.32, 0.38), Vector3(0, 0.64, 0), head)
	brick(g, mats, Vector3(0.1, 0.1, 0.04), Vector3(-0.1, 0.68, 0.2), Color("#ffc23a"), false, true)
	brick(g, mats, Vector3(0.1, 0.1, 0.04), Vector3(0.1, 0.68, 0.2), Color("#ffc23a"), false, true)
	brick(g, mats, Vector3(0.22, 0.04, 0.04), Vector3(0, 0.55, 0.2), dark, false)
	brick(g, mats, Vector3(0.08, 0.18, 0.08), Vector3(-0.16, 0.9, 0), Color("#e8dcc0"), false)
	brick(g, mats, Vector3(0.08, 0.18, 0.08), Vector3(0.16, 0.9, 0), Color("#e8dcc0"), false)
	if boss: # gold crown of studded bricks and a cape plate
		brick(g, mats, Vector3(0.46, 0.08, 0.42), Vector3(0, 0.84, 0), Color("#e8b018"))
		for cx in [-0.16, 0.0, 0.16]:
			brick(g, mats, Vector3(0.08, 0.14, 0.08), Vector3(cx, 0.95, 0.15), Color("#e8b018"), false)
		brick(g, mats, Vector3(0.56, 0.4, 0.06), Vector3(0, 0.36, -0.22), Color("#8a1a1a"), false)
	root.scale = Vector3.ONE * (3.2 if boss else 1.3)
	root.set_meta("mats", mats)
	root.set_meta("body", g)
	return root

func spawn_enemy(at := Vector2(-1, -1), archer := false) -> void:
	var x := at.x
	var z := at.y
	var tries := 0
	while at.x < 0:
		x = rnd(4, N - 4)
		z = rnd(4, N - 4)
		tries += 1
		if (walkable(x, z) and Vector2(x - player.x, z - player.z).length() >= 9) or tries > 1000:
			break
	var node := make_monster()
	add_child(node)
	var hp: int = (20 + player.lv * 8) if archer else (30 + player.lv * 10)
	if archer: # brick archer: green body, mustard head
		var mats: Array = node.get_meta("mats")
		mats[2].albedo_color = Color("#3f8a3a")
		mats[5].albedo_color = Color("#d9b03a")
	enemies.append({"x": x, "z": z, "hp": float(hp), "max_hp": hp, "node": node, "shadow": blob(0.8), "t": rnd(0, 5),
		"atk_cd": 1.0, "hurt": 0.0, "kx": 0.0, "kz": 0.0, "wx": x, "wz": z, "dead": false, "respawn": 0.0,
		"archer": archer, "cave": at.x >= CAVE_X - 0.5})

# the Brick King waits at the northern edge of the map; he does not respawn
# ---- brick wolves: quick pack hunters in the forest and on the hill. A wolf circles Sora about 3 tiles out,
# then a 0.35 s crouch ("!") and a straight lunge (7 tiles/s for 0.35 s); after it, 0.8 s to catch its breath.
func make_wolf() -> Node3D:
	var root := Node3D.new()
	var g := Node3D.new()
	root.add_child(g)
	var mats: Array = []
	var fur := Color("#7a6a5a")
	var dark := Color("#3a3230")
	brick(g, mats, Vector3(0.36, 0.3, 0.8), Vector3(0, 0.38, 0), fur)          # body
	brick(g, mats, Vector3(0.32, 0.3, 0.34), Vector3(0, 0.55, 0.5), fur)       # head
	brick(g, mats, Vector3(0.2, 0.14, 0.2), Vector3(0, 0.48, 0.74), dark, false) # snout
	brick(g, mats, Vector3(0.08, 0.14, 0.06), Vector3(-0.1, 0.76, 0.46), dark, false) # ears
	brick(g, mats, Vector3(0.08, 0.14, 0.06), Vector3(0.1, 0.76, 0.46), dark, false)
	brick(g, mats, Vector3(0.07, 0.07, 0.03), Vector3(-0.08, 0.6, 0.67), Color("#ffc23a"), false, true) # eyes
	brick(g, mats, Vector3(0.07, 0.07, 0.03), Vector3(0.08, 0.6, 0.67), Color("#ffc23a"), false, true)
	for leg in [Vector3(-0.12, 0.12, 0.28), Vector3(0.12, 0.12, 0.28), Vector3(-0.12, 0.12, -0.28), Vector3(0.12, 0.12, -0.28)]:
		brick(g, mats, Vector3(0.1, 0.24, 0.1), leg, dark, false)
	brick(g, mats, Vector3(0.08, 0.08, 0.36), Vector3(0, 0.48, -0.52), fur, false) # tail
	root.scale = Vector3.ONE * 1.3
	root.set_meta("mats", mats)
	root.set_meta("body", g)
	return root

func spawn_wolf(at: Vector2) -> void:
	var node := make_wolf()
	add_child(node)
	var hp: int = 25 + player.lv * 7
	enemies.append({"x": at.x, "z": at.y, "hp": float(hp), "max_hp": hp, "node": node, "shadow": blob(0.7), "t": rnd(0, 5),
		"atk_cd": rnd(1.0, 2.5), "hurt": 0.0, "kx": 0.0, "kz": 0.0, "wx": at.x, "wz": at.y, "dead": false, "respawn": 0.0,
		"wolf": true, "cave": true, "wind": 0.0, "stun": 0.0, "dash": 0.0, "dir": Vector2.ZERO, "rest": 0.0, "hit_done": false,
		"side": 1.0 if rng.randf() < 0.5 else -1.0})

func update_wolf(e: Dictionary, dt: float, d: float, to: Vector2) -> void:
	e.t += dt
	e.atk_cd -= dt
	e.hurt -= dt
	e.rest -= dt
	e.stun = e.get("stun", 0.0) - dt
	var dirn: Vector2 = to / maxf(d, 0.01)
	var v := Vector2.ZERO
	if e.hurt > 0.0 or e.stun > 0.0:
		e.dash = 0.0
		e.wind = 0.0
		v = Vector2(e.kx, e.kz)
	elif e.dash > 0.0:
		e.dash -= dt
		v = e.dir * 7.0
		if not e.hit_done and d < 1.0:
			e.hit_done = true
			player_hit(int(round(rnd(7, 10) + player.lv)), Vector2(e.x, e.z), e)
		if e.dash <= 0.0:
			e.rest = 0.8
	elif e.wind > 0.0:
		e.wind -= dt
		if e.wind <= 0.0:
			e.dash = 0.35
			e.dir = dirn
			e.hit_done = false
			e.atk_cd = rnd(1.6, 2.4)
	elif e.rest > 0.0:
		pass
	elif d < 9.0 and not intro:
		if e.atk_cd <= 0.0 and d < 4.0:
			e.wind = 0.35
			pop_num(Vector3(e.x, height_at(e.x, e.z) + 1.1, e.z), "!", Color("#ff5a4a"))
		else: # circle her about 3 tiles out, sliding in or out to keep the ring
			v = dirn.rotated(PI / 2.0 * e.side) * 3.2 + dirn * clampf(d - 3.0, -1.0, 1.0) * 2.5
	else:
		if Vector2(e.wx - e.x, e.wz - e.z).length() < 0.3 or rng.randf() < 0.005:
			e.wx = e.x + rnd(-3, 3)
			e.wz = e.z + rnd(-3, 3)
		var w := Vector2(e.wx - e.x, e.wz - e.z)
		if w.length() > 0.01:
			v = w.normalized() * 1.2
	e.kx *= pow(0.002, dt)
	e.kz *= pow(0.002, dt)
	var nx: float = e.x + v.x * dt
	var nz: float = e.z + v.y * dt
	if walkable(nx, e.z): e.x = nx
	else: e.side = -e.side # a wall: circle the other way
	if walkable(e.x, nz): e.z = nz
	var node: Node3D = e.node
	var y := height_at(e.x, e.z)
	var run := absf(sin(e.t * 14.0)) if v.length() > 0.5 else 0.0
	node.position = Vector3(e.x, y + run * 0.08, e.z)
	if e.wind > 0.0 or e.dash > 0.0:
		node.rotation.y = atan2(dirn.x, dirn.y)
	elif v.length() > 0.1:
		node.rotation.y = lerp_angle(node.rotation.y, atan2(v.x, v.y), minf(1.0, dt * 10.0))
	var body: Node3D = node.get_meta("body")
	body.scale = Vector3(1.0, 0.85 if e.wind > 0.0 else 1.0, 1.0) # crouches before the lunge
	for m in node.get_meta("mats"):
		m.emission_enabled = e.hurt > 0 or e.wind > 0.0
		m.emission = Color("#ff3a2a") if e.wind > 0.0 and e.hurt <= 0 else Color.WHITE
		m.emission_energy_multiplier = 0.9
	e.shadow.position = Vector3(e.x, y + 0.02, e.z)

# ---- 달빛 시련: a ring of standing stones in the village's south-west corner, open after the lantern night.
# E at the moon stone starts five waves; the next comes 2.5 s after the last one falls. Fainting or leaving
# the village ends the run. The first clear gives max HP +20, attack +3 and 300 gold; later clears 80 gold.
const TRIAL_WAVES := [
	["g", "g", "g", "g"],
	["g", "g", "g", "a", "a"],
	["w", "w", "w"],
	["s", "s", "a", "a", "g"],
	["W", "w", "w"], # W: the trial warden, a big goblin
]
var trial_wave := 0          # 0 idle, 1..5 the wave being fought
var trial_wait := 0.0        # pause before the next wave
var trial_start := 0.0
var trial_best := 0.0        # best clear in seconds (0: never cleared)
var trial_stone: Node3D

func build_trial() -> void:
	var at: Vector2 = village.marks.R
	trial_stone = Node3D.new()
	var stone: Material = mat_color(Color("#8a8a94"))
	var core: MeshInstance3D = box(Vector3(0.7, 1.3, 0.7), stone)
	core.position = Vector3(0, 0.65, 0)
	trial_stone.add_child(core)
	var moon: MeshInstance3D = box(Vector3(0.4, 0.4, 0.08), glow_mat(Color("#dfe8ff"), 1.2))
	moon.position = Vector3(0, 1.05, 0.36)
	trial_stone.add_child(moon)
	for k in 6: # the ring of low standing stones
		var a := k * TAU / 6.0
		var post: MeshInstance3D = box(Vector3(0.3, 0.6, 0.3), stone)
		post.position = Vector3(cos(a) * 2.2, 0.3, sin(a) * 2.2)
		trial_stone.add_child(post)
	var glow := OmniLight3D.new() # a pale moonlight over the ring; this corner of the village has no lantern
	glow.light_color = Color("#bcd6ff")
	glow.light_energy = 1.8
	glow.omni_range = 7.0
	glow.position = Vector3(0, 2.2, 0)
	trial_stone.add_child(glow)
	trial_stone.position = Vector3(at.x, 0, at.y)
	add_child(trial_stone)
	rocks.append({"x": at.x, "z": at.y, "r": 0.45})

func trial_key() -> bool:
	if trial_stone == null or Vector2(player.x, player.z).distance_to(village.marks.R) > 1.6:
		return false
	if night_q < 4:
		toast("시련의 돌은 아직 잠들어 있다")
		return true
	if trial_wave > 0:
		return true
	trial_wave = 1
	trial_wait = 1.5
	trial_start = t
	show_story("", STORY.TRIAL_IN)
	return true

func trial_foes() -> Array:
	return enemies.filter(func(e): return e.get("trial", false) and not e.dead)

func spawn_trial_wave() -> void:
	var c: Vector2 = village.marks.R
	var list: Array = TRIAL_WAVES[trial_wave - 1]
	for i in list.size():
		var at := c + Vector2(1.5, 0)
		for tries in 30:
			var a := rnd(0, TAU)
			var cand := c + Vector2(cos(a), sin(a)) * rnd(4.0, 5.5)
			if walkable(cand.x, cand.y):
				at = cand
				break
		var kind: String = list[i]
		if kind == "w":
			spawn_wolf(at)
		else:
			spawn_enemy(at, kind == "a")
		var e: Dictionary = enemies[enemies.size() - 1]
		e.trial = true
		e.cave = true
		if kind == "s":
			give_shield(e)
		if kind == "W":
			e.hp = 300.0 + player.lv * 30
			e.max_hp = int(e.hp)
			e.size_k = 1.7 # update_enemies sets the scale every frame, so the warden's size goes through this
			var mats: Array = e.node.get_meta("mats")
			mats[2].albedo_color = Color("#6a6a78")
			mats[5].albedo_color = Color("#dfe8ff")
		burst(Vector3(at.x, 0.6, at.y), Color("#dfe8ff"), 12, 2.0)
	toast(tr("달빛 시련 %d/5") % trial_wave)
	sfx(330 + trial_wave * 60, 0.3, "triangle", 0.2)

func update_trial(dt: float) -> void:
	if trial_wave == 0:
		return
	if not in_village:
		end_trial("마을을 벗어나 시련이 끝났다")
		return
	if story_open:
		return
	if trial_wait > 0.0:
		trial_wait -= dt
		if trial_wait <= 0.0:
			spawn_trial_wave()
		return
	if trial_foes().is_empty():
		if trial_wave >= TRIAL_WAVES.size():
			clear_trial()
		else:
			trial_wave += 1
			trial_wait = 2.5

func end_trial(msg: String) -> void:
	for e in trial_foes():
		e.dead = true
		e.node.queue_free()
		e.shadow.queue_free()
	trial_wave = 0
	trial_wait = 0.0
	toast(msg)

func clear_trial() -> void:
	var secs := t - trial_start
	var first := trial_best <= 0.0
	trial_wave = 0
	if first:
		player.max_hp += 20
		player.atk += 3
		player.gold += 300
		show_story("", STORY.TRIAL_DONE)
	else:
		player.gold += 80
	player.hp = float(player.max_hp)
	if first or secs < trial_best:
		trial_best = secs
	burst(Vector3(player.x, 1.6, player.z), Color("#dfe8ff"), 40, 4.0)
	sfx(784, 0.3, "triangle", 0.25)
	toast(tr("달빛 시련을 마쳤다: %d분 %02d초") % [int(secs) / 60, int(secs) % 60] + ("" if first else tr(" (금화 +80)")))
	save_game()

# ---- the pinwheel race on the wind hills (west of the gorge): E at the race post starts a 25 s run;
# pass through all five pinwheels, in any order. The first win gives the wind shoes (running 6.2 -> 7.0
# tiles/s); later wins 30 gold. The best time shows in the journal.
const RACE_POST := Vector2(2, 21)  # hill tiles
const RACE_WHEELS := [Vector2(9, 4), Vector2(17, 2), Vector2(12, 9), Vector2(7, 15), Vector2(16, 21)]
const RACE_TIME := 25.0
var race_on := false
var race_left := 0.0
var race_got: Array = []
var race_nodes: Array = []
var race_best := 0.0
var race_quest := ""          # the quest line to put back after the race
var has_shoes := false

func build_race() -> void:
	var hx := float(HILL.HILL_X)
	var post := Node3D.new()
	var wood: Material = mat_color(Color("#7a5a3a"))
	var pole: MeshInstance3D = box(Vector3(0.18, 1.6, 0.18), wood)
	pole.position = Vector3(0, 0.8, 0)
	post.add_child(pole)
	var flag: MeshInstance3D = box(Vector3(0.7, 0.4, 0.06), mat_color(Color("#e8b018")))
	flag.position = Vector3(0.38, 1.4, 0)
	post.add_child(flag)
	post.position = Vector3(hx + RACE_POST.x, 0, RACE_POST.y)
	add_child(post)
	rocks.append({"x": hx + RACE_POST.x, "z": RACE_POST.y, "r": 0.3})
	var cols := [Color("#e84a4a"), Color("#4a8ae8"), Color("#e8c84a"), Color("#4ac87a")]
	for p in RACE_WHEELS:
		var g := Node3D.new()
		var stick: MeshInstance3D = box(Vector3(0.1, 1.3, 0.1), wood)
		stick.position = Vector3(0, 0.65, 0)
		g.add_child(stick)
		var hub := Node3D.new()
		hub.name = "hub"
		hub.position = Vector3(0, 1.35, 0.08)
		g.add_child(hub)
		for k in 4:
			var blade: MeshInstance3D = box(Vector3(0.42, 0.16, 0.03), mat_color(cols[k]))
			blade.position = Vector3(cos(k * PI / 2.0) * 0.22, sin(k * PI / 2.0) * 0.22, 0)
			blade.rotation.z = k * PI / 2.0
			hub.add_child(blade)
		g.position = Vector3(hx + p.x, 0, p.y)
		g.visible = false
		add_child(g)
		race_nodes.append(g)

func race_key() -> bool:
	if race_on or Vector2(player.x, player.z).distance_to(Vector2(HILL.HILL_X + RACE_POST.x, RACE_POST.y)) > 1.6:
		return false
	race_on = true
	race_left = RACE_TIME
	race_got = []
	race_quest = ui.quest.text
	for g in race_nodes:
		g.visible = true
	sfx(523, 0.12, "triangle", 0.2)
	get_tree().create_timer(0.15).timeout.connect(func(): sfx(784, 0.2, "triangle", 0.2))
	toast("바람개비 다섯 개를 지나자!")
	return true

func update_race(dt: float) -> void:
	for g in race_nodes:
		if g.visible:
			g.get_node("hub").rotation.z += dt * 6.0
	if not race_on:
		return
	if not in_hill or in_cloud() or in_castle():
		end_race("경주를 그만두었다")
		return
	race_left -= dt
	for i in race_nodes.size():
		if i in race_got:
			continue
		var w := Vector2(HILL.HILL_X + RACE_WHEELS[i].x, RACE_WHEELS[i].y)
		if Vector2(player.x, player.z).distance_to(w) < 1.0:
			race_got.append(i)
			race_nodes[i].visible = false
			burst(Vector3(w.x, 1.3, w.y), Color("#f2ead8"), 14, 2.0)
			sfx(660 + race_got.size() * 80, 0.12, "triangle", 0.2)
	set_quest(tr("바람개비 경주 %d/5 · %d초") % [race_got.size(), int(ceil(race_left))])
	if race_got.size() == RACE_WHEELS.size():
		var secs := RACE_TIME - race_left
		var first := not has_shoes
		end_race(tr("바람개비 경주 성공! %.1f초") % secs)
		if first:
			has_shoes = true
			show_story("", STORY.RACE_WIN)
		else:
			player.gold += 30
		if race_best <= 0.0 or secs < race_best:
			race_best = secs
		save_game()
	elif race_left <= 0.0:
		end_race("시간이 다 됐다. 깃대에서 다시 해 보자")

func end_race(msg: String) -> void:
	race_on = false
	for g in race_nodes:
		g.visible = false
	set_quest(race_quest)
	toast(msg)

# ---- fishing at the south lake's east shore (after the sluice is unwound): E casts; after 2 - 5 s a fish
# bites ("!" and a plop) and E within 0.7 s lands it. Five kinds; landing all five gets 100 gold and max HP +10.
const FISH := [["붕어", 40], ["메기", 25], ["무지개송어", 18], ["벽돌 물고기", 12], ["황금 잉어", 5]] # name, weight
var fish_state := ""        # "", "wait" (line in the water), "bite"
var fish_t := 0.0
var fish_kinds := [false, false, false, false, false]
var bobber: Node3D

func fish_key() -> bool:
	if lake_q < 2 or Vector2(player.x, player.z).distance_to(lake.marks.f) > 1.5:
		return false
	match fish_state:
		"":
			fish_state = "wait"
			fish_t = rnd(2.0, 5.0)
			if bobber == null:
				bobber = Node3D.new()
				var b: MeshInstance3D = box(Vector3(0.14, 0.14, 0.14), mat_color(Color("#e84a4a")))
				bobber.add_child(b)
				add_child(bobber)
			bobber.visible = true
			bobber.position = Vector3(lake.marks.f.x, -0.25, lake.marks.f.y + 2.0)
			sfx(300, 0.15, "noise", 0.08, -100)
			toast("낚싯줄을 던졌다. 찌가 흔들리면 E!")
		"wait":
			fish_state = ""
			bobber.visible = false
			toast("너무 일찍 당겼다")
		"bite":
			land_fish()
	return true

func land_fish() -> void:
	fish_state = ""
	bobber.visible = false
	var total := 0
	for f in FISH:
		total += f[1]
	var roll := rng.randi() % total
	var k := 0
	for i in FISH.size():
		roll -= FISH[i][1]
		if roll < 0:
			k = i
			break
	var fresh: bool = not fish_kinds[k]
	fish_kinds[k] = true
	var n: int = fish_kinds.count(true)
	player.gold += 5 + k * 5
	burst(Vector3(lake.marks.f.x, 0.4, lake.marks.f.y + 1.5), Color("#9fd4ff"), 16, 2.0)
	sfx(660 + k * 80, 0.15, "triangle", 0.2)
	toast(tr("%s을(를) 낚았다! (%d/5 종류)") % [tr(FISH[k][0]), n] if fresh else tr("%s을(를) 낚았다") % tr(FISH[k][0]))
	if fresh and n == FISH.size():
		player.gold += 100
		player.max_hp += 10
		player.hp = float(player.max_hp)
		show_story("", STORY.FISH_ALL)
	save_game()

func update_fishing(dt: float) -> void:
	if fish_state == "":
		return
	if not in_lake or in_grotto() or Vector2(player.x, player.z).distance_to(lake.marks.f) > 2.0:
		fish_state = ""
		bobber.visible = false
		return
	fish_t -= dt
	bobber.position.y = -0.25 + (sin(t * 30.0) * 0.06 if fish_state == "bite" else sin(t * 2.0) * 0.02)
	if fish_state == "wait" and fish_t <= 0.0:
		fish_state = "bite"
		fish_t = 0.7
		pop_num(bobber.position + Vector3(0, 0.8, 0), "!", Color("#ffd84a"))
		sfx(500, 0.1, "noise", 0.12, -300)
	elif fish_state == "bite" and fish_t <= 0.0:
		fish_state = ""
		bobber.visible = false
		toast("물고기가 미끼만 먹고 달아났다")

# ---- brick bats in the cave and the castle library: they flutter in a loose ring about 2.5 tiles from Sora,
# then a 0.4 s shiver ("!") and a swoop straight through where she stood (8 tiles/s for 0.5 s)
const BAT_SPOTS := [Vector2(126, 3), Vector2(122, 12), Vector2(126, 14), Vector2(105, 12), Vector2(441, 3), Vector2(447, 5)]

func spawn_bat(at: Vector2) -> void:
	var root := Node3D.new()
	var g := Node3D.new()
	root.add_child(g)
	var mats: Array = []
	brick(g, mats, Vector3(0.3, 0.26, 0.3), Vector3(0, 0, 0), Color("#4a3a5a"))
	brick(g, mats, Vector3(0.06, 0.06, 0.03), Vector3(-0.07, 0.04, 0.16), Color("#ff6a4a"), false, true)
	brick(g, mats, Vector3(0.06, 0.06, 0.03), Vector3(0.07, 0.04, 0.16), Color("#ff6a4a"), false, true)
	for side in [-1.0, 1.0]:
		var wing := Node3D.new()
		wing.name = "wl" if side < 0 else "wr"
		wing.position = Vector3(side * 0.15, 0.05, 0)
		g.add_child(wing)
		var w := box(Vector3(0.42, 0.04, 0.26), mat_color(Color("#3a2e48")))
		w.position = Vector3(side * 0.21, 0, 0)
		wing.add_child(w)
	root.scale = Vector3.ONE * 1.3
	root.set_meta("mats", mats)
	root.set_meta("body", g)
	add_child(root)
	var hp: int = 15 + player.lv * 5
	enemies.append({"x": at.x, "z": at.y, "hp": float(hp), "max_hp": hp, "node": root, "shadow": blob(0.4), "t": rnd(0, 5),
		"atk_cd": rnd(1.5, 3.0), "hurt": 0.0, "kx": 0.0, "kz": 0.0, "wx": at.x, "wz": at.y, "dead": false, "respawn": 0.0,
		"bat": true, "cave": true, "wind": 0.0, "stun": 0.0, "dash": 0.0, "dir": Vector2.ZERO, "hit_done": false})

func update_bat(e: Dictionary, dt: float, d: float, to: Vector2) -> void:
	e.t += dt
	e.atk_cd -= dt
	e.hurt -= dt
	e.stun = e.get("stun", 0.0) - dt
	var dirn: Vector2 = to / maxf(d, 0.01)
	var v := Vector2.ZERO
	if e.hurt > 0.0 or e.stun > 0.0:
		e.dash = 0.0
		e.wind = 0.0
		v = Vector2(e.kx, e.kz)
	elif e.dash > 0.0:
		e.dash -= dt
		v = e.dir * 8.0
		if not e.hit_done and d < 0.8:
			e.hit_done = true
			player_hit(int(round(rnd(6, 9) + player.lv)), Vector2(e.x, e.z), e)
	elif e.wind > 0.0:
		e.wind -= dt
		if e.wind <= 0.0:
			e.dash = 0.5
			e.dir = dirn
			e.hit_done = false
			e.atk_cd = rnd(2.0, 3.0)
	elif d < 8.0 and not intro:
		if e.atk_cd <= 0.0 and d < 4.0:
			e.wind = 0.4
			pop_num(Vector3(e.x, 2.0, e.z), "!", Color("#ff5a4a"))
		else: # a jittery ring around her
			v = dirn.rotated(PI / 2.0) * (2.5 + sin(e.t * 3.0) * 1.5) + dirn * clampf(d - 2.5, -1.0, 1.0) * 2.0
	else:
		v = Vector2(sin(e.t * 1.3), cos(e.t * 0.9)) * 1.0
	e.kx *= pow(0.002, dt)
	e.kz *= pow(0.002, dt)
	var nx: float = e.x + v.x * dt
	var nz: float = e.z + v.y * dt
	if walkable(nx, e.z): e.x = nx
	if walkable(e.x, nz): e.z = nz
	var node: Node3D = e.node
	var body: Node3D = node.get_meta("body")
	var flap := sin(e.t * (30.0 if e.wind > 0.0 else 18.0)) * 0.7
	body.get_node("wl").rotation.z = flap
	body.get_node("wr").rotation.z = -flap
	node.position = Vector3(e.x, 1.1 + sin(e.t * 4.0) * 0.12 - (0.5 if e.dash > 0.0 else 0.0), e.z)
	node.rotation.y = atan2(dirn.x, dirn.y)
	for m in node.get_meta("mats"):
		m.emission_enabled = e.hurt > 0 or e.wind > 0.0
		m.emission = Color("#ff3a2a") if e.wind > 0.0 and e.hurt <= 0 else Color.WHITE
		m.emission_energy_multiplier = 0.9
	e.shadow.position = Vector3(e.x, 0.02, e.z)

# ---- inside the village houses: Space at a door goes in. One small room (x >= HOUSE_X) is dressed for whichever
# house it is; each of the five houses has a cupboard to look in once. The last house keeps an old picture of the moonkeepers with Hangyeol.
const HOUSE_X := 480
const HOUSE_ROWS := ["#########", "#.......#", "#.......#", "#.......#", "#.......#", "#.......#", "####S####"]
const HOUSE_LOOT := [["gold", 30], ["pots", 1], ["gold", 60], ["pots", 2], ["picture", 0]] # one per house, in build order
const HOUSE_WALLS := [Color("#e4dccc"), Color("#d8c8a8"), Color("#c8d8c8"), Color("#e0c8c0"), Color("#c8c8dc")]
var in_house := -1
var house_seen := [false, false, false, false, false]
var house_wall_mat: StandardMaterial3D
var cupboard: Node3D

func house_char(x: float, z: float) -> String:
	var tx := int(round(x)) - HOUSE_X
	var tz := int(round(z))
	if tx < 0 or tz < 0 or tz >= HOUSE_ROWS.size() or tx >= HOUSE_ROWS[0].length():
		return "#"
	return HOUSE_ROWS[tz][tx]

func build_house_room() -> void:
	var floor_mat: Material = mat_color(Color("#a07a52"))
	house_wall_mat = mat_color(HOUSE_WALLS[0])
	for z in HOUSE_ROWS.size():
		for x in HOUSE_ROWS[0].length():
			var c: String = HOUSE_ROWS[z][x]
			var b: MeshInstance3D
			if c == "#":
				b = box(Vector3(1, 1.2 if z == 0 else 0.3, 1), house_wall_mat) # the back wall stands, the rest stay low
				b.position = Vector3(HOUSE_X + x, (0.6 if z == 0 else 0.15) - 0.0, z)
			else:
				b = box(Vector3(1, 0.4, 1), floor_mat)
				b.position = Vector3(HOUSE_X + x, -0.2, z)
			add_child(b)
	var wood: Material = mat_color(Color("#6a4a2e"))
	var cloth: Material = mat_color(Color("#c85a5a"))
	for part in [[Vector3(1.6, 0.4, 0.9), Vector3(HOUSE_X + 1.8, 0.2, 1.6), cloth], [Vector3(0.6, 0.2, 0.9), Vector3(HOUSE_X + 1.3, 0.5, 1.6), mat_color(Color("#f0e8d8"))],
			[Vector3(1.2, 0.6, 0.8), Vector3(HOUSE_X + 5.0, 0.3, 3.5), wood], [Vector3(0.9, 0.06, 0.9), Vector3(HOUSE_X + 5.0, 0.62, 3.5), mat_color(Color("#e8dcc0"))]]:
		var b := box(part[0], part[2])
		b.position = part[1]
		add_child(b)
	rocks.append({"x": HOUSE_X + 1.8, "z": 1.6, "r": 0.8})
	rocks.append({"x": HOUSE_X + 5.0, "z": 3.5, "r": 0.6})
	cupboard = Node3D.new()
	var cb := box(Vector3(1.0, 1.4, 0.5), wood)
	cb.position = Vector3(0, 0.7, 0)
	cupboard.add_child(cb)
	var knob := box(Vector3(0.1, 0.1, 0.06), mat_color(Color("#e8b018")))
	knob.position = Vector3(0.2, 0.8, 0.27)
	cupboard.add_child(knob)
	cupboard.position = Vector3(HOUSE_X + 6.5, 0, 1.3)
	add_child(cupboard)
	rocks.append({"x": HOUSE_X + 6.5, "z": 1.3, "r": 0.5})
	var hearth := OmniLight3D.new()
	hearth.light_color = Color("#ffc890")
	hearth.light_energy = 2.0
	hearth.omni_range = 8.0
	hearth.position = Vector3(HOUSE_X + 4.0, 2.5, 3.0)
	add_child(hearth)

func house_door_near() -> int:
	for i in village.doors.size():
		if Vector2(player.x, player.z).distance_to(village.doors[i]) < 0.9:
			return i
	return -1

func enter_house(i: int) -> void:
	in_house = i
	house_wall_mat.albedo_color = HOUSE_WALLS[i % HOUSE_WALLS.size()]
	player.x = HOUSE_X + 4.0
	player.z = 5.0
	ground_y = 0.0
	ui.zone_sub.text = tr("마을 집 %d") % (i + 1)
	var img := Image.create(HOUSE_X + 9, 7, false, Image.FORMAT_RGBA8) # a tiny map of the room for the minimap
	img.fill(Color(0, 0, 0, 0))
	for z in HOUSE_ROWS.size():
		for x in HOUSE_ROWS[0].length():
			if HOUSE_ROWS[z][x] != "#":
				img.set_pixel(HOUSE_X + x, z, Color("#6a5034"))
	ui.mini.map_tex = ImageTexture.create_from_image(img)
	snap_mates()
	save_game()

func leave_house() -> void:
	var d: Vector2 = village.doors[in_house]
	in_house = -1
	player.x = d.x
	player.z = d.y + 0.4
	ground_y = 0.0
	ui.zone_sub.text = "마을 거리"
	ui.mini.map_tex = village.map_tex(VILLAGE.VILLAGE_X + VILLAGE.W)
	snap_mates()
	save_game()

func cupboard_key() -> bool:
	if in_house < 0 or Vector2(player.x, player.z).distance_to(Vector2(cupboard.position.x, cupboard.position.z)) > 1.5:
		return false
	if house_seen[in_house]:
		toast("찬장은 비어 있다")
		return true
	house_seen[in_house] = true
	var loot: Array = HOUSE_LOOT[in_house % HOUSE_LOOT.size()]
	match loot[0]:
		"gold":
			player.gold += loot[1]
			toast(tr("찬장에서 금화 %d닢을 찾았다") % loot[1])
		"pots":
			player.pots += loot[1]
			toast(tr("찬장에서 회복약 %d개를 찾았다") % loot[1])
		"mp":
			player.mp = minf(player.max_mp, player.mp + loot[1])
			toast("찬장의 기세 사탕을 먹었다")
		"picture":
			show_story("", STORY.HOUSE_PICTURE)
	sfx(784, 0.12, "triangle", 0.25)
	save_game()
	return true

# ---- feats: six long goals listed in the journal; each gives 50 gold the moment it is reached
const FEATS := [["섬광 피하기 10번", "dodges", 10], ["섬광 막기 10번", "guards", 10], ["치명타 50번", "crits", 50],
	["괴물 100마리 물리치기", "kills", 100], ["보스 10마리 모두 물리치기", "bosses", 10], ["레벨 15", "level", 15]]
var stats := {"dodges": 0, "guards": 0, "crits": 0, "kills": 0}
var play_secs := 0.0         # time spent playing (not on the title, not in shops or talk scenes)

func play_time_text() -> String:
	var m := int(play_secs) / 60
	return tr("%d시간 %d분") % [m / 60, m % 60]
var feats_done := [false, false, false, false, false, false]
var feat_t := 0.0

func bosses_beaten() -> int:
	var king := story_step >= 5
	return int(king) + int(has_skip) + int(night_q >= 4) + int(forest_q >= 3) + int(lake_q >= 4) + int(grotto_q >= 3) \
		+ int(hill_q >= 3) + int(cloud_q >= 3) + int(castle_q >= 3) + int(garden_q >= 5)

func feat_value(key: String) -> int:
	match key:
		"bosses": return bosses_beaten()
		"level": return player.lv
	return int(stats.get(key, 0))

func check_feats() -> void:
	for i in FEATS.size():
		if not feats_done[i] and feat_value(FEATS[i][1]) >= FEATS[i][2]:
			feats_done[i] = true
			player.gold += 50
			toast(tr("도전 과제: %s (금화 +50)") % tr(FEATS[i][0]))
			sfx(784, 0.15, "triangle", 0.22)
			get_tree().create_timer(0.15).timeout.connect(func(): sfx(1046, 0.25, "triangle", 0.22))
			save_game()
			return # one at a time, so each toast is seen

# ---- Doran's three letters (after the island is home again): to Bori at the cottage, to Simji on the square,
# and to the mailbox of Mulgyeol's island hut. Bringing word back gets 150 gold and max HP +10.
var mail_q := 0             # 0 not asked, 1 carrying letters, 2 done
var mail_got := [false, false, false] # Bori, Simji, the island hut

func mail_errand() -> bool:
	if mail_q == 0:
		mail_q = 1
		show_story("", STORY.MAIL_ASK)
		save_game()
		return true
	if mail_q == 1 and mail_got.count(true) == 3:
		mail_q = 2
		player.gold += 150
		player.max_hp += 10
		player.hp = float(player.max_hp)
		show_story("", STORY.MAIL_DONE)
		save_game()
		return true
	if mail_q == 1:
		show_story("", STORY.FOLK_AGAIN.doran_mail)
		return true
	return false

func deliver(i: int, lines: Array) -> bool:
	if mail_q != 1 or mail_got[i]:
		return false
	mail_got[i] = true
	show_story("", lines)
	sfx(660, 0.15, "triangle", 0.2)
	if mail_got.count(true) == 3:
		toast("편지를 모두 전했다. 도란에게 알리자")
	save_game()
	return true

# ---- the lantern festival: once Simji has his letter, on full-moon nights (moon at least 95% full) sky lanterns
# drift up over the village; Simji hands out festival rice cakes once (three potions)
var fest_gift := false
var fest_seen := false
var fest_t := 0.0

func festival_now() -> bool:
	return mail_got[1] and in_village and in_house < 0 and is_night() and moon_phase().x >= 0.95

func update_festival(dt: float) -> void:
	if not festival_now() or story_open:
		return
	if not fest_seen:
		fest_seen = true
		toast("보름달 아래 등불 축제가 열렸다")
	fest_t -= dt
	if fest_t > 0.0:
		return
	fest_t = 0.5
	var at := Vector3(VILLAGE.VILLAGE_X + rnd(3, 29), rnd(0.5, 1.5), rnd(3, 21))
	var lamp := box(Vector3(0.24, 0.32, 0.24), glow_mat(Color("#ff9a3a"), 0.7)) # low glow keeps the orange under bloom
	lamp.position = at
	add_fx(lamp, 9.0, func(n: Node3D, k: float, d: float):
		n.position.y += d * 0.7
		n.position.x += sin(k * 9.0) * d * 0.2
		n.scale = Vector3.ONE * (1.0 - k * 0.6))

func festival_key() -> bool:
	if not festival_now() or Vector2(player.x, player.z).distance_to(village.marks.M) > 1.8:
		return false
	if fest_gift:
		show_story("", STORY.FEST_AGAIN)
		return true
	fest_gift = true
	player.pots += 3
	show_story("", STORY.FESTIVAL)
	save_game()
	return true

# ---- a new round (새 바퀴) after the ending: E twice at the garden's heart starts the story over, keeping level,
# attack, max HP, gold, potions, keepsakes, the woken skill, feats and records. Monsters then take
# 1/(1 + 0.5 x round) of the damage and deal (1 + 0.5 x round) times as much.
const NG_KEEP := ["lv", "xp", "max_hp", "atk", "gold", "pots", "has_pearl", "has_feather", "has_acorn", "has_ring", "has_shoes",
	"has_armour", "has_tea", "has_shard", "has_bookmark", "skill_up", "stats", "feats", "trial_best", "race_best", "fish"]
var ng := 0                 # how many rounds were finished before this one
var ng_armed := 0.0         # seconds left to confirm with a second E

func ng_mult() -> float:
	return 1.0 + 0.5 * ng

func ng_key() -> bool:
	if not in_garden or garden_q < 5 or Vector2(player.x, player.z).distance_to(garden.marks.C) > 3.0:
		return false
	if ng_armed <= 0.0:
		ng_armed = 10.0
		show_story("", STORY.NEW_ROUND_ASK)
		return true
	new_round()
	return true

func new_round() -> void:
	write_new_round()
	get_tree().reload_current_scene()

# the save a new round starts from: only what carries over, story back to 0
func write_new_round() -> void:
	save_game()
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	var keep := {"ng": ng + 1, "story": 0}
	for k in NG_KEEP:
		if d.has(k):
			keep[k] = d[k]
	keep["hp"] = keep.get("max_hp", 100)
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(keep))
	f.close()

# ---- moon waystones: a standing stone in each hub. E at one opens a list of the stones already reached;
# a number key (1 - 6) travels there. Esc or E closes the list.
const WAY_NAMES := ["늪 오두막", "마을 광장", "남쪽 호수 부두", "굳은 숲 입구", "바람 언덕", "달지기 성 문"]
var way_open := false
var way_nodes: Array = []

func way_spot(i: int) -> Vector2:
	match i:
		0: return Vector2(shop_pos.x + 2.5, shop_pos.z + 1.5)
		1: return village.marks.M + Vector2(3.0, -2.5)
		2: return lake.marks.P + Vector2(4.0, -1.5)
		3: return forest.marks.S + Vector2(2.5, -1.5)
		4: return hill.marks.S + Vector2(2.0, -1.5)
		5: return castle.marks.S + Vector2(2.5, 1.5)
	return Vector2.ZERO

func way_known(i: int) -> bool:
	match i:
		0: return story_step >= 3
		1: return story_step >= 8
		2: return lake_q >= 1
		3: return forest_q >= 1
		4: return hill_q >= 1
		5: return castle_q >= 1
	return false

func build_ways() -> void:
	var stone: Material = mat_color(Color("#8a8a94"))
	var moon: Material = glow_mat(Color("#bcd6ff"), 0.9)
	for i in WAY_NAMES.size():
		var at := way_spot(i)
		var g := Node3D.new()
		var b := box(Vector3(0.5, 1.2, 0.4), stone)
		b.position = Vector3(0, 0.6, 0)
		g.add_child(b)
		var m := box(Vector3(0.3, 0.3, 0.06), moon)
		m.position = Vector3(0, 0.9, 0.22)
		g.add_child(m)
		g.position = Vector3(at.x, height_at(at.x, at.y), at.y)
		add_child(g)
		way_nodes.append(g)
		rocks.append({"x": at.x, "z": at.y, "r": 0.35})

func way_near() -> int:
	for i in WAY_NAMES.size():
		if Vector2(player.x, player.z).distance_to(way_spot(i)) < 1.4:
			return i
	return -1

func way_key() -> bool:
	if way_open:
		toggle_ways(false)
		return true
	if way_near() < 0:
		return false
	toggle_ways(true)
	return true

func toggle_ways(show: bool) -> void:
	way_open = show
	ui.ways.visible = show
	if show:
		var lines: Array = [tr("달빛 길돌: 숫자 키로 건너가기 (Esc 닫기)"), ""]
		for i in WAY_NAMES.size():
			lines.append("%d   %s" % [i + 1, tr(WAY_NAMES[i]) if way_known(i) else "? ? ?"])
		ui.ways_text.text = "\n".join(lines)

func travel(i: int) -> void:
	toggle_ways(false)
	if not way_known(i) or way_near() == i:
		return
	sfx(988, 0.4, "sine", 0.2, -300)
	fade_then(func():
		gust_dir = Vector2.ZERO
		if lake_q == 3: # left the turtle fight: it starts over from the pier
			lake_q = 2
			if lake_npc != null:
				lake_npc.visible = true
		in_cave = false
		in_village = false
		in_forest = false
		in_lake = false
		in_hill = false
		in_garden = false
		in_house = -1
		match i:
			0:
				if ui.has("outside_map"):
					ui.mini.map_tex = ui.outside_map
				ui.zone_name.text = "갈대늪"
				ui.zone_sub.text = "보리 할머니의 오두막"
			1:
				var e0 := errand
				errand = maxi(errand, 1) # no arrival scene again
				enter_village()
				errand = e0
			2: enter_lake()
			3: enter_forest()
			4: enter_hill()
			5: enter_castle()
		var to := way_spot(i) + Vector2(0, 1.2)
		player.x = to.x
		player.z = to.y
		ground_y = height_at(to.x, to.y)
		snap_mates()
		save_game())

const CHANGES := [
	"2026-10-23 낮",
	"· 설정 창을 더했다 (Esc 또는 왼쪽 아래 설정 단추).",
	"· 밤이 여름처럼 짧아졌다: 21시에 어두워지고 4시면 밝아온다.",
	"· 밤에 소라가 너무 어둡던 것을 고쳤다. 등불 곁에서는 환해진다.",
	"· 보리 할머니도 E로 말을 건다. 5시 방향 걸음과 동료들의 방향을 바로잡았다.",
	"· 물빛 동굴이 밝아지고, 나가는 계단과 내려가는 계단이 잘 보인다.",
	"",
	"2026-10-23 밤",
	"· 새 지역: 섬 밑 물빛 동굴, 언덕 위 구름 둔덕, 가라앉은 달지기 성.",
	"· 새 보스: 벽돌 게, 벽돌 허수아비, 벽돌 기사. 새 괴물: 벽돌 늑대, 벽돌 박쥐.",
	"· 곁이야기: 지도 조각, 반딧불 병, 달 순서 돌, 다람쥐, 울림 수정, 바람개비 경주, 낚시, 달꽃, 집 안, 도란의 편지, 등불 축제, 서재의 책.",
	"· 달빛 시련, 세 돌단, 일지(Q), 달빛 길돌, 도전 과제, 새 바퀴.",
]

# ---- settings (modelled on Space Oddity's 설정): opened by the 설정 button or Esc, the world waits while it is open.
# Head: sound on/off and text size 가- / 가+. Tabs: 설정 (comfort and display), 도움말 (controls), 바뀐 것, 만든 이.
# Saved apart from the game in user://settings.json, so F9 (start over) keeps them.
const SETTINGS_PATH := "user://settings.json"
const TEXT_SIZES := [0.85, 1.0, 1.15, 1.3]
var cfg := {"text": 1, "shake": true, "tilt": true, "nums": true}
var settings_open := false
var set_tab := 0
var tilt_rect: ColorRect
var text_bases: Array = [] # [Label, base size] scaled by the text size setting

# ---- the look shared by the menus, taken from Space Oddity's style.css (the user asked for its menus):
# navy glass buttons with a thin pale line that brighten under the mouse, gold for what is chosen,
# dialogs in #091627 with a #53718b line, 14 px corners and a deep shadow. Icons are its line drawings.
const MENU_GOLD := Color("#f6b951")
const ODD_INK := Color("#e3efff")
const ODD_MUTED := Color("#b6cbe0")
const ICON_SVG := {
	"help": '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#eef3ff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path stroke-width="2.4" d="M8.5 9a3.5 3.5 0 1 1 5.3 3c-1.1.7-1.8 1.4-1.8 2.8"/><circle cx="12" cy="18.6" r="0.6" stroke-width="1.6"/></svg>',
	"journal": '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#eef3ff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 4h11a1.5 1.5 0 0 1 1.5 1.5V20H7a2 2 0 0 1 0-4h11.5"/><path d="M5 18V6a2 2 0 0 1 2-2"/><path d="M13 4v6l-1.8-1.3L9.4 10V4"/></svg>',
	"gear": '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#eef3ff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="5.6"/><circle cx="12" cy="12" r="1.9"/><path d="M12 3.2v3.2M12 17.6v3.2M3.2 12h3.2M17.6 12h3.2M5.8 5.8L8 8M16 16l2.2 2.2M5.8 18.2L8 16M16 8l2.2-2.2"/></svg>',
	"sound": '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#eef3ff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 9.5h3l4.5-3.8v12.6L7 14.5H4z"/><path d="M15 9.2a4 4 0 0 1 0 5.6"/><path d="M17.6 6.6a7.6 7.6 0 0 1 0 10.8"/></svg>',
	"mute": '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#eef3ff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 9.5h3l4.5-3.8v12.6L7 14.5H4z"/><path d="M15.5 9.5l5 5M20.5 9.5l-5 5"/></svg>',
	"back": '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#eef3ff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14.5 5.5L8 12l6.5 6.5"/></svg>',
}
var menu_theme: Theme
var icon_cache := {}

func flat(bg: Color, rim: Color, rim_w := 1, radius := 8, pad := 6.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = rim
	sb.set_border_width_all(rim_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad + 6
	sb.content_margin_right = pad + 6
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	sb.anti_aliasing = true
	return sb

func glass_normal() -> StyleBoxFlat:
	return flat(Color("#0d1a3acc"), Color("#9fb4ff66"))

func glass_hover() -> StyleBoxFlat:
	return flat(Color("#26456199"), Color("#93d2ff88"))

func glass_chosen() -> StyleBoxFlat:
	return flat(Color("#0d1a3acc"), MENU_GOLD)

func get_menu_theme() -> Theme:
	if menu_theme != null:
		return menu_theme
	menu_theme = Theme.new()
	menu_theme.set_stylebox("normal", "Button", glass_normal())
	menu_theme.set_stylebox("hover", "Button", glass_hover())
	menu_theme.set_stylebox("pressed", "Button", glass_hover())
	menu_theme.set_stylebox("disabled", "Button", flat(Color("#0d1a3a73"), Color("#9fb4ff2a")))
	menu_theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	menu_theme.set_color("font_color", "Button", ODD_INK)
	menu_theme.set_color("font_hover_color", "Button", Color.WHITE)
	menu_theme.set_color("font_pressed_color", "Button", Color.WHITE)
	menu_theme.set_color("font_disabled_color", "Button", Color(0.89, 0.94, 1.0, 0.45))
	menu_theme.set_font("font", "Button", ui_font)
	menu_theme.set_font_size("font_size", "Button", 13)
	return menu_theme

func odd_icon(kind: String) -> ImageTexture:
	if icon_cache.has(kind):
		return icon_cache[kind]
	var img := Image.new()
	img.load_svg_from_string(ICON_SVG[kind], 2.0) # 48 px, drawn at 22 - 24 px on screen like Space Oddity's
	var tex := ImageTexture.create_from_image(img)
	icon_cache[kind] = tex
	return tex

func menu_panel(root: Control, pos: Vector2, size: Vector2, anchor: int) -> Panel:
	var p := panel(root, pos, size, anchor)
	var sb := flat(Color("#091627"), Color("#53718b"), 1, 14, 0.0)
	sb.shadow_color = Color(0, 0, 0, 0.53)
	sb.shadow_size = 24
	sb.shadow_offset = Vector2(0, 12)
	p.add_theme_stylebox_override("panel", sb)
	p.theme = get_menu_theme()
	return p

# a thin pale rule
func menu_rule(parent: Control, pos: Vector2, width: float) -> void:
	var r := ColorRect.new()
	r.color = Color("#9fb4ff33")
	r.position = pos
	r.size = Vector2(width, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)

func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
	if typeof(d) != TYPE_DICTIONARY:
		return
	for k in cfg:
		if d.has(k):
			cfg[k] = d[k]
	cfg.text = clampi(int(cfg.text), 0, TEXT_SIZES.size() - 1)
	muted = bool(d.get("muted", muted))

func save_settings() -> void:
	var d := cfg.duplicate()
	d["muted"] = muted
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))

func apply_settings() -> void:
	if tilt_rect != null:
		tilt_rect.visible = bool(cfg.tilt)
	var k: float = TEXT_SIZES[int(cfg.text)]
	for tb in text_bases:
		var c: Control = tb[0]
		c.add_theme_font_size_override("normal_font_size" if c is RichTextLabel else "font_size", int(round(tb[1] * k)))
	refresh_sound_btn()
	if ui.has("set_rows"):
		for key in ui.set_rows:
			var b: Button = ui.set_rows[key]
			var on: bool = (not muted) if key == "sound" else bool(cfg[key])
			b.text = tr("켜짐") if on else tr("꺼짐")
			# Space Oddity: a pressed button gets a gold rim and gold text
			b.add_theme_stylebox_override("normal", glass_chosen() if on else glass_normal())
			b.add_theme_color_override("font_color", MENU_GOLD if on else ODD_INK)
		ui.set_minus.disabled = int(cfg.text) <= 0
		ui.set_plus.disabled = int(cfg.text) >= TEXT_SIZES.size() - 1

func scale_text(l: Control) -> void:
	text_bases.append([l, l.get_theme_font_size("normal_font_size" if l is RichTextLabel else "font_size")])

func set_button(parent: Control, text: String, pos: Vector2, size: Vector2, fn: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", ui_font)
	b.add_theme_font_size_override("font_size", 13)
	b.position = pos
	b.size = size
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(fn)
	parent.add_child(b)
	return b

# Space Oddity's settings sheet: the whole screen in #0d1a3a, a back arrow 8 px from the corner, and a column at most
# 640 px wide: the head (title at left, sound and 가- 가+ at right), four equal tabs, the page as label rows with the
# description beside and a small button under it, and the way back at the foot
func build_settings(root: Control) -> void:
	var sp := Panel.new()
	sp.set_anchors_preset(Control.PRESET_FULL_RECT)
	sp.add_theme_stylebox_override("panel", flat(Color("#0d1a3a"), Color(0, 0, 0, 0), 0, 0))
	sp.theme = get_menu_theme()
	sp.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(sp)
	var back := Button.new()
	back.icon = odd_icon("back")
	back.expand_icon = true
	back.focus_mode = Control.FOCUS_NONE
	back.position = Vector2(8, 8)
	back.size = Vector2(44, 44)
	back.pressed.connect(func(): toggle_settings(false))
	sp.add_child(back)
	var col := Control.new() # the 640 px column, centred
	col.set_anchors_preset(Control.PRESET_CENTER_TOP)
	col.offset_left = -320
	col.offset_right = 320
	col.offset_top = 54
	col.offset_bottom = 54 + 560
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sp.add_child(col)
	var h1 := label(col, "설정", Vector2(0, 2), 24, ODD_INK)
	h1.size = Vector2(300, 40)
	ui.set_sound = Button.new()
	ui.set_sound.icon = odd_icon("sound")
	ui.set_sound.expand_icon = true
	ui.set_sound.focus_mode = Control.FOCUS_NONE
	ui.set_sound.tooltip_text = tr("효과음") + " (M)"
	ui.set_sound.position = Vector2(640 - 44 * 3 - 16, 0)
	ui.set_sound.size = Vector2(44, 40)
	ui.set_sound.pressed.connect(func(): toggle_sound(); apply_settings())
	col.add_child(ui.set_sound)
	ui.set_minus = set_button(col, "가−", Vector2(640 - 44 * 2 - 8, 0), Vector2(44, 40), func(): cfg.text = maxi(0, int(cfg.text) - 1); save_settings(); apply_settings())
	ui.set_plus = set_button(col, "가+", Vector2(640 - 44, 0), Vector2(44, 40), func(): cfg.text = mini(TEXT_SIZES.size() - 1, int(cfg.text) + 1); save_settings(); apply_settings())
	var tabs := ["설정", "도움말", "바뀐 것", "만든 이"]
	ui.set_tabs = []
	ui.set_pages = []
	var tw := (640.0 - 8 * 3) / 4.0
	for i in tabs.size():
		var tb := set_button(col, tabs[i], Vector2(i * (tw + 8), 54), Vector2(tw, 38), func(): show_set_tab(i))
		ui.set_tabs.append(tb)
		var page := Control.new()
		page.position = Vector2(0, 106)
		page.size = Vector2(640, 400)
		page.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(page)
		ui.set_pages.append(page)
	# 설정: rows of label (90 px) and description with a small button under it
	ui.set_rows = {}
	var rows := [["shake", "화면 흔들림", "벨 때와 보스가 내려찍을 때 화면이 흔들린다. 어지러우면 끄세요."],
		["tilt", "미니어처 흐림", "화면 위아래를 흐리게 하고 색을 입혀 작은 정원처럼 보이게 한다. 흐린 게 불편하면 끄세요."],
		["nums", "피해 숫자", "때리고 맞을 때 숫자를 띄운다. 공격 직전의 \"!\" 표시는 늘 보인다."],
		["sound", "효과음", "위의 스피커 단추, M 키, 화면 왼쪽 아래 단추로도 켜고 끈다."]]
	for i in rows.size():
		var r: Array = rows[i]
		var y := i * 92
		var t := label(ui.set_pages[0], r[1], Vector2(0, y), 13, Color("#eef3ff"))
		t.add_theme_font_override("font", ui_font)
		t.size = Vector2(90, 20)
		var dsc := label(ui.set_pages[0], r[2], Vector2(106, y), 13, ODD_MUTED)
		dsc.size = Vector2(534, 36)
		dsc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		scale_text(dsc)
		var key: String = r[0]
		ui.set_rows[key] = set_button(ui.set_pages[0], "켜짐", Vector2(106, y + 42), Vector2(74, 34), func():
			if key == "sound":
				toggle_sound()
			else:
				cfg[key] = not bool(cfg[key])
			save_settings()
			apply_settings())
	var lt := label(ui.set_pages[0], "언어", Vector2(0, 4 * 92), 13, Color("#eef3ff"))
	lt.size = Vector2(90, 20)
	var lang := label(ui.set_pages[0], "한국어. 영어, 일본어, 중국어는 번역 표만 준비되어 있다.", Vector2(106, 4 * 92), 13, ODD_MUTED)
	lang.size = Vector2(534, 20)
	# 도움말
	var help_rows := [["이동", "WASD, 방향키. Shift로 달린다 (물수제비 걸음을 얻으면 물 위도)"], ["싸움", "J 또는 왼쪽 클릭 베기, K 또는 오른쪽 클릭 구르기, L 막기"],
		["기술", "U I O 또는 1 2 3, 회복약은 4"], ["왕관", "E: 말 걸기, 등불, 벽돌 풀기, 길돌, 낚시"], ["열기", "Space: 상자, 집. Q 일지, H 조작법, M 소리, T 3시간 보내기"],
		["화면", "Z X 또는 휠로 확대·축소. F8 처음 자리로, F9 처음부터. Esc 이 창"], ["요령", "맞기 직전에 구르면 섬광 피하기, 막으면 섬광 막기. 괴물은 때리기 전에 빨갛게 부풀고 \"!\"가 뜬다"]]
	for i in help_rows.size():
		var ht := label(ui.set_pages[1], help_rows[i][0], Vector2(0, i * 48), 13, Color("#eef3ff"))
		ht.size = Vector2(90, 20)
		var hd := label(ui.set_pages[1], help_rows[i][1], Vector2(106, i * 48), 13, ODD_MUTED)
		hd.size = Vector2(534, 40)
		hd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		scale_text(hd)
	# 바뀐 것
	var news := label(ui.set_pages[2], "\n".join(CHANGES), Vector2(0, 0), 13, ODD_MUTED)
	news.size = Vector2(640, 400)
	news.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scale_text(news)
	# 만든 이
	var about_rows := [["만든 사람", "destory1984 (기획, 그림 주문), Claude (코드)"], ["그림", "GPT 이미지 생성. 소라의 쉬는 몸짓과 이 창의 모양은 같은 작가의 우주 한량에서 가져왔다"],
		["글꼴", "Pretendard (SIL 오픈 폰트 라이선스 1.1)"], ["라이선스", "코드는 MIT. 소라 캐릭터와 제목 그림은 destory1984의 것이다"]]
	for i in about_rows.size():
		var at := label(ui.set_pages[3], about_rows[i][0], Vector2(0, i * 48), 13, Color("#eef3ff"))
		at.size = Vector2(90, 20)
		var ad := label(ui.set_pages[3], about_rows[i][1], Vector2(106, i * 48), 13, ODD_MUTED)
		ad.size = Vector2(534, 40)
		ad.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		scale_text(ad)
	var ct := label(ui.set_pages[3], "만든 코드", Vector2(0, 4 * 48), 13, Color("#eef3ff"))
	ct.size = Vector2(90, 20)
	set_button(ui.set_pages[3], "깃허브에서 보기", Vector2(106, 4 * 48 - 6), Vector2(150, 36), func(): OS.shell_open("https://github.com/destory1984/oddity-of-the-wilds"))
	set_button(col, "놀이로 돌아가기", Vector2(0, 514), Vector2(640, 42), func(): toggle_settings(false))
	sp.visible = false
	ui.settings = sp
	show_set_tab(0)

func show_set_tab(i: int) -> void:
	set_tab = i
	for k in ui.set_pages.size():
		ui.set_pages[k].visible = k == i
		var tb: Button = ui.set_tabs[k]
		tb.add_theme_color_override("font_color", MENU_GOLD if k == i else ODD_INK) # aria-selected: gold rim, gold text
		tb.add_theme_stylebox_override("normal", glass_chosen() if k == i else glass_normal())

func toggle_settings(show: bool) -> void:
	settings_open = show
	ui.settings.visible = show
	if show:
		ui.help.visible = false
		ui.journal.visible = false
		show_set_tab(0)
		apply_settings()

# ---- companions talk now and then: when Sora has stood still about 9 s with no monster within 8 tiles,
# Mulgyeol or Noeul says a short line in a speech balloon (one fitting the place or the night when there is one);
# sometimes the other answers. 14 - 24 s between lines.
var chat_t := 0.0
var chat_cd := 6.0

# a speech balloon: a cream rounded card with a brown rim and a little tail pointing down at the speaker,
# drawn once per width and kept
var balloon_cache := {}

func balloon_tex(w: int) -> ImageTexture:
	if balloon_cache.has(w):
		return balloon_cache[w]
	var h := 52
	var tail := 14
	var img := Image.create(w, h + tail, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rim := Color("#5a3a22")
	var fill := Color("#fff8e8")
	var r := 16
	for y in h:
		for x in w:
			var cx := clampi(x, r, w - 1 - r)
			var cy := clampi(y, r, h - 1 - r)
			var d := Vector2(x - cx, y - cy).length()
			if d <= r:
				img.set_pixel(x, y, rim if d > r - 3 else fill)
	for k in tail: # the tail: a small triangle under the middle
		var half := int((tail - k) * 0.8)
		for x in range(w / 2 - half, w / 2 + half + 1):
			var edge := x <= w / 2 - half + 2 or x >= w / 2 + half - 2 or k == tail - 1
			img.set_pixel(x, h - 3 + k, rim if edge else fill)
	var tex := ImageTexture.create_from_image(img)
	balloon_cache[w] = tex
	return tex

func say_bubble(who: Node3D, text: String, dur := 3.5) -> void:
	var b := Node3D.new()
	var w := 40 + text.length() * 26
	w = int(ceil(w / 16.0)) * 16 # a few widths only, so the cache stays small
	var card := Sprite3D.new()
	card.texture = balloon_tex(w)
	card.pixel_size = 0.0065
	card.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	card.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	card.no_depth_test = true
	card.shaded = false
	card.render_priority = 1
	card.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	b.add_child(card)
	var l := Label3D.new()
	l.text = text
	l.font = ui_font
	l.font_size = 30
	l.pixel_size = 0.0065
	l.modulate = Color("#3a2414")
	l.outline_size = 0
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 2
	l.position = Vector3(0, 0.045, 0) # centred on the card, above the tail
	b.add_child(l)
	b.position = Vector3(0, 2.45, 0)
	b.scale = Vector3.ONE * 0.2
	who.add_child(b)
	var tw := b.create_tween() # pops up, then fades away
	tw.tween_property(b, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(dur)
	tw.tween_property(card, "modulate:a", 0.0, 0.3)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.3)
	tw.tween_callback(b.queue_free)

func chat_lines(id: String) -> Array:
	var lines: Array = STORY.MATE_CHAT[id].duplicate()
	var place := ""
	if in_lake: place = "lake"
	elif in_village: place = "village"
	elif in_castle(): place = "castle"
	elif in_cloud(): place = "cloud"
	elif in_hill: place = "hill"
	elif in_forest: place = "forest"
	elif in_marsh(): place = "marsh"
	var key := id + "_" + place
	if STORY.MATE_CHAT.has(key):
		lines.append_array(STORY.MATE_CHAT[key])
		lines.append_array(STORY.MATE_CHAT[key]) # a place line is twice as likely
	if is_night() and STORY.MATE_CHAT.has(id + "_night"):
		lines.append_array(STORY.MATE_CHAT[id + "_night"])
	return lines

func update_chat(dt: float) -> void:
	chat_cd -= dt
	var still: bool = Vector2(player.vx, player.vz).length() < 0.3 and not story_open and not intro and in_house < 0
	chat_t = chat_t + dt if still else 0.0
	if chat_t < 9.0 or chat_cd > 0.0:
		return
	if enemies.any(func(e): return not e.dead and not e.get("prop", false) and Vector2(e.x - player.x, e.z - player.z).length() < 8.0):
		return
	var who: Array = []
	if mate != null and mate.visible: who.append(["mulgyeol", mate])
	if mate2 != null and mate2.visible: who.append(["noeul", mate2])
	if who.is_empty():
		return
	chat_cd = rnd(14.0, 24.0)
	if who.size() == 2 and rng.randf() < 0.3: # the two of them trade a line
		var pair: Array = STORY.MATE_BANTER[rng.randi() % STORY.MATE_BANTER.size()]
		var first: Node3D = mate if pair[0] == "mulgyeol" else mate2
		var second: Node3D = mate2 if pair[0] == "mulgyeol" else mate
		say_bubble(first, tr(pair[1]))
		get_tree().create_timer(2.2).timeout.connect(func(): if is_instance_valid(second): say_bubble(second, tr(pair[2])))
		return
	var pick: Array = who[rng.randi() % who.size()]
	var lines := chat_lines(pick[0])
	say_bubble(pick[1], tr(lines[rng.randi() % lines.size()]))

# the signpost by the east bridge: the only way from the marsh to the village
# Built after the map, props, plants and monsters so the random draws that place them are the same as before.
func village_sign() -> void:
	# a short deck over the east edge water to the village road
	for bx in [46, 47]:
		for bz in [20, 21]:
			map[idx(bx, bz)] = BRIDGE
			hgt[idx(bx, bz)] = 0.08
	lego_deck(46, 46, 20)
	var g := Node3D.new()
	var wood: Material = mat_color(Color("#6a4a2e"))
	var pole: MeshInstance3D = box(Vector3(0.14, 1.5, 0.14), wood)
	pole.position = Vector3(0, 0.75, 0)
	g.add_child(pole)
	var board: MeshInstance3D = box(Vector3(1.9, 0.42, 0.08), mat_color(Color("#c8a46a")))
	board.position = Vector3(0, 1.3, 0.08)
	g.add_child(board)
	var t := Label3D.new()
	t.text = tr("등불 마을 →")
	t.font = ui_font
	t.font_size = 36
	t.pixel_size = 0.006
	t.modulate = Color("#3a2414")
	t.outline_size = 0
	t.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	t.position = Vector3(0, 1.3, 0.14)
	g.add_child(t)
	var glow := box(Vector3(0.2, 0.26, 0.2), glow_mat(Color("#ffc46a"), 1.6))
	glow.position = Vector3(0, 1.62, 0)
	g.add_child(glow)
	g.position = Vector3(43.6, height_at(43.6, 18.6), 18.6)
	add_child(g)
	rocks.append({"x": 43.6, "z": 18.6, "r": 0.25})

# 3. companions' status under Sora's bars: portrait, name and a bar that fills as their next blow comes ready
func build_mate_hud(root: Control) -> void:
	ui.mate_rows = []
	for i in 2:
		var row := Control.new()
		row.position = Vector2(140, 150 + i * 34)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(row)
		var face := TextureRect.new()
		face.texture = load("res://art/portrait/%s.png" % ["mulgyeol", "jae"][i])
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		face.size = Vector2(28, 28)
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(face)
		label(row, ["물결", "노을"][i], Vector2(34, 0), 13, Color("#f6d27a"))
		var back := ColorRect.new()
		back.color = Color(0.1, 0.1, 0.15, 0.8)
		back.position = Vector2(34, 19)
		back.size = Vector2(110, 6)
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(back)
		var fill := ColorRect.new()
		fill.color = Color("#7ac8ff") if i == 0 else Color("#c8c8d0")
		fill.position = Vector2(34, 19)
		fill.size = Vector2(110, 6)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(fill)
		var act := label(row, "", Vector2(82, 1), 11, Color("#c9bfa6"))
		act.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		row.visible = false
		ui.mate_rows.append({"row": row, "fill": fill, "act": act})

func update_mate_hud() -> void:
	var data := [[mate, mate_cd, 1.0], [mate2, mate2_cd, 1.4]]
	for i in 2:
		var r: Dictionary = ui.mate_rows[i]
		var node: Node3D = data[i][0]
		r.row.visible = node != null and not intro and not in_cave
		if not r.row.visible:
			continue
		var id: String = ["mulgyeol", "noeul"][i]
		var frac: float = clampf(mate_health(id) / mate_max(), 0.0, 1.0)
		r.fill.size.x = 110.0 * frac
		r.fill.color = Color("#e05a4a") if frac < 0.3 else Color("#6ad07a")
		var fighting: bool = enemies.any(func(e): return not e.dead and not e.get("prop", false) and Vector2(e.x - node.position.x, e.z - node.position.z).length() < 5.0)
		if mate_down[id] > 0.0:
			r.act.text = tr("쉬는 중 %d초") % int(ceil(mate_down[id]))
		else:
			r.act.text = tr("싸우는 중") if fighting else tr("따라가는 중")

# ---- the bottom-left buttons: Space Oddity's 44 px glass squares with its line icons; the key is in the tooltip
func icon_button(root: Control, kind: String, key: String, tip: String, x: float, fn: Callable) -> Button:
	var b := Button.new()
	b.icon = odd_icon(kind)
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.tooltip_text = tr(tip) + " (" + key + ")"
	b.focus_mode = Control.FOCUS_NONE
	b.theme = get_menu_theme()
	for st in ["normal", "hover", "pressed"]:
		var sb: StyleBoxFlat = glass_hover() if st != "normal" else glass_normal()
		sb.content_margin_left = 11
		sb.content_margin_right = 11
		sb.content_margin_top = 11
		sb.content_margin_bottom = 11
		b.add_theme_stylebox_override(st, sb)
	place(b, Control.PRESET_BOTTOM_LEFT, Vector2(x, -58), Vector2(44, 44))
	b.pressed.connect(fn)
	root.add_child(b)
	return b

func spawn_boss() -> void:
	var spot := Vector2(16, 4)
	for tries in 40:
		if walkable(spot.x, spot.y):
			break
		spot = Vector2(rnd(6, 20), rnd(3, 6))
	var node := make_monster(true)
	add_child(node)
	var hp := 950
	enemies.append({"x": spot.x, "z": spot.y, "hp": float(hp), "max_hp": hp, "node": node, "shadow": blob(2.4), "t": 0.0,
		"atk_cd": 2.0, "hurt": 0.0, "kx": 0.0, "kz": 0.0, "wx": spot.x, "wz": spot.y, "dead": false, "respawn": 0.0,
		"boss": true, "home": spot, "stomp": 0.0, "swing": 0.0, "stun": 0.0, "phase": 1, "roar": 0.0, "wave_r": -1.0, "face": Vector2(0, 1)})

func build_chests() -> void:
	var tex := make_tex(16, 14, func(img: Image):
		px(img, 1, 3, 14, 11, Color("#7a4a24"))
		px(img, 1, 3, 14, 4, Color("#9a6232"))
		px(img, 1, 7, 14, 1, Color("#3a2312"))
		px(img, 0, 3, 1, 11, Color("#d9b04a"))
		px(img, 15, 3, 1, 11, Color("#d9b04a"))
		px(img, 7, 6, 2, 3, Color("#ffd84a")))
	for p in [Vector2(17, 21), Vector2(24, 39), Vector2(40, 8), Vector2(7, 40), Vector2(42, 30)]:
		if not walkable(p.x, p.y):
			continue
		var s := Sprite3D.new()
		s.texture = tex
		s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		s.scale = Vector3(1, 1.0 / cos(0.78), 1)
		s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		s.shaded = false
		s.pixel_size = 0.05
		s.offset = Vector2(0, 7)
		s.position = Vector3(p.x, height_at(p.x, p.y), p.y)
		add_child(s)
		blob(0.8).position = Vector3(p.x, height_at(p.x, p.y) + 0.02, p.y)
		chests.append({"x": p.x, "z": p.y, "node": s, "open": false})

# ---------------------------------------------------------------- particles
func build_particles() -> void:
	motes = CPUParticles3D.new()
	motes.amount = 60
	motes.lifetime = 6.0
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	motes.emission_box_extents = Vector3(14, 1, 14)
	motes.gravity = Vector3(0, 0.05, 0)
	motes.initial_velocity_min = 0.1
	motes.initial_velocity_max = 0.3
	motes.direction = Vector3(0, 1, 0)
	motes.spread = 180.0
	var q := QuadMesh.new()
	q.size = Vector2(0.11, 0.11)
	q.material = glow_mat(Color("#fff0a8"), 6.0)
	q.material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	motes.mesh = q
	add_child(motes)

	rain = CPUParticles3D.new()
	rain.amount = 1200
	rain.lifetime = 0.6
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(14, 0.5, 14)
	rain.gravity = Vector3(0, -30, 0)
	rain.direction = Vector3(0, -1, 0)
	rain.initial_velocity_min = 8.0
	rain.initial_velocity_max = 10.0
	var rq := BoxMesh.new()
	rq.size = Vector3(0.02, 0.45, 0.02)
	rq.material = mat_color(Color(0.72, 0.8, 0.88, 0.5))
	rq.material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rain.mesh = rq
	rain.emitting = false
	add_child(rain)

func burst(pos: Vector3, color: Color, n := 14, spd := 3.0) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = n
	p.lifetime = 0.6
	p.direction = Vector3(0, 1, 0)
	p.spread = 80.0
	p.initial_velocity_min = spd * 0.5
	p.initial_velocity_max = spd * 1.5
	p.gravity = Vector3(0, -9, 0)
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.12)
	q.material = glow_mat(color, 2.5)
	q.material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	p.mesh = q
	p.position = pos
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)

func add_fx(node: Node3D, life: float, update: Callable) -> void:
	add_child(node)
	fx.append({"node": node, "life": life, "t": 0.0, "update": update})

func ring_mesh(r0: float, r1: float, a0: float, arc: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 24
	for i in seg:
		var a := a0 + arc * i / seg
		var b := a0 + arc * (i + 1) / seg
		var p := [Vector3(cos(a) * r0, 0, sin(a) * r0), Vector3(cos(a) * r1, 0, sin(a) * r1), Vector3(cos(b) * r1, 0, sin(b) * r1), Vector3(cos(b) * r0, 0, sin(b) * r0)]
		for k in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(p[k])
	return st.commit()

func slash_fx(pos: Vector3, ang: float, big: bool, span := 1.8) -> void:
	var m := MeshInstance3D.new()
	ang += (1.8 - span) / 2.0 # keep the arc centred where the 1.8-rad arc was
	m.mesh = ring_mesh(1.6 if big else 0.55, 2.4 if big else 1.25, 0.0, TAU if big else span)
	var mat := glow_mat(Color("#bfe7ff") if big else Color.WHITE, 2.5)
	m.material_override = mat
	m.position = pos + Vector3(0, 0.5, 0)
	m.rotation.y = ang
	add_fx(m, 0.22, func(n: Node3D, k: float, _dt: float):
		mat.albedo_color.a = 1.0 - k
		n.scale = Vector3.ONE * (1.0 + k * 0.4))

func pillar(pos: Vector3) -> void:
	var m := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.35
	c.bottom_radius = 0.35
	c.height = 8.0
	m.mesh = c
	var mat := glow_mat(Color("#fff1c0"), 2.0)
	m.material_override = mat
	m.position = pos + Vector3(0, 4, 0)
	add_fx(m, 1.6, func(n: Node3D, k: float, _dt: float):
		mat.albedo_color.a = sin(k * PI) * 0.9
		n.scale = Vector3(1.0 + k, 1.0, 1.0 + k))

func pop_num(pos: Vector3, text: String, color := Color.WHITE) -> void:
	if not bool(cfg.nums) and text != "!" and text != "막음": # numbers can be switched off in the settings; warnings stay
		return
	var l := Label3D.new()
	l.text = text
	l.font = ui_font
	l.font_size = 64
	l.outline_size = 12
	l.pixel_size = 0.006
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = pos + Vector3(rnd(-0.2, 0.2), 0, 0)
	add_fx(l, 1.0, func(n: Node3D, k: float, dt: float):
		n.position.y += dt * 1.2
		(n as Label3D).modulate.a = 1.0 - maxf(0.0, k - 0.5) * 2.0)

# ---------------------------------------------------------------- sound
# tiny synth: renders a short tone to a 16-bit WAV and plays it once
var sfx_cache := {}

var sfx_log: Array = []      # "wave:freq" of every sound played, read by tests

func sfx(freq: float, dur := 0.1, wave := "square", vol := 0.25, slide := 0.0) -> void:
	sfx_log.append("%s:%d" % [wave, int(freq)])
	if muted:
		return
	var pl := AudioStreamPlayer.new()
	pl.stream = sfx_stream(freq, dur, wave, vol, slide)
	add_child(pl)
	pl.play()
	pl.finished.connect(pl.queue_free)

func sfx_stream(freq: float, dur := 0.1, wave := "square", vol := 0.25, slide := 0.0) -> AudioStreamWAV:
	var key := "%s|%s|%s|%s|%s" % [freq, dur, wave, vol, slide]
	var stream: AudioStreamWAV = sfx_cache.get(key)
	if stream == null:
		var rate := 22050
		var n := int(rate * dur)
		var data := PackedByteArray()
		data.resize(n * 2)
		var phase := 0.0
		var lp := 0.0
		for i in n:
			var k := float(i) / n
			var f := freq * pow(maxf(30.0, freq + slide) / freq, k) if slide != 0.0 else freq
			phase += f / rate
			var x := fmod(phase, 1.0)
			var v: float
			match wave:
				"square": v = 1.0 if x < 0.5 else -1.0
				"sawtooth": v = x * 2.0 - 1.0
				"triangle": v = 1.0 - 4.0 * absf(x - 0.5)
				"step": # brushed grass: filtered noise that swells in, then fades
					lp = lerpf(lp, randf_range(-1.0, 1.0), 0.12)
					v = lp * 2.4 * minf(1.0, k * 6.0)
				"noise":
					lp = lerpf(lp, randf_range(-1.0, 1.0), 0.18) # one-pole low-pass takes the hiss off
					v = lp * 2.2 * (0.6 + 0.4 * sin(phase * TAU))
				_: v = sin(phase * TAU)
			v *= vol * pow(0.0001 if wave != "step" else 0.01, k) # exponential fade like the web version
			data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
		stream = AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.mix_rate = rate
		stream.data = data
		sfx_cache[key] = stream
	return stream

# footsteps: a grass rustle, or a hollow knock on bridge planks; a few cached variants
var step_frame := -1

# Footsteps: soft and varied so they sit under the music of the marsh, not on top of it.
# A grass step is a short brush of filtered noise with a gentle fade in; a bridge step is a quiet knock.
const STEP_GAP := 0.42  # at most ~2.4 steps a second, even when running
var last_step := -9.0

func footstep() -> void:
	if t - last_step < STEP_GAP:
		return
	last_step = t
	var v := rnd(0.045, 0.07)
	if tile_at(player.x, player.z) == BRIDGE:
		sfx(rnd(130.0, 170.0), 0.05, "triangle", v * 1.6, -40.0)
	else:
		sfx(rnd(70.0, 120.0), 0.09, "step", v)

# ---------------------------------------------------------------- combat
func damage_enemy(e: Dictionary, amt: float, from: Vector2, kb := 4.0, force_crit := false, stop := 0.05) -> void:
	if e.get("locked", false) or e.get("air", false):
		return # the mold at its last sliver only breaks to the wind; the hawk is out of reach in the air
	if e.get("shield", 0) > 0 and e.get("wind", 0.0) <= 0.0:
		e.shield -= 1
		pop_num(Vector3(e.x, 1.4, e.z), "막음", Color("#c8c8d0"))
		burst(Vector3(e.x, 0.6, e.z), Color("#c8962a"), 8, 2.0)
		sfx(700, 0.06, "square", 0.15, -300)
		if e.shield <= 0:
			e.shield_node.queue_free()
			toast("방패가 깨졌다")
		return
	if e.dead or e.get("roar", 0.0) > 0.0:
		return
	if e.has("cage"):
		cage_hit(e)
		return
	if e.get("knight", false) and e.stun <= 0.0 and e.tired <= 0.0 and e.dash <= 0.0:
		var from_dir := (from - Vector2(e.x, e.z)).normalized()
		if from_dir.dot(e.face) > 0.34: # within about 70 degrees either side of where the shield points
			pop_num(Vector3(e.x, 2.2, e.z), "막음", Color("#c8c8d0"))
			burst(Vector3(e.x + e.face.x * 0.6, 1.2, e.z + e.face.y * 0.6), Color("#c8962a"), 6, 2.0)
			sfx(700, 0.06, "square", 0.15, -300)
			return
	var crit := force_crit or rng.randf() < (0.25 if has_ring else 0.15)
	if crit:
		stats.crits += 1
	if (e.get("boss", false) or e.get("mole", false)) and e.get("stun", 0.0) > 0.0:
		amt *= 1.5
	var dmg := int(round(amt / ng_mult() * rnd(0.85, 1.15) * (1.0 if force_crit else (1.8 if crit else 1.0))))
	hitstop = maxf(hitstop, 0.09 if crit and stop < 0.09 else stop)
	if e.get("wind", 0.0) > 0.0 and not e.get("boss", false):
		e.wind = 0.0 # a hit interrupts a goblin's wind-up
		e.atk_cd = 1.6
	e.hp -= dmg
	e.hurt = 0.12
	var d := Vector2(e.x - from.x, e.z - from.y)
	if d.length() < 0.01:
		d = Vector2(0, 1)
	d = d.normalized() * (kb * 0.15 if e.get("boss", false) else kb)
	e.kx = d.x
	e.kz = d.y
	var y := height_at(e.x, e.z)
	pop_num(Vector3(e.x, y + 1.2, e.z), str(dmg) + ("!" if crit else ""))
	burst(Vector3(e.x, y + 0.5, e.z), Color("#ffd28a"), 8, 2.0)
	shake = maxf(shake, 0.18 if crit else 0.08)
	sfx(520.0 if crit else 300.0, 0.08, "square", 0.2, -200.0)
	if e.hp <= 0:
		e.dead = true
		e.respawn = 8.0
		stats.kills += 1
		e.node.queue_free()
		e.shadow.queue_free()
		burst(Vector3(e.x, y + 0.4, e.z), Color("#ff9a4a"), 26, 3.5)
		if e.get("noeul", false):
			get_tree().create_timer(1.0).timeout.connect(noeul_turned if e.get("second", false) else noeul_beaten)
		elif e.get("turtle", false):
			get_tree().create_timer(1.0).timeout.connect(turtle_beaten)
		elif e.get("crab", false):
			get_tree().create_timer(1.0).timeout.connect(crab_beaten)
		elif e.get("scare", false):
			get_tree().create_timer(1.0).timeout.connect(scarecrow_beaten)
		elif e.get("knight", false):
			get_tree().create_timer(1.0).timeout.connect(knight_beaten)
		elif e.get("hawk", false):
			get_tree().create_timer(1.0).timeout.connect(hawk_beaten)
		elif e.get("mole", false):
			player.gold += 150
			gain_xp(120)
			get_tree().create_timer(1.2).timeout.connect(mole_defeated)
		elif e.get("boss", false):
			player.gold += 300
			toast("벽돌왕을 쓰러뜨렸다! 금화 +300")
			get_tree().create_timer(1.5).timeout.connect(open_cave.bind(Vector2(e.x, e.z)))
			ui.boss.visible = false
			shake = 0.6
			for k in 4:
				burst(Vector3(e.x + rnd(-1, 1), y + rnd(0.5, 2.5), e.z + rnd(-1, 1)), Color("#e8b018"), 30, 5.0)
			gain_xp(200)
		else:
			var g := 3 + rng.randi() % 5
			player.gold += g
			toast(tr("금화 +%d") % g)
			gain_xp(12)

func gain_xp(n: int) -> void:
	if has_bookmark:
		n = int(round(n * 1.2))
	player.xp += n
	while player.xp >= player.lv * 25:
		player.xp -= player.lv * 25
		player.lv += 1
		player.max_hp += 12
		player.atk += 3
		player.hp = float(player.max_hp)
		ui.banner_title.text = tr("레벨 %d") % player.lv
		ui.banner_sub.text = LV_MOVES.get(player.lv, "최대 체력 +12 · 공격력 +3")
		ui.banner.modulate.a = 1.0
		banner_t = 2.5
		pillar(Vector3(player.x, height_at(player.x, player.z), player.z))
		sfx(523, 0.15, "triangle", 0.3)
		get_tree().create_timer(0.12).timeout.connect(func(): sfx(659, 0.15, "triangle", 0.3))
		get_tree().create_timer(0.24).timeout.connect(func(): sfx(784, 0.3, "triangle", 0.3))

func nearest_enemy(range_: float):
	var best = null
	var bd := range_
	for e in enemies:
		if not e.dead:
			var d := Vector2(e.x - player.x, e.z - player.z).length()
			if d < bd:
				bd = d
				best = e
	return best

# moves that open with level (the banner names them when they arrive)
const LV_MOVES := {
	2: "새 기술: 4타 연속기 (J를 네 번, 넷째 타는 한 바퀴 베기)",
	3: "새 기술: 달려 베기 (Shift로 달리며 J)",
	4: "새 기술: 모아 베기 (L로 막으며 1초 모은 뒤 J)",
	6: "새 기술: 5타 마무리 (다섯째 타는 땅 내려찍기)",
	8: "새 기술: 빛 칼날 (연속기 마지막 타가 빛 칼날을 날린다)",
}

# the sword's arc widens as Sora grows: about 70 degrees at Lv1, 150 from Lv8; hits follow the arc
func slash_span() -> float:
	return clampf(1.2 + 0.2 * (player.lv - 1), 1.2, 2.6)

func combo_len() -> int:
	return 3 + (1 if player.lv >= 2 else 0) + (1 if player.lv >= 6 else 0)

# one swing of the combo; the last swing of the chain is the finisher:
# 3 hits: a heavy cut; 4 hits: a full spin; 5 hits: a ground slam
func attack() -> void:
	if player.atk_cd > 0 or player.dodge > 0:
		return
	if player.lv >= 4 and guarding and t - guard_since >= 1.0:
		charged_slash()
		return
	if player.lv >= 3 and key_down(KEY_SHIFT) and Vector2(player.vx, player.vz).length() > 4.0 and player.sp >= 15.0:
		dash_slash()
		return
	var tg = nearest_enemy(2.2)
	if tg != null:
		player.face = Vector2(tg.x - player.x, tg.z - player.z).normalized()
	var n := combo_len()
	player.combo = (player.combo + 1) % n if player.combo_t > 0 else 0
	player.combo_t = 0.6
	var last: bool = player.combo == n - 1
	var spin: bool = last and n == 4 or player.combo == 3 and n == 5
	var slam: bool = last and n == 5
	player.atk_cd = 0.38 if last else (0.3 if spin else 0.24)
	var f: Vector2 = player.face
	var here := Vector3(player.x, height_at(player.x, player.z), player.z)
	if spin or slam:
		slash_fx(here, 0.0, true)
	else:
		var ang := -atan2(f.y, f.x) - 0.9 * (-1.0 if player.combo == 1 else 1.0) + 0.9
		slash_fx(Vector3(player.x + f.x * 0.5, here.y, player.z + f.y * 0.5), ang, false, slash_span())
	var cone := cos(slash_span() / 2.0 + 0.45)
	var reach := 2.6 if slam else (2.0 if spin else 1.7)
	var mult: float = 2.4 if slam else (1.6 if spin else ([1.0, 1.15, 1.4][mini(player.combo, 2)] if not last else 1.8))
	var hit_any := false
	for e in enemies:
		if e.dead:
			continue
		var d := Vector2(e.x - player.x, e.z - player.z)
		if d.length() < reach and (spin or slam or d.normalized().dot(f) > cone):
			var countering := counter_t > 0.0
			damage_enemy(e, player.atk * (2.5 if countering else mult), Vector2(player.x, player.z), 7.0 if last else 3.0,
				countering, 0.14 if countering else (0.09 if last else 0.05))
			player.mp = minf(player.max_mp, player.mp + 5.0)
			last_hit_t = t
			hit_any = true
	if hit_any and counter_t > 0.0:
		counter_t = 0.0
	if in_cave:
		for c in crystals:
			var dc := Vector2(c.x - player.x, c.z - player.z)
			if dc.length() < reach + 0.3 and (spin or slam or dc.normalized().dot(f) > cone):
				crystal_hit(c)
	if slam:
		shake = maxf(shake, 0.3)
		burst(here + Vector3(0, 0.2, 0), Color("#d8c8a0"), 30, 3.5)
	if last and player.lv >= 8:
		light_blade(f)
	var lunge := 4.0 if last else 2.0
	player.vx += f.x * lunge
	player.vz += f.y * lunge
	sfx(180.0 + player.combo * 60.0, 0.07, "sawtooth", 0.12, 300.0)

# Lv3: running with Shift, J dashes 3 m ahead and cuts everything along the way
func dash_slash() -> void:
	player.sp -= 15.0
	player.combo = 0
	player.combo_t = 0.0
	player.atk_cd = 0.4
	var f: Vector2 = player.face
	var start := Vector2(player.x, player.z)
	var end := start
	for k in 12: # stop short of walls and water
		var nxt := start + f * (0.25 * (k + 1))
		if not player_can(nxt.x, nxt.y):
			break
		end = nxt
	for e in enemies:
		if e.dead:
			continue
		var p := Vector2(e.x, e.z)
		var along := clampf((p - start).dot(f), 0.0, start.distance_to(end))
		if p.distance_to(start + f * along) < 1.1:
			damage_enemy(e, player.atk * 1.5, start, 5.0, false, 0.07)
			player.mp = minf(player.max_mp, player.mp + 5.0)
			last_hit_t = t
	player.x = end.x
	player.z = end.y
	player.vx = f.x * 3.0
	player.vz = f.y * 3.0
	var ang := -atan2(f.y, f.x)
	slash_fx(Vector3(end.x, height_at(end.x, end.y), end.y), ang, false)
	burst(Vector3((start.x + end.x) / 2.0, 0.6, (start.y + end.y) / 2.0), Color("#bfe7ff"), 16, 2.5)
	sfx(260, 0.12, "sawtooth", 0.15, 600)

# Lv4: guard for a second to gather light, then J: a wide, heavy cut in front
func charged_slash() -> void:
	guard_since = t
	player.combo = 0
	player.atk_cd = 0.5
	var f: Vector2 = player.face
	var here := Vector3(player.x, height_at(player.x, player.z), player.z)
	slash_fx(here + Vector3(f.x * 0.8, 0, f.y * 0.8), -atan2(f.y, f.x), true)
	for e in enemies:
		if e.dead:
			continue
		var d := Vector2(e.x - player.x, e.z - player.z)
		if d.length() < 2.8 and d.normalized().dot(f) > 0.2:
			damage_enemy(e, player.atk * 3.0, Vector2(player.x, player.z), 10.0, true, 0.14)
			last_hit_t = t
	shake = maxf(shake, 0.35)
	burst(here + Vector3(f.x, 0.8, f.y), Color("#fff1a0"), 30, 3.5)
	sfx(330, 0.3, "sawtooth", 0.25, -200)

# Lv8: the finisher sends a blade of light forward (it flies like the ember bolt)
func light_blade(f: Vector2) -> void:
	var b := MeshInstance3D.new()
	b.mesh = ring_mesh(0.3, 0.6, -0.9, 1.8)
	b.material_override = glow_mat(Color("#dff4ff"), 4.0)
	b.position = Vector3(player.x, height_at(player.x, player.z) + 0.6, player.z)
	b.rotation.y = atan2(f.x, f.y) + PI / 2
	add_child(b)
	projectiles.append({"node": b, "v": f * 12.0, "life": 0.7})

const SKILL_MP := [30, 15, 60]
const SKILL_CD := [3.0, 1.2, 6.0]
var skill_up := -1           # the skill woken at the cave shrine: 0 whirl, 1 ember bolt, 2 radiant nova
var shrine_seen := false
var shrine_nodes: Array = []

func skill_cost(i: int) -> int:
	return 45 if i == 2 and skill_up == 2 else SKILL_MP[i]

func use_skill(i: int) -> void:
	if player.cds[i] > 0:
		return
	if player.mp < skill_cost(i):
		toast("기세가 모자라다")
		return
	player.mp -= skill_cost(i)
	player.cds[i] = SKILL_CD[i] * (0.8 if has_shard else 1.0)
	var here := Vector3(player.x, height_at(player.x, player.z), player.z)
	var me := Vector2(player.x, player.z)
	match i:
		0: # whirl (woken: wider and harder)
			var woke := skill_up == 0
			sfx(140, 0.3, "sawtooth", 0.2, 400)
			slash_fx(here, 0.0, true)
			if woke: # the woken whirl throws a wider ring of wind
				burst(here + Vector3(0, 0.5, 0), Color("#9fd4ff"), 30, 5.0)
			for e in enemies:
				if not e.dead and Vector2(e.x, e.z).distance_to(me) < (3.4 if woke else 2.6):
					damage_enemy(e, player.atk * (1.9 if woke else 1.4), me, 6.0)
		1: # ember bolt
			sfx(400, 0.2, "triangle", 0.2, -250)
			var tg = nearest_enemy(12.0)
			var dir: Vector2 = (Vector2(tg.x, tg.z) - me).normalized() if tg != null else player.face
			for a in ([-0.22, 0.0, 0.22] if skill_up == 1 else [0.0]): # woken: three bolts in a fan
				var b := MeshInstance3D.new()
				var sp := SphereMesh.new()
				sp.radius = 0.16
				sp.height = 0.32
				b.mesh = sp
				b.material_override = glow_mat(Color("#ff8a2a"), 4.0)
				if a == 0.0: # one light is enough; the web renderer lights a mesh with at most 8
					var l := OmniLight3D.new()
					l.light_color = Color("#ff8a3a")
					l.light_energy = 2.0
					l.omni_range = 4.0
					b.add_child(l)
				b.position = here + Vector3(0, 0.6, 0)
				add_child(b)
				projectiles.append({"node": b, "v": dir.rotated(a) * 14.0, "life": 1.2})
		2: # radiant nova
			var m := MeshInstance3D.new()
			m.mesh = ring_mesh(0.2, 0.6, 0.0, TAU)
			var mat := glow_mat(Color("#fff1a0"), 3.0)
			m.material_override = mat
			m.position = here + Vector3(0, 0.3, 0)
			add_fx(m, 0.7, func(n: Node3D, k: float, _dt: float):
				n.scale = Vector3.ONE * (1.0 + k * 9.0)
				mat.albedo_color.a = 1.0 - k)
			burst(here + Vector3(0, 0.8, 0), Color("#fff1a0"), 40, 4.0)
			for e in enemies:
				if not e.dead and Vector2(e.x, e.z).distance_to(me) < 5:
					damage_enemy(e, player.atk * 2.2, me, 9.0)
			shake = 0.3
			sfx(220, 0.6, "sine", 0.4, 600)
			if skill_up == 2: # woken: the light mends her too
				var heal := int(player.max_hp * 0.15)
				player.hp = minf(float(player.max_hp), player.hp + heal)
				pop_num(here + Vector3(0, 1.6, 0), "+" + str(heal), Color("#7aff8a"))

func drink_potion() -> void:
	if player.pots <= 0:
		toast("회복약이 없다")
		return
	if player.cds[3] > 0:
		return
	player.pots -= 1
	player.cds[3] = 2.0
	var h := minf(player.max_hp - player.hp, 65.0 if has_acorn else 45.0)
	player.hp += h
	var y := height_at(player.x, player.z)
	pop_num(Vector3(player.x, y + 1.9, player.z), "+%d" % int(h), Color("#8dff9a"))
	burst(Vector3(player.x, y + 0.6, player.z), Color("#8dff9a"), 20, 2.0)
	sfx(660, 0.25, "sine", 0.25, 300)

func dodge() -> void:
	var cost := 15 if has_feather else 25
	if player.dodge > 0 or player.sp < cost:
		return
	player.sp -= cost
	player.dodge = 0.32
	player.inv = 0.3
	dodge_start = t
	var d := Vector2(player.vx, player.vz)
	d = player.face if d.length() < 0.1 else d.normalized()
	player.dvx = d.x * 11.0
	player.dvz = d.y * 11.0
	sfx(120, 0.12, "triangle", 0.15, 80)

func in_marsh() -> bool:
	return not (in_cave or in_village or in_forest or in_lake or in_hill or in_garden)

func interact() -> void:
	if in_cave and cave_interact():
		return
	if in_village and in_house >= 0 and cupboard_key():
		return
	if in_village and in_house < 0 and house_door_near() >= 0 and fade_rect.color.a == 0.0:
		var hi := house_door_near()
		fade_then(func(): enter_house(hi))
		return
	if near_shop() and doran_q == 2 and not shop_open:
		deliver_letter()
		return
	if near_shop() and not shop_open and deliver(0, STORY.MAIL_BORI):
		return
	if near_shop() and marsh.picked_count() == 3 and not has_tea and not shop_open:
		has_tea = true
		show_story("", STORY.MOON_TEA)
		save_game()
		return
	if near_shop():
		toggle_shop(not shop_open)
		return
	if in_grotto() and grotto_key():
		return
	if in_cloud() and cloud_key():
		return
	if in_forest and forest.solved and not forest.chest_open and Vector2(player.x, player.z).distance_to(forest.marks.c) < 1.6:
		open_grove_chest()
		return
	if in_marsh() and marsh.near_chest(self):
		marsh.open_chest(self)
		return
	for c in chests:
		if not c.open and Vector2(c.x - player.x, c.z - player.z).length() < 1.5:
			c.open = true
			c.node.modulate = Color(0.55, 0.55, 0.55)
			var g := 15 + rng.randi() % 15
			player.gold += g
			player.pots += 1
			burst(Vector3(c.x, height_at(c.x, c.z) + 0.6, c.z), Color("#ffd84a"), 30, 3.0)
			toast(tr("금화 %d닢과 회복약을 찾았다") % g)
			sfx(784, 0.12, "triangle", 0.25)
			get_tree().create_timer(0.1).timeout.connect(func(): sfx(1046, 0.25, "triangle", 0.25))
			return

# ---------------------------------------------------------------- day and night
# The clock runs on its own: one in-game hour every DAY_SPEED seconds (a full day in 6 minutes).
# Light, fog and sky blend between these key hours; T skips ahead three hours.
const DAY_SPEED := 15.0
const KEY_HOURS := [ # a summer day: the sun sets late and rises early, so night runs only 21:00 - 04:00
	{"h": 0.0, "sun": "#6a7cc8", "si": 0.25, "amb": "#2a3460", "ai": 0.55, "fog": "#141a30", "el": 0.9, "night": 1.0, "beams": 0.0},
	{"h": 4.0, "sun": "#6a7cc8", "si": 0.25, "amb": "#2a3460", "ai": 0.55, "fog": "#141a30", "el": 0.1, "night": 1.0, "beams": 0.0},
	{"h": 5.5, "sun": "#ff9a6a", "si": 0.9, "amb": "#b08aa0", "ai": 0.8, "fog": "#d8a08a", "el": 0.2, "night": 0.4, "beams": 0.6},
	{"h": 8.0, "sun": "#fff0d0", "si": 1.5, "amb": "#e8eef8", "ai": 1.0, "fog": "#cfe0e8", "el": 0.7, "night": 0.0, "beams": 0.3},
	{"h": 13.0, "sun": "#fff4e0", "si": 1.7, "amb": "#eaf4ff", "ai": 1.05, "fog": "#cfe2ee", "el": 1.1, "night": 0.0, "beams": 0.2},
	{"h": 17.5, "sun": "#ffc06a", "si": 1.5, "amb": "#fff0d0", "ai": 0.95, "fog": "#e8c98a", "el": 0.55, "night": 0.1, "beams": 1.0},
	{"h": 19.5, "sun": "#ff7a4a", "si": 0.9, "amb": "#9a7aa8", "ai": 0.7, "fog": "#b07a80", "el": 0.2, "night": 0.6, "beams": 0.5},
	{"h": 21.0, "sun": "#6a7cc8", "si": 0.3, "amb": "#2a3460", "ai": 0.55, "fog": "#141a30", "el": 0.6, "night": 1.0, "beams": 0.0},
	{"h": 24.0, "sun": "#6a7cc8", "si": 0.25, "amb": "#2a3460", "ai": 0.55, "fog": "#141a30", "el": 0.9, "night": 1.0, "beams": 0.0},
]

# night for game rules (fireflies, moonflowers, crown costs, resting, the lantern night): 21:00 - 04:00
func is_night() -> bool:
	return hour >= 21.0 or hour < 4.0
var hour := 16.5
var day := 0                 # counts noons; the moon runs an 8-night cycle

const MOON_DAYS := 8

# 0 = thin crescent .. 1 = full; waxing for the first half of the cycle
func moon_phase() -> Vector2:
	var p := float(day % MOON_DAYS) / MOON_DAYS
	return Vector2(0.15 + 0.85 * (1.0 - absf(2.0 * p - 1.0)), 1.0 if p < 0.5 else -1.0)
var sun_el := 0.55
var night := 0.1
var beams := 1.0

func skip_time(hours: float) -> void:
	if hour < 12.0 and hour + hours >= 12.0 or hour + hours >= 36.0:
		day += 1
	hour = fmod(hour + hours, 24.0)
	toast(tr("%02d시") % int(hour))

func update_daylight(dt: float) -> void:
	if in_grotto(): # underground: the same soft blue light at any hour, a lamp on Sora (the clock waits, as in the cave)
		sun.light_energy = 0.35
		env.ambient_light_color = Color("#9ab4d8")
		env.ambient_light_energy = 1.4
		env.glow_intensity = 0.6
		env.glow_bloom = 0.05
		env.fog_light_color = Color("#0a1a2e")
		env.background_color = Color("#06101c")
		cave_light.light_energy = 2.4
		cave_light.position = Vector3(player.x, 1.8, player.z)
		motes.emitting = false
		motes.visible = false
		return
	if in_cave:
		sun.light_energy = 0.0
		env.ambient_light_color = Color("#4a6aa0")
		env.ambient_light_energy = 0.9
		env.glow_intensity = 0.6
		env.glow_bloom = 0.05
		env.fog_light_color = Color("#081426")
		env.background_color = Color("#050a14")
		cave_light.light_energy = 2.2
		cave_light.position = Vector3(player.x, 1.6, player.z)
		motes.emitting = false
		motes.visible = false
		return
	cave_light.light_energy = 0.0
	env.glow_intensity = 0.8
	env.glow_bloom = 0.05
	var before := hour
	hour = fmod(hour + dt / DAY_SPEED, 24.0)
	if before < 12.0 and hour >= 12.0:
		day += 1
	var i := 0
	while KEY_HOURS[i + 1].h <= hour:
		i += 1
	var a: Dictionary = KEY_HOURS[i]
	var b: Dictionary = KEY_HOURS[i + 1]
	var k := smoothstep(0.0, 1.0, (hour - a.h) / (b.h - a.h))
	sun.light_color = Color(a.sun).lerp(Color(b.sun), k)
	night = lerpf(a.night, b.night, k)
	sun.light_energy = lerpf(a.si, b.si, k) * 1.1 * lerpf(1.0, 0.5 + 0.7 * moon_phase().x, night) # fuller moon, brighter night
	env.ambient_light_color = Color(a.amb).lerp(Color(b.amb), k)
	env.ambient_light_energy = lerpf(a.ai, b.ai, k) * 0.4
	var fog := Color(a.fog).lerp(Color(b.fog), k)
	env.fog_light_color = fog
	env.background_color = fog
	sun_el = lerpf(a.el, b.el, k)
	night = lerpf(a.night, b.night, k)
	beams = lerpf(a.beams, b.beams, k)
	motes.emitting = night > 0.3 # fireflies only come out after dusk
	motes.visible = night > 0.3   # and vanish at once in daylight instead of lingering

# ---------------------------------------------------------------- HUD
func panel(parent: Control, pos: Vector2, size: Vector2, anchor := Control.PRESET_TOP_LEFT) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.063, 0.078, 0.133, 0.86)
	sb.border_color = Color(0.725, 0.635, 0.45, 0.55)
	sb.set_border_width_all(1)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	place(p, anchor, pos, size)
	return p

# pin a control to a corner/edge: pos is the offset from that anchor point
func place(c: Control, anchor: int, pos: Vector2, size: Vector2) -> void:
	c.set_anchors_preset(anchor)
	c.offset_left = pos.x
	c.offset_top = pos.y
	c.offset_right = pos.x + size.x
	c.offset_bottom = pos.y + size.y

func label(parent: Control, text: String, pos: Vector2, size := 16, color := Color("#efe6cf"), font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_override("font", font if font else ui_font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func bar(parent: Control, pos: Vector2, color: Color) -> ColorRect:
	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.13, 0.13)
	bg.position = pos
	bg.size = Vector2(200, 6)
	parent.add_child(bg)
	var fg := ColorRect.new()
	fg.color = color
	fg.size = Vector2(200, 6)
	bg.add_child(fg)
	return fg

func build_hud() -> void:
	hud = CanvasLayer.new()
	hud.layer = 1
	add_child(hud)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(root)
	ui.root = root
	# the old boxy panels stay in a hidden holder (their labels still carry values); hud.gd draws the HUD
	var legacy := Control.new()
	legacy.set_anchors_preset(Control.PRESET_FULL_RECT)
	legacy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	legacy.visible = false
	root.add_child(legacy)
	ui.legacy = legacy
	var deco := Control.new()
	deco.set_script(load("res://hud.gd"))
	deco.main = self
	deco.set_anchors_preset(Control.PRESET_FULL_RECT)
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(deco)

	var zone := panel(legacy, Vector2(14, 12), Vector2(190, 58))
	label(zone, "◆", Vector2(14, 16), 16, Color("#b9a273"))
	ui.zone_name = label(zone, "갈대늪", Vector2(42, 6), 19)
	ui.zone_sub = label(zone, "등불여울 건널목", Vector2(42, 32), 13, Color("#a99d84"))

	var stats := panel(legacy, Vector2(14, 72), Vector2(396, 92))
	label(stats, "레벨", Vector2(14, 8), 11, Color("#a99d84"))
	ui.lv = label(stats, "1", Vector2(18, 24), 30)
	for row in [["체력", 10, Color("#d83a44")], ["기세", 30, Color("#f08a2a")], ["기력", 50, Color("#e9d39a")]]:
		label(stats, row[0], Vector2(56, row[1] - 4), 11, Color("#a99d84"))
	ui.hp = bar(stats, Vector2(100, 10), Color("#d83a44"))
	ui.mp = bar(stats, Vector2(100, 30), Color("#f08a2a"))
	ui.sp = bar(stats, Vector2(100, 50), Color("#e9d39a"))
	label(stats, "경험", Vector2(56, 66), 11, Color("#a99d84"))
	ui.xp = bar(stats, Vector2(100, 70), Color("#8de07a"))
	ui.xpt = label(stats, "", Vector2(310, 63), 12, Color("#8de07a"))
	ui.spt = label(stats, "", Vector2(310, 43), 12)
	ui.hpt = label(stats, "", Vector2(310, 3), 12)
	ui.mpt = label(stats, "", Vector2(310, 23), 12)

	# shop screen: Bori standing on the left, a display board of item cards on the right,
	# her line at the bottom; the game stays visible, dimmed, behind
	var shop := ColorRect.new()
	shop.color = Color(0.008, 0.016, 0.043, 0.55)
	shop.set_anchors_preset(Control.PRESET_FULL_RECT)
	shop.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(shop)
	var keeper := TextureRect.new()
	keeper.texture = load("res://art/portrait/bori.png")
	keeper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	keeper.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	keeper.flip_h = true # she faces the board
	keeper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shop.add_child(keeper)
	place(keeper, Control.PRESET_CENTER_LEFT, Vector2(30, -330), Vector2(440, 600))
	ui.shop_keeper = keeper
	var board := Control.new()
	board.set_script(load("res://frame.gd"))
	board.kind = "box"
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shop.add_child(board)
	place(board, Control.PRESET_CENTER, Vector2(-160, -270), Vector2(620, 420))
	var btab := Control.new()
	btab.set_script(load("res://frame.gd"))
	btab.kind = "tab"
	board.add_child(btab)
	btab.position = Vector2(40, -18)
	btab.size = Vector2(220, 32)
	var st := label(btab, "보리 할머니의 상점", Vector2(0, 4), 16, Color("#f6d27a"))
	st.size = Vector2(220, 24)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.shop_gold = label(board, "", Vector2(400, 14), 16, Color("#ffd84a"))
	ui.shop_gold.size = Vector2(190, 22)
	ui.shop_gold.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ui.shop_btns = []
	for i in SHOP.size():
		var it: Dictionary = SHOP[i]
		var card := Control.new()
		card.set_script(load("res://frame.gd"))
		card.kind = "tab"
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		board.add_child(card)
		card.position = Vector2(30 + (i % 2) * 290, 52 + (i / 2) * 176)
		card.size = Vector2(270, 160)
		var icon := TextureRect.new()
		var ip := "res://art/ui/item_%d.png" % i
		icon.texture = load(ip) if ResourceLoader.exists(ip) else null
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.position = Vector2(12, 12)
		icon.size = Vector2(96, 96)
		card.add_child(icon)
		label(card, "%d" % (i + 1), Vector2(10, 6), 12, Color("#a99d84"))
		label(card, it.name, Vector2(118, 18), 17)
		var dsc := label(card, it.desc, Vector2(118, 46), 13, Color("#a99d84"))
		dsc.size = Vector2(140, 40)
		dsc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var b := Button.new()
		b.text = tr("◆ %d  사기") % it.price
		b.add_theme_font_override("font", ui_font)
		b.add_theme_font_size_override("font_size", 15)
		b.position = Vector2(118, 112)
		b.size = Vector2(138, 34)
		var idx_ := i
		b.pressed.connect(func(): buy(idx_))
		card.add_child(b)
		ui.shop_btns.append(b)
	var say := Control.new()
	say.set_script(load("res://frame.gd"))
	say.kind = "box"
	say.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shop.add_child(say)
	place(say, Control.PRESET_CENTER_BOTTOM, Vector2(-470, -150), Vector2(940, 100))
	var stab := Control.new()
	stab.set_script(load("res://frame.gd"))
	stab.kind = "tab"
	say.add_child(stab)
	stab.position = Vector2(40, -18)
	stab.size = Vector2(150, 32)
	var sn := label(stab, "보리 할머니", Vector2(0, 4), 16, Color("#f6d27a"))
	sn.size = Vector2(150, 24)
	sn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.shop_say = label(say, "", Vector2(40, 32), 19)
	ui.shop_say.size = Vector2(860, 40)
	label(say, "1 → 4 사기  ·  E / Space / Esc 닫기", Vector2(680, 70), 12, Color("#a99d84"))
	shop.visible = false
	ui.shop = shop
	ui.shop_hint = label(root, "E  보리 할머니의 상점", Vector2.ZERO, 16, Color("#fff1c8"))
	place(ui.shop_hint, Control.PRESET_CENTER_BOTTOM, Vector2(-150, -260), Vector2(300, 24))
	ui.shop_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.shop_hint.add_theme_constant_override("outline_size", 6)
	ui.shop_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	ui.shop_hint.visible = false

	# boss health bar, top centre, shown while the Brick King is awake
	var bb := panel(root, Vector2(-220, 14), Vector2(440, 40), Control.PRESET_CENTER_TOP)
	var bn := label(bb, "벽돌왕", Vector2(0, 2), 13, Color("#f6b951"))
	ui.boss_name = bn
	bn.size = Vector2(440, 18)
	bn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var bbg := ColorRect.new()
	bbg.color = Color(0.13, 0.13, 0.13)
	bbg.position = Vector2(10, 24)
	bbg.size = Vector2(420, 8)
	bb.add_child(bbg)
	ui.boss_bar = ColorRect.new()
	ui.boss_bar.color = Color("#9a4ad8")
	ui.boss_bar.size = Vector2(420, 8)
	bbg.add_child(ui.boss_bar)
	bb.visible = false
	ui.boss = bb

	fade_rect = ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 0)
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(fade_rect)

	# quest line, top centre under the boss bar
	ui.quest = label(root, "", Vector2.ZERO, 17, Color("#fff1c8"))
	place(ui.quest, Control.PRESET_CENTER_TOP, Vector2(-300, 62), Vector2(600, 26))
	ui.quest.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.quest.add_theme_constant_override("outline_size", 6)
	ui.quest.add_theme_color_override("font_outline_color", Color("#02040b"))
	ui.quest.visible = false

	# blue edge while a flash dodge slows the world
	var tint := ColorRect.new()
	tint.color = Color(0.35, 0.65, 1.0, 0.16)
	tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tint.visible = false
	root.add_child(tint)
	root.move_child(tint, 0)
	ui.slowmo_tint = tint

	# sky dial under the stats: sun and moon travel the arc with the clock
	var sky := Control.new()
	sky.set_script(load("res://sky.gd"))
	sky.main = self
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky.clip_contents = true
	legacy.add_child(sky)
	place(sky, Control.PRESET_TOP_LEFT, Vector2(14, 166), Vector2(190, 64))

	# circular minimap, top right
	var mask := TextureRect.new()
	var circle := Image.create(186, 186, false, Image.FORMAT_RGBA8)
	circle.fill(Color(0, 0, 0, 0))
	for y in 186:
		for x in 186:
			if Vector2(x - 92.5, y - 92.5).length() < 92:
				circle.set_pixel(x, y, Color.WHITE)
	mask.texture = ImageTexture.create_from_image(circle)
	mask.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	place(mask, Control.PRESET_TOP_RIGHT, Vector2(-200, 12), Vector2(186, 186))
	mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(mask)
	var mini := Control.new()
	mini.set_script(load("res://minimap.gd"))
	mini.size = Vector2(186, 186)
	mini.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mimg := Image.create(N, N, false, Image.FORMAT_RGBA8)
	var pal := [Color("#1d4f7c"), Color("#16302e"), Color("#2c4a48"), Color("#c8962a")]
	for z in N:
		for x in N:
			mimg.set_pixel(x, z, pal[map[idx(x, z)]])
	for z in range(1, N - 1):
		for x in range(1, N - 1):
			var w := map[idx(x, z)] == WATER
			if not w:
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if map[idx(x + d.x, z + d.y)] == WATER:
						mimg.set_pixel(x, z, Color("#3fa0c8"))
				if hgt[idx(x, z)] > 0.5 and (x + z) % 3 == 0:
					mimg.set_pixel(x, z, Color("#23423e"))
	mini.map_tex = ImageTexture.create_from_image(mimg)
	ui.mini = mini
	mini.main = self
	mask.add_child(mini)

	# skills, bottom right
	var names := ["회오리", "불씨탄", "빛파동", "×3"]
	var keys_ := ["U", "I", "O", "4"]
	var icons := ["○", "●", "◇", "♥"]
	var icon_cols := [Color("#9fd4ff"), Color("#ff8a2a"), Color("#fff1a0"), Color("#8dff9a")]
	ui.cd = []
	for i in 4:
		var slot := panel(legacy, Vector2(-290 + i * 70, -86), Vector2(56, 48), Control.PRESET_BOTTOM_RIGHT)
		label(slot, keys_[i], Vector2(3, 1), 10, Color("#e9dfc4"))
		label(slot, icons[i], Vector2(18, 10), 22, icon_cols[i])
		var cd := ColorRect.new()
		cd.color = Color(0, 0, 0, 0.65)
		cd.size = Vector2(56, 0)
		slot.add_child(cd)
		ui.cd.append(cd)
		var n := label(legacy, names[i], Vector2(0, 0), 12)
		place(n, Control.PRESET_BOTTOM_RIGHT, Vector2(-290 + i * 70, -36), Vector2(56, 20))
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if i == 3:
			ui.pots = n
	var gold := panel(legacy, Vector2(-80, -130), Vector2(66, 30), Control.PRESET_BOTTOM_RIGHT)
	ui.gold = label(gold, "◆ 0", Vector2(10, 4), 14, Color("#ffd84a"))

	# controls help, starts hidden; H or the button toggles it
	var help := menu_panel(root, Vector2(14, -530), Vector2(340, 461), Control.PRESET_BOTTOM_LEFT) # ends above the buttons
	help.mouse_filter = Control.MOUSE_FILTER_STOP
	label(help, "조작법", Vector2(14, 8), 12, Color("#a99d84"))
	var rows := [["WASD / 방향키", "이동"], ["Shift", "달리기"], ["J / 왼쪽 클릭", "공격 (연속기)"], ["K / 오른쪽 클릭", "구르기 (때맞추면 섬광)"], ["L / 가운데 클릭", "막기 (때맞추면 반격, Lv4부터 1초 모아 J)"],
		["U I O / 1 2 3", "스킬 (기세 30·15·60)"], ["4", "회복약"], ["Space", "상자 열기, 들어가기"], ["E", "왕관 만지기, 말 걸기 (보리 할머니 포함)"], ["Z X / 휠", "확대·축소"], ["T R P", "3시간 뒤로 / 비 / 사진"], ["F8", "처음 자리로 (진행은 그대로)"], ["F9", "처음부터 (저장 지우기)"], ["Q", "일지 (할 일과 곁이야기)"], ["H", "조작법 숨기기"]]
	for i in rows.size():
		label(help, rows[i][0], Vector2(14, 34 + i * 27), 13, Color("#e9dfc4"))
		label(help, rows[i][1], Vector2(150, 34 + i * 27), 15)
	var close := Button.new()
	close.text = "X"
	close.add_theme_font_override("font", ui_font)
	close.position = Vector2(310, 6)
	close.size = Vector2(24, 24)
	close.pressed.connect(func(): toggle_help(false))
	help.add_child(close)
	help.visible = false
	ui.help = help
	# the journal (Q): what to do now, the side stories found so far and the keepsakes Sora carries
	var journal := menu_panel(root, Vector2(14, -530), Vector2(740, 461), Control.PRESET_BOTTOM_LEFT)
	journal.mouse_filter = Control.MOUSE_FILTER_STOP
	label(journal, "일지", Vector2(14, 8), 12, Color("#a99d84"))
	menu_rule(journal, Vector2(14, 28), 712)
	ui.journal_text = journal_column(journal, Vector2(14, 36), Vector2(380, 415))
	ui.journal_text2 = journal_column(journal, Vector2(410, 36), Vector2(316, 415)) # the right column: feats and keepsakes
	var jclose := Button.new()
	jclose.text = "X"
	jclose.add_theme_font_override("font", ui_font)
	jclose.position = Vector2(710, 6)
	jclose.size = Vector2(24, 24)
	jclose.pressed.connect(func(): toggle_journal(false))
	journal.add_child(jclose)
	journal.visible = false
	ui.journal = journal
	var ways := menu_panel(root, Vector2(14, -350), Vector2(330, 220), Control.PRESET_BOTTOM_LEFT)
	var wt := label(ways, "", Vector2(16, 12), 15, Color("#e9dfc4"))
	wt.size = Vector2(300, 200)
	wt.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	ui.ways_text = wt
	ways.visible = false
	ui.ways = ways
	ui.hint = icon_button(root, "help", "H", "조작법", 14, func(): toggle_help(true))
	ui.sound_btn = icon_button(root, "sound", "M", "효과음", 66, toggle_sound)
	refresh_sound_btn()
	ui.journal_btn = icon_button(root, "journal", "Q", "일지", 118, func(): toggle_journal(not ui.journal.visible))
	ui.settings_btn = icon_button(root, "gear", "Esc", "설정", 170, func(): toggle_settings(not settings_open))
	build_settings(root)

	ui.toast = label(root, "", Vector2(0, 0), 20)
	place(ui.toast, Control.PRESET_CENTER_BOTTOM, Vector2(-300, -220), Vector2(600, 30))
	ui.toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.toast.add_theme_constant_override("outline_size", 6)
	ui.toast.add_theme_color_override("font_outline_color", Color.BLACK)

	var banner := Control.new()
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(banner)
	ui.banner_title = label(banner, "레벨 2", Vector2(-200, 120), 40)
	ui.banner_title.size = Vector2(400, 50)
	ui.banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := label(banner, "최대 체력 +12 · 공격력 +3", Vector2(-300, 170), 18)
	ui.banner_sub = sub
	for l in [ui.banner_title, sub]:
		l.add_theme_constant_override("outline_size", 8)
		l.add_theme_color_override("font_outline_color", Color("#02040b"))
	sub.size = Vector2(600, 30)
	ui.banner_title.size = Vector2(600, 50)
	ui.banner_title.position = Vector2(-300, 120)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.modulate.a = 0.0
	ui.banner = banner

	# story illustration layer (above the HUD, below the title): the picture is shown whole over a
	# dimmed, enlarged copy of itself, with a dialogue box (face, name, typewriter text) at the bottom
	var story := ColorRect.new()
	story.color = Color(0.008, 0.016, 0.043, 1.0)
	story.set_anchors_preset(Control.PRESET_FULL_RECT)
	story.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(story)
	var back := TextureRect.new()
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	back.modulate = Color(0.25, 0.28, 0.4)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story.add_child(back)
	# the illustration sits in a gold frame in the middle; the game stays visible, dimmed, around it
	var pic_frame := Control.new()
	pic_frame.set_script(load("res://frame.gd"))
	pic_frame.kind = "picture"
	pic_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story.add_child(pic_frame)
	place(pic_frame, Control.PRESET_CENTER, Vector2(-448, -330), Vector2(896, 504))
	var img := TextureRect.new()
	img.set_anchors_preset(Control.PRESET_FULL_RECT)
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	img.clip_contents = true
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic_frame.add_child(img)
	# standing portraits for talk scenes (no big picture): Sora on the left, the other speaker on the right
	for side in ["left", "right"]:
		var pr := TextureRect.new()
		pr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		story.add_child(pr)
		if side == "left":
			place(pr, Control.PRESET_BOTTOM_LEFT, Vector2(20, -640), Vector2(460, 560))
		else:
			place(pr, Control.PRESET_BOTTOM_RIGHT, Vector2(-480, -640), Vector2(460, 560))
		ui["por_" + side] = pr
	# ornate dialogue box with a name plate on its top edge
	var cap := Control.new()
	cap.set_script(load("res://frame.gd"))
	cap.kind = "box"
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story.add_child(cap)
	place(cap, Control.PRESET_CENTER_BOTTOM, Vector2(-470, -168), Vector2(940, 144))
	var tab := Control.new()
	tab.set_script(load("res://frame.gd"))
	tab.kind = "tab"
	tab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.add_child(tab)
	tab.position = Vector2(40, -18)
	tab.size = Vector2(190, 32)
	var who := label(tab, "", Vector2(0, 4), 16, Color("#f6d27a"))
	who.size = Vector2(190, 24)
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var face := TextureRect.new()
	face.position = Vector2(22, 26)
	face.size = Vector2(100, 100)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	cap.add_child(face)
	var cap_text := label(cap, "", Vector2(140, 34), 20)
	cap_text.size = Vector2(760, 90)
	cap_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var cap_hint := label(cap, "▼", Vector2(905, 116), 13, Color("#e8b018"))
	cap_hint.size = Vector2(20, 18)
	ui.story_tab = tab
	ui.story_frame = pic_frame
	ui.story_cap = cap
	ui.story_hint = cap_hint
	story.visible = false
	ui.story = story
	ui.story_img = img
	cap_text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	ui.story_text = cap_text
	ui.story_face = face
	ui.story_who = who
	ui.story_more = cap_hint

	# title screen in the house style: pixel lettering 20% from the top, gold subtitle, pale hint
	var title := ColorRect.new()
	title.color = Color(0.008, 0.016, 0.043, 0.5)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(title)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
	col.add_theme_constant_override("separation", 20)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_child(col)
	col.anchor_left = 0.0
	col.anchor_right = 1.0
	col.anchor_top = 0.2
	col.anchor_bottom = 1.0
	var logo := TextureRect.new()
	logo.texture = load("res://art/title/title.png")
	logo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR # GPT logo is drawn at high resolution
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(0, 300)
	col.add_child(logo)
	var tsub := label(col, "갈대 늪 너머, 이상한 것들이 깨어난다", Vector2.ZERO, 18, Color("#f6b951"))
	tsub.add_theme_constant_override("outline_size", 6)
	tsub.add_theme_color_override("font_outline_color", Color("#02040b"))
	tsub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var thint := label(col, "아무 키나 눌러 시작", Vector2.ZERO, 13, Color("#dfe6ff"))
	ui.title_hint = thint
	thint.add_theme_constant_override("outline_size", 6)
	thint.add_theme_color_override("font_outline_color", Color("#02040b"))
	thint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var blink := thint.create_tween().set_loops()
	blink.tween_property(thint, "modulate:a", 0.3, 0.9)
	blink.tween_property(thint, "modulate:a", 1.0, 0.9)
	ui.title = title
	for c in root.get_children():
		if c != title:
			c.visible = false
	ui.hidden_for_intro = root.get_children().filter(func(c): return c != title and c != ui.help and c != ui.journal and c != ui.ways and c != ui.settings and c != ui.boss and c != ui.shop and c != ui.shop_hint and c != ui.slowmo_tint and c != ui.story and c != ui.quest and c != ui.legacy)
	for k in ["zone", "stats"]:
		pass

# ---------------------------------------------------------------- story illustrations
# A full-screen illustration with a caption box; any key or click turns the page, the last one closes it.
var story_open := false
# story progress: 0 = not started, 1 = touch the crown (E), 2 = go to the cottage, 3 = met Bori
var story_step := 0
var dark_lamp: OmniLight3D = null
var dark_glass_mat: Material = null

# the lantern nearest the start begins dark; touching the crown lights it
func darken_first_lamp() -> void:
	var best: OmniLight3D = null
	for l in lanterns:
		if not l.has_meta("glass") or l.position.x > 100.0: # marsh street lanterns only
			continue
		if best == null or Vector2(l.position.x, l.position.z).distance_to(START) < Vector2(best.position.x, best.position.z).distance_to(START):
			best = l
	dark_lamp = best
	var glass: MeshInstance3D = best.get_meta("glass")
	dark_glass_mat = glass.material_override
	glass.material_override = mat_color(Color("#3a3428"))

func begin_opening() -> void:
	story_step = 1
	set_quest("왕관을 만져 보자 (E)")

func touch_crown() -> void:
	if story_step != 1 or dark_lamp == null:
		return
	var l := dark_lamp
	dark_lamp = null
	var glass: MeshInstance3D = l.get_meta("glass")
	glass.material_override = dark_glass_mat
	burst(l.position, Color("#ffc46a"), 24, 2.5)
	burst(Vector3(player.x, ground_y + 1.6, player.z), Color("#9fd4ff"), 14, 1.5)
	sfx(523, 0.4, "sine", 0.3, 300)
	story_step = 2
	crown_pips = maxi(0, crown_pips - 1)
	pip_flash = 0.3
	set_quest("")
	save_game()
	show_story("res://art/story/02_lantern.jpg", STORY.LANTERN)
	# a second later the brick pile beside the lamp stands up
	get_tree().create_timer(1.0).timeout.connect(func():
		spawn_enemy()
		var g: Dictionary = enemies[enemies.size() - 1]
		g.x = l.position.x + 1.2
		g.z = l.position.z + 0.8
		g.atk_cd = 1.5
		burst(Vector3(g.x, height_at(g.x, g.z) + 0.4, g.z), Color("#c9a066"), 20, 2.0)
		pop_num(Vector3(g.x, height_at(g.x, g.z) + 1.3, g.z), "!", Color("#ff5a4a"))
		sfx(110, 0.25, "square", 0.25, 80)
		get_tree().create_timer(4.0).timeout.connect(func(): set_quest("쪽지에 적힌 서쪽 오두막을 찾아가자")))

func meet_bori() -> void:
	story_step = 3
	save_game()
	set_quest("북쪽 벽돌왕을 쓰러뜨려 물길을 열어라 (상점에서 약을 챙기자)")
	show_story("", STORY.BORI)

# story step 5: the Brick King falls, the blocked waterway breaks free and a cave mouth opens
var cave_pos := Vector2(-99, -99)
var veg_meshes: Array = []

# clear grass and reeds inside a circle (e.g. around the cave mouth)
func clear_vegetation(at: Vector2, r: float) -> void:
	for mm in veg_meshes:
		for i in mm.instance_count:
			var o: Vector3 = mm.get_instance_transform(i).origin
			if Vector2(o.x, o.z).distance_to(at) < r:
				mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.001), o))

func open_cave(at: Vector2, with_story := true) -> void:
	story_step = 5
	cave_pos = at + Vector2(0, -1.5)
	clear_vegetation(cave_pos, 2.2)
	var g := Node3D.new()
	g.position = Vector3(cave_pos.x, height_at(cave_pos.x, cave_pos.y), cave_pos.y)
	add_child(g)
	# seen from above: a dark pit in the ground ringed by stone blocks, with steps going down
	var pit := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.3
	cyl.bottom_radius = 1.3
	cyl.height = 0.05
	pit.mesh = cyl
	pit.material_override = mat_color(Color("#07070c"))
	pit.position = Vector3(0, 0.03, 0)
	g.add_child(pit)
	var stone := mat_color(Color("#6a6e7a"))
	for k in 12:
		var a := TAU * k / 12.0
		var b := box(Vector3(0.55, 0.35, 0.55), stone)
		b.position = Vector3(cos(a) * 1.55, 0.17, sin(a) * 1.55)
		b.rotation.y = -a
		g.add_child(b)
	for k in 3:
		var st := box(Vector3(0.9, 0.06, 0.3), mat_color(Color("#4a4e5a").darkened(k * 0.25)))
		st.position = Vector3(0, 0.06 - k * 0.02, 0.8 - k * 0.35)
		g.add_child(st)
	var glow := OmniLight3D.new()
	glow.light_color = Color("#6aa8ff")
	glow.light_energy = 1.5
	glow.omni_range = 3.0
	glow.position = Vector3(0, 0.3, 0)
	g.add_child(glow)
	if not with_story:
		return
	burst(g.position + Vector3(0, 1, 0), Color("#9fd4ff"), 40, 4.0)
	sfx(196, 0.8, "sine", 0.3, 200)
	shake = 0.4
	save_game()
	show_story("res://art/story/05_brick_king.jpg", STORY.BOSS_FALLS)
	set_quest("땅 아래로 가는 동굴이 열렸다 (다음 장에서 계속)")

# ---------------------------------------------------------------- save
# Saved to user://save.json (on the web this lives in the browser's IndexedDB) every 5 s
# and at story beats. F9 wipes it and restarts.
var SAVE_PATH := "user://save.json"
var save_t := 0.0
var loaded := false

func save_game() -> void:
	if intro:
		return
	var boss_dead := false
	for e in enemies:
		if e.get("boss", false) and e.dead:
			boss_dead = true
	var d := {"lv": player.lv, "xp": player.xp, "max_hp": player.max_hp, "hp": player.hp, "atk": player.atk,
		"gold": player.gold, "pots": player.pots, "x": player.x, "z": player.z,
		"story": story_step, "quest": ui.quest.text, "boss_dead": boss_dead, "in_cave": in_cave, "in_village": in_village, "met": met.keys(), "pips": crown_pips, "errand": errand, "kid_q": kid_q, "doran_q": doran_q, "mul_q": mul_q, "night_q": night_q, "in_forest": in_forest, "in_garden": in_garden, "in_hill": in_hill, "hill_q": hill_q, "mills": hill.mills.map(func(mm): return mm.turning), "in_lake": in_lake, "lake_q": lake_q, "garden_q": garden_q, "forest_q": forest_q, "walls": forest.walls.map(func(w): return w.open), "stones": forest.stones.map(func(st): return st.phase), "grove": forest.solved, "grove_chest": forest.chest_open, "has_unbrick": has_unbrick, "vlit": village.dark.map(func(d): return d.lit), "cave_exit_seen": cave_exit_seen, "has_skip": has_skip, "has_key": has_key, "door_open": cave_door_open, "saw_painting": saw_painting, "hour": hour, "day": day,
		"chests": chests.map(func(c): return c.open), "scraps": marsh.found, "moon_chest": marsh.chest_open,
		"fly_q": fly_q, "flies": marsh.flies.map(func(f): return f.caught),
		"grotto_q": grotto_q, "grotto_side": grotto_side, "has_pearl": has_pearl,
		"cloud_q": cloud_q, "cloud_chest": cloud_chest, "has_feather": has_feather,
		"skill_up": skill_up, "crystal_done": crystal_done, "has_ring": has_ring, "freed": forest.freed, "has_acorn": has_acorn, "shrine_seen": shrine_seen, "trial_best": trial_best, "race_best": race_best, "books": castle.books.map(func(b): return b.read), "has_bookmark": has_bookmark, "has_shard": has_shard, "shop_bought": shop_bought, "play_secs": play_secs, "ng": ng, "fest_gift": fest_gift, "mail_q": mail_q, "mail_got": mail_got, "stats": stats, "feats": feats_done, "houses": house_seen, "flowers": marsh.picked, "has_tea": has_tea, "fish": fish_kinds, "has_shoes": has_shoes,
		"seals": garden.seals.map(func(sl): return sl.open),
		"castle_q": castle_q, "bars": castle.bars, "levers": castle.levers.map(func(lv): return lv.up), "vault": castle.vault_open, "has_armour": has_armour, "castle_gate": castle.gate_open, "castle_pages": castle.pages.map(func(pg): return pg.read)}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))

func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(d) != TYPE_DICTIONARY:
		return
	loaded = true
	for k in ["lv", "xp", "max_hp", "atk", "gold", "pots"]:
		player[k] = int(d.get(k, player[k]))
	player.hp = float(d.get("hp", player.max_hp))
	player.x = float(d.get("x", player.x))
	player.z = float(d.get("z", player.z))
	ground_y = height_at(player.x, player.z)
	hour = float(d.get("hour", hour))
	day = int(d.get("day", day))
	story_step = int(d.get("story", 0))
	var was_in_cave := bool(d.get("in_cave", false))
	crown_pips = int(d.get("pips", 8))
	errand = int(d.get("errand", 0))
	kid_q = int(d.get("kid_q", 0))
	doran_q = int(d.get("doran_q", 0))
	mul_q = int(d.get("mul_q", 0))
	night_q = int(d.get("night_q", 0))
	forest_q = int(d.get("forest_q", 0))
	garden_q = int(d.get("garden_q", 0))
	hill_q = int(d.get("hill_q", 0))
	var ms: Array = d.get("mills", [])
	for i in mini(ms.size(), hill.mills.size()):
		if ms[i]:
			hill.wind_mill(hill.mills[i], self)
	if hill_q >= 2:
		hill.raise_bridge()
	if forest_q >= 3:
		join_noeul()
	lake_q = int(d.get("lake_q", 0))
	var turtle_cut := lake_q == 3
	if lake_q == 3:
		lake_q = 2 # the turtle fight starts over from the pier
	if lake_q >= 2:
		lake.thaw()
	if lake_q >= 4:
		join_mate()
	if garden_q >= 2 and garden_q < 5:
		garden_q = 1 # the mold fight starts over when she walks back in
	var ph: Array = d.get("stones", [])
	for i in mini(ph.size(), forest.stones.size()):
		forest.stones[i].phase = int(ph[i])
		forest.show_phase(forest.stones[i])
	if bool(d.get("grove", false)):
		forest.open_gate()
	if bool(d.get("grove_chest", false)):
		forest.open_chest_look()
	var wo: Array = d.get("walls", [])
	for i in mini(wo.size(), forest.walls.size()):
		if wo[i]:
			forest.open_wall(forest.walls[i])
	if forest_q == 2:
		forest_q = 1 # the duel starts over when she walks back to the clearing
	has_unbrick = bool(d.get("has_unbrick", false))
	if night_q == 1 or night_q == 2:
		night_q = 0 # a chase cut short by quitting starts over the next night
	if night_q == 3:
		spawn_noeul_duel()
	if mul_q == 1:
		place_oar()
	for id in d.get("met", []):
		met[id] = true
	var vlit: Array = d.get("vlit", [])
	for i in mini(vlit.size(), village.dark.size()):
		if vlit[i]:
			var vd: Dictionary = village.dark[i]
			vd.lit = true
			vd.light.set_meta("dark", false)
			vd.glass.material_override = vd.glass.get_meta("lit_mat")
	if bool(d.get("in_village", false)):
		var vx: float = player.x
		var vz: float = player.z
		if vx >= HOUSE_X - 0.5: # saved inside a house: wake on the square instead
			vx = village.marks.M.x - 2.0
			vz = village.marks.M.y + 1.0
		var e0 := errand
		errand = maxi(errand, 1) # do not replay the arrival scene
		enter_village()
		errand = e0
		player.x = vx
		player.z = vz
		if kid_q > 0:
			place_kid()
	grotto_q = int(d.get("grotto_q", 0))
	if grotto_q == 2:
		grotto_q = 1 # the crab fight starts over when she walks back into the last room
	has_pearl = bool(d.get("has_pearl", false))
	grotto_side = bool(d.get("grotto_side", false))
	if grotto_side:
		grotto.opened_look(grotto.side_chest)
	if grotto_q >= 3:
		grotto.chest.visible = true
	if grotto_q >= 4:
		grotto.opened_look(grotto.chest)
	if bool(d.get("in_lake", false)):
		var lx: float = player.x
		var lz: float = player.z
		enter_lake()
		if lx >= GROTTO.GROTTO_X - 0.5:
			enter_grotto()
		player.x = lx
		player.z = lz
		if turtle_cut: # saved on the island mid-fight: back to the pier, where Mulgyeol rows again
			player.x = lake.marks.P.x
			player.z = lake.marks.P.y - 1.0
		snap_mate()
	cloud_q = int(d.get("cloud_q", 0))
	if cloud_q == 2:
		cloud_q = 1 # the scarecrow fight starts over when she walks back onto its island
	cloud_chest = bool(d.get("cloud_chest", false))
	if cloud_chest:
		cloud.opened_look()
	has_feather = bool(d.get("has_feather", false))
	skill_up = int(d.get("skill_up", -1))
	crystal_done = bool(d.get("crystal_done", false))
	has_ring = bool(d.get("has_ring", false))
	crystal_chest.visible = crystal_done and not has_ring
	var fr: Array = d.get("freed", [])
	for i in mini(fr.size(), forest.freed.size()):
		forest.freed[i] = bool(fr[i])
	has_acorn = bool(d.get("has_acorn", false))
	trial_best = float(d.get("trial_best", 0.0))
	race_best = float(d.get("race_best", 0.0))
	var bks: Array = d.get("books", [])
	for i in mini(bks.size(), castle.books.size()):
		castle.books[i].read = bool(bks[i])
	has_bookmark = bool(d.get("has_bookmark", false))
	has_shard = bool(d.get("has_shard", false))
	if has_shard:
		cloud.shard_look()
	var sb: Array = d.get("shop_bought", [])
	for i in mini(sb.size(), shop_bought.size()):
		shop_bought[i] = int(sb[i])
	play_secs = float(d.get("play_secs", 0.0))
	ng = int(d.get("ng", 0))
	fest_gift = bool(d.get("fest_gift", false))
	mail_q = int(d.get("mail_q", 0))
	var mg: Array = d.get("mail_got", [])
	for i in mini(mg.size(), mail_got.size()):
		mail_got[i] = bool(mg[i])
	var st: Dictionary = d.get("stats", {})
	for k in stats:
		stats[k] = int(st.get(k, 0))
	var fd: Array = d.get("feats", [])
	for i in mini(fd.size(), feats_done.size()):
		feats_done[i] = bool(fd[i])
	var hs: Array = d.get("houses", [])
	for i in mini(hs.size(), house_seen.size()):
		house_seen[i] = bool(hs[i])
	var fl: Array = d.get("flowers", [])
	for i in mini(fl.size(), marsh.picked.size()):
		marsh.picked[i] = bool(fl[i])
	has_tea = bool(d.get("has_tea", false))
	for k in ["has_pearl", "has_feather", "has_acorn", "has_ring", "has_shoes", "has_armour", "has_tea", "has_shard", "has_bookmark"]:
		set(k, bool(d.get(k, get(k))))
	if bool(d.get("has_armour", false)) and not castle.vault_open: # a new round keeps the armour: the treasury stays empty
		castle.open_vault_look()
	if bool(d.get("has_ring", false)):
		crystal_done = true
	var fk: Array = d.get("fish", [])
	for i in mini(fk.size(), fish_kinds.size()):
		fish_kinds[i] = bool(fk[i])
	has_shoes = bool(d.get("has_shoes", false))
	shrine_seen = bool(d.get("shrine_seen", false))
	castle_q = int(d.get("castle_q", 0))
	if castle_q == 2:
		castle_q = 1 # the knight fight starts over
	if bool(d.get("castle_gate", false)):
		castle.open_gate()
	var sls: Array = d.get("seals", [])
	for i in mini(sls.size(), garden.seals.size()):
		if bool(sls[i]):
			garden.open_seal(garden.seals[i])
	var lvs: Array = d.get("levers", [])
	for i in mini(lvs.size(), castle.levers.size()):
		if bool(lvs[i]):
			castle.flip_lever(i)
	if bool(d.get("vault", false)):
		castle.open_vault_look()
	has_armour = bool(d.get("has_armour", false))
	var cps: Array = d.get("castle_pages", [])
	for i in mini(cps.size(), castle.pages.size()):
		castle.pages[i].read = bool(cps[i])
	if castle.pages_read() == 3:
		castle.open_door()
	if bool(d.get("in_hill", false)):
		var hx: float = player.x
		var hz: float = player.z
		enter_hill()
		if hx >= CASTLE.CASTLE_X - 0.5:
			enter_castle()
		elif hx >= CLOUD.CLOUD_X - 0.5:
			enter_cloud()
		player.x = hx
		player.z = hz
		snap_mates()
	if bool(d.get("in_garden", false)):
		var gx: float = player.x
		var gz: float = player.z
		enter_garden()
		player.x = gx
		player.z = gz
	if bool(d.get("in_forest", false)):
		var fx: float = player.x
		var fz: float = player.z
		enter_forest()
		player.x = fx
		player.z = fz
	has_skip = bool(d.get("has_skip", false))
	cave_exit_seen = bool(d.get("cave_exit_seen", false))
	marsh.restore(d.get("scraps", []), bool(d.get("moon_chest", false)))
	fly_q = int(d.get("fly_q", 0))
	var fc: Array = d.get("flies", [])
	for i in mini(fc.size(), marsh.flies.size()):
		marsh.flies[i].caught = bool(fc[i])
	marsh.flies_on = fly_q == 1
	if fly_q >= 3:
		build_jar()
	var opened: Array = d.get("chests", [])
	for i in mini(opened.size(), chests.size()):
		if opened[i]:
			chests[i].open = true
			chests[i].node.modulate = Color(0.55, 0.55, 0.55)
	if story_step >= 2 and dark_lamp != null: # the first lamp was already lit
		var glass: MeshInstance3D = dark_lamp.get_meta("glass")
		glass.material_override = dark_glass_mat
		dark_lamp = null
	if d.get("boss_dead", false):
		for e in enemies:
			if e.get("boss", false) and is_instance_valid(e.node):
				e.dead = true
				e.node.queue_free()
				e.shadow.queue_free()
				open_cave(Vector2(e.x, e.z), false)
	if was_in_cave: # rebuild the cave state, then put Sora back where she saved
		var px: float = player.x
		var pz: float = player.z
		enter_cave()
		player.x = px
		player.z = pz
		has_key = bool(d.get("has_key", false))
		saw_painting = bool(d.get("saw_painting", false))
		if bool(d.get("door_open", false)) and is_instance_valid(door_node):
			cave_door_open = true
			door_node.queue_free()
			ui.mini.map_tex = cave_map_tex()
		if has_key:
			key_chest.modulate = Color(0.55, 0.55, 0.55)
	if is_instance_valid(ui.title_hint):
		ui.title_hint.text = "아무 키나 눌러 이어하기  ·  F9 처음부터"
	if story_step >= 6: # later chapters: the quest line as it was saved (older saves keep what the zone set)
		if d.has("quest"):
			set_quest(String(d.quest))
	else:
		set_quest(["", "왕관을 만져 보자 (E)", "서쪽 오두막으로 가 보자", "북쪽 벽돌왕이 늪의 물길을 막고 있다", "", "땅 아래로 가는 동굴이 열렸다"][clampi(story_step, 0, 5)])

# keep level, gold and story, but put Sora back at the starting crossing (F8)
func return_to_start() -> void:
	cam_yaw = CAM_YAW
	if not in_marsh() and ui.has("outside_map"):
		ui.mini.map_tex = ui.outside_map
	in_cave = false
	in_village = false
	in_forest = false
	in_lake = false
	in_hill = false
	in_garden = false
	in_house = -1
	gust_dir = Vector2.ZERO
	ui.boss.visible = false
	player.x = START.x
	player.z = START.y
	ground_y = height_at(START.x, START.y)
	ui.zone_name.text = "갈대늪"
	ui.zone_sub.text = "등불여울 건널목"
	toast("건널목으로 돌아왔다")
	save_game()

func reset_game() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	get_tree().reload_current_scene()

func build_cave() -> void:
	cave_grid = []
	for line in CAVE_ROWS.split("\n"):
		cave_grid.append(line)
	var floors: Array = []
	var walls: Array = []
	for z in CAVE_H:
		for x in CAVE_W:
			var c: String = cave_grid[z][x]
			var w := Vector2(CAVE_X + x, z)
			if c in "SPKDBE123":
				cave_marks[c] = w
			if c == "#":
				# only walls that touch the floor get built, to keep the count small
				var edge := false
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx: int = x + d.x
					var nz: int = z + d.y
					if nx >= 0 and nz >= 0 and nx < CAVE_W and nz < CAVE_H and cave_grid[nz][nx] != "#":
						edge = true
				if edge:
					walls.append(w)
			else:
				floors.append(w)
	# Concept E, second pass (art direction from GPT, 2026-10-23).
	# Walls on the camera side of a floor stay low so they never hide Sora; the rest stand tall
	# with irregular protrusions. Everything uses a world-space slate shader, built in 6x6 chunks
	# because the web renderer lights each mesh with at most 8 lights.
	var pool_tiles: Array = floors.filter(func(f): return cave_char(f.x, f.y) == "w")
	floors = floors.filter(func(f): return cave_char(f.x, f.y) != "w")
	var blocks: Array = [] # [Transform3D, Color]
	for w in floors:
		blocks.append([Transform3D(Basis().scaled(Vector3(1, 0.4, 1)), Vector3(w.x, -0.2, w.y)), Color(1.15, 1.15, 1.2)])
	for w in walls:
		var camera_side := cave_char(w.x, w.y - 1) != "#" or cave_char(w.x, w.y - 2) != "#" # floor within two tiles north: this wall is in front
		var h := 0.35 if camera_side else rnd(2.4, 3.0)
		blocks.append([Transform3D(Basis().scaled(Vector3(1, h, 1)), Vector3(w.x, h / 2.0, w.y)), Color(1, 1, 1)])
		if not camera_side and rng.randf() < 0.6: # a jutting stone on the face
			var j := rnd(0.4, 0.6)
			var off := Vector3(rnd(-0.25, 0.25), rnd(0.3, h - 0.4), rnd(-0.25, 0.25))
			for d in [Vector2(0, 1), Vector2(1, 0), Vector2(-1, 0)]:
				if cave_char(w.x + d.x, w.y + d.y) != "#":
					off += Vector3(d.x, 0, d.y) * 0.5
					break
			blocks.append([Transform3D(Basis(Vector3.UP, rnd(0, 0.6)).scaled(Vector3(j, j, j)), Vector3(w.x, 0, w.y) + off), Color(1.1, 1.1, 1.1)])
	var stone := ShaderMaterial.new()
	stone.shader = load("res://shaders/cave_stone.gdshader")
	var chunks := {}
	for bl in blocks:
		var o: Vector3 = bl[0].origin
		var key := Vector2i(int(o.x - CAVE_X) / 6, int(o.z) / 6)
		if not chunks.has(key):
			chunks[key] = []
		chunks[key].append(bl)
	for key in chunks:
		var list: Array = chunks[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = BoxMesh.new()
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i][0])
			mm.set_instance_color(i, list[i][1])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = stone
		add_child(mmi)
	# glowing pools, sunk 0.15 below the floor
	var pool := ShaderMaterial.new()
	pool.shader = load("res://shaders/cave_pool.gdshader")
	for t2 in pool_tiles:
		var pb := box(Vector3(1, 0.1, 1), pool)
		pb.position = Vector3(t2.x, -0.2, t2.y)
		add_child(pb)
	if not pool_tiles.is_empty():
		var c := Vector2.ZERO
		for t2 in pool_tiles:
			c += t2
		c /= pool_tiles.size()
		var pl := OmniLight3D.new()
		pl.light_color = Color("#25dce8")
		pl.light_energy = 1.6
		pl.omni_range = 4.5
		pl.position = Vector3(c.x, 0.5, c.y)
		add_child(pl)
	# crystals: five-sided cones in clusters of three at the foot of the back walls; violet mushrooms in pairs
	var wall_feet: Array = floors.filter(func(f): return cave_char(f.x, f.y - 1) == "#" or cave_char(f.x - 1, f.y) == "#" or cave_char(f.x + 1, f.y) == "#")
	wall_feet.shuffle()
	var teal := StandardMaterial3D.new()
	teal.albedo_color = Color("#55efff")
	teal.emission_enabled = true
	teal.emission = Color("#55efff")
	teal.emission_energy_multiplier = 2.5
	var violet := teal.duplicate()
	violet.albedo_color = Color("#c35beb")
	violet.emission = Color("#c35beb")
	violet.emission_energy_multiplier = 1.5
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.12
	cone.height = 0.7
	cone.radial_segments = 5
	cone.rings = 1
	for i in mini(14, wall_feet.size()):
		var w: Vector2 = wall_feet[i]
		var cl := Node3D.new()
		cl.position = Vector3(w.x + rnd(-0.2, 0.2), 0.0, w.y + rnd(-0.2, 0.2))
		add_child(cl)
		for k in 3:
			var sc := rnd(0.6, 1.2)
			var sh := MeshInstance3D.new()
			sh.mesh = cone
			sh.material_override = teal
			sh.scale = Vector3.ONE * sc
			sh.position = Vector3(rnd(-0.18, 0.18), 0.35 * sc, rnd(-0.18, 0.18))
			sh.rotation = Vector3(rnd(-0.35, 0.35), rnd(0, TAU), rnd(-0.35, 0.35))
			cl.add_child(sh)
		var cll := OmniLight3D.new()
		cll.light_color = Color("#55efff")
		cll.light_energy = 1.2
		cll.omni_range = 3.0
		cll.position = Vector3(0, 0.6, 0)
		cl.add_child(cll)
	for i in range(14, mini(30, wall_feet.size())):
		var w: Vector2 = wall_feet[i]
		for k in 2:
			var at := Vector3(w.x + rnd(-0.3, 0.3), 0, w.y + rnd(-0.3, 0.3))
			var stem := box(Vector3(0.05, 0.16, 0.05), mat_color(Color("#d8d0e8")))
			stem.position = at + Vector3(0, 0.08, 0)
			add_child(stem)
			var capm := box(Vector3(0.2, 0.07, 0.2), violet)
			capm.position = at + Vector3(0, 0.18, 0)
			add_child(capm)
		if i % 4 == 0:
			var vl := OmniLight3D.new()
			vl.light_color = Color("#c35beb")
			vl.light_energy = 0.6
			vl.omni_range = 2.0
			vl.position = Vector3(w.x, 0.4, w.y)
			add_child(vl)
	# rubble along the walls gives a sense of scale
	var rubble_mat := ShaderMaterial.new()
	rubble_mat.shader = load("res://shaders/cave_stone.gdshader")
	rubble_mat.set_shader_parameter("lift", 2.2)
	for i in 50:
		var w: Vector2 = wall_feet[rng.randi() % wall_feet.size()]
		var r := rnd(0.12, 0.3)
		var rb := box(Vector3(r, r * 0.7, r), rubble_mat)
		rb.position = Vector3(w.x + rnd(-0.35, 0.35), r * 0.35, w.y + rnd(-0.35, 0.35))
		rb.rotation.y = rnd(0, PI)
		add_child(rb)
	# low mist drifting over the floor
	var mist := CPUParticles3D.new()
	mist.amount = 60
	mist.lifetime = 8.0
	mist.preprocess = 8.0
	mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	mist.emission_box_extents = Vector3(CAVE_W / 2.0, 0.1, CAVE_H / 2.0)
	mist.position = Vector3(CAVE_X + CAVE_W / 2.0, 0.25, CAVE_H / 2.0)
	mist.direction = Vector3(1, 0, 0)
	mist.spread = 30.0
	mist.initial_velocity_min = 0.05
	mist.initial_velocity_max = 0.2
	mist.gravity = Vector3.ZERO
	mist.scale_amount_min = 3.0
	mist.scale_amount_max = 5.0
	var mq := QuadMesh.new()
	mq.size = Vector2(1, 1)
	var mm2 := StandardMaterial3D.new()
	mm2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm2.albedo_color = Color(0.55, 0.75, 1.0, 0.06)
	mm2.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mq.material = mm2
	mist.mesh = mq
	add_child(mist)
	# exit light at E
	var e: Vector2 = cave_marks.E
	var l := OmniLight3D.new()
	l.light_color = Color("#ffe0a0")
	l.light_energy = 3.0
	l.omni_range = 5.0
	l.position = Vector3(e.x - 0.5, 1.0, e.y)
	add_child(l)
	cave_light = OmniLight3D.new()
	cave_light.light_color = Color("#a8c8ff")
	cave_light.omni_range = 9.0
	cave_light.light_energy = 0.0
	add_child(cave_light)

var cave_light: OmniLight3D

# ---------------------------------------------------------------- village (story step 8)
const VILLAGE := preload("res://village.gd")
var village = VILLAGE.new()
const FOREST := preload("res://forest.gd")
var forest = FOREST.new()
var in_forest := false
const HILL := preload("res://hill.gd")
var hill = HILL.new()
var in_hill := false
var hill_q := 0            # 0 never entered, 1 winding the mills, 2 bridge up, 3 hawk beaten
var mate2: Node3D          # Noeul as a second companion (after he turns in the forest)
var mate2_cd := 0.0
const LAKE := preload("res://lake.gd")
var lake = LAKE.new()
var in_lake := false
var lake_q := 0            # 0 not yet, 1 at the lake, 2 thawed, 3 on the island (turtle), 4 Mulgyeol joined
var lake_npc: Sprite3D     # Mulgyeol waiting on the pier before he joins
var mate: Node3D           # Mulgyeol as a companion
var mate_cd := 0.0
const GARDEN := preload("res://garden.gd")
const MARSH := preload("res://marsh.gd")
const GROTTO := preload("res://grotto.gd")
const CLOUD := preload("res://cloud.gd")
const CASTLE := preload("res://castle.gd")
var castle = CASTLE.new()   # 가라앉은 달지기 성 between the hill and the garden (Sora is still in_hill in there)
var castle_q := 0           # 0 never entered, 1 inside, 2 fighting the knight, 3 knight beaten (east gate open)
var castle_spawned := false
var has_armour := false
var has_bookmark := false   # 달지기 책갈피 for reading all five library books: experience x1.2
var has_tea := false        # 달꽃 차 from Bori: resting fills a pip in 6 s by a lantern (12 s with the jar)     # 달지기 갑옷 from the castle treasury: damage taken x0.85
var cloud = CLOUD.new()     # 구름 둔덕 above the hill (Sora is still in_hill up there)
var cloud_q := 0            # 0 never entered, 1 inside, 2 fighting the scarecrow, 3 scarecrow beaten
var cloud_chest := false
var cloud_spawned := false
var has_feather := false    # 바람 깃털: a dodge costs 15 stamina instead of 25
var gust_dir := Vector2.ZERO # a wind vent is carrying Sora this way
var gust_t := 0.0
var gust_gap := false
var gust_solid := 0.0
var on_vent_prev := false
var grotto = GROTTO.new()   # 물빛 동굴 under Mulgyeol's island (Sora is still in_lake down there)
var grotto_q := 0           # 0 never entered, 1 inside, 2 fighting the crab, 3 crab beaten, 4 pearl taken
var grotto_side := false    # the side-room chest is open
var grotto_spawned := false
var has_pearl := false      # 물빛 진주: stamina refills 1.5 times as fast
var marsh = MARSH.new()     # the map scraps and the moonkeeper chest
var garden = GARDEN.new()
var in_garden := false
var garden_q := 0          # 0 never entered, 1 inside, 2 fighting the mold, 3 the villagers' lights are coming, 4 ready to wind, 5 wound (the end)
var mold_wave := {}        # the mold's expanding shock ring: {"r": radius, "node": MeshInstance3D}
var ring_k := -1           # the ring post the villagers are lighting now (-1: not lighting)
var ring_t := 0.0          # seconds spent on this post
var forest_q := 0          # 0 never entered, 1 walking the forest, 2 second duel, 3 Noeul turned
var in_village := false
var crown_pips := 8        # the crown's moon gauge, 0..8
var pip_flash := 0.0
var rest_t := 0.0
var met := {}               # villagers already greeted
var errand := 0            # 0 not given, 1 lighting lanterns, 2 lanterns done, 3 rewarded
var kid_q := 0             # Kongal's errand: 0 not given, 1 find the kid goblin, 2 it follows Sora, 3 home
var kid_node: Node3D
var fly_q := 0             # errand 5, the kid's firefly jar: 0 not given, 1 catching, 2 caught five, 3 jar lent to Sora
var jar_node: Node3D       # Sora's firefly jar, a little glow at her side after dark once fly_q is 3
var mul_q := 0             # Mulgyeol's oar: 0 not given, 1 fetch it from the NW pond, 2 carrying it, 3 returned
var oar_node: Node3D
const OAR_AT := Vector2(9.0, 11.0) # middle of the north-west marsh pond, reachable only by water skip
var night_q := 0           # the lantern night: 0 not yet, 1 chasing Noeul, 2 fell, 3 duel, 4 won
var has_unbrick := false   # crown power 3 (벽돌 풀기), granted after the duel
var noeul_node: Node3D     # Noeul during the chase (the duel uses an enemy entry)
var noeul_way := 0
var after_story := Callable() # runs once when the current story closes
const NOEUL_WAY := [Vector2(16, 6), Vector2(20, 6), Vector2(24, 7), Vector2(27, 10), Vector2(28, 15), Vector2(29, 18)]
const NOEUL_DUEL_AT := Vector2(28, 12)
var doran_q := 0           # Doran's letter: 0 not given, 1 read it with the crown, 2 carry it to Bori, 3 delivered

func enter_village() -> void:
	in_village = true
	story_step = maxi(story_step, 8)
	var sp: Vector2 = village.marks.S
	player.x = sp.x
	player.z = sp.y
	ground_y = 0.0
	if not ui.has("outside_map"):
		ui.outside_map = ui.mini.map_tex
	ui.mini.map_tex = village.map_tex(VILLAGE.VILLAGE_X + VILLAGE.W)
	ui.zone_name.text = "등불 마을"
	ui.zone_sub.text = "돌 광장"
	save_game()
	if errand == 0:
		set_quest("광장의 등불지기에게 말을 걸자 (E)")
		show_story("", STORY.VILLAGE)

func leave_village() -> void:
	in_village = false
	player.x = 44.0
	player.z = 20.0
	ground_y = height_at(player.x, player.z)
	if ui.has("outside_map"):
		ui.mini.map_tex = ui.outside_map
	ui.zone_name.text = "갈대늪"
	ui.zone_sub.text = "동쪽 물가"
	save_game()

func lamp_cost() -> int:
	return 1 if is_night() else 2 # the crown is half as strong by day

func spend_pips(n: int) -> bool:
	if crown_pips < n:
		toast("눈금이 모자라. 밤에 켜진 등불 곁에서 쉬자")
		return false
	crown_pips -= n
	pip_flash = 0.3
	return true

# E key: talk to Simji, light a dark village lantern, or (in the marsh opening) touch the crown
func crown_key() -> void:
	var me := Vector2(player.x, player.z)
	if way_key():
		return
	if in_marsh() and near_shop(): # Bori answers to E like every other villager (Space still works)
		interact()
		return
	if in_cave and shrine_key():
		return
	if in_forest:
		if grove_key():
			return
		if try_unbrick():
			return
	if ng_key():
		return
	if in_garden and garden_q == 4:
		final_wind()
		return
	if in_garden and garden_q == 1 and seal_key():
		return
	if in_grotto() and grotto_key():
		return
	if in_cloud() and cloud_key():
		return
	if in_castle() and castle_key():
		return
	if in_lake and not in_grotto() and fish_key():
		return
	if in_lake and not in_grotto() and Vector2(player.x, player.z).distance_to(lake.marks.h) < 2.0 and deliver(2, STORY.MAIL_HUT):
		return
	if in_lake and lake_key():
		return
	if in_hill and race_key():
		return
	if in_hill and hill_key():
		return
	if in_village:
		if cupboard_key():
			return
		if trial_key():
			return
		if me.distance_to(village.marks.M) < 1.8 and deliver(1, STORY.MAIL_SIMJI):
			return
		if festival_key():
			return
		if me.distance_to(village.marks.M) < 1.8:
			if errand == 0:
				errand = 1
				show_story("", STORY.SIMJI)
				set_quest("동쪽 끝 꺼진 등불을 왕관으로 켜자 (E) 0/3")
			elif errand == 2:
				errand = 3
				crown_pips = 8
				player.gold += 60
				player.pots += 1
				show_story("", STORY.SIMJI_DONE)
				set_quest("광장 서쪽의 콩알이 울고 있다. 말을 걸어 보자 (E)")
			save_game()
			return
		for id in village.folk_pos:
			if me.distance_to(village.folk_pos[id]) < 1.6:
				if id == "kongal" and errand >= 3 and kid_q != 1 and (kid_q != 3 or doran_q < 3 or fly_q < 3):
					kongal_errand()
					return
				if id == "mulgyeol" and doran_q >= 3 and mul_q != 1:
					mulgyeol_errand()
					return
				if id == "doran" and kid_q >= 3 and doran_q < 2:
					doran_errand()
					return
				if id == "doran" and doran_q >= 3 and lake_q >= 4 and mail_q < 2 and mail_errand():
					met[id] = true
					return
				folk_talk(id)
				met[id] = true
				save_game()
				return
		if errand == 1:
			for d in village.dark:
				if not d.lit and me.distance_to(d.pos) < 1.6:
					if not spend_pips(lamp_cost()):
						return
					light_village_lamp(d)
					return
	touch_crown()

# errand 2: Kongal's kid goblin was dragged to the south field by three goblins
func kongal_errand() -> void:
	if kid_q == 0:
		kid_q = 1
		show_story("", STORY.KONGAL_LOST)
		set_quest("남쪽 들판에서 꼬마 고블린을 찾자")
		place_kid()
	elif kid_q == 2:
		kid_q = 3
		player.gold += 40
		player.pots += 1
		show_story("", STORY.KONGAL_DONE)
		set_quest("우편배달부 도란에게 말을 걸어 보자 (E)")
		place_kid()
	elif kid_q >= 3 and doran_q >= 3 and fly_q == 0:
		fly_q = 1
		marsh.flies_on = true
		show_story("", STORY.FLY_ASK)
	elif fly_q == 1:
		show_story("", STORY.FOLK_AGAIN.kongal_fly)
	elif fly_q == 2:
		fly_q = 3
		player.gold += 30
		show_story("", STORY.FLY_DONE)
		build_jar()
	else:
		folk_talk("kongal")
	save_game()

# first meeting: the long introduction; afterwards a short line that follows their errand
func folk_talk(id: String) -> void:
	if not met.has(id):
		show_story("", STORY.FOLK[id])
		return
	var q := {"doran": doran_q, "kongal": kid_q, "mulgyeol": mul_q}[id] as int
	var key := id + ("_done" if q >= 3 else ("_carry" if id == "doran" and q == 2 else ("_search" if q == 1 and id != "doran" else "_wait")))
	show_story("", STORY.FOLK_AGAIN[key])

# errand 3: the crown loosens the first line of Doran's century-old letter; it is for Bori
func doran_errand() -> void:
	if doran_q == 0:
		doran_q = 1
		show_story("", STORY.DORAN_ASK)
		set_quest("도란의 편지에 왕관을 대 보자 (E, 달빛 눈금 사용)")
	elif spend_pips(lamp_cost()):
		doran_q = 2
		burst(Vector3(player.x, 1.4, player.z), Color("#9fd4ff"), 18, 1.5)
		sfx(587, 0.4, "sine", 0.3, 300)
		show_story("", STORY.DORAN_READ)
		set_quest("편지를 서쪽 늪 오두막의 보리 할머니께 전하자 (E)")
	else:
		return
	save_game()

func deliver_letter() -> void:
	doran_q = 3
	crown_pips = 8
	player.max_hp += 10
	player.hp = float(player.max_hp)
	show_story("", STORY.BORI_LETTER)
	set_quest("마을의 뱃사공 물결에게 가 보자 (E)")
	save_game()

# errand 4: Mulgyeol's oar floats in the middle of the half-hardened NW pond
func mulgyeol_errand() -> void:
	if mul_q == 0:
		mul_q = 1
		show_story("", STORY.MUL_ASK)
		set_quest("늪 북서쪽 연못 한가운데의 노를 건져 오자 (Shift로 물 위 달리기)")
		place_oar()
	elif mul_q == 2:
		mul_q = 3
		player.gold += 50
		show_story("", STORY.MUL_DONE)
		set_quest("마을 심부름을 모두 마쳤다. 밤이 되면 마을에서 쉬자")
	else:
		folk_talk("mulgyeol")
	save_game()

func place_oar() -> void:
	if oar_node != null:
		return
	oar_node = Node3D.new()
	var wood: Material = mat_color(Color("#8a5a2e"))
	for part in [[Vector3(0.08, 0.08, 1.6), Vector3(0, 0, 0)], [Vector3(0.3, 0.06, 0.5), Vector3(0, 0, 0.95)]]:
		var b: MeshInstance3D = box(part[0], wood)
		b.position = part[1]
		oar_node.add_child(b)
	var glow := OmniLight3D.new() # a faint glint so it can be spotted from the shore
	glow.light_color = Color("#bfe6ff")
	glow.light_energy = 1.2
	glow.omni_range = 3.0
	glow.position = Vector3(0, 0.8, 0)
	oar_node.add_child(glow)
	oar_node.position = Vector3(OAR_AT.x, -0.15, OAR_AT.y)
	oar_node.rotation.y = 0.7
	add_child(oar_node)

func update_oar() -> void:
	if oar_node == null or not oar_node.visible:
		return
	oar_node.position.y = -0.15 + sin(t * 2.0) * 0.04
	if mul_q == 1 and not in_village and not in_cave and Vector2(player.x, player.z).distance_to(OAR_AT) < 1.4:
		mul_q = 2
		oar_node.visible = false
		burst(Vector3(player.x, 0.4, player.z), Color("#9fe0ff"), 18, 1.5)
		sfx(659, 0.3, "triangle", 0.25)
		toast("물결의 노를 건졌다")
		set_quest("노를 마을의 물결에게 가져가자 (E)")
		for at in [Vector2(6, 15), Vector2(12, 15)]: # the bricks on the shore wake up
			spawn_enemy(at)
		save_game()

# ---- the lantern night (story step 9)
# companions and Noeul are drawn facing screen-right; the camera is turned, so "left" must be judged on screen,
# not by world x (walking toward the bottom of the screen has a leftward screen component)
func screen_left(v: Vector2) -> bool:
	return v.dot(Vector2(cos(cam_yaw), -sin(cam_yaw))) < 0.0

func noeul_sprite() -> Sprite3D:
	var spr := Sprite3D.new() # GPT pixel sprite: 0 arms crossed, 1 running, 2 casting
	spr.texture = load("res://art/folk/noeul.png")
	spr.hframes = 3
	spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	spr.scale = Vector3(1, 1.0 / cos(0.78), 1)
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	spr.shaded = false
	spr.pixel_size = 1.8 / 180.0
	spr.offset = Vector2(0, 90)
	return spr

func village_lamps() -> Array:
	return lanterns.filter(func(l): return l.position.x > VILLAGE.VILLAGE_X - 1.0 and l.position.x < VILLAGE.VILLAGE_X + VILLAGE.W + 1.0)

func set_village_lamps(on: bool) -> void:
	for l in village_lamps():
		var g: MeshInstance3D = l.get_meta("glass")
		if not g.has_meta("lit_mat"):
			g.set_meta("lit_mat", g.material_override)
		g.material_override = g.get_meta("lit_mat") if on else mat_color(Color("#3a3428"))
		l.visible = on
		l.set_meta("dark", not on)
	if on:
		for d in village.dark:
			d.lit = true

func start_night() -> void:
	night_q = 1
	story_step = maxi(story_step, 9)
	set_village_lamps(false)
	noeul_way = 0
	if noeul_node == null:
		noeul_node = Node3D.new()
		noeul_node.add_child(noeul_sprite())
		add_child(noeul_node)
	var p: Vector2 = NOEUL_WAY[0]
	noeul_node.position = Vector3(VILLAGE.VILLAGE_X + p.x, 0, p.y)
	noeul_node.visible = true
	show_story("", STORY.NOEUL_COMES)
	set_quest("등불을 끈 노을을 쫓자 (Shift로 달리기)")
	save_game()

# Noeul keeps a few steps ahead of Sora along the path; at the last point he turns and she falls
func update_night(dt: float) -> void:
	var night_now := is_night()
	if in_village and in_house < 0 and night_q == 0 and mul_q == 3 and night_now and not story_open and fade_rect.color.a == 0.0:
		start_night()
	if night_q != 1 or noeul_node == null or story_open:
		return
	var me := Vector2(player.x, player.z)
	var at := Vector2(noeul_node.position.x, noeul_node.position.z)
	var spr: Sprite3D = noeul_node.get_child(0)
	var last := noeul_way >= NOEUL_WAY.size() - 1
	if not last and me.distance_to(at) < 4.5:
		var w: Vector2 = NOEUL_WAY[noeul_way + 1] + Vector2(VILLAGE.VILLAGE_X, 0)
		var step := w - at
		if step.length() < 0.2:
			noeul_way += 1
		else:
			at += step.normalized() * minf(step.length(), dt * 4.8)
		spr.frame = 1
		spr.flip_h = screen_left(Vector2(step.x, step.y))
	else:
		spr.frame = 0
	noeul_node.position = Vector3(at.x, 0, at.y)
	if last and me.distance_to(at) < 1.8:
		night_fall()

func night_fall() -> void:
	night_q = 2
	noeul_node.get_child(0).frame = 2
	burst(noeul_node.position + Vector3(0, 1.0, 0), Color("#8a8a8a"), 30, 3.0)
	shake = 0.3
	sfx(90, 0.5, "sawtooth", 0.25, -40)
	show_story("res://art/story/08_dark_night.jpg", STORY.NIGHT_FALL)
	after_story = rise_together
	save_game()

func rise_together() -> void:
	noeul_node.visible = false
	player.x = village.marks.M.x - 1.5
	player.z = village.marks.M.y + 1.5
	player.hp = float(player.max_hp)
	crown_pips = 8
	set_village_lamps(true)
	burst(Vector3(player.x, 1.6, player.z), Color("#ffc46a"), 40, 4.0)
	night_q = 3
	show_story("res://art/story/09_rise_together.jpg", STORY.RISE_TOGETHER)
	after_story = spawn_noeul_duel
	set_quest("동쪽 들판의 노을과 겨루자")
	save_game()

func spawn_noeul_duel(second := false) -> void:
	if enemies.any(func(e): return e.get("noeul", false) and not e.dead):
		return
	var at: Vector2 = forest.marks.N if second else NOEUL_DUEL_AT + Vector2(VILLAGE.VILLAGE_X, 0)
	var node := Node3D.new()
	node.add_child(noeul_sprite())
	add_child(node)
	var hp := 830.0 if second else 550.0
	enemies.append({"x": at.x, "z": at.y, "hp": hp, "max_hp": int(hp), "node": node, "shadow": blob(0.8), "t": 0.0,
		"atk_cd": 2.0, "hurt": 0.0, "kx": 0.0, "kz": 0.0, "wx": at.x, "wz": at.y, "dead": false, "respawn": 0.0,
		"noeul": true, "second": second, "cave": true, "wind": 0.0, "dash": 0.0, "dir": Vector2.ZERO, "stun": 0.0, "next": "dash", "rings": []})

# Noeul's duel: a quick telegraphed dash, then rings of brick dust around Sora; below half HP, three rings
func update_noeul(e: Dictionary, dt: float, d: float, to: Vector2) -> void:
	var node: Node3D = e.node
	var spr: Sprite3D = node.get_child(0)
	var awake := d < 9.0
	ui.boss.visible = awake or (ui.boss.visible and d < 13.0)
	ui.boss_name.text = "노을"
	ui.boss_bar.size.x = 420.0 * maxf(0.0, e.hp) / e.max_hp
	e.t += dt
	e.hurt -= dt
	e.stun -= dt
	spr.modulate = Color(1.6, 1.4, 1.4) if e.hurt > 0.0 else Color.WHITE
	if e.dash > 0.0:
		e.dash -= dt
		var nx: float = e.x + e.dir.x * 11.0 * dt
		var nz: float = e.z + e.dir.y * 11.0 * dt
		if walkable(nx, nz):
			e.x = nx
			e.z = nz
			if Vector2(player.x - e.x, player.z - e.z).length() < 0.9:
				player_hit(20, Vector2(e.x, e.z) - e.dir, e)
		else:
			e.dash = 0.0
		spr.frame = 1
	elif e.stun > 0.0:
		spr.frame = 0
	elif e.wind > 0.0:
		e.wind -= dt
		spr.frame = 2 if e.next == "dust" else 1
		if e.wind <= 0.0:
			if e.next == "dash":
				e.dash = 0.45
				e.next = "dust"
			else:
				for r in e.rings:
					burst(Vector3(r.x, 0.3, r.y), Color("#9a9a9a"), 18, 3.0)
					if Vector2(player.x, player.z).distance_to(r) < 1.2:
						player_hit(16, r, e)
				sfx(110, 0.25, "square", 0.2, -40)
				e.next = "dash"
			e.atk_cd = 1.15
	elif awake:
		spr.frame = 0
		e.atk_cd -= dt
		if e.atk_cd <= 0.0:
			if e.next == "dash":
				e.wind = 0.55
				e.dir = to / maxf(d, 0.01)
				pop_num(Vector3(e.x, 2.4, e.z), "!", Color("#ff5a4a"))
				sfx(160, 0.4, "sawtooth", 0.2, 160)
			else:
				e.wind = 0.8
				e.rings = [Vector2(player.x, player.z)]
				if e.hp < e.max_hp / 2.0 or e.get("second", false):
					for k in (4 if e.get("second", false) and e.hp < e.max_hp / 2.0 else 2):
						e.rings.append(Vector2(player.x, player.z) + Vector2(rnd(-2.2, 2.2), rnd(-2.2, 2.2)))
				for r in e.rings:
					warn_ring(Vector3(r.x, 0.0, r.y), 1.2, 0.8)
		elif d < 3.0: # keeps his distance
			var nx: float = e.x - to.x / d * 2.0 * dt
			var nz: float = e.z - to.y / d * 2.0 * dt
			if walkable(nx, e.z): e.x = nx
			if walkable(e.x, nz): e.z = nz
	spr.flip_h = screen_left(e.dir if e.dash > 0.0 else to)
	node.position = Vector3(e.x, 0, e.z)
	e.shadow.position = Vector3(e.x, 0.02, e.z)

func noeul_beaten() -> void:
	night_q = 4
	has_unbrick = true
	ui.boss.visible = false
	player.gold += 100
	gain_xp(150)
	set_quest("물결과 함께 남쪽 호수를 풀자 (마을 남쪽 문)")
	show_story("", STORY.NOEUL_LOSES)
	save_game()

# ---- the hardened forest (story step 10)
func enter_forest() -> void:
	in_village = false
	in_forest = true
	story_step = maxi(story_step, 10)
	player.x = forest.marks.S.x + 1.2
	player.z = forest.marks.S.y
	ground_y = 0.0
	if not ui.has("outside_map"):
		ui.outside_map = ui.mini.map_tex
	ui.mini.map_tex = forest.map_tex(FOREST.FOREST_X + FOREST.W)
	ui.zone_name.text = "굳은 숲"
	ui.zone_sub.text = "회색 오솔길"
	if forest_q == 0:
		forest_q = 1
		for g in forest.goblins:
			spawn_enemy(g)
			enemies[enemies.size() - 1].cave = true
		for w in forest.wolves:
			spawn_wolf(w)
		show_story("", STORY.FOREST_IN)
	spawn_cages()
	if forest_q < 3:
		set_quest("벽돌 벽을 왕관으로 풀며 숲 동쪽 끝의 노을에게 가자 (E)")
	save_game()

func leave_forest() -> void:
	in_forest = false
	in_village = true
	player.x = village.marks.F.x - 1.2
	player.z = village.marks.F.y
	ground_y = 0.0
	ui.mini.map_tex = village.map_tex(VILLAGE.VILLAGE_X + VILLAGE.W)
	ui.zone_name.text = "등불 마을"
	ui.zone_sub.text = "동쪽 문"
	save_game()

func unbrick_cost() -> int:
	return 2 if is_night() else 3 # the crown is weaker by day

# E next to a closed brick wall: the crown turns it back into soil, and the noise wakes nearby bricks
func try_unbrick() -> bool:
	for w in forest.walls:
		if not w.open and Vector2(player.x, player.z).distance_to(w.pos) < 1.6:
			if not spend_pips(unbrick_cost()):
				return true
			forest.open_wall(w)
			burst(Vector3(w.pos.x, 0.7, w.pos.y), Color("#8a6a4a"), 36, 3.5)
			burst(Vector3(player.x, 1.6, player.z), Color("#9fd4ff"), 14, 1.5)
			shake = 0.25
			sfx(196, 0.5, "triangle", 0.3, -60)
			toast("벽돌 벽이 흙으로 풀렸다")
			save_game()
			return true
	return false

# the moon-stone grove in the forest's north-west: E turns a stone to the next phase, reads the tablet,
# or opens the niche chest once the stones read crescent to full from east to west
func grove_key() -> bool:
	var me := Vector2(player.x, player.z)
	if forest.solved and not forest.chest_open and me.distance_to(forest.marks.c) < 1.6:
		open_grove_chest()
		return true
	var near = null # the closest stone within reach
	for st in forest.stones:
		if me.distance_to(st.pos) < 1.3 and (near == null or me.distance_to(st.pos) < me.distance_to(near.pos)):
			near = st
	var tablet_d := me.distance_to(forest.marks.t)
	if tablet_d < 1.6 and (near == null or tablet_d < me.distance_to(near.pos)):
		show_story("", STORY.GROVE_TABLET)
		return true
	if near == null:
		return false
	near.phase = (near.phase + 1) % 4
	forest.show_phase(near)
	sfx(392 + near.phase * 98, 0.15, "triangle", 0.2)
	burst(Vector3(near.pos.x, 1.3, near.pos.y), Color("#dfe8ff"), 8, 1.0)
	if not forest.solved and forest.is_solved():
		forest.open_gate()
		burst(Vector3(forest.marks.V.x, 0.7, forest.marks.V.y), Color("#8a6a4a"), 36, 3.5)
		shake = 0.25
		sfx(196, 0.5, "triangle", 0.3, -60)
		show_story("", STORY.GROVE_OPEN)
	save_game()
	return true

func open_grove_chest() -> void:
	forest.open_chest_look()
	player.max_hp += 15
	player.hp = float(player.max_hp)
	player.pots += 2
	player.gold += 120
	burst(Vector3(forest.marks.c.x, 0.8, forest.marks.c.y), Color("#e8d27a"), 40, 3.0)
	sfx(784, 0.12, "triangle", 0.25)
	show_story("", STORY.GROVE_CHEST)
	toast("최대 체력 +15, 회복약 2개, 금화 120")
	save_game()

# ---- five squirrels shut in brick cages around the forest: three sword hits break a cage.
# Freeing all five gets the acorn: potions heal 65 instead of 45. Companions leave the cages to Sora.
var cages_spawned := false
var has_acorn := false

func spawn_cages() -> void:
	if cages_spawned:
		return
	cages_spawned = true
	for i in FOREST.CAGES.size():
		if forest.freed[i]:
			continue
		var at: Vector2 = FOREST.CAGES[i] + Vector2(FOREST.FOREST_X, 0)
		var root := Node3D.new()
		var g := Node3D.new()
		root.add_child(g)
		var mats: Array = []
		brick(g, mats, Vector3(0.8, 0.1, 0.8), Vector3(0, 0.05, 0), Color("#8a8a90"))
		brick(g, mats, Vector3(0.8, 0.1, 0.8), Vector3(0, 0.85, 0), Color("#a8322a"))
		for k in 4: # bars at the corners
			brick(g, mats, Vector3(0.1, 0.7, 0.1), Vector3(-0.35 + (k % 2) * 0.7, 0.45, -0.35 + (k / 2) * 0.7), Color("#8a8a90"), false)
		var fur := mat_color(Color("#c8783a")) # the squirrel inside, sitting up with its tail curled
		for part in [[Vector3(0.22, 0.26, 0.2), Vector3(0, 0.25, 0)], [Vector3(0.18, 0.16, 0.18), Vector3(0, 0.45, 0.04)], [Vector3(0.14, 0.34, 0.12), Vector3(0, 0.36, -0.18)]]:
			var b := box(part[0], fur)
			b.position = part[1]
			g.add_child(b)
		add_child(root)
		root.position = Vector3(at.x, 0, at.y)
		enemies.append({"x": at.x, "z": at.y, "hp": 3.0, "max_hp": 3, "node": root, "shadow": blob(0.6), "t": 0.0,
			"atk_cd": 99.0, "hurt": 0.0, "kx": 0.0, "kz": 0.0, "wx": at.x, "wz": at.y, "dead": false, "respawn": 0.0,
			"cage": i, "cave": true, "prop": true})
		root.set_meta("mats", mats)
		root.set_meta("body", g)

func cage_hit(e: Dictionary) -> void:
	e.hp -= 1.0
	e.hurt = 0.12
	burst(Vector3(e.x, 0.6, e.z), Color("#a8322a"), 8, 2.0)
	sfx(500, 0.06, "square", 0.15, -200)
	(e.node.get_meta("body") as Node3D).rotation.y = rnd(-0.2, 0.2)
	if e.hp > 0.0:
		return
	e.dead = true
	e.node.queue_free()
	e.shadow.queue_free()
	forest.freed[int(e.cage)] = true
	burst(Vector3(e.x, 0.6, e.z), Color("#c8783a"), 20, 2.5)
	sfx(880, 0.15, "triangle", 0.2)
	var n: int = forest.freed.filter(func(f): return f).size()
	if n >= forest.freed.size():
		has_acorn = true
		show_story("", STORY.SQUIRRELS_DONE)
	else:
		toast(tr("다람쥐를 구했다 %d/5") % n)
	save_game()

func update_forest() -> void:
	if forest_q == 1 and not story_open and Vector2(player.x, player.z).distance_to(forest.marks.N) < 6.0:
		forest_q = 2
		show_story("", STORY.NOEUL_DUEL2)
		after_story = spawn_noeul_duel.bind(true)
		set_quest("노을과 다시 겨루자")
		save_game()

func noeul_turned() -> void:
	forest_q = 3
	join_noeul()
	ui.boss.visible = false
	player.gold += 150
	gain_xp(250)
	show_story("res://art/story/10_jae_turns.jpg", STORY.NOEUL_TURNS)
	set_quest("숲 동쪽 끝 길로, 바람 언덕에 가자")
	save_game()

# ---- the south lake and Mulgyeol joining (between the lantern night and the forest)
func enter_lake() -> void:
	in_village = false
	in_lake = true
	player.x = lake.marks.S.x
	player.z = lake.marks.S.y + 1.2
	ground_y = 0.0
	ui.mini.map_tex = lake.map_tex(LAKE.LAKE_X + LAKE.W)
	ui.zone_name.text = "남쪽 호수"
	ui.zone_sub.text = "굳은 물가"
	if lake_q < 3:
		if lake_npc == null:
			lake_npc = folk_sprite("mulgyeol")
			add_child(lake_npc)
		lake_npc.position = Vector3(lake.marks.P.x + 1.0, 0, lake.marks.P.y)
		lake_npc.visible = true
	if lake_q == 0:
		lake_q = 1
		show_story("", STORY.LAKE_IN)
		set_quest("수문의 벽돌을 왕관으로 풀자 (E)")
	save_game()

func leave_lake() -> void:
	in_lake = false
	in_village = true
	player.x = village.marks.K.x
	player.z = village.marks.K.y - 1.2
	ground_y = 0.0
	ui.mini.map_tex = village.map_tex(VILLAGE.VILLAGE_X + VILLAGE.W)
	ui.zone_name.text = "등불 마을"
	ui.zone_sub.text = "남쪽 문"
	ui.boss.visible = false
	save_game()

# E at the lake: unwind the sluice, ask Mulgyeol for the boat, or row back from the island
func lake_key() -> bool:
	var me := Vector2(player.x, player.z)
	if lake_q == 1 and me.distance_to(lake.marks.D) < 1.6:
		if spend_pips(unbrick_cost()):
			lake.thaw()
			lake_q = 2
			burst(Vector3(lake.marks.D.x, 0.6, lake.marks.D.y), Color("#9fd4ff"), 40, 4.0)
			shake = 0.3
			sfx(196, 0.6, "triangle", 0.3, -60)
			ui.mini.map_tex = lake.map_tex(LAKE.LAKE_X + LAKE.W)
			show_story("", STORY.LAKE_THAW)
			set_quest("부두의 물결에게 말을 걸자 (E)")
			save_game()
		return true
	if lake_q == 2 and lake_npc != null and me.distance_to(Vector2(lake_npc.position.x, lake_npc.position.z)) < 1.6:
		fade_then(row_to_island)
		return true
	if lake_q >= 4 and me.distance_to(lake.marks.Q) < 1.6:
		fade_then(func():
			player.x = lake.marks.P.x
			player.z = lake.marks.P.y - 1.0
			snap_mate())
		return true
	if lake_q >= 4 and me.distance_to(lake.marks.P) < 1.6:
		fade_then(func():
			player.x = lake.marks.Q.x
			player.z = lake.marks.Q.y + 1.0
			snap_mate())
		return true
	return false

func row_to_island() -> void:
	lake_q = 3
	lake_npc.visible = false
	join_mate()
	player.x = lake.marks.Q.x
	player.z = lake.marks.Q.y + 1.0
	snap_mate()
	show_story("", STORY.BOAT)
	after_story = spawn_turtle
	set_quest("섬의 벽돌 거북을 물리치자")
	save_game()

func spawn_turtle() -> void:
	if enemies.any(func(e): return e.get("turtle", false) and not e.dead):
		return
	var at: Vector2 = lake.marks.T
	var root := Node3D.new()
	var shell: Material = mat_color(Color("#5f7a52"))
	var stud: Material = mat_color(Color("#7a9a62"))
	var skin: Material = mat_color(Color("#8a8a70"))
	var body := Node3D.new()
	body.name = "body"
	root.add_child(body)
	for part in [[Vector3(2.0, 0.9, 2.4), Vector3(0, 0.75, 0), shell], [Vector3(1.6, 0.4, 2.0), Vector3(0, 1.35, 0), shell],
			[Vector3(0.7, 0.6, 0.8), Vector3(0, 0.6, 1.5), skin],
			[Vector3(0.5, 0.5, 0.5), Vector3(-0.9, 0.25, 0.9), skin], [Vector3(0.5, 0.5, 0.5), Vector3(0.9, 0.25, 0.9), skin],
			[Vector3(0.5, 0.5, 0.5), Vector3(-0.9, 0.25, -0.9), skin], [Vector3(0.5, 0.5, 0.5), Vector3(0.9, 0.25, -0.9), skin]]:
		var b := box(part[0], part[2])
		b.position = part[1]
		body.add_child(b)
	for k in 4: # studs on the shell
		var s := box(Vector3(0.3, 0.16, 0.3), stud)
		s.position = Vector3(-0.4 + (k % 2) * 0.8, 1.6, -0.4 + (k / 2) * 0.8)
		body.add_child(s)
	for side in [-0.18, 0.18]:
		var eye := box(Vector3(0.12, 0.12, 0.05), glow_mat(Color("#ffb040"), 2.0))
		eye.position = Vector3(side, 0.75, 1.92)
		body.add_child(eye)
	add_child(root)
	enemies.append({"x": at.x, "z": at.y, "hp": 900.0, "max_hp": 900, "node": root, "shadow": blob(1.6), "t": 0.0,
		"atk_cd": 2.0, "hurt": 0.0, "kx": 0.0, "kz": 0.0, "wx": at.x, "wz": at.y, "dead": false, "respawn": 0.0,
		"turtle": true, "cave": true, "wind": 0.0, "dash": 0.0, "dir": Vector2.ZERO, "stun": 0.0, "next": "stomp", "spins": 0})

# the brick turtle: a stomp ring around itself, then a spinning shell charge (twice below half HP);
# hitting the island's edge leaves it stunned for a moment
func update_turtle(e: Dictionary, dt: float, d: float, to: Vector2) -> void:
	var node: Node3D = e.node
	var body: Node3D = node.get_node("body")
	ui.boss.visible = d < 12.0
	ui.boss_name.text = "벽돌 거북"
	ui.boss_bar.size.x = 420.0 * maxf(0.0, e.hp) / e.max_hp
	e.t += dt
	e.hurt -= dt
	e.stun -= dt
	body.scale = Vector3.ONE * (1.06 if e.hurt > 0.0 else 1.0)
	if e.dash > 0.0:
		e.dash -= dt
		body.rotation.y += dt * 14.0
		var nx: float = e.x + e.dir.x * 7.5 * dt
		var nz: float = e.z + e.dir.y * 7.5 * dt
		if walkable(nx, nz):
			e.x = nx
			e.z = nz
			if Vector2(player.x - e.x, player.z - e.z).length() < 1.4:
				player_hit(22, Vector2(e.x, e.z) - e.dir, e)
		else:
			e.dash = 0.0
			e.stun = 1.6
			shake = 0.3
			sfx(80, 0.3, "square", 0.3, -40)
			burst(Vector3(e.x, 0.6, e.z), Color("#7a9a62"), 20, 3.0)
		if e.dash <= 0.0 and e.spins > 0:
			e.spins -= 1
			e.wind = 0.5
			e.dir = to / maxf(d, 0.01)
	elif e.stun > 0.0:
		pass
	elif e.wind > 0.0:
		e.wind -= dt
		if e.wind <= 0.0:
			if e.next == "stomp":
				burst(Vector3(e.x, 0.3, e.z), Color("#8a8a70"), 30, 3.5)
				if d < 2.6:
					player_hit(18, Vector2(e.x, e.z), e)
				shake = 0.25
				sfx(70, 0.3, "square", 0.25, -30)
				e.next = "spin"
			else:
				e.dash = 1.1
				e.next = "stomp"
			e.atk_cd = 1.6
	elif d < 10.0:
		e.atk_cd -= dt
		if e.atk_cd <= 0.0:
			if e.next == "stomp":
				e.wind = 0.9
				warn_ring(Vector3(e.x, 0.0, e.z), 2.6, 0.9)
			else:
				e.wind = 0.8
				e.dir = to / maxf(d, 0.01)
				e.spins = 1 if e.hp < e.max_hp / 2.0 else 0
				pop_num(Vector3(e.x, 2.4, e.z), "!", Color("#ff5a4a"))
				sfx(140, 0.5, "sawtooth", 0.2, 120)
		elif d > 1.8:
			var nx: float = e.x + to.x / d * 1.0 * dt
			var nz: float = e.z + to.y / d * 1.0 * dt
			if walkable(nx, e.z): e.x = nx
			if walkable(e.x, nz): e.z = nz
			body.rotation.y = lerp_angle(body.rotation.y, atan2(to.x, to.y), dt * 3.0)
	node.position = Vector3(e.x, 0, e.z)
	e.shadow.position = Vector3(e.x, 0.02, e.z)

# ---- 물빛 동굴 under the island (after the turtle): water-skip runs, archers, the brick crab and the water pearl
func in_grotto() -> bool:
	return in_lake and player.x >= GROTTO.GROTTO_X - 0.5

# steps going down on the island's south shore, at the lake's G: a stone frame over a stair that sinks step by step
# into a dark opening, with a lamp on top, so it reads as a way down from far off
func grotto_steps() -> void:
	var g := Node3D.new()
	var frame: Material = mat_color(Color("#7a7468"))
	var hole: MeshInstance3D = box(Vector3(1.1, 0.06, 1.2), mat_color(Color("#101418")))
	hole.position = Vector3(0, 0.03, 0)
	g.add_child(hole)
	for k in 4: # steps from the near edge going down and away, each darker
		var st: MeshInstance3D = box(Vector3(0.9, 0.08, 0.26), mat_color(Color("#a8a49a").darkened(k * 0.2)))
		st.position = Vector3(0, 0.1 - k * 0.025, 0.42 - k * 0.27)
		g.add_child(st)
	for side in [-0.62, 0.62]: # low side walls
		var w: MeshInstance3D = box(Vector3(0.16, 0.4, 1.3), frame)
		w.position = Vector3(side, 0.2, 0)
		g.add_child(w)
	var back: MeshInstance3D = box(Vector3(1.4, 0.9, 0.16), frame) # the head wall at the far end
	back.position = Vector3(0, 0.45, -0.65)
	g.add_child(back)
	var lamp: MeshInstance3D = box(Vector3(0.22, 0.26, 0.22), glow_mat(Color("#9fd8ff"), 1.4))
	lamp.position = Vector3(0, 1.05, -0.65)
	g.add_child(lamp)
	var at: Vector2 = lake.marks.G
	g.position = Vector3(at.x, 0, at.y)
	add_child(g)

func enter_grotto() -> void:
	player.x = grotto.marks.S.x + 1.2
	player.z = grotto.marks.S.y
	ground_y = 0.0
	ui.mini.map_tex = grotto.map_tex(GROTTO.GROTTO_X + GROTTO.W)
	ui.zone_name.text = "물빛 동굴"
	ui.zone_sub.text = "섬 밑 물길"
	snap_mate()
	if not grotto_spawned:
		grotto_spawned = true
		for f in grotto.foes:
			spawn_enemy(f[0], f[1])
	if grotto_q == 0:
		grotto_q = 1
		show_story("", STORY.GROTTO_IN)
	save_game()

func leave_grotto() -> void:
	player.x = lake.marks.G.x
	player.z = lake.marks.G.y - 1.2
	ground_y = 0.0
	ui.mini.map_tex = lake.map_tex(LAKE.LAKE_X + LAKE.W)
	ui.zone_name.text = "남쪽 호수"
	ui.zone_sub.text = "물결의 섬"
	ui.boss.visible = false
	snap_mate()
	save_game()

# E or Space beside a grotto chest
func grotto_key() -> bool:
	var me := Vector2(player.x, player.z)
	if not grotto_side and me.distance_to(grotto.marks.p) < 1.6:
		grotto_side = true
		grotto.opened_look(grotto.side_chest)
		player.pots += 2
		player.gold += 60
		burst(Vector3(grotto.marks.p.x, 0.8, grotto.marks.p.y), Color("#bfe6ff"), 30, 3.0)
		sfx(784, 0.12, "triangle", 0.25)
		toast("회복약 2개와 금화 60닢을 찾았다")
		save_game()
		return true
	if grotto_q == 3 and me.distance_to(grotto.marks.c) < 1.6:
		grotto_q = 4
		has_pearl = true
		grotto.opened_look(grotto.chest)
		burst(Vector3(grotto.marks.c.x, 0.8, grotto.marks.c.y), Color("#9fd8ff"), 40, 3.0)
		sfx(784, 0.12, "triangle", 0.25)
		show_story("", STORY.PEARL)
		save_game()
		return true
	return false

func spawn_crab() -> void:
	if enemies.any(func(e): return e.get("crab", false) and not e.dead):
		return
	var at: Vector2 = grotto.marks.C
	var root := Node3D.new()
	var body := Node3D.new()
	body.name = "body"
	root.add_child(body)
	var shell: Material = mat_color(Color("#c8502a"))
	var dark: Material = mat_color(Color("#8a3018"))
	for part in [[Vector3(1.8, 0.6, 1.2), Vector3(0, 0.55, 0), shell], [Vector3(1.4, 0.25, 1.0), Vector3(0, 0.95, 0), dark],
			[Vector3(0.6, 0.5, 0.5), Vector3(-1.2, 0.6, 0.8), shell], [Vector3(0.6, 0.5, 0.5), Vector3(1.2, 0.6, 0.8), shell],
			[Vector3(0.25, 0.3, 0.6), Vector3(-1.2, 0.6, 1.2), dark], [Vector3(0.25, 0.3, 0.6), Vector3(1.2, 0.6, 1.2), dark]]:
		var b := box(part[0], part[2])
		b.position = part[1]
		body.add_child(b)
	for k in 6: # three legs a side
		var leg := box(Vector3(0.5, 0.14, 0.14), dark)
		leg.position = Vector3(-1.05 if k < 3 else 1.05, 0.2, -0.4 + (k % 3) * 0.4)
		body.add_child(leg)
	for side in [-0.35, 0.35]: # eyes on stalks
		var stalk := box(Vector3(0.1, 0.35, 0.1), dark)
		stalk.position = Vector3(side, 1.15, 0.45)
		body.add_child(stalk)
		var eye := box(Vector3(0.18, 0.18, 0.18), glow_mat(Color("#ffd040"), 2.0))
		eye.position = Vector3(side, 1.38, 0.45)
		body.add_child(eye)
	add_child(root)
	enemies.append({"x": at.x, "z": at.y, "hp": 760.0, "max_hp": 760, "node": root, "shadow": blob(1.5), "t": 0.0,
		"atk_cd": 1.5, "hurt": 0.0, "kx": 0.0, "kz": 0.0, "wx": at.x, "wz": at.y, "dead": false, "respawn": 0.0,
		"crab": true, "cave": true, "wind": 0.0, "stun": 0.0, "next": ""})

# the brick crab scuttles sideways to line up with Sora. Close in, a 0.6 s pinch (2.3 tiles);
# farther out, a 0.5 s wind-up then a fan of spat bricks (3, five below half health)
func update_crab(e: Dictionary, dt: float, d: float, to: Vector2) -> void:
	var node: Node3D = e.node
	var body: Node3D = node.get_node("body")
	ui.boss.visible = d < 12.0
	ui.boss_name.text = "벽돌 게"
	ui.boss_bar.size.x = 420.0 * maxf(0.0, e.hp) / e.max_hp
	e.t += dt
	e.hurt -= dt
	e.stun -= dt
	var angry: bool = e.hp < e.max_hp / 2.0
	body.scale = Vector3.ONE * (1.06 if e.hurt > 0.0 or e.wind > 0.0 else 1.0)
	if e.stun > 0.0:
		pass
	elif e.wind > 0.0:
		e.wind -= dt
		if e.wind <= 0.0:
			if e.next == "pinch":
				burst(Vector3(e.x + to.x / maxf(d, 0.01) * 1.2, 0.6, e.z + to.y / maxf(d, 0.01) * 1.2), Color("#ffd28a"), 12, 2.5)
				sfx(900, 0.06, "square", 0.2, -400)
				if d < 2.3:
					player_hit(18 + player.lv, Vector2(e.x, e.z), e)
			else:
				var n := 5 if angry else 3
				for k in n:
					var a := (k - (n - 1) / 2.0) * 0.28
					throw_brick(Vector2(e.x, e.z), (to / maxf(d, 0.01)).rotated(a), e)
			e.atk_cd = 1.0 if angry else 1.5
	else:
		e.atk_cd -= dt
		if e.atk_cd <= 0.0 and d < 9.0:
			e.next = "pinch" if d < 2.2 else "spit"
			e.wind = 0.6 if e.next == "pinch" else 0.5
			pop_num(Vector3(e.x, 2.0, e.z), "!", Color("#ff5a4a") if e.next == "pinch" else Color("#ffd84a"))
		else:
			# sideways first: match Sora's x, then creep in on z
			var v := Vector2(clampf(to.x, -1.0, 1.0) * 2.4, clampf(to.y - signf(to.y) * 1.6, -1.0, 1.0) * 0.9)
			if d < 2.1:
				v = Vector2.ZERO # close enough to pinch (2.3); its wide shell would cover her any closer
			var nx: float = e.x + v.x * dt
			var nz: float = e.z + v.y * dt
			if walkable(nx, e.z): e.x = nx
			if walkable(e.x, nz): e.z = nz
			body.position.y = absf(sin(e.t * 10.0)) * 0.06 if v.length() > 0.3 else 0.0
	body.rotation.y = lerp_angle(body.rotation.y, atan2(to.x, to.y), dt * 4.0)
	node.position = Vector3(e.x, 0, e.z)
	e.shadow.position = Vector3(e.x, 0.02, e.z)

func crab_beaten() -> void:
	grotto_q = 3
	ui.boss.visible = false
	grotto.chest.visible = true
	player.gold += 180
	gain_xp(220)
	show_story("", STORY.CRAB_DOWN)
	save_game()

# ---- 구름 둔덕 above the hill (after the hawk): wind vents across open sky, the brick scarecrow, the wind feather
func in_cloud() -> bool:
	return in_hill and player.x >= CLOUD.CLOUD_X - 0.5 and player.x < CASTLE.CASTLE_X - 0.5

# wind vents exist on the cloud mound and on the castle's broken floor
func vent_here(x: float, z: float) -> Vector2:
	if in_castle():
		return castle.vent_at(x, z)
	if in_cloud():
		return cloud.vent_at(x, z)
	return Vector2.ZERO

func gust_char(x: float, z: float) -> String:
	return castle.char_at(x, z) if x >= CASTLE.CASTLE_X - 0.5 else cloud.char_at(x, z)

func enter_cloud() -> void:
	player.x = cloud.marks.S.x + 1.2
	player.z = cloud.marks.S.y
	ground_y = 0.0
	gust_dir = Vector2.ZERO
	ui.mini.map_tex = cloud.map_tex(CLOUD.CLOUD_X + CLOUD.W)
	ui.zone_name.text = "구름 둔덕"
	ui.zone_sub.text = "바람구멍 섬들"
	snap_mates()
	if not cloud_spawned:
		cloud_spawned = true
		for f in cloud.foes:
			spawn_enemy(f[0], f[1])
	if cloud_q == 0:
		cloud_q = 1
		show_story("", STORY.CLOUD_IN)
	save_game()

func leave_cloud() -> void:
	player.x = hill.marks.U.x
	player.z = hill.marks.U.y + 1.3
	ground_y = 0.0
	gust_dir = Vector2.ZERO
	ui.mini.map_tex = hill.map_tex(HILL.HILL_X + HILL.W)
	ui.zone_name.text = "바람 언덕"
	ui.zone_sub.text = "언덕 꼭대기"
	ui.boss.visible = false
	snap_mates()
	save_game()

# stepping onto a vent from plain ground starts a gust: Sora flies 8 tiles/s the way it points, over the gap,
# and lands 0.6 tiles onto the next island. Normal walking is off while she flies.
func start_gust(dir: Vector2) -> void:
	gust_dir = dir
	gust_t = 0.0
	gust_gap = false
	gust_solid = 0.0
	player.vx = 0.0
	player.vz = 0.0
	sfx(260, 0.45, "noise", 0.1, 500)
	burst(Vector3(player.x, 0.4, player.z), Color("#ffffff"), 16, 2.0)

func update_gust(dt: float) -> void:
	gust_t += dt
	var step := gust_dir * 8.0 * dt
	var np := Vector2(player.x, player.z) + step
	if gust_char(np.x, np.y) == "#" or gust_t > 3.0:
		gust_dir = Vector2.ZERO
		return
	player.x = np.x
	player.z = np.y
	if gust_char(np.x, np.y) == "_":
		gust_gap = true
	elif gust_gap:
		gust_solid += step.length()
		if gust_solid >= 0.6 and walkable(np.x, np.y):
			gust_dir = Vector2.ZERO
	if int(gust_t * 10.0) != int((gust_t - dt) * 10.0):
		burst(Vector3(player.x, 0.5, player.z), Color("#ffffff"), 3, 0.8)

var has_shard := false      # 구름 조각: skill cooldowns x0.8

func cloud_key() -> bool:
	var cx := float(CLOUD.CLOUD_X)
	var me := Vector2(player.x, player.z)
	if not cloud.shard_open and me.distance_to(cloud.marks.q) < 1.6:
		cloud.shard_look()
		has_shard = true
		burst(Vector3(cloud.marks.q.x, 0.8, cloud.marks.q.y), Color("#bfe6ff"), 40, 3.0)
		sfx(784, 0.12, "triangle", 0.25)
		show_story("", STORY.CLOUD_SHARD)
		save_game()
		return true
	if me.x < cx + 7.0 and me.y > 10.5: # by the unseen path: hold up the crown and it shows for 3 s
		cloud.reveal_t = 3.0
		cloud.reveal(true)
		burst(Vector3(player.x, 1.6, player.z), Color("#bfe6ff"), 14, 1.5)
		sfx(988, 0.3, "sine", 0.18)
		return true
	if not cloud_chest and Vector2(player.x, player.z).distance_to(cloud.marks.c) < 1.6:
		cloud_chest = true
		cloud.opened_look()
		player.gold += 100
		player.pots += 1
		burst(Vector3(cloud.marks.c.x, 0.8, cloud.marks.c.y), Color("#f2ead8"), 30, 3.0)
		sfx(784, 0.12, "triangle", 0.25)
		toast("금화 100닢과 회복약을 찾았다")
		save_game()
		return true
	return false

func spawn_scarecrow() -> void:
	if enemies.any(func(e): return e.get("scare", false) and not e.dead):
		return
	var at: Vector2 = cloud.marks.K
	var root := Node3D.new()
	var body := Node3D.new()
	body.name = "body"
	root.add_child(body)
	var wood: Material = mat_color(Color("#6a4a2a"))
	var straw: Material = mat_color(Color("#d8b04a"))
	var cloth: Material = mat_color(Color("#4a6a9a"))
	for part in [[Vector3(0.2, 1.6, 0.2), Vector3(0, 0.8, 0), wood], [Vector3(0.8, 0.8, 0.5), Vector3(0, 1.4, 0), cloth],
			[Vector3(0.6, 0.55, 0.55), Vector3(0, 2.1, 0), straw], [Vector3(0.9, 0.12, 0.9), Vector3(0, 2.45, 0), wood],
			[Vector3(0.45, 0.3, 0.45), Vector3(0, 2.65, 0), wood]]:
		var b := box(part[0], part[2])
		b.position = part[1]
		body.add_child(b)
	for side in [-0.14, 0.14]:
		var eye := box(Vector3(0.1, 0.1, 0.05), glow_mat(Color("#ff8a30"), 2.0))
		eye.position = Vector3(side, 2.15, 0.29)
		body.add_child(eye)
	var arms := Node3D.new() # the cross-bar arms, which spin on the big attack
	arms.name = "arms"
	arms.position = Vector3(0, 1.55, 0)
	body.add_child(arms)
	var bar := box(Vector3(2.6, 0.18, 0.18), wood)
	arms.add_child(bar)
	for side in [-1.3, 1.3]:
		var tuft := box(Vector3(0.35, 0.35, 0.35), straw)
		tuft.position = Vector3(side, 0, 0)
		arms.add_child(tuft)
	add_child(root)
	enemies.append({"x": at.x, "z": at.y, "hp": 820.0, "max_hp": 820, "node": root, "shadow": blob(1.2), "t": 0.0,
		"atk_cd": 1.6, "hurt": 0.0, "kx": 0.0, "kz": 0.0, "wx": at.x, "wz": at.y, "dead": false, "respawn": 0.0,
		"scare": true, "cave": true, "wind": 0.0, "stun": 0.0, "next": "", "spins": 0, "spin_t": 0.0})

# the brick scarecrow: close in, a 0.8 s wind-up (red ring) then a 2.6-tile arm spin (twice below half);
# farther out, a 0.6 s wind-up then straw bricks flung four ways (eight below half), turned a little each time
func update_scarecrow(e: Dictionary, dt: float, d: float, to: Vector2) -> void:
	var node: Node3D = e.node
	var body: Node3D = node.get_node("body")
	var arms: Node3D = body.get_node("arms")
	ui.boss.visible = d < 12.0
	ui.boss_name.text = "벽돌 허수아비"
	ui.boss_bar.size.x = 420.0 * maxf(0.0, e.hp) / e.max_hp
	e.t += dt
	e.hurt -= dt
	e.stun -= dt
	var angry: bool = e.hp < e.max_hp / 2.0
	body.rotation.z = sin(e.t * 2.0) * 0.06 # sways on its post
	if e.spin_t > 0.0:
		e.spin_t -= dt
		arms.rotation.y += dt * 18.0
	if e.stun > 0.0:
		pass
	elif e.wind > 0.0:
		e.wind -= dt
		arms.rotation.y += dt * (6.0 if e.next == "spin" else 0.0)
		if e.wind <= 0.0:
			if e.next == "spin":
				e.spin_t = 0.5
				burst(Vector3(e.x, 1.4, e.z), Color("#d8b04a"), 24, 4.0)
				sfx(200, 0.4, "noise", 0.15, 300)
				if d < 2.6:
					player_hit(20 + player.lv, Vector2(e.x, e.z), e)
				if e.spins > 0:
					e.spins -= 1
					e.wind = 0.5
					warn_ring(Vector3(e.x, 0.0, e.z), 2.6, 0.5)
					return
			else:
				var n := 8 if angry else 4
				var a0: float = e.t
				for k in n:
					throw_brick(Vector2(e.x, e.z), Vector2.RIGHT.rotated(a0 + k * TAU / n), e)
			e.atk_cd = 1.1 if angry else 1.6
	else:
		e.atk_cd -= dt
		if e.atk_cd <= 0.0 and d < 10.0:
			e.next = "spin" if d < 2.6 else "fling"
			if e.next == "spin":
				e.wind = 0.8
				e.spins = 1 if angry else 0
				warn_ring(Vector3(e.x, 0.0, e.z), 2.6, 0.8)
			else:
				e.wind = 0.6
			pop_num(Vector3(e.x, 3.0, e.z), "!", Color("#ff5a4a") if e.next == "spin" else Color("#ffd84a"))
		elif d > 3.0: # hops slowly after her on its post
			var nx: float = e.x + to.x / d * 0.8 * dt
			var nz: float = e.z + to.y / d * 0.8 * dt
			if walkable(nx, e.z): e.x = nx
			if walkable(e.x, nz): e.z = nz
	body.position.y = absf(sin(e.t * 4.0)) * 0.08
	node.position = Vector3(e.x, 0, e.z)
	e.shadow.position = Vector3(e.x, 0.02, e.z)

func scarecrow_beaten() -> void:
	cloud_q = 3
	has_feather = true
	ui.boss.visible = false
	player.gold += 160
	gain_xp(240)
	show_story("", STORY.SCARE_DOWN)
	save_game()

# ---- 가라앉은 달지기 성 (chapter 7) between the hill and the garden: the bricked gate, the flooded hall,
# the broken floor with vents, Hangyeol's three diary pages, the moon door and the brick knight
func in_castle() -> bool:
	return in_hill and player.x >= CASTLE.CASTLE_X - 0.5

func enter_castle() -> void:
	in_hill = true
	in_garden = false
	story_step = maxi(story_step, 10)
	player.x = castle.marks.S.x + 1.2
	player.z = castle.marks.S.y
	ground_y = 0.0
	gust_dir = Vector2.ZERO
	ui.mini.map_tex = castle.map_tex(CASTLE.CASTLE_X + CASTLE.W)
	ui.zone_name.text = "가라앉은 달지기 성"
	ui.zone_sub.text = "굳은 성문"
	snap_mates()
	if not castle_spawned:
		castle_spawned = true
		for f in castle.foes:
			spawn_enemy(f[0], f[1] == "a")
			if f[1] == "s":
				give_shield(enemies[enemies.size() - 1])
		for b in BAT_SPOTS:
			if b.x >= CASTLE.CASTLE_X:
				spawn_bat(b)
	if castle_q == 0:
		castle_q = 1
		show_story("", STORY.CASTLE_IN)
	if castle_q < 3:
		set_quest(castle_quest())
	save_game()

func castle_quest() -> String:
	if not castle.gate_open:
		return "성문의 벽돌을 왕관으로 풀자 (E)"
	if not castle.door_open:
		return tr("성 안에 흩어진 한결의 일기를 찾자 (E) %d/3") % castle.pages_read()
	return "옥좌의 방으로 가자"

func leave_castle() -> void:
	player.x = hill.marks.X.x - 1.2
	player.z = hill.marks.X.y
	ground_y = 0.0
	gust_dir = Vector2.ZERO
	ui.mini.map_tex = hill.map_tex(HILL.HILL_X + HILL.W)
	ui.zone_name.text = "바람 언덕"
	ui.zone_sub.text = "매의 벼랑"
	ui.boss.visible = false
	snap_mates()
	save_game()

# E in the castle: unbrick the gate, or read a diary page; the third page opens the moon door
func castle_key() -> bool:
	var me := Vector2(player.x, player.z)
	if not castle.gate_open:
		for n in castle.gate_nodes:
			if me.distance_to(Vector2(n.position.x, n.position.z)) < 1.6:
				if not spend_pips(unbrick_cost()):
					return true
				castle.open_gate()
				burst(Vector3(n.position.x, 0.7, n.position.z), Color("#8a6a4a"), 36, 3.5)
				burst(Vector3(player.x, 1.6, player.z), Color("#9fd4ff"), 14, 1.5)
				shake = 0.25
				sfx(196, 0.5, "triangle", 0.3, -60)
				toast("성문의 벽돌이 흙으로 풀렸다")
				ui.mini.map_tex = castle.map_tex(CASTLE.CASTLE_X + CASTLE.W)
				set_quest(castle_quest())
				save_game()
				return true
	for i in castle.levers.size():
		if me.distance_to(castle.levers[i].pos) < 1.3:
			var was := castle.vault_solved()
			castle.flip_lever(i)
			sfx(220 + i * 60, 0.15, "square", 0.15, -60)
			burst(Vector3(castle.levers[i].pos.x, 0.9, castle.levers[i].pos.y), Color("#c8962a"), 6, 1.5)
			ui.mini.map_tex = castle.map_tex(CASTLE.CASTLE_X + CASTLE.W)
			if castle.vault_solved() and not was:
				shake = 0.2
				sfx(330, 0.4, "triangle", 0.25, 200)
				toast("보물고의 창살 세 개가 모두 올라갔다")
			save_game()
			return true
	if not castle.vault_open and me.distance_to(Vector2(castle.vault_chest.position.x, castle.vault_chest.position.z)) < 1.6:
		castle.open_vault_look()
		has_armour = true
		player.gold += 150
		burst(castle.vault_chest.position + Vector3(0, 0.8, 0), Color("#e8c050"), 40, 3.0)
		sfx(784, 0.12, "triangle", 0.25)
		show_story("", STORY.ARMOUR)
		save_game()
		return true
	var page_d := 99.0 # a diary page stand right beside a shelf wins when it is nearer
	for pg in castle.pages:
		page_d = minf(page_d, me.distance_to(pg.pos))
	var near_i := -1 # the nearest shelf within reach
	for i in castle.books.size():
		var d: float = me.distance_to(castle.books[i].pos)
		if d < 1.4 and d < page_d and (near_i < 0 or d < me.distance_to(castle.books[near_i].pos)):
			near_i = i
	for i in castle.books.size():
		var bk: Dictionary = castle.books[i]
		if i == near_i:
			var first: bool = not bk.read
			bk.read = true
			show_story("", STORY.BOOKS[i])
			if first:
				sfx(523, 0.15, "triangle", 0.18)
				var n: int = castle.books.filter(func(b): return b.read).size()
				if n == castle.books.size():
					has_bookmark = true
					after_story = func(): show_story("", STORY.BOOKMARK)
				else:
					toast(tr("달지기 책 %d/5") % n)
				save_game()
			return true
	for i in castle.pages.size():
		var p: Dictionary = castle.pages[i]
		if me.distance_to(p.pos) < 1.5:
			var first: bool = not p.read
			p.read = true
			show_story("", [STORY.PAGE_1, STORY.PAGE_2, STORY.PAGE_3][castle.pages_read() - 1] if first else STORY.PAGE_AGAIN)
			if first:
				sfx(660, 0.2, "triangle", 0.2)
				if castle.pages_read() == 3 and not castle.door_open:
					castle.open_door()
					shake = 0.3
					sfx(150, 0.6, "triangle", 0.3, -40)
					ui.mini.map_tex = castle.map_tex(CASTLE.CASTLE_X + CASTLE.W)
				set_quest(castle_quest())
				save_game()
			return true
	return false

func spawn_knight() -> void:
	if enemies.any(func(e): return e.get("knight", false) and not e.dead):
		return
	var at: Vector2 = castle.marks.K
	var root := Node3D.new()
	var body := Node3D.new()
	body.name = "body"
	root.add_child(body)
	var plate: Material = mat_color(Color("#7a7a86"))
	var dark: Material = mat_color(Color("#3a3a46"))
	var red: Material = mat_color(Color("#a8322a"))
	for part in [[Vector3(0.3, 0.6, 0.3), Vector3(-0.22, 0.3, 0), dark], [Vector3(0.3, 0.6, 0.3), Vector3(0.22, 0.3, 0), dark],
			[Vector3(0.9, 0.8, 0.55), Vector3(0, 1.0, 0), plate], [Vector3(0.6, 0.55, 0.55), Vector3(0, 1.7, 0), plate],
			[Vector3(0.5, 0.08, 0.06), Vector3(0, 1.72, 0.29), dark], [Vector3(0.12, 0.35, 0.12), Vector3(0, 2.1, 0), red],
			[Vector3(1.0, 0.7, 0.12), Vector3(0, 0.75, -0.32), red]]:
		var b := box(part[0], part[2])
		b.position = part[1]
		body.add_child(b)
	var shield := box(Vector3(0.9, 1.1, 0.14), mat_color(Color("#c8962a"))) # the big shield, held in front
	shield.position = Vector3(-0.35, 1.0, 0.45)
	body.add_child(shield)
	var sword := box(Vector3(0.12, 0.12, 1.3), mat_color(Color("#d8d8e0")))
	sword.name = "sword"
	sword.position = Vector3(0.62, 1.0, 0.5)
	body.add_child(sword)
	var eye := box(Vector3(0.3, 0.06, 0.05), glow_mat(Color("#ffb040"), 2.5))
	eye.position = Vector3(0, 1.74, 0.3)
	body.add_child(eye)
	root.scale = Vector3.ONE * 1.25
	add_child(root)
	enemies.append({"x": at.x, "z": at.y, "hp": 1100.0, "max_hp": 1100, "node": root, "shadow": blob(1.3), "t": 0.0,
		"atk_cd": 1.5, "hurt": 0.0, "kx": 0.0, "kz": 0.0, "wx": at.x, "wz": at.y, "dead": false, "respawn": 0.0,
		"knight": true, "cave": true, "wind": 0.0, "stun": 0.0, "tired": 0.0, "dash": 0.0, "dir": Vector2.ZERO,
		"next": "", "combo": 0, "slam_cd": 0.0, "hit_done": false, "face": Vector2(-1, 0)})

# the brick knight keeps his shield toward Sora: hits from his front 140 degrees are blocked unless he is
# stunned (flash guard: 2 s) or tired (1.2 s after a lunge, 0.6 s after his third slash).
# Close in: a three-slash combo (0.45 s wind-up each, 2.4-tile cone). From 2.4 to 8 tiles: a 0.7 s wind-up, then a lunge.
# Below half health: a 1.0 s ground slam (3-tile ring) every 6 s.
func update_knight(e: Dictionary, dt: float, d: float, to: Vector2) -> void:
	var node: Node3D = e.node
	var body: Node3D = node.get_node("body")
	var sword: Node3D = body.get_node("sword")
	ui.boss.visible = d < 13.0
	ui.boss_name.text = "벽돌 기사"
	ui.boss_bar.size.x = 420.0 * maxf(0.0, e.hp) / e.max_hp
	e.t += dt
	e.hurt -= dt
	e.stun -= dt
	e.tired -= dt
	e.slam_cd -= dt
	var angry: bool = e.hp < e.max_hp / 2.0
	var dirn: Vector2 = to / maxf(d, 0.01)
	body.rotation.x = 0.3 if (e.stun > 0.0 or e.tired > 0.0) else 0.0 # slumps forward while open
	sword.rotation.y = lerpf(sword.rotation.y, 0.0, dt * 8.0)
	if e.stun > 0.0 or e.tired > 0.0:
		e.dash = 0.0
		e.wind = 0.0
	elif e.dash > 0.0:
		e.dash -= dt
		var nx: float = e.x + e.dir.x * 10.0 * dt
		var nz: float = e.z + e.dir.y * 10.0 * dt
		if walkable(nx, nz):
			e.x = nx
			e.z = nz
		else:
			e.dash = 0.0
		if not e.hit_done and Vector2(player.x - e.x, player.z - e.z).length() < 1.3:
			e.hit_done = true
			if player_hit(22 + player.lv, Vector2(e.x, e.z) - e.dir, e) == "flash_guard":
				e.stun = 2.0
		if e.dash <= 0.0 and e.stun <= 0.0:
			e.tired = 1.2
	elif e.wind > 0.0:
		e.wind -= dt
		if e.wind <= 0.0:
			match e.next:
				"slash":
					sword.rotation.y = -1.2
					burst(Vector3(e.x + e.face.x * 1.3, 1.0, e.z + e.face.y * 1.3), Color("#e8e8f0"), 10, 2.5)
					sfx(240, 0.08, "sawtooth", 0.15, 300)
					if d < 2.4 and dirn.dot(e.face) > 0.5:
						if player_hit(14 + player.lv, Vector2(e.x, e.z), e) == "flash_guard":
							e.stun = 2.0
					var sx: float = e.x + e.face.x * 0.5
					var sz: float = e.z + e.face.y * 0.5
					if walkable(sx, sz) and d > 1.2:
						e.x = sx
						e.z = sz
					e.combo -= 1
					if e.combo > 0 and e.stun <= 0.0:
						e.wind = 0.45
						e.face = dirn
						pop_num(Vector3(e.x, 2.9, e.z), "!", Color("#ff5a4a"))
					else:
						e.atk_cd = 1.0 if angry else 1.4
						if e.stun <= 0.0:
							e.tired = 0.6
				"lunge":
					e.dash = 0.45
					e.dir = e.face
					e.hit_done = false
					sfx(160, 0.3, "sawtooth", 0.2, 200)
				"slam":
					ring_wave(Vector3(e.x, 0.05, e.z))
					shake = 0.4
					sfx(60, 0.4, "square", 0.3, -30)
					burst(Vector3(e.x, 0.3, e.z), Color("#9a9284"), 30, 4.0)
					if d < 3.0:
						player_hit(24 + player.lv, Vector2(e.x, e.z), e)
					e.atk_cd = 1.2
	else:
		var want := atan2(dirn.y, dirn.x)
		var have := atan2(e.face.y, e.face.x)
		var turn := clampf(wrapf(want - have, -PI, PI), -3.0 * dt, 3.0 * dt) # slow to turn: get behind him
		e.face = e.face.rotated(turn)
		e.atk_cd -= dt
		if e.atk_cd <= 0.0 and d < 9.0:
			if angry and e.slam_cd <= 0.0 and d < 3.5:
				e.next = "slam"
				e.wind = 1.0
				e.slam_cd = 6.0
				warn_ring(Vector3(e.x, 0.0, e.z), 3.0, 1.0)
			elif d < 2.4:
				e.next = "slash"
				e.combo = 3
				e.wind = 0.45
				pop_num(Vector3(e.x, 2.9, e.z), "!", Color("#ff5a4a"))
			else:
				e.next = "lunge"
				e.wind = 0.7
				e.face = dirn
				pop_num(Vector3(e.x, 2.9, e.z), "!", Color("#ffd84a"))
		elif d > 2.0:
			var nx: float = e.x + dirn.x * 1.4 * dt
			var nz: float = e.z + dirn.y * 1.4 * dt
			if walkable(nx, e.z): e.x = nx
			if walkable(e.x, nz): e.z = nz
	node.rotation.y = atan2(e.face.x, e.face.y)
	node.position = Vector3(e.x, 0, e.z)
	e.shadow.position = Vector3(e.x, 0.02, e.z)

func knight_beaten() -> void:
	castle_q = 3
	ui.boss.visible = false
	player.gold += 250
	gain_xp(300)
	show_story("", STORY.KNIGHT_DOWN)
	set_quest("동쪽 문을 지나 정원 한가운데로 가자")
	save_game()

func turtle_beaten() -> void:
	lake_q = 4
	ui.boss.visible = false
	player.gold += 200
	gain_xp(200)
	show_story("", STORY.ISLAND_HOME)
	set_quest("물결과 함께 마을 동쪽 문으로, 굳은 숲에 가자")
	save_game()

# ---- Mulgyeol, the companion: trots after Sora and pokes the nearest enemy with his pole
func join_mate() -> void:
	if mate != null:
		return
	mate = Node3D.new()
	mate.add_child(folk_sprite("mulgyeol"))
	add_child(mate)
	if village.folk_node.has("mulgyeol"):
		village.folk_node.mulgyeol.visible = false
		var at: Vector2 = village.folk_pos.mulgyeol
		rocks = rocks.filter(func(r): return Vector2(r.x, r.z).distance_to(at) > 0.1)
	snap_mate()

func snap_mate() -> void:
	if mate != null:
		mate.position = Vector3(player.x - 1.3, 0, player.z - 0.6)

func snap_mates() -> void:
	snap_mate()
	if mate2 != null:
		mate2.position = Vector3(player.x + 1.3, 0, player.z - 0.6)

func join_noeul() -> void:
	if mate2 != null:
		return
	mate2 = Node3D.new()
	mate2.add_child(noeul_sprite())
	add_child(mate2)
	snap_mates()

# Noeul keeps a step to Sora's right and throws brick dust at enemies within 4 m
# companions slide along walls, houses and rocks instead of walking into them (they used to stand inside roofs)
func mate_step(at: Vector3, d: Vector3) -> Vector3:
	var p := at
	if walkable(p.x + d.x, p.z) or not walkable(p.x, p.z): p.x += d.x
	if walkable(p.x, p.z + d.z) or not walkable(p.x, p.z): p.z += d.z
	return p

# ---- companions' health: goblins and thrown bricks can hit Mulgyeol and Noeul too. At 0 a companion sits out
# for 10 s (lying down, no attacks), then gets up with half health; out of a fight they heal 4 HP a second.
var mate_hp := {"mulgyeol": -1.0, "noeul": -1.0}  # -1: not set yet (full)
var mate_down := {"mulgyeol": 0.0, "noeul": 0.0}
const MATE_REST := 10.0

func mate_max() -> float:
	return 60.0 + player.lv * 6.0

func mate_node(id: String) -> Node3D:
	return mate if id == "mulgyeol" else mate2

func mate_health(id: String) -> float:
	if mate_hp[id] < 0.0:
		mate_hp[id] = mate_max()
	return mate_hp[id]

func hurt_mate(id: String, dmg: int) -> void:
	var node := mate_node(id)
	if node == null or mate_down[id] > 0.0:
		return
	mate_hp[id] = mate_health(id) - dmg
	pop_num(node.position + Vector3(0, 1.9, 0), str(dmg), Color("#ffb07a"))
	sfx(260, 0.08, "triangle", 0.1, -100)
	if mate_hp[id] <= 0.0:
		mate_hp[id] = 0.0
		mate_down[id] = MATE_REST
		var spr: Sprite3D = node.get_child(0)
		spr.billboard = BaseMaterial3D.BILLBOARD_DISABLED # tilt by hand, as for Sora
		spr.rotation = Vector3(0, cam_yaw, PI / 2.0)
		spr.modulate = Color(0.6, 0.6, 0.65)
		spr.position.y = 0.3
		toast(tr("%s이(가) 쓰러져 잠시 쉰다") % tr("물결" if id == "mulgyeol" else "노을"))

# companions near a strike or a thrown brick take the hit as well
func mate_near(at: Vector2, r: float) -> String:
	for id in ["mulgyeol", "noeul"]:
		var node := mate_node(id)
		if node != null and node.visible and mate_down[id] <= 0.0 and Vector2(node.position.x, node.position.z).distance_to(at) < r:
			return id
	return ""

# returns true while the companion is down (its update should stop there)
func mate_tick(id: String, dt: float) -> bool:
	var node := mate_node(id)
	var spr: Sprite3D = node.get_child(0)
	if mate_down[id] > 0.0:
		mate_down[id] -= dt
		if mate_down[id] <= 0.0 or not node.visible:
			mate_down[id] = 0.0
			mate_hp[id] = mate_max() * 0.5
			spr.rotation = Vector3.ZERO
			spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
			spr.modulate = Color.WHITE
			spr.position.y = 0.0
			burst(node.position + Vector3(0, 0.8, 0), Color("#9fe0ff"), 10, 1.2)
		return mate_down[id] > 0.0
	var calm := not enemies.any(func(e): return not e.dead and not e.get("prop", false) and Vector2(e.x - node.position.x, e.z - node.position.z).length() < 8.0)
	if calm:
		mate_hp[id] = minf(mate_max(), mate_health(id) + 4.0 * dt)
	return false

func update_mate2(dt: float) -> void:
	if mate2 == null:
		return
	mate2.visible = not in_cave
	var me := Vector3(player.x, 0, player.z)
	if mate2.position.distance_to(me) > 8.0:
		mate2.position = me + Vector3(1.3, 0, -0.6)
	var spr: Sprite3D = mate2.get_child(0)
	if mate_tick("noeul", dt):
		return
	mate2_cd -= dt
	var goal := me + Vector3(1.3, 0, -0.6)
	if not walkable(goal.x, goal.z):
		goal = me # her side is inside a house or a rock: just follow her
	var to := goal - mate2.position
	if to.length() > 0.3:
		mate2.position = mate_step(mate2.position, to.normalized() * minf(to.length() - 0.3, dt * 5.5))
		spr.frame = 1
		spr.flip_h = screen_left(Vector2(to.x, to.z))
	else:
		spr.frame = 0
	var target = null
	var best := 4.0
	for e in enemies:
		var dd := Vector2(e.x, e.z).distance_to(Vector2(mate2.position.x, mate2.position.z))
		if not e.dead and dd < best and not e.get("air", false) and not e.get("prop", false):
			best = dd
			target = e
	if target != null and mate2_cd <= 0.0 and not story_open:
		mate2_cd = 1.4
		spr.frame = 2
		damage_enemy(target, player.atk * 0.7, Vector2(mate2.position.x, mate2.position.z), 2.0)
		burst(Vector3(target.x, 0.8, target.z), Color("#9a9a9a"), 12, 2.0)

func update_mate(dt: float) -> void:
	if mate == null:
		return
	mate.visible = not in_cave
	var me := Vector3(player.x, 0, player.z)
	if mate.position.distance_to(me) > 8.0:
		snap_mate()
	var spr: Sprite3D = mate.get_child(0)
	if mate_tick("mulgyeol", dt):
		return
	mate_cd -= dt
	var target = null
	var best := 5.0
	for e in enemies:
		if not e.dead and not e.get("prop", false) and Vector2(e.x, e.z).distance_to(Vector2(mate.position.x, mate.position.z)) < best:
			best = Vector2(e.x, e.z).distance_to(Vector2(mate.position.x, mate.position.z))
			target = e
	var goal := me + Vector3(-1.3, 0, -0.6)
	if not walkable(goal.x, goal.z):
		goal = me
	if target != null:
		goal = Vector3(target.x, 0, target.z)
	var to := goal - mate.position
	var stop := 1.4 if target != null else 0.3
	if to.length() > stop:
		mate.position = mate_step(mate.position, to.normalized() * minf(to.length() - stop, dt * 5.5))
		mate.position.y = absf(sin(t * 11.0)) * 0.06
		spr.flip_h = screen_left(Vector2(to.x, to.z))
	else:
		mate.position.y = 0.0
	spr.frame = 1 if fmod(t, 3.0) < 0.3 else 0
	if target != null and best < 1.9 and mate_cd <= 0.0 and not story_open:
		mate_cd = 1.0
		damage_enemy(target, player.atk * 0.6, Vector2(mate.position.x, mate.position.z), 3.0)
		burst(Vector3(target.x, 0.8, target.z), Color("#7fd8d0"), 8, 1.6)

# ---- the wind hills (between the forest and the garden)
func enter_hill() -> void:
	in_forest = false
	in_hill = true
	player.x = hill.marks.S.x + 1.2
	player.z = hill.marks.S.y
	ground_y = 0.0
	ui.mini.map_tex = hill.map_tex(HILL.HILL_X + HILL.W)
	ui.zone_name.text = "바람 언덕"
	ui.zone_sub.text = "멈춘 풍차들"
	snap_mates()
	if hill_q == 0:
		hill_q = 1
		for f in hill.foes:
			if f[1] == "w":
				spawn_wolf(f[0])
				continue
			spawn_enemy(f[0], f[1] == "a")
			var e: Dictionary = enemies[enemies.size() - 1]
			e.cave = true
			if f[1] == "s":
				give_shield(e)
		show_story("", STORY.HILL_IN)
	if hill_q == 1:
		set_quest(tr("풍차를 왕관으로 감자 (E) %d/3") % hill.turning_count())
	elif hill_q == 2:
		set_quest("바람 다리를 건너 벽돌 매를 물리치자")
	save_game()

func leave_hill() -> void:
	in_hill = false
	in_forest = true
	player.x = forest.marks.E.x - 1.2
	player.z = forest.marks.E.y
	ground_y = 0.0
	ui.mini.map_tex = forest.map_tex(FOREST.FOREST_X + FOREST.W)
	ui.zone_name.text = "굳은 숲"
	ui.zone_sub.text = "노을의 빈터"
	ui.boss.visible = false
	snap_mates()
	save_game()

# a shield goblin: a round brick shield in front that takes three hits to break,
# and is lowered while the goblin winds up its own attack
func give_shield(e: Dictionary) -> void:
	e.shield = 3
	var sh := box(Vector3(0.7, 0.7, 0.12), mat_color(Color("#c8962a")))
	sh.position = Vector3(0, 0.5, 0.36)
	(e.node.get_meta("body") as Node3D).add_child(sh)
	e.shield_node = sh

func hill_key() -> bool:
	for mill in hill.mills:
		if not mill.turning and Vector2(player.x, player.z).distance_to(mill.pos) < 1.9:
			if not spend_pips(1):
				return true
			hill.wind_mill(mill, self)
			burst(Vector3(mill.pos.x, 3.0, mill.pos.y + 0.7), Color("#f2ead8"), 30, 3.0)
			sfx(330, 0.5, "sine", 0.25, 200)
			var n: int = hill.turning_count()
			if n >= 3:
				hill_q = 2
				hill.raise_bridge()
				ui.mini.map_tex = hill.map_tex(HILL.HILL_X + HILL.W)
				show_story("", STORY.WIND_BRIDGE)
				set_quest("바람 다리를 건너 벽돌 매를 물리치자")
			else:
				set_quest(tr("풍차를 왕관으로 감자 (E) %d/3") % n)
			save_game()
			return true
	return false

func update_hill(dt: float) -> void:
	for mill in hill.mills:
		if mill.turning:
			mill.blades.rotation.z += dt * 1.6
	if hill_q == 2 and not story_open and Vector2(player.x, player.z).distance_to(hill.marks.B) < 6.0 \
			and not enemies.any(func(e): return e.get("hawk", false) and not e.dead):
		show_story("", STORY.HAWK_IN)
		after_story = spawn_hawk

func spawn_hawk() -> void:
	if enemies.any(func(e): return e.get("hawk", false) and not e.dead):
		return
	var at: Vector2 = hill.marks.B
	var root := Node3D.new()
	var body := Node3D.new()
	body.name = "body"
	root.add_child(body)
	var brown: Material = mat_color(Color("#8a6a4a"))
	var grey: Material = mat_color(Color("#9a9aa2"))
	for part in [[Vector3(0.7, 0.6, 1.2), Vector3(0, 0, 0), brown], [Vector3(0.5, 0.5, 0.5), Vector3(0, 0.25, 0.75), grey],
			[Vector3(0.18, 0.14, 0.3), Vector3(0, 0.18, 1.1), mat_color(Color("#e8a020"))], [Vector3(0.5, 0.15, 0.6), Vector3(0, 0, -0.85), brown]]:
		var b := box(part[0], part[2])
		b.position = part[1]
		body.add_child(b)
	for side in [-1.0, 1.0]:
		var wing := Node3D.new()
		wing.name = "wing_l" if side < 0 else "wing_r"
		wing.position = Vector3(side * 0.35, 0.1, 0)
		body.add_child(wing)
		var w := box(Vector3(1.6, 0.1, 0.8), grey)
		w.position = Vector3(side * 0.8, 0, 0)
		wing.add_child(w)
	for side in [-0.14, 0.14]:
		var eye := box(Vector3(0.08, 0.08, 0.05), glow_mat(Color("#ffb040"), 2.0))
		eye.position = Vector3(side, 0.35, 1.0)
		body.add_child(eye)
	root.scale = Vector3.ONE * 1.4
	add_child(root)
	enemies.append({"x": at.x, "z": at.y, "hp": 780.0, "max_hp": 780, "node": root, "shadow": blob(1.2), "t": 0.0,
		"atk_cd": 2.5, "hurt": 0.0, "kx": 0.0, "kz": 0.0, "wx": at.x, "wz": at.y, "dead": false, "respawn": 0.0,
		"hawk": true, "cave": true, "air": true, "y": 2.8, "wind": 0.0, "dash": 0.0, "dir": Vector2.ZERO,
		"stun": 0.0, "target": Vector2.ZERO, "egg_cd": 1.5, "eggs": []})

# the brick hawk circles out of reach (no damage while "air"); it marks Sora's spot, dives onto it,
# and sits stunned on the ground for 2 s. Below half HP it drops brick eggs while circling.
func update_hawk(e: Dictionary, dt: float, d: float, to: Vector2) -> void:
	var node: Node3D = e.node
	var body: Node3D = node.get_node("body")
	ui.boss.visible = true
	ui.boss_name.text = "벽돌 매"
	ui.boss_bar.size.x = 420.0 * maxf(0.0, e.hp) / e.max_hp
	e.t += dt
	e.hurt -= dt
	e.stun -= dt
	var flap := sin(e.t * (14.0 if e.air else 3.0)) * 0.5
	body.get_node("wing_l").rotation.z = flap
	body.get_node("wing_r").rotation.z = -flap
	var c: Vector2 = hill.marks.B
	if e.dash > 0.0: # diving onto the marked spot
		e.dash -= dt
		var k: float = 1.0 - e.dash / 0.5
		e.x = lerpf(e.wx, e.target.x, k)
		e.z = lerpf(e.wz, e.target.y, k)
		e.y = lerpf(2.8, 0.4, k)
		if e.dash <= 0.0:
			e.air = false
			e.stun = 2.0
			shake = 0.3
			burst(Vector3(e.x, 0.3, e.z), Color("#9a9aa2"), 24, 3.0)
			sfx(80, 0.3, "square", 0.3, -40)
			if Vector2(player.x, player.z).distance_to(e.target) < 1.4:
				player_hit(24, e.target, e)
	elif e.stun > 0.0:
		pass
	elif not e.air: # take off again
		e.y = minf(2.8, e.y + dt * 3.0)
		if e.y >= 2.8:
			e.air = true
			e.atk_cd = 2.3
	elif e.wind > 0.0:
		e.wind -= dt
		if e.wind <= 0.0:
			e.dash = 0.5
			e.wx = e.x
			e.wz = e.z
	else:
		var a: float = e.t * 0.9
		var goal := c + Vector2(cos(a), sin(a)) * 3.0
		e.x = lerpf(e.x, goal.x, dt * 2.0)
		e.z = lerpf(e.z, goal.y, dt * 2.0)
		e.atk_cd -= dt
		if e.atk_cd <= 0.0:
			e.wind = 1.0
			e.target = Vector2(player.x, player.z)
			warn_ring(Vector3(e.target.x, 0.0, e.target.y), 1.4, 1.5)
			sfx(900, 0.4, "sawtooth", 0.15, -500)
		if e.hp < e.max_hp / 2.0:
			e.egg_cd -= dt
			if e.egg_cd <= 0.0:
				e.egg_cd = 1.3
				var p := Vector2(player.x, player.z) + Vector2(rnd(-2, 2), rnd(-2, 2))
				warn_ring(Vector3(p.x, 0.0, p.y), 1.0, 0.8)
				get_tree().create_timer(0.8).timeout.connect(func():
					burst(Vector3(p.x, 0.3, p.y), Color("#c8322a"), 14, 2.5)
					if Vector2(player.x, player.z).distance_to(p) < 1.0:
						player_hit(14, p, e))
	var face := Vector2(e.target.x - e.x, e.target.y - e.z) if e.wind > 0.0 or e.dash > 0.0 else Vector2(cos(e.t * 0.9 + PI / 2), sin(e.t * 0.9 + PI / 2))
	if face.length() > 0.1:
		node.rotation.y = atan2(face.x, face.y)
	node.position = Vector3(e.x, e.y, e.z)
	e.shadow.position = Vector3(e.x, 0.02, e.z)

func hawk_beaten() -> void:
	hill_q = 3
	ui.boss.visible = false
	player.gold += 250
	gain_xp(300)
	show_story("", STORY.HAWK_DOWN)
	set_quest("언덕 동쪽 끝 길로, 달지기들의 성에 가자")
	save_game()

# ---- the heart of the garden (story steps 11 and 12)
func enter_garden() -> void:
	in_forest = false
	in_hill = false
	in_garden = true
	story_step = maxi(story_step, 11)
	player.x = garden.marks.S.x + 1.5
	player.z = garden.marks.S.y
	ground_y = 0.0
	ui.mini.map_tex = garden.map_tex(GARDEN.GARDEN_X + GARDEN.W)
	ui.zone_name.text = "정원 한가운데"
	ui.zone_sub.text = "굳은달 빈터"
	if garden_q == 0:
		garden_q = 1
		show_story("", STORY.GARDEN_IN)
	if garden_q < 5:
		if garden.seals_open() < garden.seals.size():
			set_quest(tr("거푸집 둘레의 벽돌 봉인을 풀자 (E) %d/3") % garden.seals_open())
		else:
			set_quest("굳은달 거푸집의 심장을 노리자")
	if garden_q >= 5:
		garden.set_posts(8)
	save_game()

func leave_garden() -> void:
	if not castle.door_open: # a save from before the castle: open the way back west
		for pg in castle.pages:
			pg.read = true
		castle.open_door()
		castle.open_gate()
	in_garden = false
	in_hill = true
	player.x = castle.marks.E.x - 1.2
	player.z = castle.marks.E.y
	ground_y = 0.0
	ui.mini.map_tex = castle.map_tex(CASTLE.CASTLE_X + CASTLE.W)
	ui.zone_name.text = "가라앉은 달지기 성"
	ui.zone_sub.text = "옥좌의 방"
	snap_mates()
	ui.boss.visible = false
	save_game()

func update_garden(dt: float) -> void:
	if garden_q == 1 and not story_open and garden.seals_open() == garden.seals.size() and Vector2(player.x, player.z).distance_to(garden.marks.C) < 8.0:
		garden_q = 2
		spawn_mold()
	if not mold_wave.is_empty():
		update_mold_wave(dt)
	update_ring(dt)

# E beside a seal: one pip unwinds it (the heart is near, so the crown is strong), and two goblins break out
func seal_key() -> bool:
	for sl in garden.seals:
		if not sl.open and Vector2(player.x, player.z).distance_to(sl.pos) < 1.6:
			if not spend_pips(1):
				return true
			garden.open_seal(sl)
			burst(Vector3(sl.pos.x, 0.8, sl.pos.y), Color("#9a4ad8"), 30, 3.5)
			shake = 0.25
			sfx(150, 0.5, "triangle", 0.3, -40)
			for k in 2:
				spawn_enemy(sl.pos + Vector2(rnd(-1.5, 1.5), rnd(-1.5, 1.5)))
				enemies[enemies.size() - 1].cave = true
			var n: int = garden.seals_open()
			if n == garden.seals.size():
				toast("마지막 봉인이 풀렸다. 거푸집이 깨어난다")
			else:
				toast(tr("벽돌 봉인 %d/3") % n)
				set_quest(tr("거푸집 둘레의 벽돌 봉인을 풀자 (E) %d/3") % n)
			save_game()
			return true
	return false

func spawn_mold() -> void:
	if enemies.any(func(e): return e.get("mold", false) and not e.dead):
		return
	var c: Vector2 = garden.marks.C
	var node: Node3D = garden.mold(self)
	enemies.append({"x": c.x, "z": c.y, "hp": 1700.0, "max_hp": 1700, "node": node, "shadow": blob(2.2), "t": 0.0,
		"atk_cd": 2.5, "hurt": 0.0, "kx": 0.0, "kz": 0.0, "wx": c.x, "wz": c.y, "dead": false, "respawn": 0.0,
		"mold": true, "cave": true, "wind": 0.0, "stun": 0.0, "next": 0, "rings": [], "locked": false})

func mold_phase(e: Dictionary) -> int:
	var f: float = e.hp / e.max_hp
	return 1 if f > 0.66 else (2 if f > 0.33 else 3)

# the mold: drifts toward Sora; slams rings of brick (1, 3, 5 by phase), sends a shock ring out (phase 2+),
# and wakes goblins (every third move). At 12% it locks and the last wind begins.
func update_mold(e: Dictionary, dt: float, d: float, to: Vector2) -> void:
	var node: Node3D = e.node
	ui.boss.visible = true
	ui.boss_name.text = "굳은달 거푸집"
	ui.boss_bar.size.x = 420.0 * maxf(0.0, e.hp) / e.max_hp
	e.t += dt
	e.hurt -= dt
	var crescent: Node3D = node.get_node("crescent")
	crescent.rotation.y += dt * (0.4 + 0.3 * mold_phase(e))
	var heart: MeshInstance3D = node.get_node("heart")
	heart.position.y = 1.0 + sin(e.t * 3.0) * 0.15
	heart.scale = Vector3.ONE * (1.3 if e.hurt > 0.0 else 1.0)
	if e.locked:
		node.position = Vector3(e.x, 0, e.z)
		return
	if e.hp <= e.max_hp * 0.12 and garden_q == 2:
		mold_locks(e)
		return
	var ph := mold_phase(e)
	if e.wind > 0.0:
		e.wind -= dt
		if e.wind <= 0.0:
			for r in e.rings:
				burst(Vector3(r.x, 0.3, r.y), Color("#8a8a96"), 18, 3.0)
				if Vector2(player.x, player.z).distance_to(r) < 1.3:
					player_hit(18 + 4 * ph, r, e)
			shake = 0.2
			sfx(70, 0.3, "square", 0.25, -30)
			e.atk_cd = 2.0 - 0.4 * ph
	else:
		e.atk_cd -= dt
		if e.atk_cd <= 0.0:
			e.next = int(e.next) + 1
			if int(e.next) % 3 == 0 and enemies.filter(func(g): return not g.dead and in_garden_x(g.x) and not g.get("mold", false)).size() < 4:
				for k in 2: # wakes two goblins at the arena's edge
					var a := rnd(0, TAU)
					spawn_enemy(garden.marks.C + Vector2(cos(a), sin(a)) * 7.0)
					enemies[enemies.size() - 1].cave = true
				e.atk_cd = 1.5
			elif ph >= 2 and int(e.next) % 3 == 1 and mold_wave.is_empty():
				start_mold_wave(e)
				e.atk_cd = 2.4
			else:
				e.wind = 0.9
				e.rings = [Vector2(player.x, player.z)]
				for k in (ph - 1) * 2:
					e.rings.append(Vector2(player.x, player.z) + Vector2(rnd(-3, 3), rnd(-3, 3)))
				for r in e.rings:
					warn_ring(Vector3(r.x, 0.0, r.y), 1.3, 0.9)
		elif d > 1.3: # drifts after Sora, slowly
			var nx: float = e.x + to.x / d * 0.9 * dt
			var nz: float = e.z + to.y / d * 0.9 * dt
			if Vector2(nx, nz).distance_to(garden.marks.C) < 5.0:
				e.x = nx
				e.z = nz
	node.position = Vector3(e.x, 0, e.z)
	e.shadow.position = Vector3(e.x, 0.02, e.z)

# a ring of grey force rolls outward from the mold; dodge through it (the flash dodge works) or be hit
func start_mold_wave(e: Dictionary) -> void:
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.85
	tor.outer_radius = 1.0
	ring.mesh = tor
	ring.material_override = glow_mat(Color("#b48cff"), 2.0)
	ring.position = Vector3(e.x, 0.2, e.z)
	add_child(ring)
	mold_wave = {"r": 0.5, "node": ring, "c": Vector2(e.x, e.z), "hit": false}
	pop_num(Vector3(e.x, 3.0, e.z), "!", Color("#ff5a4a"))
	sfx(110, 0.6, "sawtooth", 0.25, 200)

func update_mold_wave(dt: float) -> void:
	mold_wave.r += dt * 5.0
	var ring: MeshInstance3D = mold_wave.node
	ring.scale = Vector3(mold_wave.r, 1.0, mold_wave.r)
	var pd: float = Vector2(player.x, player.z).distance_to(mold_wave.c)
	if not mold_wave.hit and absf(pd - mold_wave.r) < 0.45:
		mold_wave.hit = true
		var e: Dictionary = {} if enemies.is_empty() else enemies.filter(func(m): return m.get("mold", false))[0]
		player_hit(22, mold_wave.c, e)
	if mold_wave.r > 10.0:
		ring.queue_free()
		mold_wave = {}

func in_garden_x(x: float) -> bool:
	return x >= GARDEN.GARDEN_X - 0.5 and x < GARDEN.GARDEN_X + GARDEN.W

func mold_locks(e: Dictionary) -> void:
	e.locked = true
	garden_q = 3
	crown_pips = 0
	pip_flash = 0.5
	for g in enemies:
		if not g.dead and in_garden_x(g.x) and not g.get("mold", false):
			g.dead = true
			g.node.visible = false
			g.shadow.visible = false
	show_story("", STORY.FINAL_SHORT)
	after_story = light_ring
	save_game()

# the villagers light the ring posts one by one, each filling one pip. For every post the locked mold
# sheds two grey shards that run for that post; a shard that reaches it snuffs the flame and the post
# starts over. A post lights once its shards are cut down and at least 1.5 s have passed.
func light_ring() -> void:
	ring_k = 0
	ring_t = 0.0
	set_quest("마을 사람들이 등불을 켜는 동안 거푸집 조각을 막자 0/8")
	shed_shards()

func shed_shards() -> void:
	var c: Vector2 = garden.marks.C
	var l: OmniLight3D = garden.posts[ring_k]
	for k in 2:
		var at := c + Vector2(rnd(-1.5, 1.5), rnd(-1.5, 1.5))
		spawn_enemy(at)
		var e: Dictionary = enemies[enemies.size() - 1]
		e.shard = true
		e.cave = true # no respawn
		e.hp = 18.0 + player.lv * 4
		e.max_hp = int(e.hp)
		e.post = Vector2(l.position.x, l.position.z)
		var mats: Array = e.node.get_meta("mats")
		for m in mats:
			m.albedo_color = Color("#8a8a96").lightened(rnd(0, 0.15))
		burst(Vector3(at.x, 1.0, at.y), Color("#8a8a96"), 10, 2.0)
	sfx(110, 0.3, "square", 0.15, -30)

func update_ring(dt: float) -> void:
	if ring_k < 0 or garden_q != 3 or story_open:
		return
	ring_t += dt
	var alive := enemies.filter(func(e): return e.get("shard", false) and not e.dead)
	if alive.is_empty() and ring_t >= 1.5:
		garden.set_posts(ring_k + 1)
		crown_pips = ring_k + 1
		pip_flash = 0.3
		var l: OmniLight3D = garden.posts[ring_k]
		burst(l.position, Color("#ffc46a"), 16, 2.0)
		sfx(392 + 40 * ring_k, 0.25, "sine", 0.2)
		ring_k += 1
		ring_t = 0.0
		if ring_k >= 8:
			ring_k = -1
			garden_q = 4
			set_quest("왕관을 높이 들어 다 같이 땅을 감자 (E)")
			save_game()
		else:
			set_quest(tr("마을 사람들이 등불을 켜는 동안 거푸집 조각을 막자 %d/8") % ring_k)
			shed_shards()

# a shard ignores Sora and runs for its post; reaching it snuffs the flame being lit and two more come
func update_shard(e: Dictionary, dt: float) -> void:
	var to: Vector2 = e.post - Vector2(e.x, e.z)
	var d := to.length()
	if e.hurt <= 0.0 and e.get("stun", 0.0) <= 0.0:
		e.x += to.x / maxf(d, 0.01) * 1.9 * dt
		e.z += to.y / maxf(d, 0.01) * 1.9 * dt
	e.t += dt
	e.hurt -= dt
	e.stun = e.get("stun", 0.0) - dt
	var node: Node3D = e.node
	var hop := absf(sin(e.t * 8.0))
	node.position = Vector3(e.x, hop * 0.12, e.z)
	node.rotation.y = atan2(to.x, to.y)
	for m in node.get_meta("mats"):
		m.emission_enabled = e.hurt > 0
		m.emission = Color.WHITE
	e.shadow.position = Vector3(e.x, 0.02, e.z)
	if d < 0.8:
		e.dead = true
		e.node.queue_free()
		e.shadow.queue_free()
		burst(Vector3(e.post.x, 1.5, e.post.y), Color("#4a4652"), 24, 3.0)
		shake = 0.2
		sfx(90, 0.3, "square", 0.2, -40)
		toast("거푸집 조각이 등불을 덮쳤다!")
		for g in enemies:
			if g.get("shard", false) and not g.dead:
				g.dead = true
				g.node.queue_free()
				g.shadow.queue_free()
		ring_t = 0.0
		shed_shards()

func final_wind() -> void:
	garden_q = 5
	crown_pips = 0
	burst(Vector3(player.x, 2.0, player.z), Color("#fff1a0"), 60, 6.0)
	shake = 0.6
	show_story("res://art/story/11_final_mold.jpg", STORY.FINAL_WIND)
	after_story = mold_breaks
	save_game()

func mold_breaks() -> void:
	for e in enemies:
		if e.get("mold", false) and not e.dead:
			e.dead = true
			for k in 6:
				burst(Vector3(e.x + rnd(-2, 2), rnd(0.5, 4.0), e.z + rnd(-2, 2)), Color("#8a8a96"), 30, 5.0)
			e.node.queue_free()
			e.shadow.queue_free()
	ui.boss.visible = false
	crown_pips = 8
	player.gold += 500
	gain_xp(400)
	story_step = 12
	var record: String = tr("||여기까지 걸린 시간 %s, 물리친 괴물 %d마리, 이룬 도전 과제 %d/6.") % [play_time_text(), stats.kills, feats_done.count(true)]
	show_story("res://art/story/12_festival.jpg", STORY.ENDING + [record])
	set_quest("끝. 다시 돌기 시작한 정원을 거닐자 (정원 한가운데서 E 두 번: 새 바퀴)")
	save_game()

# put the kid goblin where kid_q says: in the field with guards, or beside Kongal
func place_kid() -> void:
	if kid_node == null:
		kid_node = village.kid_goblin(self)
	var vx := float(VILLAGE.VILLAGE_X)
	match kid_q:
		1:
			kid_node.position = Vector3(vx + village.KID_AT.x, 0, village.KID_AT.y)
			for at in village.KID_GUARDS:
				spawn_enemy(Vector2(vx + at.x, at.y))
				enemies[enemies.size() - 1].cave = true # they do not come back
		2:
			kid_node.position = Vector3(player.x - 0.8, 0, player.z + 0.4)
		3:
			var k: Vector2 = village.folk_pos.kongal
			kid_node.position = Vector3(k.x + 0.7, 0, k.y + 0.3)

# the lent firefly jar glows at Sora's side after dark and works like a lantern for resting:
# at night the crown's pips refill anywhere calm, one every 20 s (10 s beside a real lantern).
# It has no OmniLight on purpose: the marsh ground is one mesh and the web renderer lights a mesh with at most 8.
func build_jar() -> void:
	if jar_node != null:
		return
	jar_node = Node3D.new()
	var glass: MeshInstance3D = box(Vector3(0.16, 0.2, 0.16), glow_mat(Color("#d8ff7a"), 3.0))
	jar_node.add_child(glass)
	var lid: MeshInstance3D = box(Vector3(0.18, 0.05, 0.18), mat_color(Color("#7a5a32")))
	lid.position = Vector3(0, 0.12, 0)
	jar_node.add_child(lid)
	add_child(jar_node)

func update_kid(dt: float) -> void:
	if kid_node == null or not in_village:
		return
	kid_node.visible = in_village
	var me := Vector3(player.x, 0, player.z)
	if kid_q == 1 and me.distance_to(kid_node.position) < 1.2:
		var near := enemies.filter(func(e): return not e.dead and Vector2(e.x, e.z).distance_to(Vector2(player.x, player.z)) < 7.0)
		if near.is_empty():
			kid_q = 2
			burst(kid_node.position + Vector3(0, 0.6, 0), Color("#8de07a"), 16, 1.5)
			sfx(784, 0.2, "triangle", 0.2)
			toast("꼬마 고블린이 소라를 따라온다")
			set_quest("꼬마 고블린을 콩알에게 데려다주자 (E)")
			save_game()
		elif toast_t <= 0.0:
			toast("큰 고블린들이 꼬마를 붙잡고 있다")
	if kid_q == 2: # trot after Sora, a step behind
		var to := me - kid_node.position
		if to.length() > 1.0:
			kid_node.position += to.normalized() * minf(to.length() - 1.0, dt * 5.0)
		var trot := to.length() > 1.05
		kid_node.position.y = absf(sin(t * 12.0)) * 0.08 if trot else 0.0
		kid_node.get_meta("spr").frame = (1 if sin(t * 12.0) > 0.0 else 0) if trot else 0

func light_village_lamp(d: Dictionary) -> void:
	d.lit = true
	d.light.set_meta("dark", false)
	d.glass.material_override = d.glass.get_meta("lit_mat")
	burst(d.light.position, Color("#ffc46a"), 24, 2.5)
	burst(Vector3(player.x, 1.6, player.z), Color("#9fd4ff"), 14, 1.5)
	sfx(523, 0.4, "sine", 0.3, 300)
	var n: int = village.lit_count()
	if n >= 3:
		errand = 2
		set_quest("등불지기 심지에게 돌아가자")
	else:
		set_quest(tr("동쪽 끝 꺼진 등불을 왕관으로 켜자 (E) %d/3") % n)
	var at: Vector2 = d.brick
	get_tree().create_timer(1.0).timeout.connect(func():
		spawn_enemy(at)
		var g: Dictionary = enemies[enemies.size() - 1]
		g.cave = true # village goblins do not come back
		burst(Vector3(at.x, 0.4, at.y), Color("#c9a066"), 20, 2.0)
		pop_num(Vector3(at.x, 1.3, at.y), "!", Color("#ff5a4a")))
	save_game()

# rest beside a lit lantern at night with no monster near: one pip every 10 s
var rest_need := 10.0        # seconds of rest for the next pip (lantern 10, jar 20, both x0.6 with the tea)

func update_pips(dt: float) -> void:
	pip_flash -= dt
	var night_now := is_night()
	if crown_pips >= 8 or not night_now:
		rest_t = 0.0
		return
	var me := Vector3(player.x, 0, player.z)
	var near_lamp := false
	for l in lanterns:
		if not l.get_meta("dark", false) and l != dark_lamp and Vector2(l.position.x - me.x, l.position.z - me.z).length() < 2.0:
			near_lamp = true
	var calm := true
	for e in enemies:
		if not e.dead and Vector2(e.x - me.x, e.z - me.z).length() < 6.0:
			calm = false
	var jar := fly_q >= 3
	rest_need = (10.0 if near_lamp else 20.0) * (0.6 if has_tea else 1.0)
	if (near_lamp or jar) and calm and Vector2(player.vx, player.vz).length() < 0.3:
		rest_t += dt
		if rest_t >= rest_need:
			rest_t = 0.0
			crown_pips += 1
			burst(Vector3(player.x, ground_y + 1.6, player.z), Color("#9fd4ff"), 10, 1.2)
			sfx(880, 0.15, "sine", 0.15)
	else:
		rest_t = 0.0

# parchment map of the cave, drawn at its world offset so the minimap math stays the same
func cave_map_tex() -> ImageTexture:
	var img := Image.create(CAVE_X + CAVE_W, CAVE_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for z in CAVE_H:
		for x in CAVE_W:
			var c: String = cave_grid[z][x]
			var col := Color(0, 0, 0, 0) if c == "#" else (Color("#3fe0e0") if c == "w" else Color("#2a5a8a"))
			if c == "D" and not cave_door_open:
				col = Color("#c8962a")
			if c == "E":
				col = Color("#ffd060")
			img.set_pixel(CAVE_X + x, z, col)
	return ImageTexture.create_from_image(img)
var fade_rect: ColorRect

func fade_then(fn: Callable) -> void:
	var tw := create_tween()
	tw.tween_property(fade_rect, "color:a", 1.0, 0.4)
	tw.tween_callback(fn)
	tw.tween_property(fade_rect, "color:a", 0.0, 0.4)

const CAVE_SPAWNS := [ # [x, z, archer] in cave tiles
	[13, 4, false], [15, 2, false],
	[24, 2, false], [26, 5, false], [29, 3, true],
	[3, 11, false], [6, 14, false], [4, 16, false],
	[13, 11, true], [18, 15, true],
]
var cave_spawned := false
var cave_exit_seen := false
var has_key := false
var saw_painting := false
var door_node: Node3D
var key_chest: Sprite3D

# key chest, locked door and the wall painting with the rival's first appearance
func build_cave_props() -> void:
	var k: Vector2 = cave_marks.K
	key_chest = Sprite3D.new()
	key_chest.texture = chests[0].node.texture if not chests.is_empty() else null
	key_chest.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	key_chest.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	key_chest.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	key_chest.shaded = false
	key_chest.pixel_size = 0.05
	key_chest.offset = Vector2(0, 7)
	key_chest.scale = Vector3(1, 1.0 / cos(0.78), 1)
	key_chest.modulate = Color("#9fd4ff")
	key_chest.position = Vector3(k.x, 0.0, k.y)
	add_child(key_chest)
	var d: Vector2 = cave_marks.D
	door_node = Node3D.new()
	door_node.position = Vector3(d.x, 0, d.y)
	add_child(door_node)
	var wood := mat_color(Color("#7a4a24"))
	for i in 3:
		var plank := box(Vector3(0.3, 1.4, 0.9), wood)
		plank.position = Vector3(-0.32 + i * 0.32, 0.7, 0)
		door_node.add_child(plank)
	var lock := box(Vector3(0.2, 0.25, 0.95), mat_color(Color("#d9b04a")))
	lock.position = Vector3(0, 0.8, 0)
	door_node.add_child(lock)
	var p: Vector2 = cave_marks.P
	var wall := box(Vector3(2.4, 1.2, 0.06), glow_mat(Color("#3a6aa8"), 1.2))
	wall.position = Vector3(p.x, 0.9, p.y - 1.45)
	add_child(wall)

# the shrine of three stones under the cave's west hall: E or Space by a stone wakes that skill (it can be changed back)
func build_shrine() -> void:
	var stone: Material = mat_color(Color("#6a6a74"))
	var cols := [Color("#3a9cff"), Color("#ff7a1a"), Color("#ffd23a")] # whirl, ember, nova
	for i in 3:
		var at: Vector2 = cave_marks[str(i + 1)]
		var g := Node3D.new()
		var post := box(Vector3(0.7, 0.8, 0.7), stone)
		post.position = Vector3(0, 0.4, 0)
		g.add_child(post)
		var gm := StandardMaterial3D.new() # flat unshaded colour: an additive glow would bloom to white in the cave
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gm.albedo_color = cols[i]
		var gem := box(Vector3(0.32, 0.32, 0.32), gm)
		gem.name = "gem"
		gem.position = Vector3(0, 1.15, 0)
		g.add_child(gem)
		g.position = Vector3(at.x, 0, at.y)
		add_child(g)
		shrine_nodes.append(g)
		rocks.append({"x": at.x, "z": at.y, "r": 0.5})

func update_shrine(dt: float) -> void:
	for c in crystals:
		c.hurt -= dt
	for i in shrine_nodes.size():
		var gem: Node3D = shrine_nodes[i].get_node("gem")
		gem.rotation.y += dt * (2.5 if skill_up == i else 0.6)
		gem.scale = Vector3.ONE * (1.4 + sin(t * 3.0) * 0.1 if skill_up == i else 1.0)
	if in_cave and not shrine_seen and player.z > 17.6 and not story_open:
		shrine_seen = true
		show_story("", STORY.SHRINE_IN)
		save_game()

# ---- the singing crystals in the shrine room: each rings its own note when struck. Struck from the lowest note
# to the highest (the taller the crystal, the lower its note), a moonkeeper chest rises with the crystal ring:
# critical hits 15% -> 25%. A wrong note resets the run with a dull buzz.
const CRYSTAL_AT := [Vector2(2, 18), Vector2(6, 18), Vector2(10, 18), Vector2(13, 19)] # cave tiles
const CRYSTAL_NOTE := [2, 0, 3, 1] # rank of each crystal's note, 0 the lowest
const NOTES := [262.0, 330.0, 392.0, 523.0]
var crystal_run := 0         # how many notes in a row are right so far
var crystal_done := false
var has_ring := false
var crystal_chest: Node3D
var crystal_told := false

# the crystals live in their own list (not among the enemies): a sword swing in the cave checks them in attack()
var crystals: Array = []     # [{"x", "z", "node", "crystal": index, "hurt"}]

func spawn_crystals() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("#9fe0ff")
	for i in CRYSTAL_AT.size():
		var at: Vector2 = CRYSTAL_AT[i] + Vector2(CAVE_X, 0)
		var root := Node3D.new()
		var g := Node3D.new()
		root.add_child(g)
		var h: float = 1.8 - CRYSTAL_NOTE[i] * 0.45 # tallest sings lowest
		var c := box(Vector3(0.36, h, 0.36), mat)
		c.position = Vector3(0, h / 2.0, 0)
		c.rotation.y = 0.6
		g.add_child(c)
		var c2 := box(Vector3(0.2, h * 0.6, 0.2), mat)
		c2.position = Vector3(0.24, h * 0.3, 0.1)
		c2.rotation = Vector3(0, 0.3, -0.3)
		g.add_child(c2)
		root.position = Vector3(at.x, 0, at.y)
		add_child(root)
		root.set_meta("body", g)
		crystals.append({"x": at.x, "z": at.y, "node": root, "crystal": i, "hurt": 0.0})

func build_crystal_chest() -> void:
	crystal_chest = Node3D.new()
	for part in [[Vector3(0.8, 0.45, 0.55), Vector3(0, 0.22, 0), mat_color(Color("#3a5a7a"))], [Vector3(0.84, 0.1, 0.59), Vector3(0, 0.5, 0), glow_mat(Color("#9fe0ff"), 1.0)]]:
		var b := box(part[0], part[2])
		b.position = part[1]
		crystal_chest.add_child(b)
	crystal_chest.position = Vector3(CAVE_X + 7.0, 0, 21.0)
	crystal_chest.visible = crystal_done and not has_ring
	add_child(crystal_chest)

func crystal_hit(e: Dictionary) -> void:
	if e.hurt > 0.0:
		return # one sword swing rings it once
	e.hurt = 0.25
	var rank: int = CRYSTAL_NOTE[int(e.crystal)]
	sfx(NOTES[rank], 0.5, "sine", 0.3)
	burst(Vector3(e.x, 1.0, e.z), Color("#9fe0ff"), 8, 1.5)
	(e.node.get_meta("body") as Node3D).scale = Vector3.ONE * 1.12
	get_tree().create_timer(0.15).timeout.connect(func(): if is_instance_valid(e.node): (e.node.get_meta("body") as Node3D).scale = Vector3.ONE)
	if crystal_done:
		return
	if not crystal_told:
		crystal_told = true
		toast("수정이 맑게 운다. 낮은 소리부터 차례로 울려 볼까?")
	if rank == crystal_run:
		crystal_run += 1
		if crystal_run == NOTES.size():
			crystal_done = true
			crystal_chest.visible = true
			burst(crystal_chest.position + Vector3(0, 0.6, 0), Color("#9fe0ff"), 30, 3.0)
			for k in 4:
				get_tree().create_timer(0.12 * k).timeout.connect(func(): sfx(NOTES[k] * 2.0, 0.3, "sine", 0.2))
			toast("수정들이 함께 울리자 상자가 솟아올랐다")
			save_game()
	else:
		crystal_run = 1 if rank == 0 else 0
		get_tree().create_timer(0.2).timeout.connect(func(): sfx(110, 0.25, "square", 0.15))

func crystal_chest_key() -> bool:
	if not crystal_done or has_ring or Vector2(player.x, player.z).distance_to(Vector2(crystal_chest.position.x, crystal_chest.position.z)) > 1.6:
		return false
	has_ring = true
	for b in crystal_chest.get_children():
		b.transparency = 0.45
	burst(crystal_chest.position + Vector3(0, 0.8, 0), Color("#9fe0ff"), 40, 3.0)
	sfx(784, 0.12, "triangle", 0.25)
	show_story("", STORY.CRYSTAL_RING)
	save_game()
	return true

func shrine_key() -> bool:
	if crystal_chest_key():
		return true
	var me := Vector2(player.x, player.z)
	for i in 3:
		if me.distance_to(cave_marks[str(i + 1)]) < 1.4:
			if skill_up == i:
				toast("이미 깨어난 기술이다")
				return true
			skill_up = i
			burst(Vector3(cave_marks[str(i + 1)].x, 1.2, cave_marks[str(i + 1)].y), [Color("#9fd4ff"), Color("#ff8a2a"), Color("#fff1a0")][i], 30, 3.0)
			sfx(523, 0.15, "triangle", 0.22)
			get_tree().create_timer(0.12).timeout.connect(func(): sfx(784, 0.25, "triangle", 0.22))
			show_story("", [STORY.SHRINE_WHIRL, STORY.SHRINE_EMBER, STORY.SHRINE_NOVA][i])
			save_game()
			return true
	return false

func cave_interact() -> bool:
	var me := Vector2(player.x, player.z)
	if shrine_key():
		return true
	if not has_key and me.distance_to(cave_marks.K) < 1.5:
		has_key = true
		key_chest.modulate = Color(0.55, 0.55, 0.55)
		burst(key_chest.position + Vector3(0, 0.6, 0), Color("#ffd84a"), 24, 2.5)
		sfx(784, 0.12, "triangle", 0.25)
		toast("녹슨 열쇠를 얻었다")
		return true
	if not cave_door_open and me.distance_to(cave_marks.D) < 1.6:
		if has_key:
			cave_door_open = true
			door_node.queue_free()
			sfx(330, 0.3, "square", 0.2, 200)
			toast("문이 열렸다")
			ui.mini.map_tex = cave_map_tex()
		else:
			toast("잠겨 있다. 열쇠가 필요하다")
		return true
	return false

func check_painting() -> void:
	if saw_painting or Vector2(player.x, player.z).distance_to(cave_marks.P) > 2.0:
		return
	saw_painting = true
	show_story("res://art/story/06_cave_rival.jpg", STORY.PAINTING)
	set_quest("열쇠를 찾아 잠긴 문을 열자")
	save_game()

func enter_cave() -> void:
	in_cave = true
	if not cave_spawned:
		cave_spawned = true
		build_cave_props()
		spawn_mole()
		for c in CAVE_SPAWNS:
			spawn_enemy(Vector2(CAVE_X + c[0], c[1]), c[2])
		for b in BAT_SPOTS:
			if b.x < CASTLE.CASTLE_X:
				spawn_bat(b)

	story_step = maxi(story_step, 6)
	var sp: Vector2 = cave_marks.S
	player.x = sp.x
	player.z = sp.y
	ground_y = 0.0
	set_quest("동굴 깊은 곳으로")
	ui.outside_map = ui.mini.map_tex
	ui.mini.map_tex = cave_map_tex()
	ui.zone_name.text = "지하 동굴"
	ui.zone_sub.text = "벽 그림이 있는 동굴"
	save_game()

func leave_cave() -> void:
	in_cave = false
	story_step = 7
	player.x = 36.0 # east marsh shore
	player.z = 20.0
	ground_y = height_at(player.x, player.z)
	set_quest("동쪽 강을 물수제비 걸음으로 건너, 마을 불빛을 찾아라")
	if ui.has("outside_map"):
		ui.mini.map_tex = ui.outside_map
	ui.zone_name.text = "갈대늪"
	ui.zone_sub.text = "동쪽 물가"
	save_game()
	var first := not cave_exit_seen
	cave_exit_seen = true
	if first:
		show_story("", STORY.CAVE_EXIT)

func set_quest(text: String) -> void:
	ui.quest.text = text
	ui.quest.visible = text != ""
var story_lines: Array = []

const STORY := preload("res://story_lines.gd")
var typing := 0.0 # characters shown so far, for the typewriter reveal
var talk_mode := false

func show_story(path: String, lines: Array) -> void:
	fit_story()
	story_lines = lines.duplicate()
	var tex: Texture2D = load(path) if path != "" else null
	ui.story_img.texture = tex
	ui.story_frame.visible = tex != null
	talk_mode = path == ""
	ui.story.color = Color(0.008, 0.016, 0.043, 0.35 if talk_mode else 0.6) # the game stays visible behind
	for side in ["left", "right"]:
		ui["por_" + side].texture = null
	ui.story.modulate.a = 0.0
	ui.story.visible = true
	story_open = true
	show_line(story_lines.pop_front())
	create_tween().tween_property(ui.story, "modulate:a", 1.0, 0.6)

func show_line(line: String) -> void:
	var parts := line.split("|", true, 2)
	if parts.size() < 3:
		parts = PackedStringArray(["", "", line])
	ui.story_who.text = parts[0]
	var f := parts[1]
	if f == "-": # narration that also sends the other speaker off stage
		f = ""
		ui.por_right.texture = null
	var is_sora := parts[0] == "소라"
	var path := "res://art/ui/face_sora_%s.png" % f if is_sora else "res://art/ui/face_%s.png" % f
	ui.story_face.texture = load(path) if f != "" and ResourceLoader.exists(path) else null
	if talk_mode:
		# speaker's standing portrait lights up; the listener dims; narration dims both
		var por := "res://art/portrait/sora_%s.png" % f if is_sora else "res://art/portrait/%s.png" % f
		var side := "left" if is_sora else "right"
		if f != "" and ResourceLoader.exists(por):
			ui["por_" + side].texture = load(por)
		for sd in ["left", "right"]:
			var lit: bool = f != "" and sd == side
			ui["por_" + sd].modulate = Color(1, 1, 1) if lit else Color(0.45, 0.45, 0.55)
			ui["por_" + sd].offset_top = (-650.0 if lit else -630.0)
		ui.story_face.texture = null # the portrait already shows who is talking
	ui.story_text.position.x = 140.0 if ui.story_face.texture else 40.0
	ui.story_tab.visible = parts[0] != ""
	ui.story_text.text = tr(parts[2]) # translated here so the typewriter counts the shown text
	ui.story_text.visible_characters = 0
	typing = 0.0

func next_story() -> void:
	if ui.story_text.visible_characters != -1 and ui.story_text.visible_characters < ui.story_text.text.length():
		ui.story_text.visible_characters = -1 # first press finishes the line
		return
	if not story_lines.is_empty():
		show_line(story_lines.pop_front())
		sfx(660, 0.05, "triangle", 0.1)
		return
	close_story()

func close_story() -> void:
	story_open = false
	if after_story.is_valid():
		var f := after_story
		after_story = Callable()
		f.call_deferred()
	if story_step == 0 and not intro:
		begin_opening()
	var tw := create_tween()
	tw.tween_property(ui.story, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func(): ui.story.visible = false)

func toggle_sound() -> void:
	muted = not muted
	save_settings()
	toast("소리 끔" if muted else "소리 켬")
	refresh_sound_btn()

func refresh_sound_btn() -> void:
	ui.sound_btn.icon = odd_icon("mute" if muted else "sound")
	ui.sound_btn.modulate = Color(1, 1, 1, 0.6) if muted else Color.WHITE # .soundKeys button.off { opacity:.6 }
	if ui.has("set_sound"):
		ui.set_sound.icon = odd_icon("mute" if muted else "sound")
		ui.set_sound.modulate = Color(1, 1, 1, 0.6) if muted else Color.WHITE

func toggle_help(show: bool) -> void:
	if show:
		ui.journal.visible = false
	ui.help.visible = show
	ui.hint.visible = not show

# one journal column: rich text so headings can be gold; each line is translated as it is built
func journal_column(parent: Control, pos: Vector2, size: Vector2) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.position = pos
	r.size = size
	r.scroll_active = false
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	r.add_theme_font_override("normal_font", ui_font)
	r.add_theme_font_size_override("normal_font_size", 13)
	r.add_theme_color_override("default_color", Color("#e9dfc4"))
	parent.add_child(r)
	return r

const JOURNAL_HEADS := ["지금 할 일", "곁이야기", "도전 과제", "지닌 것"]

func journal_bbcode(lines: Array) -> String:
	var heads := JOURNAL_HEADS.map(func(h): return tr(h))
	var out: Array = []
	for l in lines:
		var line: String = String(l).replace("[", "[lb]")
		if l in heads:
			out.append("[color=#f6d27a][font_size=15]%s[/font_size][/color]" % line)
		elif String(l).ends_with(tr("완료")) or String(l).ends_with(tr("끝")):
			out.append("[color=#9fd8a0]%s[/color]" % line)
		else:
			out.append(line)
	return "\n".join(out)

func toggle_journal(show: bool) -> void:
	if show:
		ui.help.visible = false
		var lines: Array = journal_lines()
		var cut: int = lines.find(tr("도전 과제"))
		ui.journal_text.text = journal_bbcode(lines.slice(0, cut))
		ui.journal_text2.text = journal_bbcode(lines.slice(cut))
	ui.journal.visible = show

# one line per thing: the current quest, each side story once it has been found, and the keepsakes
func journal_lines() -> Array:
	var out: Array = []
	if ng > 0:
		out.append(tr("새 바퀴 %d (괴물이 %.1f배 단단하고 아프다)") % [ng, ng_mult()])
		out.append("")
	out.append(tr("지금 할 일"))
	out.append("  " + (tr(ui.quest.text) if ui.quest.text != "" else tr("마음 가는 대로 둘러보자")))
	out.append("")
	out.append(tr("곁이야기"))
	var side := func(name: String, state: String): out.append("  · " + tr(name) + "  —  " + state)
	if story_step >= 2:
		var n: int = marsh.count()
		side.call("늪의 옛 지도 조각", tr("끝") if marsh.chest_open else (tr("달지기 상자가 동쪽 둔덕에 솟았다") if n == 3 else tr("%d/3 찾음") % n))
	if shrine_seen:
		side.call("울림 수정", tr("끝") if has_ring else (tr("상자를 열자") if crystal_done else tr("낮은 소리부터 차례로")))
	if story_step >= 6:
		side.call("동굴의 세 돌단", tr("아직 찾지 못했다") if not shrine_seen else (tr("깨운 기술: %s") % tr(["회오리", "불씨탄", "빛파동"][skill_up]) if skill_up >= 0 else tr("하나를 고르자")))
	if marsh.picked_count() > 0 or has_tea:
		side.call("늪의 달꽃", tr("끝") if has_tea else (tr("보리 할머니께 가져가자") if marsh.picked_count() == 3 else tr("%d/3 · 달이 반 넘게 찬 밤에만 핀다") % marsh.picked_count()))
	if errand >= 1:
		side.call("마을 집 찬장", tr("%d/5 열어 봄") % house_seen.count(true))
		var done := int(errand >= 3) + int(kid_q >= 3) + int(doran_q >= 3) + int(mul_q >= 3) + int(fly_q >= 3)
		side.call("마을 심부름", tr("%d/5 마침") % done)
	if mail_got[1]:
		side.call("등불 축제", tr("끝") if fest_gift else tr("보름달 밤, 마을 광장의 심지에게"))
	if mail_q >= 1:
		side.call("도란의 편지 세 통", tr("끝") if mail_q >= 2 else (tr("도란에게 알리자") if mail_got.count(true) == 3 else tr("%d/3 전함 · 보리 할머니, 심지, 섬 오두막") % mail_got.count(true)))
	if fly_q >= 1:
		side.call("꼬마의 반딧불 병", tr("끝") if fly_q >= 3 else (tr("콩알에게 가져가자") if fly_q == 2 else tr("밤의 늪에서 %d/5") % marsh.caught()))
	if lake_q >= 2:
		side.call("호숫가 낚시", tr("끝") if fish_kinds.count(true) == 5 else tr("%d/5 종류") % fish_kinds.count(true))
	if lake_q >= 4:
		side.call("섬 밑 물빛 동굴", tr("끝") if grotto_q >= 4 else (tr("상자를 열자") if grotto_q == 3 else tr("섬 남쪽 계단으로")))
	if forest_q >= 1:
		var nf: int = forest.freed.filter(func(f): return f).size()
		side.call("갇힌 다람쥐", tr("끝") if has_acorn else tr("%d/5 구함") % nf)
		side.call("숲의 달 순서 돌", tr("끝") if forest.chest_open else (tr("상자를 열자") if forest.solved else tr("숲 북서쪽 숲터")))
	if hill_q >= 1:
		side.call("바람개비 경주", tr("최고 기록 %.1f초") % race_best if race_best > 0.0 else tr("언덕 남서쪽 깃대에서"))
	if cloud_q >= 1:
		side.call("보이지 않는 구름길", tr("끝") if has_shard else tr("첫 섬 남쪽에서 E로 길을 비춰 보자"))
	if hill_q >= 3:
		side.call("구름 둔덕", tr("끝") if cloud_q >= 3 else tr("언덕 북쪽 바람구멍으로"))
	if castle_q >= 1:
		side.call("한결의 일기", tr("%d/3 읽음") % castle.pages_read())
		side.call("서재의 달지기 책", tr("끝") if has_bookmark else tr("%d/5 읽음") % castle.books.filter(func(b): return b.read).size())
		side.call("성의 보물고", tr("끝") if castle.vault_open else (tr("상자를 열자") if castle.vault_solved() else tr("경비실의 지렛대 셋")))
	if night_q >= 4:
		side.call("달빛 시련", tr("최고 기록 %d분 %02d초") % [int(trial_best) / 60, int(trial_best) % 60] if trial_best > 0.0 else tr("마을 남서쪽 돌 둘레에서"))
	out.append("")
	out.append(tr("도전 과제"))
	for i in FEATS.size():
		var v := mini(feat_value(FEATS[i][1]), FEATS[i][2])
		out.append("  · " + tr(FEATS[i][0]) + "  —  " + (tr("완료") if feats_done[i] else "%d/%d" % [v, FEATS[i][2]]))
	out.append("")
	out.append(tr("놀이 시간 %s · 물리친 괴물 %d마리") % [play_time_text(), stats.kills])
	out.append("")
	out.append(tr("지닌 것"))
	var keep: Array = []
	if has_skip: keep.append(tr("물수제비 걸음"))
	if has_unbrick: keep.append(tr("벽돌 풀기"))
	if fly_q >= 3: keep.append(tr("반딧불 병"))
	if has_pearl: keep.append(tr("물빛 진주"))
	if has_feather: keep.append(tr("바람 깃털"))
	if has_acorn: keep.append(tr("다람쥐 도토리"))
	if has_ring: keep.append(tr("수정 반지"))
	if has_shoes: keep.append(tr("바람 신발"))
	if has_armour: keep.append(tr("달지기 갑옷"))
	if has_tea: keep.append(tr("달꽃 차"))
	if has_shard: keep.append(tr("구름 조각"))
	if has_bookmark: keep.append(tr("달지기 책갈피"))
	out.append("  " + (", ".join(keep) if not keep.is_empty() else tr("왕관 하나")))
	return out

func toast(msg: String) -> void:
	ui.toast.text = msg
	ui.toast.modulate.a = 1.0
	toast_t = 2.2

func start_game(with_story := true) -> void:
	if not intro:
		return
	intro = false
	cam_yaw = CAM_YAW # the title screen orbits the camera; play always starts from the same angle
	if with_story and (not loaded or story_step == 0): # a new round loads with the story back at 0
		show_story("res://art/story/01_wake.jpg", STORY.WAKE)
	sfx(392, 0.3, "triangle", 0.25)
	get_tree().create_timer(0.15).timeout.connect(func(): sfx(587, 0.5, "triangle", 0.25))
	for c in ui.hidden_for_intro:
		c.visible = true
	var tw := create_tween()
	tw.tween_property(ui.title, "modulate:a", 0.0, 1.2)
	tw.tween_callback(ui.title.queue_free)

# ---------------------------------------------------------------- input
# the title screen listens before any control can swallow the click or key
func _input(event: InputEvent) -> void:
	if (event is InputEventKey or event is InputEventMouseButton) and event.pressed:
		last_input_t = t
	# shop cards: a left click anywhere on a card buys it (handled here so no overlay can swallow it)
	if shop_open and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in ui.shop_btns.size():
			var card: Control = ui.shop_btns[i].get_parent()
			if card.get_global_rect().has_point(event.position):
				buy(i)
				get_viewport().set_input_as_handled()
				return
	# shop cards: a left click anywhere on a card buys it (handled here so no overlay can swallow it)
	if shop_open and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in ui.shop_btns.size():
			var card: Control = ui.shop_btns[i].get_parent()
			if card.get_global_rect().has_point(event.position):
				buy(i)
				get_viewport().set_input_as_handled()
				return
	if story_open and ((event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed)):
		next_story()
		get_viewport().set_input_as_handled()
		return
	if intro and event is InputEventKey and event.pressed and event.keycode == KEY_F9:
		reset_game()
		return
	if intro and ((event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed)):
		start_game()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if intro or down_t > 0.0:
		return
	if shop_open:
		if event is InputEventKey and event.pressed and not event.echo:
			match event.keycode:
				KEY_1, KEY_2, KEY_3, KEY_4: buy(event.keycode - KEY_1)
				KEY_SPACE, KEY_ESCAPE, KEY_E: toggle_shop(false)
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT: attack()
			MOUSE_BUTTON_RIGHT: dodge()
			MOUSE_BUTTON_WHEEL_UP: cam_dist = clampf(cam_dist - 1.2, 8, 26)
			MOUSE_BUTTON_WHEEL_DOWN: cam_dist = clampf(cam_dist + 1.2, 8, 26)
	if settings_open:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			toggle_settings(false)
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and not way_open \
			and not ui.journal.visible and not ui.help.visible:
		toggle_settings(true)
		return
	if way_open and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_6:
			travel(event.keycode - KEY_1)
			return
		if event.keycode == KEY_ESCAPE:
			toggle_ways(false)
			return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_J: attack()
			KEY_K: dodge()
			KEY_U, KEY_1: use_skill(0)
			KEY_I, KEY_2: use_skill(1)
			KEY_O, KEY_3: use_skill(2)
			KEY_4: drink_potion()
			KEY_SPACE: interact()
			KEY_T: skip_time(3.0)
			KEY_R:
				raining = not raining
				rain.emitting = raining
				toast("비가 내린다" if raining else "비가 그쳤다")
			KEY_P: ui.root.visible = not ui.root.visible
			KEY_H: toggle_help(not ui.help.visible)
			KEY_Q: toggle_journal(not ui.journal.visible)
			KEY_E: crown_key()
			KEY_F9: reset_game()
			KEY_F8: return_to_start()
			KEY_M: toggle_sound()

# ---------------------------------------------------------------- loop
func _process(dt: float) -> void:
	dt = minf(dt, 1.0 / 20.0)
	if hitstop > 0.0:
		hitstop -= dt
		return
	if shop_open: # the world waits while Sora shops: no clock, no monsters
		ui.shop_hint.visible = false
		return
	if settings_open: # and while the settings are open
		return
	if down_t > 0.0:
		t += dt
		update_fall(dt)
		update_enemies(dt, ground_y)
		return
	if story_open:
		if ui.story_text.visible_characters != -1:
			typing += dt * 40.0
			ui.story_text.visible_characters = int(typing)
			if ui.story_text.visible_characters >= ui.story_text.text.length():
				ui.story_text.visible_characters = -1
		ui.story_more.modulate.a = 0.4 + 0.6 * absf(sin(t * 4.0))
		t += dt
		if not intro: # keep the camera on Sora behind the dimmed scene
			var tg := Vector3(player.x, ground_y + 0.6, player.z)
			camera.position = tg + Vector3(sin(cam_yaw) * cos(0.78) * cam_dist, sin(0.78) * cam_dist, cos(cam_yaw) * cos(0.78) * cam_dist)
			camera.look_at(tg)
		return
	t += dt
	if intro:
		cam_yaw += dt * 0.08
	if CAM_ROTATE:
		if key_down(KEY_Q): cam_yaw -= 1.6 * dt
		if key_down(KEY_E): cam_yaw += 1.6 * dt
	if key_down(KEY_Z): cam_dist = maxf(8, cam_dist - 12 * dt)
	if key_down(KEY_X): cam_dist = minf(26, cam_dist + 12 * dt)

	# movement relative to the camera
	var fwd := Vector2(-sin(cam_yaw), -cos(cam_yaw))
	var right := Vector2(cos(cam_yaw), -sin(cam_yaw))
	var mv := Vector2.ZERO
	if not intro and not shop_open:
		if key_down(KEY_W) or key_down(KEY_UP): mv += fwd
		if key_down(KEY_S) or key_down(KEY_DOWN): mv -= fwd
		if key_down(KEY_D) or key_down(KEY_RIGHT): mv += right
		if key_down(KEY_A) or key_down(KEY_LEFT): mv -= right
	var running: bool = key_down(KEY_SHIFT) and player.sp > 0 and mv.length() > 0
	var on_water: bool = tile_at(player.x, player.z) == WATER and (player.x < CAVE_X - 0.5 or skip_water(player.x, player.z))
	skip_grace = 0.6 if has_skip and running else skip_grace - dt
	skipping = has_skip and (running or (on_water and skip_grace > 0.0))
	if has_skip and not running and mv.length() > 0 and not on_water and toast_t <= 0.0:
		var ahead := Vector2(player.x, player.z) + mv.normalized() * 0.7
		if skip_water(ahead.x, ahead.y):
			toast("Shift를 누른 채 달리면 물 위를 건넌다")
	if skipping and on_water:
		player.sp = maxf(1.0, player.sp - 6.0 * dt) # costs a little extra, but never runs dry mid-river
		if int(t * 8.0) != int((t - dt) * 8.0):
			burst(Vector3(player.x, -0.2, player.z), Color("#9fe0ff"), 4, 1.2)
	elif not running and on_water and not skipping:
		unstick() # stopped on open water: back to the nearest shore
	player.sp = maxf(0, player.sp - 22 * dt) if running else minf(100, player.sp + (27.0 if has_pearl else 18.0) * dt)
	if skipping and on_water:
		player.sp = maxf(player.sp, 1.0)
	var speed := (7.0 if has_shoes else 6.2) if running else 3.6
	var tv := Vector2.ZERO
	if mv.length() > 0:
		mv = mv.normalized()
		tv = mv * speed
		player.face = mv
	if skipping and on_water and not running: # let go for a moment: glide on in the same direction
		tv = player.face * 6.2
	if player.atk_cd > 0.1:
		tv *= 0.3
	if guarding:
		tv *= 0.4
	var blend := minf(1.0, dt * 14.0)
	player.vx += (tv.x - player.vx) * blend
	player.vz += (tv.y - player.vz) * blend
	var v := Vector2(player.vx, player.vz)
	if player.dodge > 0:
		v = Vector2(player.dvx, player.dvz)
		player.dodge -= dt
	var vent: Vector2 = vent_here(player.x, player.z)
	if gust_dir == Vector2.ZERO and vent != Vector2.ZERO and not on_vent_prev and player.dodge <= 0.0:
		start_gust(vent)
	on_vent_prev = vent != Vector2.ZERO
	if gust_dir != Vector2.ZERO:
		update_gust(dt)
		v = Vector2.ZERO
	var nx: float = player.x + v.x * dt
	var nz: float = player.z + v.y * dt
	if gust_dir == Vector2.ZERO and not player_can(player.x, player.z): # stuck in a wall (old save, knockback): hop to the nearest open floor
		unstick()
	if player_can(nx, player.z): player.x = nx
	if player_can(player.x, nz): player.z = nz

	player.atk_cd = maxf(0, player.atk_cd - dt)
	player.combo_t -= dt
	player.inv -= dt
	player.hurt_t -= dt
	for i in 4:
		player.cds[i] = maxf(0, player.cds[i] - dt)
	if t - last_hit_t > 4.0:
		player.mp = maxf(0.0, player.mp - 3.0 * dt)
	# guard: L or middle mouse held; remember when it started for the flash-guard window
	var g_now: bool = not intro and not shop_open and (key_down(KEY_L) or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)) and player.dodge <= 0
	if g_now and not guarding:
		guard_since = t
	guarding = g_now
	if guarding and player.lv >= 4 and t - guard_since >= 1.0 and int(t * 10.0) != int((t - dt) * 10.0):
		burst(Vector3(player.x, 1.0, player.z), Color("#fff1a0"), 3, 1.0) # light gathered: J for a charged cut
	counter_t -= dt
	flash_cd -= dt
	slowmo -= dt
	ui.slowmo_tint.visible = slowmo > 0
	ui.shop_hint.visible = not intro and not shop_open and near_shop()
	ui.shop_hint.text = "E  편지 전하기" if doran_q == 2 else "E  보리 할머니의 상점"
	if shop_open and not near_shop():
		toggle_shop(false)
	if key_down(KEY_J) and player.atk_cd <= 0 and not intro and not shop_open:
		attack()

	# Sora: pick one of 8 screen directions
	var f: Vector2 = player.face
	var sx := f.dot(right)
	var sz := f.dot(fwd)
	const DIRS8 := ["up", "upright", "side", "downright", "down", "downleft", "left", "upleft"]
	player.dir = DIRS8[(int(round(atan2(sx, sz) / (PI / 4.0))) + 8) % 8]
	var moving := Vector2(player.vx, player.vz).length() > 0.4
	player.anim += dt * (12.0 if running else 8.0)
	var frame := int(player.anim) % 4 if moving else 0
	var still: bool = not moving and player.atk_cd <= 0.0 and player.dodge <= 0.0 and not guarding and player.hurt_t <= 0.0
	idle_t = idle_t + dt if still else 0.0
	if idle_t > 0.6:
		update_idle(dt)
	else:
		idle_name = ""
		set_hero_frame(player.dir, frame)
	sync_ghost()
	# feet touch the ground on frames 0 and 2 of the walk cycle
	if moving and frame != step_frame and frame % 2 == 0 and player.dodge <= 0:
		footstep()
	step_frame = frame
	ground_y = lerpf(ground_y, height_at(player.x, player.z), minf(1.0, dt * 10.0))
	var gy := ground_y
	var hop := sin((player.dodge / 0.32) * PI) * 0.35 if player.dodge > 0 else 0.0
	hero.position = Vector3(player.x, gy + hop, player.z)
	var blink: bool = player.inv > 0 and player.dodge <= 0 and sin(t * 40.0) < 0
	# Sora is unshaded, so tint her by hand to sit in the night light: a mild blue at night (the old 0.5 made her
	# much darker than her companions), warmed back to full by any lit lantern within 4 tiles
	var lit := Color(1, 1, 1).lerp(Color(0.8, 0.82, 0.95), night)
	var warm := 0.0
	for l in lanterns:
		if l.visible and not l.get_meta("dark", false):
			var ld := Vector2(l.position.x - player.x, l.position.z - player.z).length()
			warm = maxf(warm, clampf(1.0 - (ld - 1.5) / 2.5, 0.0, 1.0))
	if in_cave or in_grotto() or jar_node != null and jar_node.visible:
		warm = maxf(warm, 0.6) # the cave lamp on her, or the firefly jar at her side
	lit = lit.lerp(Color(1.0, 0.95, 0.86), warm * night)
	hero.modulate = Color(1, 0.5, 0.5) if player.hurt_t > 0 else Color(lit.r, lit.g, lit.b, 0.3 if blink else 1.0)
	hero_shadow.position = Vector3(player.x, gy + 0.02, player.z)

	update_enemies(dt * (SLOWMO if slowmo > 0 else 1.0), gy)
	if not in_cave and story_step >= 5 and cave_pos.x > 0 and Vector2(player.x, player.z).distance_to(cave_pos) < 1.2 and fade_rect.color.a == 0.0:
		fade_then(enter_cave)
	if not in_cave and not in_village and story_step >= 7 and player.x > 46.5 and player.x < CAVE_X - 0.5 and player.z > 17.5 and player.z < 23.5 and fade_rect.color.a == 0.0:
		fade_then(enter_village)
	if in_village and Vector2(player.x, player.z).distance_to(village.marks.G) < 0.9 and fade_rect.color.a == 0.0:
		fade_then(leave_village)
	if in_village and Vector2(player.x, player.z).distance_to(village.marks.F) < 0.9 and fade_rect.color.a == 0.0:
		if lake_q >= 4:
			fade_then(enter_forest)
		elif toast_t <= 0.0:
			toast("동쪽 숲길은 회색 벽돌로 막혀 있다" if night_q < 4 else "물결 없이 혼자 가지 않기로 했다. 남쪽 호수로 가자")
	if in_forest and Vector2(player.x, player.z).distance_to(forest.marks.S) < 0.9 and fade_rect.color.a == 0.0:
		fade_then(leave_forest)
	if in_forest:
		update_forest()
	if in_forest and Vector2(player.x, player.z).distance_to(forest.marks.E) < 0.9 and fade_rect.color.a == 0.0:
		if forest_q >= 3:
			fade_then(enter_hill)
		elif toast_t <= 0.0:
			toast("노을이 길을 막고 있다")
	if in_hill and Vector2(player.x, player.z).distance_to(hill.marks.S) < 0.9 and fade_rect.color.a == 0.0:
		fade_then(leave_hill)
	if in_hill and Vector2(player.x, player.z).distance_to(hill.marks.X) < 0.9 and fade_rect.color.a == 0.0:
		if hill_q >= 3:
			fade_then(enter_castle)
		elif toast_t <= 0.0:
			toast("벽돌 매가 하늘을 지키고 있다")
	if in_hill and not in_cloud() and Vector2(player.x, player.z).distance_to(hill.marks.U) < 0.8 and fade_rect.color.a == 0.0:
		if hill_q >= 3:
			fade_then(enter_cloud)
		elif toast_t <= 0.0:
			toast("바람구멍에서 거센 바람이 솟는다. 벽돌 매가 하늘에 있는 동안은 위험하다")
	if in_cloud() and gust_dir == Vector2.ZERO and Vector2(player.x, player.z).distance_to(cloud.marks.S) < 0.7 and fade_rect.color.a == 0.0:
		fade_then(leave_cloud)
	if in_cloud() and cloud_q == 1 and not story_open and gust_dir == Vector2.ZERO and Vector2(player.x, player.z).distance_to(cloud.marks.K) < 6.0:
		cloud_q = 2
		show_story("", STORY.SCARE_IN)
		after_story = spawn_scarecrow
		save_game()
	if in_castle() and gust_dir == Vector2.ZERO and Vector2(player.x, player.z).distance_to(castle.marks.S) < 0.7 and fade_rect.color.a == 0.0:
		fade_then(leave_castle)
	if in_castle() and Vector2(player.x, player.z).distance_to(castle.marks.E) < 0.8 and fade_rect.color.a == 0.0:
		if castle_q >= 3 or garden_q >= 1:
			fade_then(enter_garden)
		elif toast_t <= 0.0:
			toast("동쪽 문이 굳게 닫혀 있다")
	if in_castle() and castle_q == 1 and castle.door_open and not story_open and gust_dir == Vector2.ZERO and Vector2(player.x, player.z).distance_to(castle.marks.K) < 5.0:
		castle_q = 2
		show_story("", STORY.KNIGHT_IN)
		after_story = spawn_knight
		save_game()
	if in_hill:
		update_hill(dt)
	if in_garden and Vector2(player.x, player.z).distance_to(garden.marks.S) < 0.9 and fade_rect.color.a == 0.0:
		fade_then(leave_garden)
	if in_garden:
		update_garden(dt)
	if in_village and Vector2(player.x, player.z).distance_to(village.marks.K) < 0.9 and fade_rect.color.a == 0.0:
		if night_q >= 4:
			fade_then(enter_lake)
		elif toast_t <= 0.0:
			toast("남쪽 호수는 굳어 있다. 아직 갈 수 없다")
	if in_lake and Vector2(player.x, player.z).distance_to(lake.marks.S) < 0.9 and fade_rect.color.a == 0.0:
		fade_then(leave_lake)
	if in_lake and lake_q >= 4 and Vector2(player.x, player.z).distance_to(lake.marks.G) < 0.8 and fade_rect.color.a == 0.0:
		fade_then(enter_grotto)
	if in_grotto() and Vector2(player.x, player.z).distance_to(grotto.marks.S) < 0.7 and fade_rect.color.a == 0.0:
		fade_then(leave_grotto)
	if in_grotto() and grotto_q == 1 and player.z > 13.6 and not story_open:
		grotto_q = 2
		show_story("", STORY.CRAB_IN)
		after_story = spawn_crab
		save_game()
	update_mate(dt)
	update_mate2(dt)
	update_pips(dt)
	update_kid(dt)
	update_oar()
	if in_marsh() and not intro:
		marsh.update(self)
	marsh.update_flies(self, in_marsh() and is_night())
	marsh.update_flowers(self, in_marsh() and not intro and is_night() and moon_phase().x >= 0.6)
	if jar_node != null:
		jar_node.visible = night > 0.5
		jar_node.position = Vector3(player.x + 0.35, ground_y + 0.55 + sin(t * 2.0) * 0.04, player.z + 0.1)
	update_night(dt)
	update_shrine(dt)
	update_trial(dt)
	update_race(dt)
	update_fishing(dt)
	update_chat(dt)
	update_mate_hud()
	if cloud.reveal_t > 0.0:
		cloud.reveal_t -= dt
		if cloud.reveal_t <= 0.0:
			cloud.reveal(false)
	if in_cloud() and gust_dir == Vector2.ZERO and cloud.char_at(player.x, player.z) == "," and fade_rect.color.a == 0.0:
		player.x = CLOUD.CLOUD_X + 3.0 # a step off the unseen path: back onto the entry island
		player.z = 11.0
		hurt_player(8, 0.0)
		burst(Vector3(player.x, 0.5, player.z), Color("#ffffff"), 20, 2.5)
		toast("발을 헛디뎌 구름 아래로 떨어졌다가 바람에 실려 돌아왔다")
	if not intro:
		play_secs += dt
	ng_armed -= dt
	update_festival(dt)
	feat_t -= dt
	if feat_t <= 0.0 and not intro:
		feat_t = 1.0
		check_feats()
	if in_house >= 0 and Vector2(player.x, player.z).distance_to(Vector2(HOUSE_X + 4, 6)) < 0.7 and fade_rect.color.a == 0.0:
		fade_then(leave_house)
	if in_cave:
		check_painting()
	if in_cave and not has_skip and Vector2(player.x, player.z).distance_to(cave_marks.E) < 1.6 and toast_t <= 0.0:
		toast("바깥 빛이 보인다. 하지만 수레두더지가 길을 막고 있다")
	if in_cave and has_skip and Vector2(player.x, player.z).distance_to(cave_marks.E) < 1.0 and fade_rect.color.a == 0.0:
		fade_then(leave_cave)
	update_daylight(dt)
	update_lights()
	save_t += dt
	if save_t > 5.0:
		save_t = 0.0
		save_game()
	update_projectiles(dt)
	update_enemy_shots(dt * (SLOWMO if slowmo > 0 else 1.0))
	for i in range(fx.size() - 1, -1, -1):
		var e: Dictionary = fx[i]
		e.t += dt
		var k: float = e.t / e.life
		if k >= 1.0:
			e.node.queue_free()
			fx.remove_at(i)
			continue
		e.update.call(e.node, k, dt)

	# camera follow
	var pitch := 0.78
	var target := Vector3(26, 0, 30) if intro else Vector3(player.x, gy + 0.6, player.z)
	shake = maxf(0, shake - dt)
	camera.position = target + Vector3(sin(cam_yaw) * cos(pitch) * cam_dist + rnd(-1, 1) * shake * 0.4 * (1.0 if cfg.shake else 0.0),
		sin(pitch) * cam_dist + rnd(-1, 1) * shake * 0.4 * (1.0 if cfg.shake else 0.0), cos(cam_yaw) * cos(pitch) * cam_dist)
	camera.look_at(target)
	sun.global_transform = Transform3D(Basis(), target + Vector3(-12, 10 + sun_el * 14, -8)).looking_at(target)
	motes.position = target
	rain.position = target + Vector3(0, 8, 0)

	# HUD
	banner_t -= dt
	if banner_t <= 0: ui.banner.modulate.a = maxf(0, ui.banner.modulate.a - dt * 2)
	toast_t -= dt
	if toast_t <= 0: ui.toast.modulate.a = maxf(0, ui.toast.modulate.a - dt * 3)
	ui.lv.text = str(player.lv)
	var narrow := get_viewport().get_visible_rect().size.x < 1180.0
	if ui.story.visible:
		fit_story()
	ui.quest.offset_top = (200.0 if ui.boss.visible else 150.0) if narrow else 62.0
	ui.boss.offset_top = 140.0 if narrow else 14.0
	ui.boss.offset_bottom = ui.boss.offset_top + 40.0
	ui.quest.offset_bottom = ui.quest.offset_top + 26.0
	ui.hp.size.x = 200.0 * player.hp / player.max_hp
	ui.mp.size.x = 200.0 * player.mp / player.max_mp
	ui.mp.modulate.a = 0.45 + 0.55 * absf(sin(t * 6.0)) if player.mp >= 60.0 else 1.0 # enough for 빛파동
	ui.sp.size.x = 2.0 * player.sp
	ui.xp.size.x = 200.0 * player.xp / (player.lv * 25)
	ui.xpt.text = "%d/%d" % [player.xp, player.lv * 25]
	ui.spt.text = "%d/100" % int(player.sp)
	ui.hpt.text = "%d/%d" % [ceili(player.hp), player.max_hp]
	ui.mpt.text = "%d/%d" % [int(player.mp), player.max_mp]
	ui.gold.text = "◆ %d" % player.gold
	ui.pots.text = "×%d" % player.pots
	for i in 3:
		ui.cd[i].size.y = 48.0 * player.cds[i] / SKILL_CD[i]
	ui.cd[3].size.y = 48.0 * player.cds[3] / 2.0

# keep the story picture and dialogue box off the screen edges on narrow windows
const STORY_MARGIN := 28.0
func fit_story() -> void:
	var vw := get_viewport().get_visible_rect().size.x
	var pw := minf(896.0, vw - 2.0 * (STORY_MARGIN + 12.0)) # the frame draws 10px outside its rect
	var ph := pw * 504.0 / 896.0
	ui.story_frame.offset_left = -pw / 2.0
	ui.story_frame.offset_right = pw / 2.0
	ui.story_frame.offset_top = -78.0 - ph / 2.0
	ui.story_frame.offset_bottom = -78.0 + ph / 2.0
	var cw := minf(940.0, vw - 2.0 * STORY_MARGIN)
	ui.story_cap.offset_left = -cw / 2.0
	ui.story_cap.offset_right = cw / 2.0
	ui.story_text.size.x = cw - ui.story_text.position.x - 40.0
	ui.story_hint.position.x = cw - 35.0

func update_enemies(dt: float, gy: float) -> void:
	for e in enemies.duplicate():
		if e.dead and e.get("boss", false):
			continue
		if e.dead and e.get("cave", false):
			continue
		if e.dead:
			e.respawn -= dt
			if e.respawn <= 0:
				enemies.erase(e)
				spawn_enemy(Vector2(-1, -1), e.get("archer", false))
			continue
		e.t += dt
		e.atk_cd -= dt
		e.hurt -= dt
		var to := Vector2(player.x - e.x, player.z - e.z)
		var d := to.length()
		var ev := Vector2.ZERO
		var boss: bool = e.get("boss", false)
		if boss:
			update_boss(e, dt, d, to, gy)
			continue
		if e.get("mole", false):
			update_mole(e, dt, d, to)
			continue
		if e.get("noeul", false):
			update_noeul(e, dt, d, to)
			continue
		if e.get("mold", false):
			update_mold(e, dt, d, to)
			continue
		if e.get("turtle", false):
			update_turtle(e, dt, d, to)
			continue
		if e.get("crab", false):
			update_crab(e, dt, d, to)
			continue
		if e.get("scare", false):
			update_scarecrow(e, dt, d, to)
			continue
		if e.get("knight", false):
			update_knight(e, dt, d, to)
			continue
		if e.get("shard", false):
			update_shard(e, dt)
			continue
		if e.get("wolf", false):
			update_wolf(e, dt, d, to)
			continue
		if e.get("bat", false):
			update_bat(e, dt, d, to)
			continue
		if e.get("prop", false):
			e.hurt -= dt
			e.shadow.position = Vector3(e.x, 0.02, e.z)
			continue
		if e.get("hawk", false):
			update_hawk(e, dt, d, to)
			continue
		if d < 7 and not intro and e.get("archer", false):
			if d < 4.0:
				ev = -to / maxf(d, 0.01) * 1.6
			elif d > 5.5:
				ev = to / d * 1.6
		elif d < 7 and not intro:
			if d > 0.9:
				ev = to / d * 2.3
		else:
			if Vector2(e.wx - e.x, e.wz - e.z).length() < 0.3 or rng.randf() < 0.005:
				e.wx = e.x + rnd(-3, 3)
				e.wz = e.z + rnd(-3, 3)
			var w := Vector2(e.wx - e.x, e.wz - e.z)
			if w.length() > 0.01:
				ev = w.normalized()
		ev += Vector2(e.kx, e.kz)
		e.kx *= pow(0.002, dt)
		e.kz *= pow(0.002, dt)
		if e.hurt > 0 or e.get("stun", 0.0) > 0.0 or e.get("wind", 0.0) > 0.0:
			ev = Vector2(e.kx, e.kz)
		e.stun = e.get("stun", 0.0) - dt
		var nx: float = e.x + ev.x * dt
		var nz: float = e.z + ev.y * dt
		if walkable(nx, e.z): e.x = nx
		if walkable(e.x, nz): e.z = nz
		if e.get("archer", false):
			if e.get("wind", 0.0) > 0.0:
				e.wind -= dt
				if e.wind <= 0.0:
					e.atk_cd = 2.5
					throw_brick(Vector2(e.x, e.z), to / maxf(d, 0.01), e)
			elif not intro and d < 6.0 and e.atk_cd <= 0 and e.hurt <= 0 and e.get("stun", 0.0) <= 0.0:
				e.wind = 0.6
				pop_num(Vector3(e.x, height_at(e.x, e.z) + 1.3, e.z), "!", Color("#ffd84a"))
		# wind-up 0.45 s (glows red, puffs up, "!"), then strike if Sora is still within 1.3
		if e.get("wind", 0.0) > 0.0 and not e.get("archer", false):
			e.wind -= dt
			if e.wind <= 0.0:
				e.atk_cd = 1.6
				var hitd := int(round(rnd(5, 9) + player.lv))
				if d < 1.3:
					player_hit(hitd, Vector2(e.x, e.z), e)
				else:
					var mid := mate_near(Vector2(e.x, e.z), 1.3)
					if mid != "":
						hurt_mate(mid, hitd)
		elif not e.get("archer", false) and not intro and (d < 1.1 or mate_near(Vector2(e.x, e.z), 1.1) != "") and e.atk_cd <= 0 and e.hurt <= 0 and e.get("stun", 0.0) <= 0.0:
			e.wind = 0.45
			pop_num(Vector3(e.x, height_at(e.x, e.z) + 1.3, e.z), "!", Color("#ff5a4a"))
		var ey := height_at(e.x, e.z)
		var hop := absf(sin(e.t * 6.0))
		var node: Node3D = e.node
		node.position = Vector3(e.x, ey + hop * 0.14, e.z)
		node.get_meta("body").scale = Vector3(1 + (1 - hop) * 0.08, 1 - (1 - hop) * 0.1, 1 + (1 - hop) * 0.08)
		if ev.length() > 0.1:
			node.rotation.y = atan2(ev.x, ev.y)
		var wind_now: bool = e.get("wind", 0.0) > 0.0
		node.scale = Vector3.ONE * (1.3 * e.get("size_k", 1.0) * (1.15 if wind_now else 1.0))
		for m in node.get_meta("mats"):
			m.emission_enabled = e.hurt > 0 or wind_now
			m.emission = Color("#ff3a2a") if wind_now and e.hurt <= 0 else Color.WHITE
			m.emission_energy_multiplier = 0.9
		e.shadow.position = Vector3(e.x, ey + 0.02, e.z)

# Brick King, two phases.
# Phase 1: stomp (1.2 s red ring, 3 tiles) every 3.2 s; a 0.6 s front swing when Sora is within 2.2.
# Phase 2 (below half): a 1.5 s roar (invulnerable, shoves Sora 4 tiles, calls two goblins),
# then stomps every 2.4 s with a 1.0 s wind-up and a shockwave ring that rolls out to 6 tiles.
func update_boss(e: Dictionary, dt: float, d: float, to: Vector2, gy: float) -> void:
	var node: Node3D = e.node
	var awake := d < 11.0 and not intro
	ui.boss.visible = awake or (ui.boss.visible and d < 16.0)
	ui.boss_bar.size.x = 420.0 * maxf(0.0, e.hp) / e.max_hp
	ui.boss_name.text = "벽돌왕"
	var me := Vector2(e.x, e.z)
	var ground := height_at(e.x, e.z)
	e.t += dt
	e.hurt -= dt
	e.stun -= dt
	var ev := Vector2.ZERO
	var stomp_wind := 1.2 if e.phase == 1 else 1.0
	if e.phase == 1 and e.hp < e.max_hp / 2.0:
		e.phase = 2
		e.roar = 1.5
		e.stomp = 0.0
		e.swing = 0.0
		ui.boss_bar.color = Color("#d84a6a")
		toast("벽돌왕이 성났다!")
		sfx(60, 1.2, "sawtooth", 0.35, -20)
		shake = 0.5
		if d < 5.0:
			var push := (Vector2(player.x, player.z) - me).normalized() * 4.0
			for k in 8: # slide back until something blocks
				var step := Vector2(player.x, player.z) + push / 8.0
				if walkable(step.x, step.y):
					player.x = step.x
					player.z = step.y
		spawn_enemy()
		spawn_enemy()
		for k in 2: # the two newcomers appear beside the king
			var g: Dictionary = enemies[enemies.size() - 1 - k]
			g.x = e.x + rnd(-2, 2)
			g.z = e.z + 2.0
	# shockwave ring rolling outwards (phase 2)
	if e.wave_r >= 0.0:
		var before: float = e.wave_r
		e.wave_r += 5.0 * dt
		if before < d and e.wave_r >= d and absf(d - e.wave_r) < 0.8:
			player_hit(int(8 + player.lv), me, e)
		if e.wave_r > 6.0:
			e.wave_r = -1.0
	if e.roar > 0.0:
		e.roar -= dt
		node.position = Vector3(e.x, ground + absf(sin(e.t * 30.0)) * 0.08, e.z)
	elif e.stun > 0.0:
		node.position = Vector3(e.x, ground, e.z)
	elif e.stomp > 0.0:
		e.stomp -= dt
		var k: float = 1.0 - e.stomp / stomp_wind
		node.position.y = ground + sin(k * PI) * 1.6
		if e.stomp <= 0.0:
			stomp_wave(Vector3(e.x, ground, e.z))
			if d < 3.0:
				player_hit(int(12 + player.lv * 2), me, e)
			if e.phase == 2:
				e.wave_r = 0.0
				ring_wave(Vector3(e.x, ground, e.z))
	elif e.swing > 0.0:
		e.swing -= dt
		if e.swing <= 0.0:
			slash_fx(Vector3(e.x, ground + 0.4, e.z) + Vector3(e.face.x, 0, e.face.y) * 1.0, -atan2(e.face.y, e.face.x) - PI / 2.0 + 0.9, false)
			sfx(110, 0.12, "sawtooth", 0.25, 200)
			if d < 2.0 and (to / maxf(d, 0.01)).dot(e.face) > 0.5:
				player_hit(int(8 + player.lv), me, e)
	else:
		if awake and d > 1.8:
			ev = to / d * 1.4
		elif not awake:
			var back: Vector2 = e.home - me
			if back.length() > 0.5:
				ev = back.normalized() * 1.2
		ev += Vector2(e.kx, e.kz)
		e.kx *= pow(0.002, dt)
		e.kz *= pow(0.002, dt)
		var nx: float = e.x + ev.x * dt
		var nz: float = e.z + ev.y * dt
		if walkable(nx, e.z): e.x = nx
		if walkable(e.x, nz): e.z = nz
		e.atk_cd -= dt
		if awake and e.atk_cd <= 0.0:
			if e.phase == 1 and d < 2.2 and not e.get("swung", false): # swing and stomp take turns
				e.swung = true
				e.atk_cd = 1.6
				e.swing = 0.6
				e.face = to / maxf(d, 0.01)
				pop_num(Vector3(e.x, ground + 3.6, e.z), "!", Color.WHITE)
			else:
				e.swung = false
				e.atk_cd = stomp_wind + (3.2 if e.phase == 1 else 2.4)
				e.stomp = stomp_wind
				sfx(70, 0.4, "square", 0.25, 60)
				warn_ring(Vector3(e.x, ground, e.z), 3.0, stomp_wind)
		node.position = Vector3(e.x, ground + absf(sin(e.t * 3.0)) * 0.1, e.z)
	if ev.length() > 0.1:
		node.rotation.y = atan2(ev.x, ev.y)
	var swinging: bool = e.swing > 0.0
	for m in node.get_meta("mats"):
		m.emission_enabled = e.hurt > 0 or swinging or e.roar > 0.0 or e.stun > 0.0
		m.emission = Color("#ff5a3a") if e.roar > 0.0 else (Color("#9fd4ff") if e.stun > 0.0 else Color.WHITE)
		m.emission_energy_multiplier = 0.9
	e.shadow.position = Vector3(e.x, ground + 0.02, e.z)

# phase 2 shockwave: an orange ring that rolls out at 5 tiles/s to 6 tiles; roll through it
func ring_wave(pos: Vector3) -> void:
	var m := MeshInstance3D.new()
	m.mesh = ring_mesh(0.85, 1.0, 0.0, TAU)
	var mat := glow_mat(Color("#ff8a3a"), 2.5)
	m.material_override = mat
	m.position = pos + Vector3(0, 0.2, 0)
	add_fx(m, 1.2, func(n: Node3D, k: float, _dt: float):
		n.scale = Vector3.ONE * maxf(0.01, k * 6.0)
		mat.albedo_color.a = 1.0 - k * 0.6)

# red ring on the ground showing where the stomp will land: step out or roll
func warn_ring(pos: Vector3, r: float, life: float) -> void:
	var m := MeshInstance3D.new()
	m.mesh = ring_mesh(r - 0.12, r, 0.0, TAU)
	var mat := glow_mat(Color("#ff4a3a"), 2.0)
	m.material_override = mat
	m.position = pos + Vector3(0, 0.08, 0)
	add_fx(m, life, func(_n: Node3D, k: float, _dt: float):
		mat.albedo_color.a = 0.35 + 0.65 * absf(sin(k * PI * 4.0)))

func stomp_wave(pos: Vector3) -> void:
	shake = 0.45
	sfx(55, 0.5, "square", 0.35, -30)
	var m := MeshInstance3D.new()
	m.mesh = ring_mesh(0.4, 0.9, 0.0, TAU)
	var mat := glow_mat(Color("#ffb45a"), 2.5)
	m.material_override = mat
	m.position = pos + Vector3(0, 0.15, 0)
	add_fx(m, 0.6, func(n: Node3D, k: float, _dt: float):
		n.scale = Vector3.ONE * (1.0 + k * 4.5)
		mat.albedo_color.a = 1.0 - k)
	burst(pos + Vector3(0, 0.3, 0), Color("#c9a066"), 30, 4.0)

# Every attack on Sora comes through here: flash dodge, flash guard, guard, or a plain hit.
# Returns what happened; a flash guard staggers the attacker.
func player_hit(dmg: int, src: Vector2, attacker: Dictionary) -> String:
	var gy := ground_y
	var here := Vector3(player.x, gy, player.z)
	if player.dodge > 0.0 and t - dodge_start <= 0.15 and flash_cd <= 0.0:
		slowmo = 2.0
		flash_cd = 3.0
		player.mp = minf(player.max_mp, player.mp + 20.0)
		player.sp = minf(100.0, player.sp + 25.0)
		burst(here + Vector3(0, 0.8, 0), Color("#9fe0ff"), 20, 2.5)
		sfx(880, 0.3, "sine", 0.3)
		toast("섬광 피하기!")
		stats.dodges += 1
		return "flash_dodge"
	if player.inv > 0.0:
		return "none"
	var to_src := (src - Vector2(player.x, player.z)).normalized()
	if guarding and to_src.dot(player.face) > 0.5: # attack from the front 120 degrees
		if t - guard_since <= 0.12:
			player.mp = minf(player.max_mp, player.mp + 25.0)
			counter_t = 1.5
			if not attacker.is_empty():
				attacker.stun = 2.0 if attacker.get("boss", false) else 1.0
				attacker.wind = 0.0
				attacker.swing = 0.0
			var m := MeshInstance3D.new()
			m.mesh = ring_mesh(0.7, 0.95, -PI / 2.0 - 0.9, 1.8)
			var mat := glow_mat(Color.WHITE, 3.0)
			m.material_override = mat
			m.position = here + Vector3(0, 0.6, 0)
			m.rotation.y = -atan2(player.face.y, player.face.x) - PI / 2.0
			add_fx(m, 0.2, func(_n: Node3D, k: float, _dt: float): mat.albedo_color.a = 1.0 - k)
			sfx(1200, 0.15, "square", 0.2)
			shake = maxf(shake, 0.15)
			toast("섬광 막기! 반격하라")
			stats.guards += 1
			return "flash_guard"
		player.sp = maxf(0.0, player.sp - 15.0)
		sfx(520, 0.05, "triangle", 0.1, -80) # blocked: a light tick
		hurt_player(int(ceil(dmg * 0.3)), gy)
		return "guard"
	hurt_player(dmg, gy)
	return "hit"

func hurt_player(dmg: int, gy: float) -> void:
	dmg = int(round(dmg * ng_mult()))
	if has_armour:
		dmg = maxi(1, int(round(dmg * 0.85)))
	player.hp -= dmg
	player.hurt_t = 0.2
	player.inv = 0.8
	shake = maxf(shake, 0.2)
	pop_num(Vector3(player.x, gy + 1.9, player.z), str(dmg), Color("#ff7a6a"))
	# getting hit: a short soft "oof" (two quiet tones) instead of a loud buzzing square thud
	sfx(rnd(300.0, 340.0), 0.09, "triangle", 0.13, -140.0)
	sfx(160.0, 0.12, "step", 0.08)
	if player.hp <= 0 and down_t <= 0.0:
		start_fall()

# Sora falls where she stands; 3 s later she wakes at the start (faint)
var down_t := 0.0
const DOWN_TIME := 3.0

func start_fall() -> void:
	down_t = DOWN_TIME
	player.hp = 0.0
	player.inv = 99.0
	player.vx = 0.0
	player.vz = 0.0
	player.dodge = 0.0
	guarding = false
	idle_name = ""
	set_hero_frame(player.dir, 0)
	sfx(330, 0.25, "triangle", 0.2, -200)
	get_tree().create_timer(0.3).timeout.connect(func(): sfx(150, 0.4, "triangle", 0.18, -60))
	burst(Vector3(player.x, ground_y + 0.4, player.z), Color("#d8c8a0"), 16, 1.5)

func update_fall(dt: float) -> void:
	down_t -= dt
	var k := clampf((DOWN_TIME - down_t) / 0.45, 0.0, 1.0) # tips over in 0.45 s, then lies still
	var side := -1.0 if player.face.dot(Vector2(cos(cam_yaw), -sin(cam_yaw))) < 0.0 else 1.0
	hero.billboard = BaseMaterial3D.BILLBOARD_DISABLED # a billboard ignores the node's tilt, so face the camera by hand
	hero.no_depth_test = true # lying low she would sink into the tall grass
	hero.rotation = Vector3(0, cam_yaw, -side * (PI / 2.0) * (1.0 - pow(1.0 - k, 3.0)))
	hero.position = Vector3(player.x, ground_y + 0.35 * k, player.z) # lifted a little so the grass does not swallow her
	var dim := clampf(1.0 - (DOWN_TIME - down_t - 2.0) / 1.0, 0.5, 1.0)
	hero.modulate = Color(dim, dim, dim)
	if hero_ghost != null:
		hero_ghost.visible = false
	if down_t <= 0.0:
		down_t = 0.0
		hero.rotation = Vector3.ZERO
		hero.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		hero.no_depth_test = false
		if hero_ghost != null:
			hero_ghost.visible = true
		hero.modulate = Color.WHITE
		player.inv = 0.8
		faint()

# Sora faints: say so plainly, keep gold and level, heal the boss, and wake her at the start
func faint() -> void:
	for id in ["mulgyeol", "noeul"]:
		if mate_down[id] > 0.0:
			mate_down[id] = 0.001 # gets up on the next tick
		mate_hp[id] = mate_max()
	if race_on:
		end_race("경주 중에 쓰러졌다")
	if trial_wave > 0:
		end_trial("시련에서 쓰러졌다")
	if in_garden:
		ui.mini.map_tex = village.map_tex(VILLAGE.VILLAGE_X + VILLAGE.W)
		in_garden = false
		in_village = true
		if garden_q >= 2 and garden_q < 5:
			garden_q = 1 # the fight starts over
			garden.set_posts(0)
			ring_k = -1
			for e in enemies:
				if (e.get("mold", false) or e.get("shard", false)) and not e.dead:
					e.dead = true
					e.node.queue_free()
					e.shadow.queue_free()
	if in_lake:
		in_lake = false
		in_village = true
		if grotto_q == 2:
			grotto_q = 1
			for e in enemies:
				if e.get("crab", false) and not e.dead:
					e.dead = true
					e.node.queue_free()
					e.shadow.queue_free()
		if lake_q == 3:
			for e in enemies:
				if e.get("turtle", false) and not e.dead:
					e.hp = float(e.max_hp)
					e.x = e.wx
					e.z = e.wz
			lake_q = 2 # row out again from the pier
			if lake_npc != null:
				lake_npc.visible = true
	if in_hill:
		in_hill = false
		in_village = true
		gust_dir = Vector2.ZERO
		for e in enemies:
			if e.get("hawk", false) and not e.dead:
				e.hp = float(e.max_hp)
			if (e.get("scare", false) or e.get("knight", false)) and not e.dead:
				e.dead = true
				e.node.queue_free()
				e.shadow.queue_free()
		if cloud_q == 2:
			cloud_q = 1
		if castle_q == 2:
			castle_q = 1
	if in_village or in_forest:
		in_forest = false
		in_village = true
		ui.mini.map_tex = village.map_tex(VILLAGE.VILLAGE_X + VILLAGE.W)
		ui.zone_name.text = "등불 마을"
		ui.zone_sub.text = "돌 광장"
		ui.boss.visible = false
		for e in enemies:
			if e.get("noeul", false) and not e.dead:
				e.hp = float(e.max_hp)
				e.x = e.wx
				e.z = e.wz
				e.dash = 0.0
				e.wind = 0.0
		player.hp = float(player.max_hp)
		player.x = village.marks.M.x - 1.5
		player.z = village.marks.M.y + 1.5
		player.inv = 2.0
		ground_y = 0.0
		ui.banner_title.text = "쓰러졌다"
		ui.banner_sub.text = "광장에서 다시 눈을 떴다 · 금화와 레벨은 그대로"
		ui.banner.modulate.a = 1.0
		return
	if in_cave: # wake outside: leave every bit of cave state behind
		in_cave = false
		if ui.has("outside_map"):
			ui.mini.map_tex = ui.outside_map
		ui.zone_name.text = "갈대늪"
		ui.zone_sub.text = "등불여울 건널목"
		ui.boss.visible = false
		for e in enemies:
			if e.get("mole", false) and not e.dead:
				e.hp = float(e.max_hp)
				e.x = cave_marks.B.x
				e.z = cave_marks.B.y
				e.dash = 0.0
				e.wind = 0.0
	player.hp = float(player.max_hp)
	player.x = START.x
	player.z = START.y
	player.inv = 2.0
	ground_y = height_at(START.x, START.y)
	for e in enemies:
		if e.get("boss", false) and not e.dead:
			e.hp = float(e.max_hp)
			e.x = e.home.x
			e.z = e.home.y
	ui.banner_title.text = "쓰러졌다"
	ui.banner_sub.text = "건널목에서 다시 눈을 떴다 · 금화와 레벨은 그대로"
	ui.banner.modulate.a = 1.0
	banner_t = 2.5
	sfx(330, 0.25, "triangle", 0.25, -150)
	get_tree().create_timer(0.25).timeout.connect(func(): sfx(220, 0.5, "triangle", 0.25, -100))

var enemy_shots: Array = []

func throw_brick(from: Vector2, dir: Vector2, owner: Dictionary) -> void:
	var b := box(Vector3(0.3, 0.2, 0.2), mat_color(Color("#c0522a")))
	b.position = Vector3(from.x, height_at(from.x, from.y) + 0.6, from.y)
	add_child(b)
	enemy_shots.append({"node": b, "v": dir * 4.0, "life": 2.0, "owner": owner})
	sfx(260, 0.08, "square", 0.12, -100)

func update_enemy_shots(dt: float) -> void:
	for i in range(enemy_shots.size() - 1, -1, -1):
		var sh: Dictionary = enemy_shots[i]
		sh.life -= dt
		var n: Node3D = sh.node
		n.position += Vector3(sh.v.x, 0, sh.v.y) * dt
		n.rotation.y += dt * 8.0
		var hit := Vector2(n.position.x - player.x, n.position.z - player.z).length() < 0.6
		if hit:
			player_hit(12, Vector2(n.position.x, n.position.z) - sh.v.normalized(), sh.owner)
		else:
			var mid := mate_near(Vector2(n.position.x, n.position.z), 0.6)
			if mid != "":
				hurt_mate(mid, 10)
				hit = true
		if hit or sh.life <= 0.0 or not walkable(n.position.x, n.position.z):
			n.queue_free()
			enemy_shots.remove_at(i)

# ---------------------------------------------------------------- 굴파기 수레두더지 (cave mid-boss)
# Charge: 1.0 s wind-up, then a straight dash at 9 tiles/s until it hits a wall (stuck 1.5 s, takes x1.5).
# Dirt: a 0.7 s red ring under Sora, then earth bursts up (two rings below half health).
func spawn_mole() -> void:
	var b: Vector2 = cave_marks.B
	var node := make_monster(true)
	var mats: Array = node.get_meta("mats")
	mats[2].albedo_color = Color("#6a4a2a") # brown body
	mats[5].albedo_color = Color("#3a2a20") # dark snout head
	node.scale = Vector3.ONE * 2.2
	var g: Node3D = node.get_meta("body")
	for side in [-0.32, 0.32]: # cart wheels
		var wheel := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.16
		cyl.bottom_radius = 0.16
		cyl.height = 0.08
		wheel.mesh = cyl
		wheel.material_override = mat_color(Color("#c8962a"))
		wheel.rotation.z = PI / 2
		wheel.position = Vector3(side, 0.12, 0.18)
		g.add_child(wheel)
	add_child(node)
	enemies.append({"x": b.x, "z": b.y, "hp": 650.0, "max_hp": 650, "node": node, "shadow": blob(1.8), "t": 0.0,
		"atk_cd": 2.0, "hurt": 0.0, "kx": 0.0, "kz": 0.0, "wx": b.x, "wz": b.y, "dead": false, "respawn": 0.0,
		"mole": true, "cave": true, "wind": 0.0, "dash": 0.0, "dir": Vector2.ZERO, "stun": 0.0, "next": "charge", "rings": []})

func update_mole(e: Dictionary, dt: float, d: float, to: Vector2) -> void:
	var node: Node3D = e.node
	var awake := d < 8.0
	ui.boss.visible = awake or (ui.boss.visible and d < 12.0)
	ui.boss_name.text = "굴파기 수레두더지"
	ui.boss_bar.size.x = 420.0 * maxf(0.0, e.hp) / e.max_hp
	e.t += dt
	e.hurt -= dt
	e.stun -= dt
	var me := Vector2(e.x, e.z)
	if e.dash > 0.0:
		e.dash -= dt
		var nx: float = e.x + e.dir.x * 9.0 * dt
		var nz: float = e.z + e.dir.y * 9.0 * dt
		if walkable(nx, nz):
			e.x = nx
			e.z = nz
			if Vector2(player.x - e.x, player.z - e.z).length() < 1.1:
				player_hit(25, me - e.dir, e)
		else: # crashed into the wall
			e.dash = 0.0
			e.stun = 1.5
			shake = 0.35
			sfx(80, 0.3, "square", 0.3, -40)
			burst(Vector3(e.x, 0.6, e.z), Color("#8a7a6a"), 20, 3.0)
	elif e.stun > 0.0:
		pass
	elif e.wind > 0.0:
		e.wind -= dt
		if e.wind <= 0.0:
			if e.next == "charge":
				e.dash = 1.2
				e.next = "dirt"
			else:
				for r in e.rings:
					burst(Vector3(r.x, 0.3, r.y), Color("#8a6a4a"), 18, 3.5)
					if Vector2(player.x, player.z).distance_to(r) < 1.2:
						player_hit(18, r, e)
				sfx(70, 0.25, "square", 0.25, -30)
				e.next = "charge"
			e.atk_cd = 1.4
	elif awake:
		e.atk_cd -= dt
		if e.atk_cd <= 0.0:
			if e.next == "charge":
				e.wind = 1.0
				e.dir = to / maxf(d, 0.01)
				pop_num(Vector3(e.x, 2.6, e.z), "!", Color("#ff5a4a"))
				sfx(120, 0.5, "sawtooth", 0.2, 120)
			else:
				e.wind = 0.7
				e.rings = [Vector2(player.x, player.z)]
				if e.hp < e.max_hp / 2.0:
					e.rings.append(Vector2(player.x, player.z) + Vector2(rnd(-2, 2), rnd(-2, 2)))
				for r in e.rings:
					warn_ring(Vector3(r.x, 0.0, r.y), 1.2, 0.7)
		elif d > 2.0: # trundle toward Sora
			var nx: float = e.x + to.x / d * 1.2 * dt
			var nz: float = e.z + to.y / d * 1.2 * dt
			if walkable(nx, e.z): e.x = nx
			if walkable(e.x, nz): e.z = nz
	node.position = Vector3(e.x, absf(sin(e.t * (12.0 if e.dash > 0 else 3.0))) * 0.08, e.z)
	var face: Vector2 = e.dir if e.dash > 0.0 or e.wind > 0.0 else to
	if face.length() > 0.1:
		node.rotation.y = atan2(face.x, face.y)
	var glowing: bool = e.hurt > 0 or e.wind > 0.0 or e.stun > 0.0
	for m in node.get_meta("mats"):
		m.emission_enabled = glowing
		m.emission = Color("#ff3a2a") if e.wind > 0.0 else (Color("#9fd4ff") if e.stun > 0.0 else Color.WHITE)
		m.emission_energy_multiplier = 0.9
	e.shadow.position = Vector3(e.x, 0.02, e.z)

func mole_defeated() -> void:
	has_skip = true
	ui.boss.visible = false
	set_quest("동쪽 출구로 나가자 (Shift를 누르고 물 위를 달릴 수 있다)")
	save_game()
	show_story("res://art/story/07_water_skip.jpg", STORY.WATER_SKIP)

func update_projectiles(dt: float) -> void:
	for i in range(projectiles.size() - 1, -1, -1):
		var p: Dictionary = projectiles[i]
		p.life -= dt
		var node: Node3D = p.node
		node.position += Vector3(p.v.x, 0, p.v.y) * dt
		var hit = null
		for e in enemies:
			if not e.dead and Vector2(e.x - node.position.x, e.z - node.position.z).length() < 0.7:
				hit = e
				break
		if hit != null:
			damage_enemy(hit, player.atk * 1.8, Vector2(node.position.x, node.position.z) - p.v * 0.05, 6.0)
			burst(node.position, Color("#ff9a4a"), 22, 3.0)
		if hit != null or p.life <= 0:
			node.queue_free()
			projectiles.remove_at(i)
