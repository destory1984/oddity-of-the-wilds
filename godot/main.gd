# Oddity of the Wilds: Godot 4 port of the browser demo.
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

var cam_yaw := 0.55
var cam_dist := 18.0
var shake := 0.0
var intro := true
var raining := false
var t := 0.0
var ground_y := 0.0         # smoothed ground height under the player, so 0.18 steps don't jolt the camera
var muted := false

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

func tile_at(x: float, z: float) -> int:
	var tx := int(round(x))
	var tz := int(round(z))
	if tx < 0 or tz < 0 or tx >= N or tz >= N:
		return WATER
	return map[idx(tx, tz)]

func height_at(x: float, z: float) -> float:
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
	rng.seed = 7
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
	build_player()
	for i in 9:
		spawn_enemy()
	enemies[0].x = 12.0
	enemies[0].z = 24.0
	enemies[1].x = 30.0
	enemies[1].z = 22.0
	build_chests()
	spawn_boss()
	build_particles()
	build_hud()
	update_daylight(0.0)
	# test hooks: `-- --play` skips the title, `-- --night` starts at night, `-- --shot` saves shot.png after 4 s and quits
	var args := OS.get_cmdline_user_args()
	if args.has("--play"):
		start_game()
	if args.has("--cottage"):
		player.x = 11.0
		player.z = 21.5
	if args.has("--shop"):
		player.x = shop_pos.x
		player.z = shop_pos.z
		player.gold = 120
		toggle_shop(true)
	if args.has("--boss"):
		player.x = 16.0
		player.z = 11.0
	if args.has("--night"):
		hour = 23.0
	for a in args:
		if a.begins_with("--day="):
			day = int(a.substr(6))
	if args.has("--shot"):
		get_tree().create_timer(4.0).timeout.connect(func():
			get_viewport().get_texture().get_image().save_png("res://shot.png")
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
		var length: float = b.b - b.a + 3
		var g := Node3D.new()
		var deck := box(Vector3(length, 0.12, 1.8), plank_mat)
		deck.position.y = 0.02
		g.add_child(deck)
		for side in [-0.95, 0.95]:
			for y in [0.62, 0.34]:
				var rail := box(Vector3(length, 0.08, 0.08), post_mat)
				rail.position = Vector3(0, y, side)
				g.add_child(rail)
			var i := 0.0
			while i <= length:
				var p := box(Vector3(0.14, 1.2, 0.14), post_mat)
				p.position = Vector3(i - length / 2.0, 0.15, side)
				g.add_child(p)
				i += 1.5
		g.position = Vector3((b.a + b.b) / 2.0, 0, b.z + 0.5)
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
			px(img, x, 32 - h, 1, h, Color("#6f9a34") if i % 2 else Color("#86ad3e"))
			px(img, x - 1, 32 - h - 1, 3, 6, Color("#8a4f22"))
			px(img, x - 1, 32 - h - 1, 1, 6, Color("#b5733a"))
			px(img, x, 32 - h - 3, 1, 2, Color("#c7a46a"))
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
	{"name": "마력 물약", "desc": "마력을 가득 채움", "price": 20},
	{"name": "벼린 칼날", "desc": "공격력 +3", "price": 80},
	{"name": "튼튼한 갑옷", "desc": "최대 체력 +15", "price": 80},
]

func near_shop() -> bool:
	return Vector2(player.x - shop_pos.x, player.z - shop_pos.z).length() < 1.6

func toggle_shop(open: bool) -> void:
	shop_open = open
	ui.shop.visible = open
	if open:
		refresh_shop()
		sfx(660, 0.12, "triangle", 0.2)

func refresh_shop() -> void:
	ui.shop_gold.text = "가진 금화 ◆ %d" % player.gold
	for i in SHOP.size():
		ui.shop_btns[i].disabled = player.gold < SHOP[i].price

