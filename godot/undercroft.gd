# 성 아래 잠긴 층 (a side zone under chapter 7's castle): a 30x24 cellar at x >= UNDER_X, reached by a stair (S) in the
# castle's great hall. A deep channel (~) for the water skip; a brick plug (W) in the north wall that, unwound, drains the
# flooded floor (r); a broken drop (_) crossed by the vents (< and > back); four water lamps (o) that must all burn within
# 8 s to open the moon door (D); Hangyeol's room with two big guardians (X), his fourth diary page (j), his chest (c), and a
# side chest (p) in the wind well. U, in Hangyeol's room, is a way back up once his chest is open.
# Sora counts as "on the hill" here.
extends RefCounted

const UNDER_X := 530
const W := 30
const H := 24
const ROWS := """##############################
###################WW#########
#.S......###...........b....##
#......b.~~~..s.........a...##
#..L.....~~~......L.........##
#........~~~..a.......s.....##
#.....b..###......g.........##
############................##
#..c..j..###rrrrrrrrrrrrrrrr##
#........###rrrrrrrrrrrrrrrr##
#U.......###rrrrrrrrrrrrrrrr##
#L..X..X.###rrrrrrrrrrrrrrrr##
#........##############rr#####
####DD#################rr#####
#............________........#
#..o......o..________..w.....#
#..........>.________........#
#.a..........________<...w...#
#............________........#
#..o......o..________...w..L.#
#......a.....________........#
#L..........L________......p.#
#............________........#
##############################"""
const VENTS := {"<": Vector2(-1, 0), ">": Vector2(1, 0)}
const LAMP_TIME := 8.0

var grid: Array = []
var marks := {}          # S stair up, U way back, c j p chests and diary, X guardians -> world Vector2
var guard_spots: Array = []
var foes: Array = []     # [world Vector2, kind]
var drained := false
var door_open := false
var lamps: Array = []    # [{"pos", "lit", "glass", "light", "lit_mat", "dark_mat"}]
var lamp_clock := 0.0    # seconds left to light the rest, from the first lamp lit
var plug_nodes: Array = []
var flood: MeshInstance3D
var door: Node3D
var chest: Sprite3D
var side_chest: Sprite3D
var diary: MeshInstance3D

func _init() -> void:
	for line in ROWS.split("\n"):
		grid.append(line)

func char_at(x: float, z: float) -> String:
	var tx := int(round(x)) - UNDER_X
	var tz := int(round(z))
	if tx < 0 or tz < 0 or tx >= W or tz >= H:
		return "#"
	return grid[tz][tx]

func vent_at(x: float, z: float) -> Vector2:
	return VENTS.get(char_at(x, z), Vector2.ZERO)

# shut: the moon door also closes behind her while the guardians stand (main passes it in)
func blocked(x: float, z: float, shut := false) -> bool:
	var c := char_at(x, z)
	if c == "r":
		return not drained
	if c == "D":
		return shut or not door_open
	return c == "#" or c == "~" or c == "_" or c == "o" or c == "W"

func lamps_lit() -> int:
	return lamps.filter(func(l): return l.lit).size()

