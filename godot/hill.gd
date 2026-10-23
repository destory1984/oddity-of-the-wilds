# 바람 언덕 (story step 10.5): a 34x24 area at x >= HILL_X, east of the hardened forest.
# Three windmills (M) have stopped and bricked over; winding each with the crown makes it turn.
# When all three turn, the wind lifts a plank bridge over the gorge (_) to the brick hawk's ledge (B).
# Below the south fence (rows 23 - 39, DESIGN.md "참새 방앗간"): the broken wall G opens onto a windless hollow with
# the old mill's big windmill Q. Running past four pinwheels (v) from the post P calls the wind down; the mill
# fills its channel (~), a big guardian rises at its mouth K, and over the water lie the flour boat b, the
# landing bell k and the miller's chest c.
extends RefCounted

const HILL_X := 310
const W := 34
const H := 40
const MILL_Z := 24 # first row of the mill hollow
const BRIDGE_ROWS := [11, 12, 13]
const ROWS := """##################################
#...................__.......U...#
#..........r......L.__.........w.#
#...r.........a.....__..r........#
#................r..__...........#
#.....M.............__...........#
#..........s........__.........r.#
#.................a.__.....R.....#
#...L........r......__...........#
#...............s...__........L..#
#........g..........__...........#
#...................__...........#
S========...L..M....__.L...B.....X
#...................__...........#
#............g......__...........#
#.........r.........__........L..#
#...L...............__.......w...#
#...................__...........#
#.....M.....s.......__...r.......#
#................r..__...........#
#..r...........a....__........r..#
#...........r.....L.__..w........#
#...................__...........#
###########################G######
#########################.....####
#.........###############..a..####
#..v....L.###############.s...####
#.........r##############...w.####
#.....................r.v.......j#
#....r.....Q..................w..#
#....................r....r......#
#.....P.........K..........L...v.#
#..............r.....v...........#
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
#.......b...k....................#
#................................#
#....c.....................L.....#
#................................#
##################################"""

var grid: Array = []
var marks := {}          # S entry, X exit east, B the hawk's perch, U the updraft up to the cloud mound -> world Vector2
var mills: Array = []    # [{"pos": Vector2, "blades": Node3D, "turning": bool}]
var foes: Array = []     # [world Vector2, kind] with kind "s" shield goblin, "a" archer, "g" goblin, "w" wolf
var bridge: Node3D
var bridged := false
var south_foes: Array = []  # [world Vector2, kind] below the fence: woken when the wall opens
var south_marks := {}    # G wall, Q big windmill, P wind post, K the channel mouth, b boat, k bell, c chest
var wheels: Array = []   # world Vector2 of the four pinwheels that call the wind down
var mill4 := {}          # the mill's big windmill {"pos", "blades", "turning"}; not one of the three in mills
var gate_open := false
var filled := false
var gate_node: Node3D
var water: MeshInstance3D
var sparrows: Node3D
var chest_node: Node3D

func _init() -> void:
	for line in ROWS.split("\n"):
		grid.append(line)

func char_at(x: float, z: float) -> String:
	var tx := int(round(x)) - HILL_X
	var tz := int(round(z))
	if tx < 0 or tz < 0 or tx >= W or tz >= H:
		return "#"
	return grid[tz][tx]

# the fence, rocks, windmills and the gorge block; the gorge opens where the bridge lies once it is up
func blocked(x: float, z: float) -> bool:
	var c := char_at(x, z)
	if c == "_":
		return not (bridged and int(round(z)) in BRIDGE_ROWS)
	if c == "G":
		return not gate_open
	return c == "#" or c == "r" or c == "M" or c in "Qbkc~" # the channel: only the water skip crosses it, once filled