func buy(i: int) -> void:
	var it: Dictionary = SHOP[i]
	if player.gold < it.price:
		toast("금화가 모자라다")
		return
	player.gold -= it.price
	match i:
		0: player.pots += 1
		1: player.mp = float(player.max_mp)
		2: player.atk += 3
		3:
			player.max_hp += 15
			player.hp += 15
	toast("%s을(를) 샀다" % it.name)
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
		"lv": 1, "xp": 0, "hp": 100.0, "max_hp": 100, "mp": 40.0, "max_mp": 40, "sp": 100.0, "atk": 10, "gold": 0, "pots": 3,
		"atk_cd": 0.0, "combo": 0, "combo_t": 0.0, "dodge": 0.0, "dvx": 0.0, "dvz": 0.0, "inv": 0.0, "cds": [0.0, 0.0, 0.0, 0.0], "hurt_t": 0.0,
	}
	# Sora walk sheets: 4 frames per row; straight rows front, left, right, away; diagonal rows dl, dr, ul, ur
	var straight: Texture2D = load("res://art/sora/sora-v2-walk-cut.png")
	var diag: Texture2D = load("res://art/sora/sora-v2-diag-cut.png")
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
	var ch := straight.get_height() / 4.0
	hero.pixel_size = 1.65 / ch
	hero.offset = Vector2(0, ch / 2.0)
	add_child(hero)
	hero_shadow = blob(0.9)
	set_hero_frame("down", 0)

func set_hero_frame(dir: String, frame: int) -> void:
	var e: Array = hero_tex[dir]
	var tex: Texture2D = e[0]
	var cw := tex.get_width() / 4.0
	var ch := tex.get_height() / 4.0
	hero.texture = tex
	hero.region_rect = Rect2(frame * cw, e[1] * ch, cw, ch)

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

func spawn_enemy() -> void:
	var x := 0.0
	var z := 0.0
	var tries := 0
	while true:
		x = rnd(4, N - 4)
		z = rnd(4, N - 4)
		tries += 1
		if (walkable(x, z) and Vector2(x - player.x, z - player.z).length() >= 9) or tries > 1000:
			break
	var node := make_monster()
	add_child(node)
	var hp: int = 30 + player.lv * 10
	enemies.append({"x": x, "z": z, "hp": float(hp), "max_hp": hp, "node": node, "shadow": blob(0.8), "t": rnd(0, 5),
		"atk_cd": 1.0, "hurt": 0.0, "kx": 0.0, "kz": 0.0, "wx": x, "wz": z, "dead": false, "respawn": 0.0})

# the Brick King waits at the northern edge of the map; he does not respawn
func spawn_boss() -> void:
	var spot := Vector2(16, 4)
	for tries in 40:
		if walkable(spot.x, spot.y):
			break
		spot = Vector2(rnd(6, 20), rnd(3, 6))
	var node := make_monster(true)
	add_child(node)
	var hp := 600
	enemies.append({"x": spot.x, "z": spot.y, "hp": float(hp), "max_hp": hp, "node": node, "shadow": blob(2.4), "t": 0.0,
		"atk_cd": 2.0, "hurt": 0.0, "kx": 0.0, "kz": 0.0, "wx": spot.x, "wz": spot.y, "dead": false, "respawn": 0.0,
		"boss": true, "home": spot, "stomp": 0.0})

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

func slash_fx(pos: Vector3, ang: float, big: bool) -> void:
	var m := MeshInstance3D.new()
	m.mesh = ring_mesh(1.6 if big else 0.55, 2.4 if big else 1.25, 0.0, TAU if big else 1.8)
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

func sfx(freq: float, dur := 0.1, wave := "square", vol := 0.25, slide := 0.0) -> void:
	if muted:
		return
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
				"noise":
					lp = lerpf(lp, randf_range(-1.0, 1.0), 0.18) # one-pole low-pass takes the hiss off
					v = lp * 2.2 * (0.6 + 0.4 * sin(phase * TAU))
				_: v = sin(phase * TAU)
			v *= vol * pow(0.0001, k) # exponential fade like the web version
			data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
		stream = AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.mix_rate = rate
		stream.data = data
		sfx_cache[key] = stream
	var pl := AudioStreamPlayer.new()
	pl.stream = stream
	add_child(pl)
	pl.play()
	pl.finished.connect(pl.queue_free)

# footsteps: a grass rustle, or a hollow knock on bridge planks; a few cached variants
var step_frame := -1

func footstep() -> void:
	if tile_at(player.x, player.z) == BRIDGE:
		sfx([150.0, 165.0, 140.0][rng.randi() % 3], 0.07, "triangle", 0.22, -60.0)
	else:
		sfx([90.0, 110.0, 100.0][rng.randi() % 3], 0.06, "noise", 0.12)

