# 등불 마을 (story step 8): a separate 48x36 area at x >= VILLAGE_X, built from blocks like the cave.
# Holds the map, its build, the lamplighter Simji, the three dark lanterns and the first errand.
# The first 32x24 is the old village; the market (three honesty-box stalls 1 2 3, the target yard Q) lies east,
# the inn (I, door N) and the pond with its pier (P, fishing spot f, three drifting bottles B) south.
# It moved from x 140 to x 560 when it grew, because the forest starts at x 180.
extends RefCounted

const VILLAGE_X := 560
const OLD_X := 140 # where it stood before it grew (old saves are moved over)
const W := 48
const H := 36
const ROWS := """################################################
#..HHH.......HHH.......HHH.....................#
#..HHH...L...HHH...L...HHH........TT..TT..TT..L#
#....=.........=.........=........1...2...3....#
#....=.........=.........=.......:::::::::::::.#
#....===========.........=.......:::::::::::::.#
#..............=.........=.......::::::::::::L.#
#.........L.oooooooo.L...=.......:::::::::::::.#
#...........oooooooo.....=.......:::::::::::::.#
#L..........ooooMooo.....=.....................#
G=S=========oooooooo===========================F
#L..........oooooooo.....=.....................#
#.........L.oooooooo.L...=........##########...#
#..............=.........=........#........#...#
#..HHH.........=.......b.=.b......#........#...#
#..HHH...L.....=.......d.=.d......#...Q....#.L.#
#....=.........=.........=........#........#...#
#....===========.........=........#........#...#
#..........HHH...........=........####..####...#
#..........HHH.......b...=.....................#
#....................d...=..............L......#
#..............................................#
#..............................................#
#...............=..............................#
#...............=.......L......................#
#..IIIII........=.........~~~~~~~~~~~~~~~~~~~~.#
#..IIIII....L...=.........~~~~~~~~~~~~~~~B~~~~.#
#..IIIII........=.........~~~~~~~~~~~~~~~~~~~~.#
#....N..........=.........~~~~~~~~~~~~~~~~~~~~.#
#....============......PPPPPPPPPPPPPf~~~~~~~~~.#
#...............=.........~~~~~~~~~~~~~~~~~~~~.#
#.........L.....=....L....~~~~~~~~~~~~~~~~~~~~.#
#...............=.........~~~~~~~~~~~~~~~~~B~~.#
#..L............=.........~~~~~B~~~~~~~~~~~~~~.#
#...............=..............................#
################K###############################"""

var grid: Array = []
var marks := {}          # S, G, M, F, K, R (the moon-trial stone), Q the target post, N the inn door, f the pier's end, 1 2 3 stalls -> world Vector2
var bottles: Array = []  # [{"pos": Vector2, "node": Node3D, "got": bool}]
var stall_names := {"1": "과일 가판대", "2": "달빛 가루 가판대", "3": "찻집 가판대"}
var dark: Array = []     # [{"pos": Vector2, "light": OmniLight3D, "glass": MeshInstance3D, "lit": bool, "brick": Vector2}]
var simji_node: Node3D
# villagers you can talk to with E: id and tile in the village grid
const FOLK := [
	{"id": "doran", "at": Vector2i(14, 3)},
	{"id": "kongal", "at": Vector2i(10, 15)},
	{"id": "mulgyeol", "at": Vector2i(28, 21)},
]
var folk_pos := {}
var doors: Array = []    # world Vector2 in front of each house door, in build order
var folk_node := {}

func _init() -> void:
	for line in ROWS.split("\n"):
		grid.append(line)

func char_at(x: float, z: float) -> String:
	var tx := int(round(x)) - VILLAGE_X
	var tz := int(round(z))
	if tx < 0 or tz < 0 or tx >= W or tz >= H:
		return "#"
	return grid[tz][tx]

# fence and houses block; everything else is walkable ground
func blocked(x: float, z: float) -> bool:
	var c := char_at(x, z)
	return c in "#HTI~B"

