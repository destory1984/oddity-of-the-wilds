# 가라앉은 달지기 성 (chapter 7): a 40x28 castle at x >= CASTLE_X between the wind hills and the heart of the garden.
# The bricked gate (W) opens to the crown's unwinding; a deep channel (~) in the great hall needs the water skip;
# a broken floor (_) is crossed by wind vents (> <). Hangyeol's three diary pages (j) lie in the library and the guard
# room; reading all three opens the moon door (D) to the throne room, where the brick knight (K) guards the east gate (E).
# Sora counts as "on the hill" in here.
extends RefCounted

const CASTLE_X := 430
const W := 40
const H := 28
const ROWS := """########################################
########################################
##########...........###################
##########..L......j.###################
##########.j.........###################
##########.........L.###################
##########...........###########.......#
################..##############.L...L.#
##########...~~~......#####....#.......#
##########.L.~~~......#####..L.#.......#
#........#...~~~..g...##___....#.......#
#..L.....#...~~~......##___....#.......#
#.....g..#...~~~......##___.s..#.......#
S........W...~~~.......>___....D...K...E
#........W...~~~........___<...D.......#
#........#...~~~......##___....#.......#
#..L.....#...~~~......##___..a.#.......#
#........#.a.~~~......##___....#.......#
##########...~~~....L.#####..L.#.......#
##########...~~~......#####....#.......#
##################..############.L...L.#
##########...........###########.......#
##########.......a...###################
##########..g........###################
##########.....j...g.###################
##########...........###################
########################################
########################################"""
const VENTS := {">": Vector2(1, 0), "<": Vector2(-1, 0)}

var grid: Array = []
var marks := {}          # S entry from the hill, E east gate to the garden, K the knight -> world Vector2
var foes: Array = []     # [world Vector2, kind] kind "g" goblin, "a" archer, "s" shield goblin
var pages: Array = []    # [{"pos": Vector2, "read": bool, "node": Node3D}] in reading order: library west, library east, guard room
var gate_open := false   # the bricked west gate
var door_open := false   # the moon door, after all three pages
var gate_nodes: Array = []
var door: Node3D

func _init() -> void:
	for line in ROWS.split("\n"):
		grid.append(line)

func char_at(x: float, z: float) -> String:
	var tx := int(round(x)) - CASTLE_X
	var tz := int(round(z))
	if tx < 0 or tz < 0 or tx >= W or tz >= H:
		return "#"
	return grid[tz][tx]

func vent_at(x: float, z: float) -> Vector2:
	return VENTS.get(char_at(x, z), Vector2.ZERO)

func blocked(x: float, z: float) -> bool:
	var c := char_at(x, z)
	if c == "W":
		return not gate_open
	if c == "D":
		return not door_open
	return c == "#" or c == "~" or c == "_" or c == "j"

func pages_read() -> int:
	return pages.filter(func(p): return p.read).size()

func build(m: Node) -> void:
	var blocks: Array = []
	var lamp_spots: Array = []
	for z in H:
		for x in W:
			var c: String = grid[z][x]
			var w := Vector2(CASTLE_X + x, z)
			if c in "SEK":
				marks[c] = w
			if c in "gas":
				foes.append([w, c])
			if c == "L":
				lamp_spots.append(w)
			if c == "j":
				pages.append({"pos": w, "read": false, "node": null})
			match c:
				"#":
					if x == 0 or z == 0 or x == W - 1 or z == H - 1 or _floor_near(x, z):
						blocks.append([Transform3D(Basis().scaled(Vector3(1, 1.1, 1)), Vector3(w.x, 0.15, w.y)), Color("#7a7468").lightened(m.rnd(0, 0.08))])
				"~":
					blocks.append([Transform3D(Basis().scaled(Vector3(1, 0.05, 1)), Vector3(w.x, -0.38, w.y)), Color("#1f4f7a").lightened(m.rnd(0, 0.06))])
				"_": # the broken floor: a dark drop, a few fallen stones far below
					if m.rng.randf() < 0.3:
						blocks.append([Transform3D(Basis().scaled(Vector3(0.7, 0.3, 0.7)), Vector3(w.x, -2.4, w.y)), Color("#3a3630")])
				_:
					var col := Color("#948c7e") if (x + z) % 2 == 0 else Color("#8c8476") # flagstones, a faint checker
					blocks.append([Transform3D(Basis().scaled(Vector3(1, 0.4, 1)), Vector3(w.x, -0.2, w.y)), col.lightened(m.rnd(0, 0.05))])
					if VENTS.has(c):
						vent_pad(m, w, VENTS[c])
	m.add_chunks(blocks, CASTLE_X)
	var post_mat: Material = m.mat_color(Color("#3b2a1e"))
	var glass: Material = m.glow_mat(Color("#ffc46a"), 4.0)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	glass.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	for w in lamp_spots:
		m.lantern(w.x - 0.3, w.y, post_mat, glass)
	for z in H:
		for x in W:
			if grid[z][x] == "W":
				gate_nodes.append(m.forest.brick_wall(m, Vector2(CASTLE_X + x, z)))
	door = moon_door(m, Vector2(CASTLE_X + 31, 13.5))
	var paper: Material = m.glow_mat(Color("#f2e2b0"), 0.6)
	var stand: Material = m.mat_color(Color("#5a4a3a"))
	for p in pages: # a reading stand with an open page on it
		var g := Node3D.new()
		var leg: MeshInstance3D = m.box(Vector3(0.2, 0.8, 0.2), stand)
		leg.position = Vector3(0, 0.4, 0)
		g.add_child(leg)
		var sheet: MeshInstance3D = m.box(Vector3(0.6, 0.04, 0.45), paper)
		sheet.position = Vector3(0, 0.85, 0)
		sheet.rotation.x = 0.4
		g.add_child(sheet)
		g.position = Vector3(p.pos.x, 0, p.pos.y)
		m.add_child(g)
		p.node = g
	var throne := Node3D.new() # the empty moonkeeper throne behind the knight
	var stone: Material = m.mat_color(Color("#6a6458"))
	var gold: Material = m.glow_mat(Color("#e8c050"), 0.8)
	for part in [[Vector3(1.4, 0.5, 1.0), Vector3(0, 0.25, 0), stone], [Vector3(1.4, 1.6, 0.3), Vector3(0, 1.0, 0.4), stone], [Vector3(0.5, 0.5, 0.06), Vector3(0, 1.5, 0.24), gold]]:
		var b: MeshInstance3D = m.box(part[0], part[2])
		b.position = part[1]
		throne.add_child(b)
	throne.position = Vector3(CASTLE_X + 37.5, 0, 9.0)
	throne.rotation.y = PI
	m.add_child(throne)
	m.rocks.append({"x": CASTLE_X + 37.5, "z": 9.0, "r": 0.9})