# ---------------------------------------------------------------- combat
func damage_enemy(e: Dictionary, amt: float, from: Vector2, kb := 4.0) -> void:
	if e.dead:
		return
	var crit := rng.randf() < 0.15
	var dmg := int(round(amt * rnd(0.85, 1.15) * (1.8 if crit else 1.0)))
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
		e.node.queue_free()
		e.shadow.queue_free()
		burst(Vector3(e.x, y + 0.4, e.z), Color("#ff9a4a"), 26, 3.5)
		if e.get("boss", false):
			player.gold += 300
			toast("벽돌왕을 쓰러뜨렸다! 금화 +300")
			ui.boss.visible = false
			shake = 0.6
			for k in 4:
				burst(Vector3(e.x + rnd(-1, 1), y + rnd(0.5, 2.5), e.z + rnd(-1, 1)), Color("#e8b018"), 30, 5.0)
			gain_xp(200)
		else:
			var g := 3 + rng.randi() % 5
			player.gold += g
			toast("금화 +%d" % g)
			gain_xp(12)

func gain_xp(n: int) -> void:
	player.xp += n
	while player.xp >= player.lv * 25:
		player.xp -= player.lv * 25
		player.lv += 1
		player.max_hp += 12
		player.atk += 3
		player.max_mp += 5
		player.hp = float(player.max_hp)
		player.mp = float(player.max_mp)
		ui.banner_title.text = "레벨 %d" % player.lv
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

func attack() -> void:
	if player.atk_cd > 0 or player.dodge > 0:
		return
	var tg = nearest_enemy(2.2)
	if tg != null:
		player.face = Vector2(tg.x - player.x, tg.z - player.z).normalized()
	player.combo = (player.combo + 1) % 3 if player.combo_t > 0 else 0
	player.combo_t = 0.6
	player.atk_cd = 0.38 if player.combo == 2 else 0.24
	var f: Vector2 = player.face
	var ang := -atan2(f.y, f.x) - 0.9 * (-1.0 if player.combo == 1 else 1.0) + 0.9
	slash_fx(Vector3(player.x + f.x * 0.5, height_at(player.x, player.z), player.z + f.y * 0.5), ang, false)
	for e in enemies:
		if e.dead:
			continue
		var d := Vector2(e.x - player.x, e.z - player.z)
		if d.length() < 1.7 and d.normalized().dot(f) > -0.1:
			damage_enemy(e, player.atk * (1.6 if player.combo == 2 else 1.0), Vector2(player.x, player.z), 7.0 if player.combo == 2 else 3.0)
	player.vx += f.x * 2.0
	player.vz += f.y * 2.0
	sfx(180.0 + player.combo * 60.0, 0.07, "sawtooth", 0.12, 300.0)

const SKILL_MP := [10, 8, 20]
const SKILL_CD := [3.0, 1.2, 6.0]

func use_skill(i: int) -> void:
	if player.cds[i] > 0:
		return
	if player.mp < SKILL_MP[i]:
		toast("MP가 모자라다")
		return
	player.mp -= SKILL_MP[i]
	player.cds[i] = SKILL_CD[i]
	var here := Vector3(player.x, height_at(player.x, player.z), player.z)
	var me := Vector2(player.x, player.z)
	match i:
		0: # whirl
			sfx(140, 0.3, "sawtooth", 0.2, 400)
			slash_fx(here, 0.0, true)
			for e in enemies:
				if not e.dead and Vector2(e.x, e.z).distance_to(me) < 2.6:
					damage_enemy(e, player.atk * 1.4, me, 6.0)
		1: # ember bolt
			sfx(400, 0.2, "triangle", 0.2, -250)
			var tg = nearest_enemy(12.0)
			var dir: Vector2 = (Vector2(tg.x, tg.z) - me).normalized() if tg != null else player.face
			var b := MeshInstance3D.new()
			var sp := SphereMesh.new()
			sp.radius = 0.16
			sp.height = 0.32
			b.mesh = sp
			b.material_override = glow_mat(Color("#ff8a2a"), 4.0)
			var l := OmniLight3D.new()
			l.light_color = Color("#ff8a3a")
			l.light_energy = 2.0
			l.omni_range = 4.0
			b.add_child(l)
			b.position = here + Vector3(0, 0.6, 0)
			add_child(b)
			projectiles.append({"node": b, "v": dir * 14.0, "life": 1.2})
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

