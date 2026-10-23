# 바람 언덕 (story step 10.5): a 34x24 area at x >= HILL_X, east of the hardened forest.
# Three windmills (M) have stopped and bricked over; winding each with the crown makes it turn.
# When all three turn, the wind lifts a plank bridge over the gorge (_) to the brick hawk's ledge (B).
extends RefCounted

const HILL_X := 310
const W := 34
const H := 24
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
##################################"""

var grid: Array = []
var marks := {}          # S entry, X exit east, B the hawk's perch, U the updraft up to the cloud mound -> world Vector2
var mills: Array = []    # [{"pos": Vector2, "blades": Node3D, "turning": bool}]
var foes: Array = []     # [world Vector2, kind] with kind "s" shield goblin, "a" archer, "g" goblin, "w" wolf
var bridge: Node3D
var bridged := false

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
	return c == "#" or c == "r" or c == "M"

func build(m: Node) -> void:
	var blocks: Array = []
	var lamp_spots: Array = []
	for z in H:
		for x in W:
			var c: String = grid[z][x]
			var w := Vector2(HILL_X + x, z)
			if c in "SXBUR": # R: the moon trial stones (moved here from the village, 2026-10-23)
				marks[c] = w
			if c in "sagw":
				foes.append([w, c])
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
				"M": col = Color("#f2ead8")
				"L": col = Color("#ffd060")
				"B": col = Color("#c8322a")
			img.set_pixel(HILL_X + x, z, col)
	return ImageTexture.create_from_image(img)