func build(m: Node) -> void:
	var blocks: Array = [] # [Transform3D, Color]
	var lamp_spots: Array = []
	var dark_spots: Array = []
	var bricks: Array = []
	for z in H:
		for x in W:
			var c: String = grid[z][x]
			var w := Vector2(VILLAGE_X + x, z)
			if c in "SGMFKRQNf123":
				marks[c] = w
			if c == "B":
				bottles.append({"pos": w, "node": null, "got": false})
			var col := Color("#5e8f30")
			match c:
				"=": col = Color("#b8a888")
				"o": col = Color("#9a9a8e")
				"#": col = Color("#6a4a2c")
				"H": col = Color("#4a6a2c")
				":", "1", "2", "3": col = Color("#a89880")
				"P", "f": col = Color("#9a7448")
				"~", "B": col = Color("#2a5a8a")
			col = col.lightened(m.rnd(0, 0.08))
			var hgt := 0.4
			if c == "#":
				hgt = 0.9 # low fence blocks
			if c == "~" or c == "B":
				blocks.append([Transform3D(Basis().scaled(Vector3(1, 0.05, 1)), Vector3(w.x, -0.42, w.y)), col])
				continue
			if c == "P" or c == "f":
				hgt = 0.5 # pier boards stand a little above the ground
			blocks.append([Transform3D(Basis().scaled(Vector3(1, hgt, 1)), Vector3(w.x, hgt / 2.0 - 0.4, w.y)), col])
			if c == "L":
				lamp_spots.append(w)
			if c == "d":
				dark_spots.append(w)
			if c == "b":
				bricks.append(w)
	# chunked 6x6 so each chunk sees only its nearby lanterns (the web renderer lights a mesh with at most 8)
	var chunks := {}
	for bl in blocks:
		var o: Vector3 = bl[0].origin
		var key := Vector2i(int(o.x - VILLAGE_X) / 6, int(o.z) / 6)
		if not chunks.has(key):
			chunks[key] = []
		chunks[key].append(bl)
	var cm := StandardMaterial3D.new()
	cm.vertex_color_use_as_albedo = true
	cm.roughness = 0.9
	for key in chunks:
		var list: Array = chunks[key]
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
		m.add_child(mmi)
	# houses: one per 3x2 block of H, door facing south
	var seen := {}
	for z in H:
		for x in W:
			if grid[z][x] == "H" and not seen.has(Vector2i(x, z)):
				for dz in 2:
					for dx in 3:
						seen[Vector2i(x + dx, z + dz)] = true
				house(m, Vector3(VILLAGE_X + x + 1, 0, z + 0.5))
				doors.append(Vector2(VILLAGE_X + x + 0.4, z + 1.9)) # just in front of the door
	build_market(m)
	build_inn(m)
	build_pond(m)
	var post_mat: Material = m.mat_color(Color("#3b2a1e"))
	var glass: Material = m.glow_mat(Color("#ffc46a"), 4.0)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	glass.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	for w in lamp_spots:
		m.lantern(w.x - 0.3, w.y, post_mat, glass)
	for w in dark_spots:
		m.lantern(w.x - 0.3, w.y, post_mat, glass)
		var l: OmniLight3D = m.lanterns[m.lanterns.size() - 1]
		var g: MeshInstance3D = l.get_meta("glass")
		g.set_meta("lit_mat", g.material_override)
		g.material_override = m.mat_color(Color("#3a3428"))
		l.set_meta("dark", true)
		var brick: Vector2 = w + Vector2(0, -1)
		for b in bricks:
			if b.distance_to(w) < 1.5:
				brick = b
		dark.append({"pos": w, "light": l, "glass": g, "lit": false, "brick": brick})
	for b in bricks: # a little pile of toy bricks waiting to wake
		for k in 4:
			var bb: MeshInstance3D = m.box(Vector3(0.3, 0.2, 0.2), m.mat_color(Color("#b4231e") if k % 2 == 0 else Color("#2f5fb8")))
			bb.position = Vector3(b.x + m.rnd(-0.3, 0.3), 0.1 + (k / 2) * 0.2, b.y + m.rnd(-0.3, 0.3))
			m.add_child(bb)
	for f in FOLK:
		var w := Vector2(VILLAGE_X + f.at.x, f.at.y)
		folk_pos[f.id] = w
		# GPT pixel sprite, two idle frames side by side (art/folk/<id>.png)
		var spr := Sprite3D.new()
		spr.texture = load("res://art/folk/%s.png" % f.id)
		spr.hframes = 2
		spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		spr.scale = Vector3(1, 1.0 / cos(0.78), 1)
		spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		spr.shaded = false
		spr.pixel_size = 1.75 / 170.0
		spr.offset = Vector2(0, 85)
		spr.position = Vector3(w.x, 0, w.y)
		m.add_child(spr)
		folk_node[f.id] = spr
		var tw := spr.create_tween().set_loops() # blink / idle beat every few seconds
		tw.tween_interval(2.4 + m.rnd(0, 1.2))
		tw.tween_callback(func(): spr.frame = 1)
		tw.tween_interval(0.35)
		tw.tween_callback(func(): spr.frame = 0)
		m.rocks.append({"x": w.x, "z": w.y, "r": 0.45})
	simji_node = simji(m)
	simji_node.position = Vector3(marks.M.x, 0, marks.M.y)
	m.add_child(simji_node)
	var spr: Sprite3D = simji_node.get_child(0)
	var tw := spr.create_tween().set_loops() # he blinks now and then
	tw.tween_interval(3.0)
	tw.tween_callback(func(): spr.frame = 1)
	tw.tween_interval(0.35)
	tw.tween_callback(func(): spr.frame = 0)
	m.rocks.append({"x": marks.M.x, "z": marks.M.y, "r": 0.5})