func drink_potion() -> void:
	if player.pots <= 0:
		toast("회복약이 없다")
		return
	if player.cds[3] > 0:
		return
	player.pots -= 1
	player.cds[3] = 2.0
	var h := minf(player.max_hp - player.hp, 45.0)
	player.hp += h
	var y := height_at(player.x, player.z)
	pop_num(Vector3(player.x, y + 1.9, player.z), "+%d" % int(h), Color("#8dff9a"))
	burst(Vector3(player.x, y + 0.6, player.z), Color("#8dff9a"), 20, 2.0)
	sfx(660, 0.25, "sine", 0.25, 300)

func dodge() -> void:
	if player.dodge > 0 or player.sp < 25:
		return
	player.sp -= 25
	player.dodge = 0.32
	player.inv = 0.4
	var d := Vector2(player.vx, player.vz)
	d = player.face if d.length() < 0.1 else d.normalized()
	player.dvx = d.x * 11.0
	player.dvz = d.y * 11.0
	sfx(120, 0.12, "triangle", 0.15, 80)

func interact() -> void:
	if near_shop():
		toggle_shop(not shop_open)
		return
	for c in chests:
		if not c.open and Vector2(c.x - player.x, c.z - player.z).length() < 1.5:
			c.open = true
			c.node.modulate = Color(0.55, 0.55, 0.55)
			var g := 15 + rng.randi() % 15
			player.gold += g
			player.pots += 1
			burst(Vector3(c.x, height_at(c.x, c.z) + 0.6, c.z), Color("#ffd84a"), 30, 3.0)
			toast("금화 %d닢과 회복약을 찾았다" % g)
			sfx(784, 0.12, "triangle", 0.25)
			get_tree().create_timer(0.1).timeout.connect(func(): sfx(1046, 0.25, "triangle", 0.25))
			return

# ---------------------------------------------------------------- day and night
# The clock runs on its own: one in-game hour every DAY_SPEED seconds (a full day in 6 minutes).
# Light, fog and sky blend between these key hours; T skips ahead three hours.
const DAY_SPEED := 15.0
const KEY_HOURS := [
	{"h": 0.0, "sun": "#6a7cc8", "si": 0.25, "amb": "#2a3460", "ai": 0.55, "fog": "#141a30", "el": 0.9, "night": 1.0, "beams": 0.0},
	{"h": 5.0, "sun": "#6a7cc8", "si": 0.25, "amb": "#2a3460", "ai": 0.55, "fog": "#141a30", "el": 0.1, "night": 1.0, "beams": 0.0},
	{"h": 6.5, "sun": "#ff9a6a", "si": 0.9, "amb": "#b08aa0", "ai": 0.8, "fog": "#d8a08a", "el": 0.2, "night": 0.4, "beams": 0.6},
	{"h": 9.0, "sun": "#fff0d0", "si": 1.5, "amb": "#e8eef8", "ai": 1.0, "fog": "#cfe0e8", "el": 0.7, "night": 0.0, "beams": 0.3},
	{"h": 13.0, "sun": "#fff4e0", "si": 1.7, "amb": "#eaf4ff", "ai": 1.05, "fog": "#cfe2ee", "el": 1.1, "night": 0.0, "beams": 0.2},
	{"h": 16.5, "sun": "#ffc06a", "si": 1.5, "amb": "#fff0d0", "ai": 0.95, "fog": "#e8c98a", "el": 0.55, "night": 0.1, "beams": 1.0},
	{"h": 18.5, "sun": "#ff7a4a", "si": 0.9, "amb": "#9a7aa8", "ai": 0.7, "fog": "#b07a80", "el": 0.2, "night": 0.6, "beams": 0.5},
	{"h": 20.0, "sun": "#6a7cc8", "si": 0.3, "amb": "#2a3460", "ai": 0.55, "fog": "#141a30", "el": 0.6, "night": 1.0, "beams": 0.0},
	{"h": 24.0, "sun": "#6a7cc8", "si": 0.25, "amb": "#2a3460", "ai": 0.55, "fog": "#141a30", "el": 0.9, "night": 1.0, "beams": 0.0},
]
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
	toast("%02d시" % int(hour))