func build(m: Node) -> void:
	var blocks: Array = []
	var lamp_spots: Array = []
	for z in H:
		for x in W:
			var c: String = grid[z][x]
			var w := Vector2(UNDER_X + x, z)
			if c in "SUcjp":
				marks[c] = w
			if c == "X":
				guard_spots.append(w)
			if c in "wagsb":
				foes.append([w, c])
			if c == "L":
				lamp_spots.append(w)
			match c:
				"#", "W":
					var near := false
					for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						var nx: int = x + d.x
						var nz: int = z + d.y
						if nx >= 0 and nz >= 0 and nx < W and nz < H and not grid[nz][nx] in "#W":
							near = true
					if near and c == "#":
						blocks.append([Transform3D(Basis().scaled(Vector3(1, 1.2, 1)), Vector3(w.x, 0.2, w.y)), Color("#4e5560").lightened(m.rnd(0, 0.06))])
				"~":
					blocks.append([Transform3D(Basis().scaled(Vector3(1, 0.05, 1)), Vector3(w.x, -0.38, w.y)), Color("#1f4a78").lightened(m.rnd(0, 0.06))])
				"_":
					pass
				_:
					# cold slate flagstones, a shade darker in a checker
					var col := Color("#6e7a84")
					if (x + z) % 2 == 0:
						col = col.darkened(0.06)
					blocks.append([Transform3D(Basis().scaled(Vector3(1, 0.4, 1)), Vector3(w.x, -0.2, w.y)), col.lightened(m.rnd(0, 0.04))])
					if VENTS.has(c):
						m.stairs.vent_pad(m, w, VENTS[c])
	m.add_chunks(blocks, UNDER_X)
	# the deep channel has a glowing water face; the drop a dark floor far below
	var wet: Material = m.glow_mat(Color("#2f78b8"), 0.6)
	wet.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	wet.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	var face: MeshInstance3D = m.box(Vector3(3.0, 0.02, 3.0), wet)
	face.position = Vector3(UNDER_X + 10, -0.3, 4)
	m.add_child(face)
	var deep: MeshInstance3D = m.box(Vector3(8.0, 0.1, 16.0), m.mat_color(Color("#120f18")))
	deep.position = Vector3(UNDER_X + 16.5, -2.6, 14.0)
	m.add_child(deep)
	# the flooded hall: a water sheet over the floor until the plug is pulled
	flood = m.box(Vector3(16.0, 0.05, 4.0), wet)
	flood.position = Vector3(UNDER_X + 19.5, 0.05, 9.5)
	m.add_child(flood)
	var post_mat: Material = m.mat_color(Color("#3b2a1e"))
	var glass: Material = m.glow_mat(Color("#9fd4ff"), 3.0)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	glass.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	for w in lamp_spots:
		m.lantern(w.x - 0.3, w.y, post_mat, glass)
	for z in H:
		for x in W:
			var at := Vector2(UNDER_X + x, z)
			if grid[z][x] == "W":
				plug_nodes.append(m.forest.brick_wall(m, at))
			if grid[z][x] == "o":
				var l: Dictionary = m.stairs.moon_lamp(m, at)
				l.dark_mat = (l.glass as MeshInstance3D).material_override
				lamps.append(l)
	door = Node3D.new()
	var slab: MeshInstance3D = m.box(Vector3(2.0, 1.6, 0.5), m.mat_color(Color("#5a5a66")))
	slab.position = Vector3(0, 0.8, 0)
	door.add_child(slab)
	var moon: MeshInstance3D = m.box(Vector3(0.5, 0.5, 0.1), m.glow_mat(Color("#bfe6ff"), 1.2))
	moon.position = Vector3(0, 1.0, 0.28)
	door.add_child(moon)
	door.position = Vector3(UNDER_X + 4.5, 0, 13)
	m.add_child(door)
	chest = m.chest_sprite(marks.c, Color("#ffe6a0"))
	side_chest = m.chest_sprite(marks.p, Color.WHITE)
	diary = m.box(Vector3(0.45, 0.08, 0.34), m.glow_mat(Color("#dfe8ff"), 1.5))
	diary.position = Vector3(marks.j.x, 0.5, marks.j.y)
	m.add_child(diary)
	var stand: MeshInstance3D = m.box(Vector3(0.5, 0.45, 0.4), m.mat_color(Color("#5a4632")))
	stand.position = Vector3(marks.j.x, 0.22, marks.j.y)
	m.add_child(stand)
	# the way back up from Hangyeol's room: a dark square with three pale steps
	for k in 3:
		var st: MeshInstance3D = m.box(Vector3(0.8, 0.06, 0.25), m.mat_color(Color("#a8b0bc").darkened(k * 0.2)))
		st.position = Vector3(marks.U.x, 0.03 - k * 0.12, marks.U.y - 0.3 + k * 0.25)
		m.add_child(st)

func light(l: Dictionary) -> void:
	m_light(l, true)

func put_out(l: Dictionary) -> void:
	m_light(l, false)

func m_light(l: Dictionary, on: bool) -> void:
	l.lit = on
	(l.glass as MeshInstance3D).material_override = l.lit_mat if on else l.dark_mat
	(l.light as OmniLight3D).visible = on

func drain() -> void:
	drained = true
	flood.visible = false
	for n in plug_nodes:
		n.visible = false

func open_door() -> void:
	door_open = true
	door.visible = false
	for l in lamps:
		m_light(l, true)

func map_tex(width: int) -> ImageTexture:
	var img := Image.create(width, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for z in H:
		for x in W:
			var c: String = grid[z][x]
			var col := Color("#4e5866")
			match c:
				"#", "_": col = Color(0, 0, 0, 0)
				"~": col = Color("#2c5a8a")
				"r": col = Color("#4e5866") if drained else Color("#2c5a8a")
				"W": col = Color(0, 0, 0, 0) if drained else Color("#c8322a")
				"<", ">": col = Color("#bfe6ff")
				"D": col = Color("#4e5866") if door_open else Color("#dfe8ff")
				"o": col = Color("#9fd4ff")
				"S", "U": col = Color("#ffd27a")
				"c", "p": col = Color("#ff9f5a")
				"L": col = Color("#ffd060")
			img.set_pixel(UNDER_X + x, z, col)
	return ImageTexture.create_from_image(img)