func build(m: Node) -> void:
	var blocks: Array = []
	var lamp_spots: Array = []
	for z in H:
		for x in W:
			var c: String = grid[z][x]
			var w := Vector2(HILL_X + x, z)
			if c in "SXBUR": # R: the moon trial stones (moved here from the village, 2026-10-23)
				marks[c] = w
			if c in "sagwj":
				(south_foes if z >= MILL_Z else foes).append([w, c])
			if c in "GQPKbkc":
				south_marks[c] = w
			if c == "v":
				wheels.append(w)
			if c == "~":
				blocks.append([Transform3D(Basis().scaled(Vector3(1, 0.4, 1)), Vector3(w.x, -1.4, w.y)), Color("#2a3440")]) # the dry channel bed
				continue
			if c == "L":
				lamp_spots.append(w)
			if c == "_":
				# the gorge: a far, dark floor with a little mist
				blocks.append([Transform3D(Basis().scaled(Vector3(1, 0.4, 1)), Vector3(w.x, -3.2, w.y)), Color("#2a3440")])
				continue
			var col := Color("#8ab858") # wind-combed hill grass
			var hgt := 0.4
			match c:
				"=": col = Color("#c2b48a")
				"#": col = Color("#6a7a50")
				"r": col = Color("#8a8a8a")
			if c == "#":
				hgt = 0.9
			if c == "r":
				hgt = m.rnd(0.9, 1.4)
			if (x + z * 3) % 7 == 0 and c == ".":
				col = Color("#9cc868")
			col = col.lightened(m.rnd(0, 0.07))
			blocks.append([Transform3D(Basis().scaled(Vector3(1, hgt, 1)), Vector3(w.x, hgt / 2.0 - 0.4, w.y)), col])
	m.add_chunks(blocks, HILL_X)
	var post_mat: Material = m.mat_color(Color("#3b2a1e"))
	var glass: Material = m.glow_mat(Color("#ffc46a"), 4.0)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	glass.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	for w in lamp_spots:
		m.lantern(w.x - 0.3, w.y, post_mat, glass)
	for z in H:
		for x in W:
			if grid[z][x] == "M":
				var p := Vector2(HILL_X + x, z)
				mills.append({"pos": p, "blades": windmill(m, p), "turning": false})
	bridge = Node3D.new()
	var plank: Material = m.mat_color(Color("#a07a4a"))
	for row in BRIDGE_ROWS:
		for k in 5:
			var b: MeshInstance3D = m.box(Vector3(0.36, 0.1, 0.9), plank)
			b.position = Vector3(HILL_X + 19.6 + k * 0.45, -0.02, row)
			bridge.add_child(b)
	for side in [10.5, 13.5]: # rope rails
		var rope: MeshInstance3D = m.box(Vector3(2.4, 0.05, 0.05), m.mat_color(Color("#d8c8a0")))
		rope.position = Vector3(HILL_X + 20.5, 0.5, side)
		bridge.add_child(rope)
	bridge.visible = false
	m.add_child(bridge)
	build_mill(m)

# the hollow below: the broken wall, the big windmill, the channel's hidden water, the boat, the bell, the chest,
# and the sparrows waiting on the wall
func build_mill(m: Node) -> void:
	gate_node = m.forest.brick_wall(m, south_marks.G)
	var q: Vector2 = south_marks.Q
	mill4 = {"pos": q, "blades": windmill(m, q), "turning": false}
	(mill4.blades as Node3D).get_parent().scale = Vector3.ONE * 1.3
	var wet: Material = m.glow_mat(Color("#2f78b8"), 0.6)
	wet.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	wet.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	water = m.box(Vector3(W - 2.0, 0.04, 2.0), wet)
	water.position = Vector3(HILL_X + W / 2.0 - 0.5, -0.25, 33.5)
	water.visible = false
	m.add_child(water)
	var boat := Node3D.new()
	for part in [[Vector3(1.6, 0.35, 0.7), Vector3(0, 0.1, 0)], [Vector3(0.25, 0.5, 0.7), Vector3(0.75, 0.25, 0)], [Vector3(0.6, 0.3, 0.4), Vector3(-0.2, 0.4, 0)]]:
		var bb: MeshInstance3D = m.box(part[0], m.mat_color(Color("#7a5a3a") if part[1].y < 0.35 else Color("#e8e0c8")))
		bb.position = part[1]
		boat.add_child(bb)
	boat.position = Vector3(south_marks.b.x, 0, south_marks.b.y)
	boat.rotation.y = 0.2
	m.add_child(boat)
	var wood: Material = m.mat_color(Color("#3b2a1e"))
	var pole: MeshInstance3D = m.box(Vector3(0.14, 1.7, 0.14), wood)
	pole.position = Vector3(south_marks.k.x, 0.85, south_marks.k.y)
	m.add_child(pole)
	var bell: MeshInstance3D = m.box(Vector3(0.3, 0.3, 0.3), m.mat_color(Color("#e8c84a")))
	bell.position = Vector3(south_marks.k.x + 0.25, 1.45, south_marks.k.y)
	m.add_child(bell)
	chest_node = Node3D.new()
	for part in [[Vector3(0.8, 0.45, 0.55), Vector3(0, 0.22, 0), m.mat_color(Color("#8a6a4a"))], [Vector3(0.84, 0.1, 0.59), Vector3(0, 0.5, 0), m.glow_mat(Color("#e8d27a"), 1.2)]]:
		var cb: MeshInstance3D = m.box(part[0], part[2])
		cb.position = part[1]
		chest_node.add_child(cb)
	chest_node.position = Vector3(south_marks.c.x, 0, south_marks.c.y)
	m.add_child(chest_node)
	sparrows = Node3D.new()
	var brown: Material = m.mat_color(Color("#8a6a4a"))
	for k in 6:
		var sp: MeshInstance3D = m.box(Vector3(0.14, 0.12, 0.2), brown)
		sp.position = Vector3(-0.45 + k * 0.18, 1.52 + (k % 2) * 0.03, 0.0)
		sparrows.add_child(sp)
	sparrows.position = Vector3(south_marks.G.x, 0, south_marks.G.y)
	sparrows.visible = false
	m.add_child(sparrows)