func update_daylight(dt: float) -> void:
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

	var zone := panel(root, Vector2(14, 12), Vector2(190, 58))
	label(zone, "◆", Vector2(14, 16), 16, Color("#b9a273"))
	label(zone, "갈대늪", Vector2(42, 6), 19)
	label(zone, "등불여울 건널목", Vector2(42, 32), 13, Color("#a99d84"))

	var stats := panel(root, Vector2(14, 72), Vector2(396, 72))
	label(stats, "레벨", Vector2(14, 8), 11, Color("#a99d84"))
	ui.lv = label(stats, "1", Vector2(18, 24), 30)
	for row in [["체력", 10, Color("#d83a44")], ["마력", 30, Color("#3f74e0")], ["기력", 50, Color("#e9d39a")]]:
		label(stats, row[0], Vector2(56, row[1] - 4), 11, Color("#a99d84"))
	ui.hp = bar(stats, Vector2(100, 10), Color("#d83a44"))
	ui.mp = bar(stats, Vector2(100, 30), Color("#3f74e0"))
	ui.sp = bar(stats, Vector2(100, 50), Color("#e9d39a"))
	ui.hpt = label(stats, "", Vector2(310, 3), 12)
	ui.mpt = label(stats, "", Vector2(310, 23), 12)

	# shop window
	var shop := panel(root, Vector2(-200, -150), Vector2(400, 300), Control.PRESET_CENTER)
	shop.mouse_filter = Control.MOUSE_FILTER_STOP
	var st := label(shop, "갈대늪 상점", Vector2(0, 10), 20, Color("#f6b951"))
	st.size = Vector2(400, 26)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.shop_btns = []
	for i in SHOP.size():
		var it: Dictionary = SHOP[i]
		label(shop, "%d" % (i + 1), Vector2(20, 54 + i * 50), 13, Color("#a99d84"))
		label(shop, it.name, Vector2(42, 48 + i * 50), 16)
		label(shop, it.desc, Vector2(42, 70 + i * 50), 12, Color("#a99d84"))
		var b := Button.new()
		b.text = "◆ %d" % it.price
		b.add_theme_font_override("font", ui_font)
		b.position = Vector2(290, 52 + i * 50)
		b.size = Vector2(90, 32)
		var idx_ := i
		b.pressed.connect(func(): buy(idx_))
		shop.add_child(b)
		ui.shop_btns.append(b)
	ui.shop_gold = label(shop, "", Vector2(20, 256), 14, Color("#ffd84a"))
	label(shop, "Space / Esc 닫기", Vector2(270, 258), 12, Color("#a99d84"))
	shop.visible = false
	ui.shop = shop
	ui.shop_hint = label(root, "Space  상점 들어가기", Vector2.ZERO, 16, Color("#fff1c8"))
	place(ui.shop_hint, Control.PRESET_CENTER_BOTTOM, Vector2(-150, -260), Vector2(300, 24))
	ui.shop_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.shop_hint.add_theme_constant_override("outline_size", 6)
	ui.shop_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	ui.shop_hint.visible = false

	# boss health bar, top centre, shown while the Brick King is awake
	var bb := panel(root, Vector2(-220, 14), Vector2(440, 40), Control.PRESET_CENTER_TOP)
	var bn := label(bb, "벽돌왕", Vector2(0, 2), 13, Color("#f6b951"))
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

	# sky dial under the stats: sun and moon travel the arc with the clock
	var sky := Control.new()
	sky.set_script(load("res://sky.gd"))
	sky.main = self
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky.clip_contents = true
	root.add_child(sky)
	place(sky, Control.PRESET_TOP_LEFT, Vector2(14, 146), Vector2(190, 64))

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
	var pal := [Color("#6f93a6"), Color("#d8c896"), Color("#e9d9aa"), Color("#8a5a32")]
	for z in N:
		for x in N:
			mimg.set_pixel(x, z, pal[map[idx(x, z)]])
	for z in range(1, N - 1):
		for x in range(1, N - 1):
			var w := map[idx(x, z)] == WATER
			if not w:
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if map[idx(x + d.x, z + d.y)] == WATER:
						mimg.set_pixel(x, z, Color("#7a6440"))
				if hgt[idx(x, z)] > 0.5 and (x + z) % 3 == 0:
					mimg.set_pixel(x, z, Color("#b8a474"))
	mini.map_tex = ImageTexture.create_from_image(mimg)
	mini.main = self
	mask.add_child(mini)

	# skills, bottom right
	var names := ["회오리", "불씨탄", "빛파동", "×3"]
	var keys_ := ["U", "I", "O", "4"]
	var icons := ["○", "●", "◇", "♥"]
	var icon_cols := [Color("#9fd4ff"), Color("#ff8a2a"), Color("#fff1a0"), Color("#8dff9a")]
	ui.cd = []
	for i in 4:
		var slot := panel(root, Vector2(-290 + i * 70, -86), Vector2(56, 48), Control.PRESET_BOTTOM_RIGHT)
		label(slot, keys_[i], Vector2(3, 1), 10, Color("#e9dfc4"))
		label(slot, icons[i], Vector2(18, 10), 22, icon_cols[i])
		var cd := ColorRect.new()
		cd.color = Color(0, 0, 0, 0.65)
		cd.size = Vector2(56, 0)
		slot.add_child(cd)
		ui.cd.append(cd)
		var n := label(root, names[i], Vector2(0, 0), 12)
		place(n, Control.PRESET_BOTTOM_RIGHT, Vector2(-290 + i * 70, -36), Vector2(56, 20))
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if i == 3:
			ui.pots = n
	var gold := panel(root, Vector2(-80, -130), Vector2(66, 30), Control.PRESET_BOTTOM_RIGHT)
	ui.gold = label(gold, "◆ 0", Vector2(10, 4), 14, Color("#ffd84a"))

	# controls help, starts hidden; H or the button toggles it
	var help := panel(root, Vector2(14, -330), Vector2(300, 316), Control.PRESET_BOTTOM_LEFT)
	help.mouse_filter = Control.MOUSE_FILTER_STOP
	label(help, "조작법", Vector2(14, 8), 12, Color("#a99d84"))
	var rows := [["WASD / 방향키", "이동"], ["Shift", "달리기"], ["J / 왼쪽 클릭", "공격 (연속기)"], ["K / 오른쪽 클릭", "구르기"],
		["U I O / 1 2 3", "스킬"], ["4", "회복약"], ["Space", "상자 열기"], ["Z X / 휠", "확대·축소"], ["T R P", "3시간 뒤로 / 비 / 사진"], ["H", "조작법 숨기기"]]
	for i in rows.size():
		label(help, rows[i][0], Vector2(14, 34 + i * 27), 13, Color("#e9dfc4"))
		label(help, rows[i][1], Vector2(150, 34 + i * 27), 15)
	var close := Button.new()
	close.text = "X"
	close.add_theme_font_override("font", ui_font)
	close.position = Vector2(270, 6)
	close.size = Vector2(24, 24)
	close.pressed.connect(func(): toggle_help(false))
	help.add_child(close)
	help.visible = false
	ui.help = help
	var hint := Button.new()
	hint.text = "H  조작법 보기"
	hint.add_theme_font_override("font", ui_font)
	place(hint, Control.PRESET_BOTTOM_LEFT, Vector2(14, -44), Vector2(130, 30))
	hint.pressed.connect(func(): toggle_help(true))
	root.add_child(hint)
	ui.hint = hint

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
	var sub := label(banner, "최대 체력 +12 · 공격력 +3", Vector2(-200, 170), 18)
	sub.size = Vector2(400, 30)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.modulate.a = 0.0
	ui.banner = banner

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
	ui.hidden_for_intro = root.get_children().filter(func(c): return c != title and c != ui.help and c != ui.boss and c != ui.shop and c != ui.shop_hint)
	for k in ["zone", "stats"]:
		pass