# Kongal's friend: a little green brick goblin with the red scarf she knitted (errand 2)
const KID_AT := Vector2i(6, 21)
const KID_GUARDS := [Vector2i(4, 20), Vector2i(8, 20), Vector2i(7, 22)]

func kid_goblin(m: Node) -> Node3D:
	var g := Node3D.new()
	var spr := Sprite3D.new() # GPT pixel sprite: frame 0 standing, frame 1 trotting
	spr.texture = load("res://art/folk/kid.png")
	spr.hframes = 2
	spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	spr.scale = Vector3(1, 1.0 / cos(0.78), 1)
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	spr.shaded = false
	spr.pixel_size = 1.0 / 110.0
	spr.offset = Vector2(0, 55)
	g.add_child(spr)
	g.set_meta("spr", spr)
	# it carries a little firefly jar, so it can be found in the dark south field
	var glow := OmniLight3D.new()
	glow.light_color = Color("#d8ffb0")
	glow.light_energy = 1.2
	glow.omni_range = 2.8
	glow.position = Vector3(0, 0.6, 0.4)
	g.add_child(glow)
	m.add_child(g)
	return g

# the village houses: the stilt house the user picked from five drafts (2026-10-23, draft 5)
func house(m: Node, at: Vector3) -> void:
	house_draft(m, at, 4, false)

# the tall old lamplighter: GPT pixel sprite (two idle frames) and the glow of his own lamp
func simji(m: Node) -> Node3D:
	var g := Node3D.new()
	var spr := Sprite3D.new()
	spr.texture = load("res://art/folk/simji.png")
	spr.hframes = 2
	spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	spr.scale = Vector3(1, 1.0 / cos(0.78), 1)
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	spr.shaded = false
	spr.pixel_size = 2.1 / 200.0
	spr.offset = Vector2(0, 100)
	g.add_child(spr)
	var glow := OmniLight3D.new() # his own lamp lights him up at night
	glow.light_color = Color("#ffd8a0")
	glow.light_energy = 1.4
	glow.omni_range = 2.5
	glow.position = Vector3(-0.3, 1.9, 0.4)
	g.add_child(glow)
	return g