func open_wall() -> void:
	gate_open = true
	gate_node.visible = false
	sparrows.visible = false

func wind_mill4(m: Node) -> void:
	wind_mill(mill4, m)

func fill() -> void:
	filled = true
	water.visible = true

func chest_look() -> void:
	for b in chest_node.get_children():
		b.transparency = 0.45

# a stone windmill; its blades are grey brick until wound, then white canvas that turns
func windmill(m: Node, at: Vector2) -> Node3D:
	var g := Node3D.new()
	g.position = Vector3(at.x, 0, at.y)
	m.add_child(g)
	var stone: Material = m.mat_color(Color("#d8d0c0"))
	for k in 3:
		var b: MeshInstance3D = m.box(Vector3(1.3 - k * 0.2, 1.0, 1.3 - k * 0.2), stone)
		b.position = Vector3(0, 0.5 + k * 1.0, 0)
		g.add_child(b)
	var cap: MeshInstance3D = m.box(Vector3(1.1, 0.6, 1.2), m.mat_color(Color("#8a3a2a")))
	cap.position = Vector3(0, 3.2, 0)
	g.add_child(cap)
	var door: MeshInstance3D = m.box(Vector3(0.4, 0.7, 0.05), m.mat_color(Color("#5a3a26")))
	door.position = Vector3(0, 0.35, 0.66)
	g.add_child(door)
	var blades := Node3D.new()
	blades.position = Vector3(0, 3.0, 0.7)
	g.add_child(blades)
	var brick: Material = m.mat_color(Color("#8a8a90"))
	for k in 4:
		var arm := Node3D.new()
		arm.rotation.z = TAU * k / 4.0
		blades.add_child(arm)
		var sail: MeshInstance3D = m.box(Vector3(0.45, 1.5, 0.06), brick)
		sail.position = Vector3(0, 0.95, 0)
		arm.add_child(sail)
	m.rocks.append({"x": at.x, "z": at.y, "r": 0.85})
	return blades

func wind_mill(mill: Dictionary, m: Node) -> void:
	mill.turning = true
	var canvas: Material = m.mat_color(Color("#f2ead8"))
	for arm in mill.blades.get_children():
		(arm.get_child(0) as MeshInstance3D).material_override = canvas

func turning_count() -> int:
	return mills.filter(func(mm): return mm.turning).size()

func raise_bridge() -> void:
	bridged = true
	bridge.visible = true

func map_tex(width: int) -> ImageTexture:
	var img := Image.create(width, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for z in H:
		for x in W:
			var c: String = grid[z][x]
			var col := Color("#1e3420")
			match c:
				"#", "r": col = Color(0, 0, 0, 0)
				"_": col = Color("#a07a4a") if bridged and z in BRIDGE_ROWS else Color(0, 0, 0, 0)
				"=": col = Color("#4a5a3a")
				"M", "Q": col = Color("#f2ead8")
				"~": col = Color("#2f78b8") if filled else Color("#1a1826")
				"G": col = Color("#1e3420") if gate_open else Color("#c8322a")
				"b", "k", "c": col = Color("#bcd6ff")
				"P": col = Color("#7ac8e8")
				"L": col = Color("#ffd060")
				"B": col = Color("#c8322a")
			img.set_pixel(HILL_X + x, z, col)
	return ImageTexture.create_from_image(img)