func toggle_help(show: bool) -> void:
	ui.help.visible = show
	ui.hint.visible = not show

func toast(msg: String) -> void:
	ui.toast.text = msg
	ui.toast.modulate.a = 1.0
	toast_t = 2.2

func start_game() -> void:
	if not intro:
		return
	intro = false
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
	if intro and ((event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed)):
		start_game()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if intro:
		return
	if shop_open:
		if event is InputEventKey and event.pressed and not event.echo:
			match event.keycode:
				KEY_1, KEY_2, KEY_3, KEY_4: buy(event.keycode - KEY_1)
				KEY_SPACE, KEY_ESCAPE: toggle_shop(false)
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT: attack()
			MOUSE_BUTTON_RIGHT: dodge()
			MOUSE_BUTTON_WHEEL_UP: cam_dist = clampf(cam_dist - 1.2, 8, 26)
			MOUSE_BUTTON_WHEEL_DOWN: cam_dist = clampf(cam_dist + 1.2, 8, 26)
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
			KEY_M:
				muted = not muted
				toast("소리 끔" if muted else "소리 켬")

# ---------------------------------------------------------------- loop
func _process(dt: float) -> void:
	dt = minf(dt, 1.0 / 20.0)
	t += dt
	if intro:
		cam_yaw += dt * 0.08
	if CAM_ROTATE:
		if Input.is_key_pressed(KEY_Q): cam_yaw -= 1.6 * dt
		if Input.is_key_pressed(KEY_E): cam_yaw += 1.6 * dt
	if Input.is_key_pressed(KEY_Z): cam_dist = maxf(8, cam_dist - 12 * dt)
	if Input.is_key_pressed(KEY_X): cam_dist = minf(26, cam_dist + 12 * dt)

	# movement relative to the camera
	var fwd := Vector2(-sin(cam_yaw), -cos(cam_yaw))
	var right := Vector2(cos(cam_yaw), -sin(cam_yaw))
	var mv := Vector2.ZERO
	if not intro and not shop_open:
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): mv += fwd
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): mv -= fwd
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): mv += right
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): mv -= right
	var running: bool = Input.is_key_pressed(KEY_SHIFT) and player.sp > 0 and mv.length() > 0
	player.sp = maxf(0, player.sp - 22 * dt) if running else minf(100, player.sp + 18 * dt)
	var speed := 6.2 if running else 3.6
	var tv := Vector2.ZERO
	if mv.length() > 0:
		mv = mv.normalized()
		tv = mv * speed
		player.face = mv
	if player.atk_cd > 0.1:
		tv *= 0.3
	var blend := minf(1.0, dt * 14.0)
	player.vx += (tv.x - player.vx) * blend
	player.vz += (tv.y - player.vz) * blend
	var v := Vector2(player.vx, player.vz)
	if player.dodge > 0:
		v = Vector2(player.dvx, player.dvz)
		player.dodge -= dt
	var nx: float = player.x + v.x * dt
	var nz: float = player.z + v.y * dt
	if walkable(nx, player.z): player.x = nx
	if walkable(player.x, nz): player.z = nz

	player.atk_cd = maxf(0, player.atk_cd - dt)
	player.combo_t -= dt
	player.inv -= dt
	player.hurt_t -= dt
	for i in 4:
		player.cds[i] = maxf(0, player.cds[i] - dt)
	player.mp = minf(player.max_mp, player.mp + 2.5 * dt)
	ui.shop_hint.visible = not intro and not shop_open and near_shop()
	if shop_open and not near_shop():
		toggle_shop(false)
	if Input.is_key_pressed(KEY_J) and player.atk_cd <= 0 and not intro and not shop_open:
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
	set_hero_frame(player.dir, frame)
	# feet touch the ground on frames 0 and 2 of the walk cycle
	if moving and frame != step_frame and frame % 2 == 0 and player.dodge <= 0:
		footstep()
	step_frame = frame
	ground_y = lerpf(ground_y, height_at(player.x, player.z), minf(1.0, dt * 10.0))
	var gy := ground_y
	var hop := sin((player.dodge / 0.32) * PI) * 0.35 if player.dodge > 0 else 0.0
	hero.position = Vector3(player.x, gy + hop, player.z)
	var blink: bool = player.inv > 0 and player.dodge <= 0 and sin(t * 40.0) < 0
	# Sora is unshaded, so tint her by hand to sit in the night light
	var lit := Color(1, 1, 1).lerp(Color(0.5, 0.56, 0.8), night)
	hero.modulate = Color(1, 0.5, 0.5) if player.hurt_t > 0 else Color(lit.r, lit.g, lit.b, 0.3 if blink else 1.0)
	hero_shadow.position = Vector3(player.x, gy + 0.02, player.z)

	update_enemies(dt, gy)
	update_daylight(dt)
	update_lights()
	update_projectiles(dt)
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
	camera.position = target + Vector3(sin(cam_yaw) * cos(pitch) * cam_dist + rnd(-1, 1) * shake * 0.4,
		sin(pitch) * cam_dist + rnd(-1, 1) * shake * 0.4, cos(cam_yaw) * cos(pitch) * cam_dist)
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
	ui.hp.size.x = 200.0 * player.hp / player.max_hp
	ui.mp.size.x = 200.0 * player.mp / player.max_mp
	ui.sp.size.x = 2.0 * player.sp
	ui.hpt.text = "%d/%d" % [ceili(player.hp), player.max_hp]
	ui.mpt.text = "%d/%d" % [int(player.mp), player.max_mp]
	ui.gold.text = "◆ %d" % player.gold
	ui.pots.text = "×%d" % player.pots
	for i in 3:
		ui.cd[i].size.y = 48.0 * player.cds[i] / SKILL_CD[i]
	ui.cd[3].size.y = 48.0 * player.cds[3] / 2.0

