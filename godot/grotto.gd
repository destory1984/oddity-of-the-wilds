# 물빛 동굴 (chapter 4 side area): a 30x20 grotto under Mulgyeol's island at x >= GROTTO_X, entered from G on the island.
# Three rooms joined by short runs of deep water (~) that only the water skip crosses. The brick crab (C) waits
# in the last room; beating it lets the moonkeeper chest (c) open with the water pearl. A side room holds a chest (p).
# Sora counts as "in the lake" while down here; the grotto is told apart by x.
extends RefCounted

const GROTTO_X := 350
const W := 30
const H := 20
const ROWS := """##############################
#........###.........##......#
#.S......###..a....g.##...p..#
#.....g..~~~.................#
#........~~~....L............#
#....L...~~~.........##..a...#
#........###......g..##....L.#
#........###.........##......#
############.........#########
###############...############
###############...############
###############~~~############
###############~~~############
###############~~~############
###........................###
###..L..................L..###
###............C........c..###
###.......a................###
###........................###
##############################"""

var grid: Array = []
var marks := {}          # S entry/exit, C crab, c pearl chest, p side chest -> world Vector2
var foes: Array = []     # [world Vector2, archer]
var chest: Node3D
var side_chest: Node3D

func _init() -> void:
	for line in ROWS.split("\n"):
		grid.append(line)

func char_at(x: float, z: float) -> String:
	var tx := int(round(x)) - GROTTO_X
	var tz := int(round(z))
	if tx < 0 or tz < 0 or tx >= W or tz >= H:
		return "#"
	return grid[tz][tx]

# rock, deep water and the two chests block; the water is crossed by skipping (main.skip_water)
func blocked(x: float, z: float) -> bool:
	var c := char_at(x, z)
	return c == "#" or c == "~" or c == "c" or c == "p"

func build(m: Node) -> void:
	var blocks: Array = []
	var lamp_spots: Array = []
	for z in H:
		for x in W:
			var c: String = grid[z][x]
			var w := Vector2(GROTTO_X + x, z)
			if c in "SCcp":
				marks[c] = w
			if c == "g" or c == "a":
				foes.append([w, c == "a"])
			if c == "L":
				lamp_spots.append(w)
			var col := Color("#4e5a66") # wet blue-grey stone
			var hgt := 0.4
			match c:
				"#":
					col = Color("#2a3038")
					hgt = 0.9
				"~":
					col = Color("#1f4f7a")
					hgt = 0.05
			col = col.lightened(m.rnd(0, 0.08))
			blocks.append([Transform3D(Basis().scaled(Vector3(1, hgt, 1)), Vector3(w.x, hgt / 2.0 - 0.4, w.y)), col])
			if c == "#" and m.rng.randf() < 0.12: # a bricked water wheel stuck in the wall here and there
				blocks.append([Transform3D(Basis().scaled(Vector3(0.9, 0.9, 0.2)), Vector3(w.x, 0.75, w.y + 0.45)), Color("#6a6a74")])
	m.add_chunks(blocks, GROTTO_X)
	var post_mat: Material = m.mat_color(Color("#3b2a1e"))
	var glass: Material = m.glow_mat(Color("#9fd8ff"), 4.0) # cold blue lamps under the water
	glass.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	glass.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	for w in lamp_spots:
		m.lantern(w.x - 0.3, w.y, post_mat, glass)
	chest = chest_node(m, marks.c, Color("#2a4a7a"))
	chest.visible = false
	side_chest = chest_node(m, marks.p, Color("#6a4a2a"))

func chest_node(m: Node, at: Vector2, body: Color) -> Node3D:
	var g := Node3D.new()
	var lid: Material = m.glow_mat(Color("#bfe6ff"), 1.4)
	for part in [[Vector3(0.8, 0.45, 0.55), Vector3(0, 0.22, 0), m.mat_color(body)], [Vector3(0.84, 0.1, 0.59), Vector3(0, 0.5, 0), lid]]:
		var b: MeshInstance3D = m.box(part[0], part[2])
		b.position = part[1]
		g.add_child(b)
	g.position = Vector3(at.x, 0, at.y)
	m.add_child(g)
	return g

func opened_look(g: Node3D) -> void:
	for b in g.get_children():
		b.transparency = 0.45

func map_tex(width: int) -> ImageTexture:
	var img := Image.create(width, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for z in H:
		for x in W:
			var c: String = grid[z][x]
			var col := Color("#1e2a34")
			match c:
				"#": col = Color(0, 0, 0, 0)
				"~": col = Color("#2c5a8a")
				"L": col = Color("#9fd8ff")
				"c", "p": col = Color("#bfe6ff")
				"C": col = Color("#c8502a")
			img.set_pixel(GROTTO_X + x, z, col)
	return ImageTexture.create_from_image(img)