func map_tex(width: int) -> ImageTexture:
	var img := Image.create(width, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for z in H:
		for x in W:
			var c: String = grid[z][x]
			var col := Color("#16302e")
			match c:
				"#": col = Color(0, 0, 0, 0)
				"=": col = Color("#2c4a48")
				"o": col = Color("#3a5a6a")
				"H", "I", "T": col = Color("#c8962a")
				"L", "d": col = Color("#ffd060")
				":", "1", "2", "3": col = Color("#3a4a50")
				"~", "B": col = Color("#2c5a8a")
				"P", "f": col = Color("#6a5034")
				"Q", "N": col = Color("#ffd060")
			img.set_pixel(VILLAGE_X + x, z, col)
	return ImageTexture.create_from_image(img)

func lit_count() -> int:
	return dark.filter(func(d): return d.lit).size()

# three honesty-box stalls with striped awnings, each with a little sign; nobody minds them, the coins go in the box
func build_market(m: Node) -> void:
	var wood: Material = m.mat_color(Color("#7a5232"))
	var cloths := [Color("#c84a3a"), Color("#3a7ac8"), Color("#3aa86a")]
	var goods := [Color("#e84a4a"), Color("#bfe6ff"), Color("#c8a46a")]
	for k in 3:
		var key := str(k + 1)
		var at: Vector2 = marks[key]
		var g := Node3D.new()
		g.position = Vector3(at.x + 0.5, 0, at.y - 1.0)
		m.add_child(g)
		for side in [-0.85, 0.85]:
			var post: MeshInstance3D = m.box(Vector3(0.1, 1.6, 0.1), wood)
			post.position = Vector3(side, 0.8, 0.3)
			g.add_child(post)
		var counter: MeshInstance3D = m.box(Vector3(1.9, 0.7, 0.6), wood)
		counter.position = Vector3(0, 0.35, 0.1)
		g.add_child(counter)
		for st in 4: # striped awning
			var cloth: MeshInstance3D = m.box(Vector3(0.48, 0.06, 0.9), m.mat_color(cloths[k] if st % 2 == 0 else Color("#f2ead8")))
			cloth.position = Vector3(-0.72 + st * 0.48, 1.62, 0.2)
			cloth.rotation.x = 0.25
			g.add_child(cloth)
		for n in 5: # goods on the counter
			var item: MeshInstance3D = m.box(Vector3(0.18, 0.16, 0.18), m.mat_color(goods[k].darkened(0.1 * (n % 2))))
			item.position = Vector3(-0.7 + n * 0.35, 0.78, 0.1 + m.rnd(-0.1, 0.1))
			g.add_child(item)
		var box: MeshInstance3D = m.box(Vector3(0.26, 0.22, 0.2), m.mat_color(Color("#4a3a2a")))
		box.position = Vector3(0.7, 0.81, 0.36)
		g.add_child(box)
		var sign := Label3D.new()
		sign.text = tr(stall_names[key])
		sign.font = m.ui_font
		sign.font_size = 34
		sign.pixel_size = 0.006
		sign.modulate = Color("#3a2414")
		sign.outline_size = 8
		sign.outline_modulate = Color("#f2ead8")
		sign.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		sign.position = Vector3(0, 2.0, 0.3)
		g.add_child(sign)
	# the target post in the fenced yard: a pole with a round red and white board
	var q: Vector2 = marks.Q
	var tg := Node3D.new()
	tg.position = Vector3(q.x, 0, q.y)
	m.add_child(tg)
	var pole: MeshInstance3D = m.box(Vector3(0.14, 1.4, 0.14), wood)
	pole.position = Vector3(0, 0.7, 0)
	tg.add_child(pole)
	for r in 3:
		var ring: MeshInstance3D = m.box(Vector3(0.7 - r * 0.2, 0.7 - r * 0.2, 0.06), m.mat_color(Color("#c8322a") if r % 2 == 0 else Color("#f2ead8")))
		ring.position = Vector3(0, 1.3, 0.1 + r * 0.02)
		tg.add_child(ring)
	m.rocks.append({"x": q.x, "z": q.y, "r": 0.3})

# the inn: a long two-storey house with a hanging sign
func build_inn(m: Node) -> void:
	var n: Vector2 = marks.N
	var g := Node3D.new()
	g.position = Vector3(n.x, 0, n.y - 2.0)
	m.add_child(g)
	var body: MeshInstance3D = m.box(Vector3(4.8, 2.4, 2.8), m.mat_color(Color("#e8dcc4")))
	body.position = Vector3(0, 1.2, 0)
	g.add_child(body)
	for side in [-1.0, 1.0]:
		var r: MeshInstance3D = m.box(Vector3(5.2, 0.14, 1.9), m.mat_color(Color("#3a5a7a")))
		r.position = Vector3(0, 2.8, side * 0.7)
		r.rotation.x = side * 0.6
		g.add_child(r)
	var door: MeshInstance3D = m.box(Vector3(0.7, 1.1, 0.06), m.mat_color(Color("#5a3a26")))
	door.position = Vector3(0, 0.55, 1.42)
	g.add_child(door)
	for wx in [-1.6, 1.6]:
		for wy in [0.9, 1.8]:
			var win: MeshInstance3D = m.box(Vector3(0.6, 0.45, 0.06), m.glow_mat(Color("#ffc46a"), 1.5))
			win.position = Vector3(wx, wy, 1.42)
			g.add_child(win)
	var sign := Label3D.new()
	sign.text = tr("여관 · 하룻밤 금화 10")
	sign.font = m.ui_font
	sign.font_size = 34
	sign.pixel_size = 0.006
	sign.modulate = Color("#3a2414")
	sign.outline_size = 8
	sign.outline_modulate = Color("#f2ead8")
	sign.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sign.position = Vector3(0, 3.4, 1.4)
	g.add_child(sign)

# the pond: a water face, posts under the pier, and three glass bottles drifting with letters inside
func build_pond(m: Node) -> void:
	var wet: Material = m.glow_mat(Color("#2f78b8"), 0.6)
	wet.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	wet.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	var face: MeshInstance3D = m.box(Vector3(20.0, 0.02, 9.0), wet)
	face.position = Vector3(VILLAGE_X + 35.5, -0.34, 29)
	m.add_child(face)
	var wood: Material = m.mat_color(Color("#5a3e26"))
	for x in range(26, 37, 2):
		for dz in [-0.45, 0.45]:
			var post: MeshInstance3D = m.box(Vector3(0.12, 0.7, 0.12), wood)
			post.position = Vector3(VILLAGE_X + x, -0.15, 29 + dz)
			m.add_child(post)
	var glass: Material = m.glow_mat(Color("#bfe6c8"), 1.0)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	glass.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	for b in bottles:
		var g := Node3D.new()
		var body: MeshInstance3D = m.box(Vector3(0.18, 0.32, 0.18), glass)
		body.position = Vector3(0, 0.1, 0)
		g.add_child(body)
		var cork: MeshInstance3D = m.box(Vector3(0.1, 0.1, 0.1), m.mat_color(Color("#8a6a44")))
		cork.position = Vector3(0, 0.31, 0)
		g.add_child(cork)
		g.rotation.z = 0.9
		g.position = Vector3(b.pos.x, -0.3, b.pos.y)
		m.add_child(g)
		b.node = g

func bottles_got() -> int:
	return bottles.filter(func(b): return b.got).size()

# ---- five house drafts for the user to pick from (scene "house_designs"); door faces south (+z) like house()
const HOUSE_DRAFTS := ["동화 초가집", "레고 벽돌집", "등불 목조집", "버섯 집", "물가 기둥집"]

func house_draft(m: Node, at: Vector3, k: int, labelled := true) -> void:
	var g := Node3D.new()
	g.position = at
	m.add_child(g)
	var add := func(size: Vector3, pos: Vector3, col: Color, rot := Vector3.ZERO, glow := false) -> MeshInstance3D:
		var b: MeshInstance3D = m.box(size, m.glow_mat(col, 1.5) if glow else m.mat_color(col))
		b.position = pos
		b.rotation = rot
		g.add_child(b)
		return b
	match k:
		0: # 동화 초가집: cream walls, a thick stepped straw roof, a round window and a flower box
			add.call(Vector3(2.6, 1.3, 1.8), Vector3(0, 0.65, 0), Color("#f2e6c8"))
			for s in 4:
				add.call(Vector3(3.2 - s * 0.6, 0.3, 2.3 - s * 0.45), Vector3(0, 1.45 + s * 0.28, 0), Color("#d8b25a").darkened(s * 0.05))
			add.call(Vector3(0.55, 0.9, 0.06), Vector3(-0.6, 0.45, 0.92), Color("#7a4a2a"))
			add.call(Vector3(0.45, 0.45, 0.06), Vector3(0.6, 0.85, 0.92), Color("#ffc46a"), Vector3(0, 0, PI / 4), true)
			add.call(Vector3(0.7, 0.16, 0.2), Vector3(0.6, 0.5, 1.0), Color("#8a5a32"))
			for f in 4:
				add.call(Vector3(0.12, 0.12, 0.12), Vector3(0.35 + f * 0.17, 0.64, 1.0), [Color("#e84a6a"), Color("#ffd23a"), Color("#e84a6a"), Color("#9a6ae8")][f])
		1: # 레고 벽돌집: walls stacked from studded toy bricks in four colours, a red studded roof
			var cols := [Color("#c8322a"), Color("#2f5fb8"), Color("#e8c23a"), Color("#3a9a4a")]
			for row in 4:
				for c in 4:
					add.call(Vector3(0.64, 0.32, 1.8), Vector3(-0.96 + c * 0.64 + (0.16 if row % 2 else 0.0), 0.16 + row * 0.32, 0), cols[(row + c) % 4])
			add.call(Vector3(2.9, 0.3, 2.1), Vector3(0, 1.43, 0), Color("#b4231e"))
			for sx in 4:
				for sz in 3:
					add.call(Vector3(0.18, 0.12, 0.18), Vector3(-1.05 + sx * 0.7, 1.64, -0.6 + sz * 0.6), Color("#d8342c"))
			add.call(Vector3(0.55, 0.9, 0.06), Vector3(-0.5, 0.45, 0.92), Color("#f2ead8"))
			add.call(Vector3(0.5, 0.4, 0.06), Vector3(0.6, 0.85, 0.92), Color("#bfe6ff"), Vector3.ZERO, true)
		2: # 등불 목조집: white plaster in dark timber frames, a slate roof, a lantern hung over the door
			add.call(Vector3(2.6, 1.5, 1.8), Vector3(0, 0.75, 0), Color("#efe8da"))
			for x in [-1.25, -0.4, 0.4, 1.25]:
				add.call(Vector3(0.12, 1.5, 0.05), Vector3(x, 0.75, 0.92), Color("#3a2618"))
			add.call(Vector3(2.62, 0.12, 0.05), Vector3(0, 0.8, 0.93), Color("#3a2618"))
			add.call(Vector3(1.2, 0.1, 0.05), Vector3(0.82, 0.8, 0.94), Color("#3a2618"), Vector3(0, 0, 0.55))
			for side in [-1.0, 1.0]:
				add.call(Vector3(3.0, 0.12, 1.3), Vector3(0, 1.85, side * 0.5), Color("#4a5468"), Vector3(side * 0.7, 0, 0))
			add.call(Vector3(0.55, 0.95, 0.06), Vector3(-0.15, 0.47, 0.95), Color("#5a3a26"))
			add.call(Vector3(0.22, 0.28, 0.22), Vector3(-0.15, 1.15, 1.15), Color("#ffc46a"), Vector3.ZERO, true)
			add.call(Vector3(0.5, 0.4, 0.06), Vector3(0.85, 1.05, 0.95), Color("#ffc46a"), Vector3.ZERO, true)
		3: # 버섯 집: a fat pale stem with a door and a big red cap with white spots
			add.call(Vector3(1.8, 1.4, 1.6), Vector3(0, 0.7, 0), Color("#efe2c8"))
			add.call(Vector3(3.0, 0.5, 2.6), Vector3(0, 1.6, 0), Color("#c83a32"))
			add.call(Vector3(2.2, 0.4, 1.9), Vector3(0, 2.0, 0), Color("#c83a32"))
			add.call(Vector3(1.2, 0.3, 1.0), Vector3(0, 2.3, 0), Color("#c83a32"))
			for sp in [Vector3(-0.9, 1.87, 0.9), Vector3(0.7, 1.87, 1.0), Vector3(0.2, 2.21, 0.75), Vector3(-0.5, 2.21, -0.3), Vector3(0.9, 1.87, -0.6)]:
				add.call(Vector3(0.28, 0.06, 0.28), sp, Color("#f8f4ea"))
			add.call(Vector3(0.5, 0.85, 0.06), Vector3(-0.3, 0.42, 0.82), Color("#6a4a2a"))
			add.call(Vector3(0.36, 0.36, 0.06), Vector3(0.45, 0.85, 0.82), Color("#ffc46a"), Vector3.ZERO, true)
		4: # 물가 기둥집: a blue-shuttered house on stilts with a porch, steps and a chimney under a tall roof
			for x in [-1.1, 1.1]:
				for z in [-0.7, 0.7]:
					add.call(Vector3(0.16, 0.6, 0.16), Vector3(x, 0.3, z), Color("#5a3e26"))
			add.call(Vector3(2.8, 0.12, 2.4), Vector3(0, 0.62, 0.2), Color("#9a7448"))
			add.call(Vector3(2.4, 1.2, 1.6), Vector3(0, 1.28, -0.1), Color("#e8e0cc"))
			for side in [-1.0, 1.0]:
				add.call(Vector3(2.8, 0.12, 1.25), Vector3(0, 2.25, -0.1 + side * 0.45), Color("#2f5a7a"), Vector3(side * 0.85, 0, 0))
			add.call(Vector3(0.3, 0.8, 0.3), Vector3(0.8, 2.5, -0.4), Color("#7a5a4a"))
			add.call(Vector3(0.5, 0.85, 0.06), Vector3(-0.5, 1.1, 0.72), Color("#5a3a26"))
			for sx in [0.35, 0.95]:
				add.call(Vector3(0.18, 0.45, 0.06), Vector3(sx, 1.35, 0.72), Color("#3a6ac8"))
			add.call(Vector3(0.4, 0.45, 0.06), Vector3(0.65, 1.35, 0.71), Color("#ffc46a"), Vector3.ZERO, true)
			for st in 3:
				add.call(Vector3(0.6, 0.08, 0.25), Vector3(-0.5, 0.48 - st * 0.18, 1.5 + st * 0.25), Color("#9a7448"))
	if not labelled:
		return
	var t := Label3D.new()
	t.text = "%d  %s" % [k + 1, tr(HOUSE_DRAFTS[k])]
	t.font = m.ui_font
	t.font_size = 40
	t.pixel_size = 0.008
	t.modulate = Color("#3a2414")
	t.outline_size = 10
	t.outline_modulate = Color("#f2ead8")
	t.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	t.no_depth_test = true
	t.position = Vector3(0, 3.4, 0)
	g.add_child(t)