func update_enemies(dt: float, gy: float) -> void:
	for e in enemies.duplicate():
		if e.dead and e.get("boss", false):
			continue
		if e.dead:
			e.respawn -= dt
			if e.respawn <= 0:
				enemies.erase(e)
				spawn_enemy()
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
		if d < 7 and not intro:
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
		if e.hurt > 0:
			ev = Vector2(e.kx, e.kz)
		var nx: float = e.x + ev.x * dt
		var nz: float = e.z + ev.y * dt
		if walkable(nx, e.z): e.x = nx
		if walkable(e.x, nz): e.z = nz
		if not intro and d < 1.1 and e.atk_cd <= 0 and e.hurt <= 0:
			e.atk_cd = 1.4
			if player.inv <= 0:
				var dmg := int(round(rnd(5, 9) + player.lv))
				player.hp -= dmg
				player.hurt_t = 0.2
				player.inv = 0.5
				shake = 0.2
				pop_num(Vector3(player.x, gy + 1.9, player.z), str(dmg), Color("#ff7a6a"))
				sfx(90, 0.15, "square", 0.25, -40)
				if player.hp <= 0:
					player.hp = float(player.max_hp)
					player.x = START.x
					player.z = START.y
					toast("건널목에서 다시 눈을 떴다…")
		var ey := height_at(e.x, e.z)
		var hop := absf(sin(e.t * 6.0))
		var node: Node3D = e.node
		node.position = Vector3(e.x, ey + hop * 0.14, e.z)
		node.get_meta("body").scale = Vector3(1 + (1 - hop) * 0.08, 1 - (1 - hop) * 0.1, 1 + (1 - hop) * 0.08)
		if ev.length() > 0.1:
			node.rotation.y = atan2(ev.x, ev.y)
		for m in node.get_meta("mats"):
			m.emission_enabled = e.hurt > 0
			m.emission = Color.WHITE
			m.emission_energy_multiplier = 0.9
		e.shadow.position = Vector3(e.x, ey + 0.02, e.z)

