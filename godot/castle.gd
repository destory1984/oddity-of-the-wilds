# 가라앉은 달지기 성 (chapter 7): a 40x28 castle at x >= CASTLE_X between the wind hills and the heart of the garden.
# The bricked gate (W) opens to the crown's unwinding; a deep channel (~) in the great hall needs the water skip;
# a broken floor (_) is crossed by wind vents (> <). Hangyeol's three diary pages (j) lie in the library and the guard
# room; reading all three opens the moon door (D) to the throne room, where the brick knight (K) guards the east gate (E).
# East of the guard room, three barred gates (1 2 3) guard the treasury (T); the levers (l) on the guard room's
# north wall each flip two gates or one: open all three to reach the moonkeeper armour.
# South of the throne room, the moonkeepers' quarters (rows 22 - 38, DESIGN.md 달지기 숙소): the knight's rusty
# spring opens the clockwork door (Q); the tin doorkeeper on the workshop stand (k) walks to the bunk room door (n).
# Sora counts as "on the hill" in here.
extends RefCounted

const CASTLE_X := 430
const W := 40
const H := 40
const ROWS := """########################################
########################################
##########....b.b....###################
##########..L......j.###################
##########.j.........###################
##########.........L.###################
##########b.......b.b###########.......#
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
##########...l.l.l...###......##.......#
##########.......a...###......#####Q####
##########..g........123....T.#####.####
##########.....j...g.###......#####.####
##########...........###......#####.####
###################################.####
###############.r.r.m.rr.##.L...y....L.#
###############..........##............#
###############.......v..##..g......g..#
###############...v...........tttttt...#
###############..........##..........y.#
###############L.........##......s...a.#
###################..######........y...#
###############..........#######n#######
###############..........##....o.h.....#
###############.k........##.d.d....d.d.#
###############..........##...........c#
###############.........L##.d.d..L.d.d.#
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
const LEVER_FLIPS := [[0, 1], [1, 2], [2]] # which gates each lever flips (solved by the first and third)
var bars := [false, false, false]       # gate open?
var bar_nodes: Array = []
var levers: Array = []                  # [{"pos": Vector2, "handle": Node3D, "up": bool}]
var vault_chest: Node3D
var vault_open := false
var books: Array = []   # [{"pos": Vector2, "read": bool}] the library shelves (b), in reading order
# 달지기 숙소: the dining hall's g a s (z >= 27) are kept apart from foes, so entering the castle spawns the same
const QUARTERS_Z := 27
const DOLL_PATH := [Vector2(447, 36), Vector2(449.5, 35), Vector2(449.5, 33), Vector2(449.5, 31), Vector2(455.5, 30),
	Vector2(458, 31.5), Vector2(462, 33), Vector2(462, 34)] # the doorkeeper's walk from his stand to the bunk room door
var quarter_foes: Array = []  # [world Vector2, kind] spawned the first time Sora steps into the dining hall
var quarter_bats: Array = []  # [world Vector2, "v"] the basket room
var heaps: Array = []         # the brick heaps (y) in the dining hall
var racks: Array = []         # the basket racks (r)
var quarters_open := false    # the clockwork door Q
var bunk_open := false        # the bunk room door n
var spring_node: Node3D       # the rusty spring where the knight knelt
var spring_glow: StandardMaterial3D
var qdoor: Node3D
var bunk_door: Node3D
var doll: Node3D              # the tin doorkeeper
var doll_eye: MeshInstance3D
var doll_drop: Node3D         # his spring, knocked out onto the floor
var heap_nodes: Array = []
var quarters_chest: Node3D
var chest_open_look := false
var ledger_name: MeshInstance3D # Sora's name in the line after Hangyeol's
var eye_on: StandardMaterial3D
var eye_off: StandardMaterial3D

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
	if c in "123":
		return not bars[int(c) - 1]
	if c == "l" or c == "T" or c == "b":
		return true
	if c == "Q":
		return not quarters_open
	if c == "n":
		return not bunk_open
	if c in "rmtkohdc":
		return true
	return c == "#" or c == "~" or c == "_" or c == "j"

func pages_read() -> int:
	return pages.filter(func(p): return p.read).size()

func build(m: Node) -> void:
	var blocks: Array = []
	var lamp_spots: Array = []
	var lit_path := quarters_path_tiles()
	for z in H:
		for x in W:
			var c: String = grid[z][x]
			var w := Vector2(CASTLE_X + x, z)
			if c in "SEKQmknohc":
				marks[c] = w
			if c in "gas":
				if z >= QUARTERS_Z:
					quarter_foes.append([w, c])
				else:
					foes.append([w, c])
			if c == "v":
				quarter_bats.append([w, c])
			if c == "y":
				heaps.append(w)
			if c == "r":
				racks.append(w)
			if c == "L":
				lamp_spots.append(w)
			if c == "j":
				pages.append({"pos": w, "read": false, "node": null})
			match c:
				"#":
					if _low_wall(x, z): # the quarters' inner walls stay low, so the one-tile doorways show (GPT's note)
						blocks.append([Transform3D(Basis().scaled(Vector3(1, 0.75, 1)), Vector3(w.x, -0.025, w.y)), Color("#7a7468").lightened(m.rnd(0, 0.08))])
					elif x == 0 or z == 0 or x == W - 1 or z == H - 1 or _floor_near(x, z):
						blocks.append([Transform3D(Basis().scaled(Vector3(1, 1.1, 1)), Vector3(w.x, 0.15, w.y)), Color("#7a7468").lightened(m.rnd(0, 0.08))])
				"~":
					blocks.append([Transform3D(Basis().scaled(Vector3(1, 0.05, 1)), Vector3(w.x, -0.38, w.y)), Color("#1f4f7a").lightened(m.rnd(0, 0.06))])
				"_": # the broken floor: a dark drop, a few fallen stones far below
					if m.rng.randf() < 0.3:
						blocks.append([Transform3D(Basis().scaled(Vector3(0.7, 0.3, 0.7)), Vector3(w.x, -2.4, w.y)), Color("#3a3630")])
				_:
					var col := Color("#948c7e") if (x + z) % 2 == 0 else Color("#8c8476") # flagstones, a faint checker
					if x >= 27 and z >= 35: # the bunk room: wooden boards
						col = Color("#7a5a3a") if (x + z) % 2 == 0 else Color("#72543a")
					if lit_path.has(Vector2i(x, z)): # the way through the quarters, one step lighter
						col = Color("#b0a38c")
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
	build_vault(m)
	var wood: Material = m.mat_color(Color("#5a3a26"))
	var spines := [Color("#a8322a"), Color("#2a5a9a"), Color("#3a8a4a"), Color("#c8962a")]
	for z in H:
		for x in W:
			if grid[z][x] == "b":
				var g := Node3D.new()
				var shelf: MeshInstance3D = m.box(Vector3(0.9, 1.5, 0.5), wood)
				shelf.position = Vector3(0, 0.75, 0)
				g.add_child(shelf)
				for k in 4:
					var bk: MeshInstance3D = m.box(Vector3(0.16, 0.34, 0.4), m.mat_color(spines[k]))
					bk.position = Vector3(-0.3 + k * 0.2, 1.05, 0.06)
					g.add_child(bk)
				g.position = Vector3(CASTLE_X + x, 0, z)
				m.add_child(g)
				books.append({"pos": Vector2(CASTLE_X + x, z), "read": false})
	build_quarters(m)

# ---- 달지기 숙소 (DESIGN.md): boxes only, colours from GPT's notes; light only from self-lit glass
func _low_wall(x: int, z: int) -> bool:
	return z >= QUARTERS_Z and z <= 38 and x > 14 and x < 39 and (x == 25 or x == 26 or z == 33 or z == 34)

# the threshold, the doorways and the bunk room door joined by a lighter floor (the doorkeeper's walk and the corridor)
func quarters_path_tiles() -> Dictionary:
	var out := {}
	for z in range(23, QUARTERS_Z + 1):
		out[Vector2i(35, z)] = true
	for i in DOLL_PATH.size() - 1:
		var a: Vector2 = DOLL_PATH[i]
		var b: Vector2 = DOLL_PATH[i + 1]
		for k in 21:
			var p := a.lerp(b, k / 20.0)
			var t := Vector2i(int(round(p.x)) - CASTLE_X, int(round(p.y)))
			if t.y >= 0 and t.y < grid.size() and grid[t.y][t.x] in ".gasvyLn":
				out[t] = true
	return out

func _part(m: Node, g: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var b: MeshInstance3D = m.box(size, mat)
	b.position = pos
	g.add_child(b)
	return b

# an upright eight-sided block (three boxes): baskets, bowls, the key mark, the buckler
func octo(m: Node, g: Node3D, w: float, h: float, pos: Vector3, mat: Material) -> void:
	_part(m, g, Vector3(w, h, w * 0.42), pos, mat)
	_part(m, g, Vector3(w * 0.42, h, w), pos, mat)
	var d := _part(m, g, Vector3(w * 0.7, h, w * 0.7), pos, mat)
	d.rotation.y = PI / 4.0

# the key mark: an eight-sided plate with a key bow on top, lying flat (the door turns it upright).
# The rusty spring has the same shape, so finding it points to the door (GPT's note)
func key_mark(m: Node, s: float, mat: Material) -> Node3D:
	var g := Node3D.new()
	octo(m, g, s, 0.06, Vector3.ZERO, mat)
	_part(m, g, Vector3(s * 0.22, 0.06, s * 0.5), Vector3(0, 0, -s * 0.62), mat)
	_part(m, g, Vector3(s * 0.5, 0.06, s * 0.16), Vector3(0, 0, -s * 0.86), mat)
	return g

func basket(m: Node, g: Node3D, s: float, pos: Vector3) -> void:
	octo(m, g, s, s, pos, m.mat_color(Color("#c8a860")))
	for dy in [-0.22, 0.2]:
		octo(m, g, s * 1.06, 0.03, pos + Vector3(0, s * dy, 0), m.mat_color(Color("#8a6a3a")))
	octo(m, g, s * 0.62, 0.02, pos + Vector3(0, s * 0.5 + 0.006, 0), m.mat_color(Color("#3a2a1a")))

func build_quarters(m: Node) -> void:
	var wood: Material = m.mat_color(Color("#5a3a26"))
	var oak: Material = m.mat_color(Color("#6a4a32"))
	var stone: Material = m.mat_color(Color("#6a6458"))
	var brass: Material = m.mat_color(Color("#c8962a"))
	var paper: Material = m.mat_color(Color("#f2ead8"))
	var ink: Material = m.mat_color(Color("#3a3028"))
	# Q: a dark stone leaf with the brass key mark on both faces, only its edge faintly lit
	qdoor = Node3D.new()
	_part(m, qdoor, Vector3(1.0, 1.1, 0.3), Vector3(0, 0.55, 0), stone)
	for side in [-1.0, 1.0]:
		var rim := key_mark(m, 0.44, m.glow_mat(Color("#ffc46a"), 0.6))
		rim.rotation.x = PI / 2.0
		rim.position = Vector3(0, 0.66, side * 0.16)
		qdoor.add_child(rim)
		var mk := key_mark(m, 0.36, brass)
		mk.rotation.x = PI / 2.0
		mk.position = Vector3(0, 0.66, side * 0.18)
		qdoor.add_child(mk)
	qdoor.position = Vector3(marks.Q.x, 0, marks.Q.y)
	m.add_child(qdoor)
	# the rusty spring where the knight knelt, glowing faintly (main pulses it)
	spring_node = Node3D.new()
	spring_glow = m.glow_mat(Color("#ffc46a"), 0.3)
	var halo := key_mark(m, 0.5, spring_glow)
	halo.position.y = 0.02
	spring_node.add_child(halo)
	var sp := key_mark(m, 0.4, m.mat_color(Color("#8a5a3a")))
	sp.position.y = 0.06
	spring_node.add_child(sp)
	_part(m, spring_node, Vector3(0.1, 0.1, 0.1), Vector3(0, 0.12, 0), oak)
	spring_node.position = Vector3(marks.K.x + 0.6, 0, marks.K.y + 0.5)
	spring_node.visible = false
	m.add_child(spring_node)
	# the basket racks: a low frame, three reed baskets on top (low, so the room behind shows)
	for w in racks:
		var g := Node3D.new()
		_part(m, g, Vector3(0.9, 0.7, 0.45), Vector3(0, 0.35, -0.18), wood)
		_part(m, g, Vector3(0.94, 0.05, 0.5), Vector3(0, 0.45, -0.16), oak)
		for k in 3:
			basket(m, g, 0.26, Vector3(-0.3 + k * 0.3, 0.84, -0.16))
		g.position = Vector3(w.x, 0, w.y)
		m.add_child(g)
	for at in [Vector2(445.25, 28.2), Vector2(453.75, 28.2)]: # dry reed bundles in the corners
		var g := Node3D.new()
		for k in 5:
			var r := _part(m, g, Vector3(0.06, 0.06, 0.8), Vector3(-0.12 + k * 0.06, 0.03 + (k % 2) * 0.05, 0), m.mat_color(Color("#b8a070")))
			r.rotation.y = 0.1 * (k - 2)
		g.position = Vector3(at.x, 0, at.y)
		m.add_child(g)
	# the tally board: rows of marks, a ring for each; the last mark slanted, its ring set apart and empty
	var tb := Node3D.new()
	_part(m, tb, Vector3(1.2, 1.1, 0.1), Vector3(0, 0.75, -0.35), m.mat_color(Color("#5a4a3a")))
	for row in 3:
		for k in 9:
			var last := row == 2 and k == 8
			var bar := _part(m, tb, Vector3(0.03, 0.14, 0.02), Vector3(-0.5 + k * 0.1 + (0.06 if last else 0.0), 1.18 - row * 0.19, -0.29), paper)
			if last:
				bar.rotation.z = 0.45
	for k in 5:
		var last := k == 4
		var hx := -0.46 + k * 0.2 + (0.16 if last else 0.0)
		_part(m, tb, Vector3(0.05, 0.08, 0.05), Vector3(hx, 0.56, -0.27), brass)
		if not last:
			basket(m, tb, 0.13, Vector3(hx, 0.44, -0.22))
	tb.position = Vector3(marks.m.x, 0, marks.m.y)
	m.add_child(tb)
	# the long table: a top on four thick legs, six bowls turned over; the corridor south of it stays clear
	var tt := Node3D.new()
	_part(m, tt, Vector3(6.0, 0.12, 1.0), Vector3(0, 0.7, 0), oak)
	for lx in [-2.7, 2.7]:
		for lz in [-0.35, 0.35]:
			_part(m, tt, Vector3(0.2, 0.64, 0.2), Vector3(lx, 0.32, lz), oak)
	for k in 6:
		octo(m, tt, 0.3, 0.07, Vector3(-2.5 + k * 1.0, 0.8, 0.12 if k % 2 == 0 else -0.14), m.mat_color(Color("#bcb4a4")))
	tt.position = Vector3(462.5, 0, 30)
	m.add_child(tt)
	# the brick heaps the doorkeeper's walk shakes loose
	for w in heaps:
		var g := Node3D.new()
		for part in [[Vector3(0.4, 0.2, 0.3), Vector3(-0.1, 0.1, 0), "#a8322a"], [Vector3(0.3, 0.2, 0.3), Vector3(0.22, 0.1, 0.1), "#7a7468"],
				[Vector3(0.3, 0.18, 0.26), Vector3(0.05, 0.29, 0.02), "#a8322a"], [Vector3(0.2, 0.14, 0.2), Vector3(-0.2, 0.07, -0.25), "#7a7468"]]:
			_part(m, g, part[0], part[1], m.mat_color(Color(part[2])))
		g.position = Vector3(w.x, 0, w.y)
		m.add_child(g)
		heap_nodes.append(g)
	# the workshop stand: a low base and a back like a chair's, the note tied to it
	var st := Node3D.new()
	_part(m, st, Vector3(0.8, 0.3, 0.8), Vector3(0, 0.15, 0), stone)
	_part(m, st, Vector3(0.8, 0.9, 0.15), Vector3(0, 0.6, -0.33), stone)
	_part(m, st, Vector3(0.22, 0.26, 0.02), Vector3(0.22, 0.75, -0.25), paper)
	st.position = Vector3(marks.k.x, 0, marks.k.y)
	m.add_child(st)
	build_doll(m)
	# the bunk room door: wooden boards with a keyhole on both faces
	bunk_door = Node3D.new()
	_part(m, bunk_door, Vector3(1.0, 1.1, 0.25), Vector3(0, 0.55, 0), wood)
	for side in [-1.0, 1.0]:
		_part(m, bunk_door, Vector3(0.12, 0.22, 0.03), Vector3(0, 0.6, side * 0.14), m.mat_color(Color("#1a1418")))
	bunk_door.position = Vector3(marks.n.x, 0, marks.n.y)
	m.add_child(bunk_door)
	# eight bunks, blankets folded square in two big layers, a pillow each
	for z in H:
		for x in W:
			if grid[z][x] == "d":
				var g := Node3D.new()
				_part(m, g, Vector3(0.85, 0.35, 1.1), Vector3(0, 0.175, 0), wood)
				_part(m, g, Vector3(0.62, 0.1, 0.42), Vector3(0, 0.4, 0.2), m.mat_color(Color("#8a6a9a")))
				_part(m, g, Vector3(0.56, 0.08, 0.36), Vector3(0, 0.49, 0.2), m.mat_color(Color("#9a7aaa")))
				_part(m, g, Vector3(0.5, 0.1, 0.26), Vector3(0, 0.4, -0.36), m.mat_color(Color("#e8e0d0")))
				g.position = Vector3(CASTLE_X + x, 0, z)
				m.add_child(g)
	# the doorkeeper's chair
	var ch := Node3D.new()
	_part(m, ch, Vector3(0.55, 0.08, 0.5), Vector3(0, 0.36, 0), oak)
	for lx in [-0.22, 0.22]:
		for lz in [-0.2, 0.2]:
			_part(m, ch, Vector3(0.07, 0.34, 0.07), Vector3(lx, 0.17, lz), oak)
	_part(m, ch, Vector3(0.55, 0.5, 0.07), Vector3(0, 0.62, -0.22), oak)
	ch.position = Vector3(marks.h.x, 0, marks.h.y)
	m.add_child(ch)
	# the ledger on a post: a thick cover, two open pages tilted to the light; the far names are ink bars, and after
	# Hangyeol's line one long-empty line (GPT's note); Sora's name appears there once she writes it
	var lg := Node3D.new()
	_part(m, lg, Vector3(0.12, 0.8, 0.12), Vector3(0, 0.4, -0.1), wood)
	var book := Node3D.new()
	book.position = Vector3(0, 0.84, 0)
	book.rotation.x = 0.4
	lg.add_child(book)
	_part(m, book, Vector3(0.8, 0.07, 0.56), Vector3.ZERO, m.mat_color(Color("#4a2e20")))
	for side in [-1.0, 1.0]:
		var pg := _part(m, book, Vector3(0.36, 0.03, 0.48), Vector3(side * 0.19, 0.05, 0), paper)
		pg.rotation.z = -side * 0.06
	for k in 6: # the left page full of names
		_part(m, book, Vector3(0.24 - (k % 3) * 0.03, 0.012, 0.03), Vector3(-0.2, 0.072, -0.17 + k * 0.065), ink)
	_part(m, book, Vector3(0.22, 0.012, 0.03), Vector3(0.18, 0.072, -0.17), ink) # Hangyeol, the last name
	_part(m, book, Vector3(0.26, 0.008, 0.012), Vector3(0.18, 0.07, -0.1), m.mat_color(Color("#cfc6b4"))) # the empty line under it
	ledger_name = _part(m, book, Vector3(0.16, 0.012, 0.03), Vector3(0.16, 0.074, -0.105), ink)
	ledger_name.visible = false
	lg.position = Vector3(marks.o.x, 0, marks.o.y - 0.15)
	m.add_child(lg)
	# the quarters' chest at the end of the bunk room
	quarters_chest = Node3D.new()
	_part(m, quarters_chest, Vector3(0.55, 0.45, 0.8), Vector3(0, 0.225, 0), m.mat_color(Color("#8a5a3a")))
	_part(m, quarters_chest, Vector3(0.57, 0.06, 0.82), Vector3(0, 0.3, 0), brass)
	var lid := Node3D.new()
	lid.name = "lid"
	lid.position = Vector3(0, 0.45, 0)
	_part(m, lid, Vector3(0.58, 0.12, 0.84), Vector3(0, 0.06, 0), m.mat_color(Color("#d8c8a0")))
	quarters_chest.add_child(lid)
	quarters_chest.position = Vector3(marks.c.x, 0, marks.c.y)
	m.add_child(quarters_chest)

# the tin doorkeeper: the knight's helmet and shoulders, a short body, thick arms and legs, a key for a right hand
# and a small brass buckler on the left arm. Only his eyes glow, and only once he is wound
func build_doll(m: Node) -> void:
	var tin: Material = m.mat_color(Color("#9fb4c8"), 0.5)
	var joint: Material = m.mat_color(Color("#4a5a6a"))
	var brass: Material = m.mat_color(Color("#c8962a"))
	eye_on = m.glow_mat(Color("#ffc46a"), 2.0)
	eye_off = m.mat_color(Color("#263440"))
	doll = Node3D.new()
	var body := Node3D.new()
	body.name = "body"
	doll.add_child(body)
	var legs := Node3D.new()
	legs.name = "legs"
	legs.position = Vector3(0, 0.3, 0)
	body.add_child(legs)
	for lx in [-0.13, 0.13]:
		_part(m, legs, Vector3(0.2, 0.3, 0.22), Vector3(lx, -0.15, 0), joint)
	_part(m, body, Vector3(0.5, 0.36, 0.36), Vector3(0, 0.48, 0), tin)
	_part(m, body, Vector3(0.66, 0.12, 0.4), Vector3(0, 0.66, 0), tin) # shoulders
	_part(m, body, Vector3(0.4, 0.34, 0.38), Vector3(0, 0.88, 0), tin) # helmet
	_part(m, body, Vector3(0.08, 0.14, 0.08), Vector3(0, 1.11, 0), joint) # crest
	doll_eye = _part(m, body, Vector3(0.3, 0.05, 0.04), Vector3(0, 0.9, 0.2), eye_off)
	var hole := _part(m, body, Vector3(0.16, 0.16, 0.04), Vector3(0, 0.48, 0.18), eye_off) # the empty spring hole
	hole.name = "hole"
	var sp := key_mark(m, 0.16, m.mat_color(Color("#8a5a3a")))
	sp.name = "spring"
	sp.rotation.x = PI / 2.0
	sp.position = Vector3(0, 0.5, 0.2)
	body.add_child(sp)
	for side in [-1.0, 1.0]:
		_part(m, body, Vector3(0.15, 0.34, 0.17), Vector3(side * 0.38, 0.46, 0), joint)
	_part(m, body, Vector3(0.06, 0.06, 0.24), Vector3(0.38, 0.27, 0.12), brass) # the key hand
	_part(m, body, Vector3(0.06, 0.12, 0.05), Vector3(0.38, 0.23, 0.22), brass)
	var bk := Node3D.new() # the buckler, a cut-cornered plate with a bright rim and a boss, on from the start
	bk.name = "buckler"
	bk.position = Vector3(-0.48, 0.48, 0.03)
	bk.rotation.z = PI / 2.0
	body.add_child(bk)
	octo(m, bk, 0.34, 0.03, Vector3(0, -0.015, 0), m.mat_color(Color("#e8c060"), 0.4)) # the rim, behind
	octo(m, bk, 0.3, 0.03, Vector3(0, 0.0, 0), m.mat_color(Color("#c8962a"), 0.4))
	_part(m, bk, Vector3(0.08, 0.05, 0.08), Vector3(0, 0.03, 0), m.mat_color(Color("#e8c060"), 0.4)) # the boss
	m.add_child(doll)
	doll_on_stand()

func doll_on_stand() -> void:
	doll.position = Vector3(marks.k.x, 0.3, marks.k.y)
	doll.rotation = Vector3.ZERO
	(doll.get_node("body/legs") as Node3D).rotation.x = 0.0

func doll_place(at: Vector2, face: Vector2) -> void:
	doll.position = Vector3(at.x, 0, at.y)
	if face.length() > 0.01:
		doll.rotation.y = atan2(face.x, face.y)

func doll_wound(on: bool) -> void:
	doll_eye.material_override = eye_on if on else eye_off
	(doll.get_node("body/spring") as Node3D).visible = on
	(doll.get_node("body/hole") as Node3D).visible = not on

# resting in his chair: the legs forward, the eyes dimmed but still lit
func doll_sit(give: bool) -> void:
	var h: Vector2 = marks.h
	doll.position = Vector3(h.x, 0.09, h.y + 0.04)
	doll.rotation = Vector3.ZERO
	(doll.get_node("body/legs") as Node3D).rotation.x = -PI / 2.0
	if give:
		(doll.get_node("body/buckler") as Node3D).visible = false

func doll_rest_eye(m: Node) -> void:
	doll_eye.material_override = m.glow_mat(Color("#ffc46a"), 0.5)

func set_spring(on: bool) -> void:
	spring_node.visible = on

func open_quarters() -> void:
	quarters_open = true
	qdoor.visible = false

func open_bunk() -> void:
	bunk_open = true
	bunk_door.visible = false

func show_heaps(on: bool) -> void:
	for n in heap_nodes:
		n.visible = on

func quarters_chest_look(open: bool) -> void:
	chest_open_look = open
	var lid: Node3D = quarters_chest.get_node("lid")
	lid.position = Vector3(0, 0.62, -0.36) if open else Vector3(0, 0.45, 0)
	lid.rotation.x = -1.25 if open else 0.0

# every prop for a saved step at once (loads, scenes and tests; both ways). The walk itself is main's
func quarters_look(q: int, spring_on: bool, box_open: bool) -> void:
	set_spring(spring_on)
	quarters_open = q >= 2
	qdoor.visible = not quarters_open
	qdoor.position = Vector3(marks.Q.x, 0, marks.Q.y)
	bunk_open = q >= 4
	bunk_door.visible = not bunk_open
	show_heaps(true)
	doll_wound(q >= 3)
	if doll_drop != null:
		doll_drop.visible = false
	(doll.get_node("body/buckler") as Node3D).visible = q < 5
	doll_on_stand()
	if q == 3:
		doll_place(DOLL_PATH[0], Vector2(1, 0))
	elif q == 4:
		doll_place(Vector2(463, 36), Vector2(0, 1))
	elif q >= 5:
		doll_sit(true)
	ledger_name.visible = q >= 5
	quarters_chest_look(box_open)

func build_vault(m: Node) -> void:
	var iron: Material = m.mat_color(Color("#4a4a56"))
	for i in 3:
		var g := Node3D.new()
		for k in 4:
			var b: MeshInstance3D = m.box(Vector3(0.12, 1.4, 0.12), iron)
			b.position = Vector3(0, 0.7, -0.36 + k * 0.24)
			g.add_child(b)
		g.position = Vector3(CASTLE_X + 21 + i, 0, 23)
		m.add_child(g)
		bar_nodes.append(g)
	for z in H:
		for x in W:
			if grid[z][x] == "l":
				var g := Node3D.new()
				var base: MeshInstance3D = m.box(Vector3(0.5, 0.5, 0.3), m.mat_color(Color("#6a6458")))
				base.position = Vector3(0, 0.6, -0.3)
				g.add_child(base)
				var handle := Node3D.new()
				handle.position = Vector3(0, 0.6, -0.15)
				var stick: MeshInstance3D = m.box(Vector3(0.08, 0.6, 0.08), m.mat_color(Color("#c8962a")))
				stick.position = Vector3(0, 0.3, 0)
				handle.add_child(stick)
				handle.rotation.x = 0.6
				g.add_child(handle)
				g.position = Vector3(CASTLE_X + x, 0, z)
				m.add_child(g)
				levers.append({"pos": Vector2(CASTLE_X + x, z), "handle": handle, "up": false})
	vault_chest = Node3D.new()
	for part in [[Vector3(0.9, 0.5, 0.6), Vector3(0, 0.25, 0), m.mat_color(Color("#5a3a6a"))], [Vector3(0.94, 0.12, 0.64), Vector3(0, 0.56, 0), m.glow_mat(Color("#e8c050"), 1.0)]]:
		var b: MeshInstance3D = m.box(part[0], part[2])
		b.position = part[1]
		vault_chest.add_child(b)
	vault_chest.position = Vector3(CASTLE_X + 28, 0, 23)
	m.add_child(vault_chest)

func flip_lever(i: int) -> void:
	var lv: Dictionary = levers[i]
	lv.up = not lv.up
	(lv.handle as Node3D).rotation.x = -0.6 if lv.up else 0.6
	for gi in LEVER_FLIPS[i]:
		bars[gi] = not bars[gi]
		bar_nodes[gi].visible = not bars[gi]

func vault_solved() -> bool:
	return bars[0] and bars[1] and bars[2]

func open_vault_look() -> void:
	vault_open = true
	for b in vault_chest.get_children():
		b.transparency = 0.45

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
				"1", "2", "3": col = Color("#3a3630") if bars[int(c) - 1] else Color("#8a8a96")
				"l": col = Color("#c8962a")
				"T": col = Color("#e8c050")
				"b": col = Color("#8a5a3a")
				"L": col = Color("#ffd060")
				"K": col = Color("#c8322a")
				"Q": col = Color("#3a3630") if quarters_open else Color("#c8962a")
				"n": col = Color("#5a4632") if bunk_open else Color("#8a5a3a")
				"r", "m": col = Color("#c8a860")
				"t": col = Color("#6a4a32")
				"k": col = Color("#9fb4c8")
				"d": col = Color("#8a6a9a")
				"c": col = Color("#5a4632") if chest_open_look else Color("#ff9f5a")
				"o", "h": col = Color("#f2ead8")
			if x >= 27 and z >= 35 and col == Color("#3a3630"): # the bunk room's boards
				col = Color("#5a4632")
			img.set_pixel(CASTLE_X + x, z, col)
	return ImageTexture.create_from_image(img)
