# 등불 마을 (story step 8): a separate 32x24 area at x >= VILLAGE_X, built from blocks like the cave.
# Holds the map, its build, the lamplighter Simji, the three dark lanterns and the first errand.
extends RefCounted

const VILLAGE_X := 140
const W := 32
const H := 24
const ROWS := """################################
#..HHH.......HHH.......HHH.....#
#..HHH...L...HHH...L...HHH.....#
#....=.........=.........=.....#
#....=.........=.........=.....#
#....===========.........=.....#
#..............=.........=.....#
#.........L.oooooooo.L...=.....#
#...........oooooooo.....=.....#
#L..........ooooMooo.....=.....#
G=S=========oooooooo===========F
#L..........oooooooo.....=.....#
#.........L.oooooooo.L...=.....#
#..............=.........=.....#
#..HHH.........=.......b.=.b...#
#..HHH...L.....=.......d.=.d...#
#....=.........=.........=.....#
#....===========.........=.....#
#..........HHH...........=.....#
#..........HHH.......b...=.....#
#....................d...=.....#
#..............................#
#..............................#
################K###############"""

var grid: Array = []
var marks := {}          # S, G, M -> world Vector2
var dark: Array = []     # [{"pos": Vector2, "light": OmniLight3D, "glass": MeshInstance3D, "lit": bool, "brick": Vector2}]
var simji_node: Node3D
# villagers you can talk to with E: id and tile in the village grid
const FOLK := [
	{"id": "doran", "at": Vector2i(14, 3)},
	{"id": "kongal", "at": Vector2i(10, 15)},
	{"id": "mulgyeol", "at": Vector2i(28, 21)},
]
var folk_pos := {}
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
	return c == "#" or c == "H"

func build(m: Node) -> void:
	var blocks: Array = [] # [Transform3D, Color]
	var lamp_spots: Array = []
	var dark_spots: Array = []
	var bricks: Array = []
	for z in H:
		for x in W:
			var c: String = grid[z][x]
			var w := Vector2(VILLAGE_X + x, z)
			if c in "SGMFK":
				marks[c] = w
			var col := Color("#5e8f30")
			match c:
				"=": col = Color("#b8a888")
				"o": col = Color("#9a9a8e")
				"#": col = Color("#6a4a2c")
				"H": col = Color("#4a6a2c")
			col = col.lightened(m.rnd(0, 0.08))
			var hgt := 0.4
			if c == "#":
				hgt = 0.9 # low fence blocks
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

func house(m: Node, at: Vector3) -> void:
	var g := Node3D.new()
	g.position = at
	m.add_child(g)
	var wall: Material = m.mat_color(Color("#e4dccc"))
	var roof: Material = m.mat_color(Color("#7a3a2a"))
	var b: MeshInstance3D = m.box(Vector3(2.8, 1.4, 1.8), wall)
	b.position = Vector3(0, 0.7, 0)
	g.add_child(b)
	for side in [-1.0, 1.0]:
		var r: MeshInstance3D = m.box(Vector3(3.1, 0.12, 1.25), roof)
		r.position = Vector3(0, 1.75, side * 0.45)
		r.rotation.x = side * 0.6
		g.add_child(r)
	var door: MeshInstance3D = m.box(Vector3(0.5, 0.9, 0.06), m.mat_color(Color("#5a3a26")))
	door.position = Vector3(-0.6, 0.45, 0.92)
	g.add_child(door)
	var win: MeshInstance3D = m.box(Vector3(0.6, 0.4, 0.06), m.glow_mat(Color("#ffc46a"), 1.5))
	win.position = Vector3(0.6, 0.85, 0.92)
	g.add_child(win)

# a tall old lamplighter built from blocks: grey coat, white beard, brass pole
func simji(m: Node) -> Node3D:
	var g := Node3D.new()
	var coat: Material = m.mat_color(Color("#2f3f7a"))
	for part in [[Vector3(0.45, 0.9, 0.35), Vector3(0, 0.45, 0), coat],
			[Vector3(0.36, 0.34, 0.34), Vector3(0, 1.08, 0), m.mat_color(Color("#f1c08f"))],
			[Vector3(0.3, 0.3, 0.1), Vector3(0, 0.92, 0.18), m.mat_color(Color("#f4f4f4"))],
			[Vector3(0.4, 0.12, 0.4), Vector3(0, 1.3, 0), m.mat_color(Color("#e8e8e8"))],
			[Vector3(0.06, 1.8, 0.06), Vector3(0.35, 0.9, 0), m.mat_color(Color("#c8962a"))]]:
		var b: MeshInstance3D = m.box(part[0], part[2])
		b.position = part[1]
		g.add_child(b)
	var lamp: MeshInstance3D = m.box(Vector3(0.16, 0.2, 0.16), m.glow_mat(Color("#ffc46a"), 3.0))
	lamp.position = Vector3(0.35, 1.85, 0)
	g.add_child(lamp)
	var glow := OmniLight3D.new() # his own lamp lights him up at night
	glow.light_color = Color("#ffd8a0")
	glow.light_energy = 1.4
	glow.omni_range = 2.5
	glow.position = Vector3(0.2, 1.6, 0.4)
	g.add_child(glow)
	g.scale = Vector3.ONE * 1.25
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
				"H": col = Color("#c8962a")
				"L", "d": col = Color("#ffd060")
			img.set_pixel(VILLAGE_X + x, z, col)
	return ImageTexture.create_from_image(img)

func lit_count() -> int:
	return dark.filter(func(d): return d.lit).size()