# Brick King: wakes when Sora comes near, lumbers after her, and every few
# seconds leaps and stomps, sending out a shockwave ring
func update_boss(e: Dictionary, dt: float, d: float, to: Vector2, gy: float) -> void:
	var node: Node3D = e.node
	var awake := d < 11.0 and not intro
	ui.boss.visible = awake or (ui.boss.visible and d < 16.0)
	ui.boss_bar.size.x = 420.0 * maxf(0.0, e.hp) / e.max_hp
	var ev := Vector2.ZERO
	if e.stomp > 0:
		e.stomp -= dt
		var k: float = 1.0 - e.stomp / 0.9
		node.position.y = height_at(e.x, e.z) + sin(k * PI) * 1.6
		if e.stomp <= 0:
			stomp_wave(Vector3(e.x, height_at(e.x, e.z), e.z))
			if d < 4.2 and player.inv <= 0:
				hurt_player(int(18 + player.lv * 2), gy)
	else:
		if awake and d > 1.8:
			ev = to / d * 1.4
		elif not awake:
			var home: Vector2 = e.home
			var back := home - Vector2(e.x, e.z)
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
		if awake and e.atk_cd <= 0:
			e.atk_cd = 3.2 if e.hp > e.max_hp / 2 else 2.2 # angrier at half health
			e.stomp = 0.9
			sfx(70, 0.4, "square", 0.25, 60)
		node.position = Vector3(e.x, height_at(e.x, e.z) + absf(sin(e.t * 3.0)) * 0.1, e.z)
	e.t += dt
	e.hurt -= dt
	if ev.length() > 0.1:
		node.rotation.y = atan2(ev.x, ev.y)
	for m in node.get_meta("mats"):
		m.emission_enabled = e.hurt > 0
		m.emission = Color.WHITE
		m.emission_energy_multiplier = 0.9
	e.shadow.position = Vector3(e.x, height_at(e.x, e.z) + 0.02, e.z)

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

func hurt_player(dmg: int, gy: float) -> void:
	player.hp -= dmg
	player.hurt_t = 0.2
	player.inv = 0.5
	shake = maxf(shake, 0.2)
	pop_num(Vector3(player.x, gy + 1.9, player.z), str(dmg), Color("#ff7a6a"))
	sfx(90, 0.15, "square", 0.25, -40)
	if player.hp <= 0:
		player.hp = float(player.max_hp)
		player.x = START.x
		player.z = START.y
		toast("건널목에서 다시 눈을 떴다…")

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