# wall blocks are drawn only along the rooms, so the solid rock between them costs nothing
func _floor_near(x: int, z: int) -> bool:
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var tx: int = x + dx
			var tz: int = z + dz
			if tx >= 0 and tz >= 0 and tx < W and tz < H and grid[tz][tx] != "#":
				return true
	return false

func vent_pad(m: Node, w: Vector2, d: Vector2) -> void:
	var pad: MeshInstance3D = m.box(Vector3(0.9, 0.06, 0.9), m.glow_mat(Color("#8fc8f0"), 0.5))
	pad.position = Vector3(w.x, 0.03, w.y)
	m.add_child(pad)
	var ink: Material = m.mat_color(Color("#1e3a66"))
	var tip := w + d * 0.3
	for part in [[w - d * 0.05, d, 0.55], [tip + d.rotated(2.36) * 0.14, d.rotated(2.36), 0.3], [tip + d.rotated(-2.36) * 0.14, d.rotated(-2.36), 0.3]]:
		var at: Vector2 = part[0]
		var dir: Vector2 = part[1]
		var bar: MeshInstance3D = m.box(Vector3(part[2], 0.05, 0.1), ink)
		bar.position = Vector3(at.x, 0.08, at.y)
		bar.rotation.y = atan2(-dir.y, dir.x)
		m.add_child(bar)

# two tall stone leaves with a crescent of light across them
func moon_door(m: Node, at: Vector2) -> Node3D:
	var g := Node3D.new()
	var slab: MeshInstance3D = m.box(Vector3(0.5, 1.8, 2.0), m.mat_color(Color("#5a5a66")))
	slab.position = Vector3(0, 0.9, 0)
	g.add_child(slab)
	var moon: MeshInstance3D = m.box(Vector3(0.55, 0.5, 0.18), m.glow_mat(Color("#dfe8ff"), 1.5))
	moon.position = Vector3(0, 1.3, 0.3)
	g.add_child(moon)
	g.position = Vector3(at.x, 0, at.y)
	m.add_child(g)
	return g

func open_gate() -> void:
	gate_open = true
	for n in gate_nodes:
		n.visible = false

func open_door() -> void:
	door_open = true
	door.visible = false

func map_tex(width: int) -> ImageTexture:
	var img := Image.create(width, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for z in H:
		for x in W:
			var c: String = grid[z][x]
			var col := Color("#3a3630")
			match c:
				"#", "_": col = Color(0, 0, 0, 0)
				"~": col = Color("#2c5a8a")
				">", "<": col = Color("#bfe6ff")
				"W": col = Color("#3a3630") if gate_open else Color("#c8322a")
				"D": col = Color("#3a3630") if door_open else Color("#dfe8ff")
				"j": col = Color("#f2e2b0")
				"L": col = Color("#ffd060")
				"K": col = Color("#c8322a")
			img.set_pixel(CASTLE_X + x, z, col)
	return ImageTexture.create_from_image(img)
