# 정원 한가운데 (story step 11): a round arena at x >= GARDEN_X where the hardened-moon mold waits.
# Eight dark lantern posts ring the arena; in the last wind the villagers' lights fill them one by one.
# Below it (rows 22 - 39, DESIGN.md "한결의 마지막 길"): the yard where Hangyeol camped the night before he went in.
# From the stairs' top Sora comes in at A; root bricks (R) close the west yard off from his camp (k j c); his
# footprints (h) cross the deep gap (,) and only show when the crown shines; the brick Hangyeol rises at X; the
# grey gate (G, row 21) opens onto the arena when he falls.
extends RefCounted

const GARDEN_X := 230
const W := 26
const H := 40
const ROAD_Z := 22 # first row of the yard below the arena
const ROAD_ROWS := [
	"#########..........#######",
	"#########..........#######",
	"#########....X.....#######",
	"#########..........#######",
	"#########L........L#######",
	"#############..###########",
	"#,,,,,,,,,,,,hhh,,,,,,,,,#",
	"#,,,,,,,,,,,,,,hhh,,,,,,,#",
	"#,,,,,,,,,,,,,,,,hhh,,,,,#",
	"#,,,,,,,,,,,,,,,,,,h,,,,,#",
	"#################........#",
	"#L............a.#....k...#",
	"#......w........#.....j..#",
	"#..Y.......s....R........#",
	"#...............R......c.#",
	"#A........w.....#.......L#",
	"#...............#........#",
	"##########################",
]
const GATE_COLS := [13, 14, 15] # row 21: the grey gate into the arena
const CENTER := Vector2(14, 11)
const RADIUS := 9.5

var marks := {}          # S (entry from the forest), C (centre) -> world Vector2
var posts: Array = []    # the 8 ring lanterns: OmniLight3D, dark until the last wind
var seals: Array = []    # [{"pos": Vector2, "node": Node3D, "open": bool}] the brick seals that keep the mold asleep
var road_marks := {}     # A in/out, Y waystone, X the brick Hangyeol, k hook, j diary, c blanket -> world Vector2
var road_foes: Array = []  # [world Vector2, "w" | "s" | "a"]
var roots: Array = []    # [world Vector2, Node3D] the two root bricks
var roots_open := false
var gate_nodes: Array = []
var gate_open := false
var path_tiles: Array = []  # world Vector2 of Hangyeol's footprints over the gap
var path_nodes: Array = []
var reveal_t := 0.0
var blanket: Node3D

func char_at(x: float, z: float) -> String:
	var tx := int(round(x)) - GARDEN_X
	var tz := int(round(z))
	if tx < 0 or tz < 0 or tx >= W or tz >= H:
		return "#"
	if tz >= ROAD_Z:
		return ROAD_ROWS[tz - ROAD_Z][tx]
	if tz == ROAD_Z - 1 and tx in GATE_COLS:
		return "G"
	if tz == int(CENTER.y) and tx <= int(CENTER.x - RADIUS) + 1 and tx >= 1:
		return "=" # the brick road in from the forest
	return "." if Vector2(tx, tz).distance_to(CENTER) <= RADIUS else "#"

func blocked(x: float, z: float) -> bool:
	var c := char_at(x, z)
	if c == "#" or c in "Lkjc":
		return true
	if c == "R":
		return not roots_open
	if c == "G":
		return not gate_open
	for sl in seals:
		if not sl.open and Vector2(x, z).distance_to(sl.pos) < 0.6:
			return true
	return false

func seals_open() -> int:
	return seals.filter(func(sl): return sl.open).size()

func open_seal(sl: Dictionary) -> void:
	sl.open = true
	sl.node.visible = false

func build(m: Node) -> void:
	marks.S = Vector2(GARDEN_X + 1, CENTER.y)
	marks.C = Vector2(GARDEN_X + CENTER.x, CENTER.y)
	var blocks: Array = []
	for z in H:
		for x in W:
			var w := Vector2(GARDEN_X + x, z)
			var c := char_at(w.x, w.y)
			var col := Color("#8a8a90") # ground pressed flat into grey brick
			var hgt := 0.4
			if c == "," or c == "h":
				continue # the deep gap: no ground, a dark floor far below
			if c == "#":
				col = Color("#4a4652")
				hgt = m.rnd(1.2, 2.4) # jagged brick cliffs around the arena
			elif c == "=":
				col = Color("#a39c90")
			elif (x + z) % 3 == 0:
				col = Color("#7a7a82") # cracks
			col = col.lightened(m.rnd(0, 0.06))
			blocks.append([Transform3D(Basis().scaled(Vector3(1, hgt, 1)), Vector3(w.x, hgt / 2.0 - 0.4, w.y)), col])
	var chunks := {}
	for bl in blocks:
		var o: Vector3 = bl[0].origin
		var key := Vector2i(int(o.x - GARDEN_X) / 6, int(o.z) / 6)
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
	var post_mat: Material = m.mat_color(Color("#3b2a1e"))
	var glass: Material = m.glow_mat(Color("#ffc46a"), 4.0)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	glass.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	for k in 8:
		var a := TAU * k / 8.0 + PI / 8.0
		var p: Vector2 = marks.C + Vector2(cos(a), sin(a)) * (RADIUS - 1.5)
		m.lantern(p.x - 0.3, p.y, post_mat, glass)
		var l: OmniLight3D = m.lanterns[m.lanterns.size() - 1]
		var g: MeshInstance3D = l.get_meta("glass")
		g.set_meta("lit_mat", g.material_override)
		posts.append(l)
	set_posts(0)
	# three brick seals around the heart: the mold sleeps until all are unwound
	for k in 3:
		var a2 := TAU * k / 3.0 - PI / 2.0
		var at: Vector2 = marks.C + Vector2(cos(a2), sin(a2)) * 5.0
		var g := Node3D.new()
		var grey: Material = m.mat_color(Color("#6a6672"))
		var violet: Material = m.glow_mat(Color("#9a4ad8"), 1.0)
		var block: MeshInstance3D = m.box(Vector3(1.0, 1.4, 1.0), grey)
		block.position = Vector3(0, 0.7, 0)
		g.add_child(block)
		var rune: MeshInstance3D = m.box(Vector3(0.4, 0.4, 0.06), violet)
		rune.position = Vector3(0, 0.9, 0.52)
		g.add_child(rune)
		g.position = Vector3(at.x, 0, at.y)
		m.add_child(g)
		seals.append({"pos": at, "node": g, "open": false})
	build_road(m, post_mat, glass)

# the yard below: lanterns after the ring posts (posts took the last of m.lanterns), root bricks, the grey gate,
# the gap's dark floor, the hidden footprints, and Hangyeol's camp
func build_road(m: Node, post_mat: Material, glass: Material) -> void:
	var violet: Material = m.glow_mat(Color("#9a4ad8"), 1.0)
	var grey: Material = m.mat_color(Color("#6a6672"))
	var step: Material = m.glow_mat(Color("#bfe6ff"), 1.2)
	for z in range(ROAD_Z - 1, H):
		for x in W:
			var w := Vector2(GARDEN_X + x, z)
			var c := char_at(w.x, w.y)
			match c:
				"A", "Y", "X", "k", "j", "c":
					road_marks[c] = w
				"w", "s", "a":
					road_foes.append([w, c])
				"L":
					m.lantern(w.x - 0.3, w.y, post_mat, glass)
				"R":
					var wall: Node3D = m.forest.brick_wall(m, w)
					var rune: MeshInstance3D = m.box(Vector3(0.36, 0.36, 0.06), violet)
					rune.position = Vector3(0, 0.9, 0.48)
					wall.add_child(rune)
					roots.append([w, wall])
				"G":
					var g := Node3D.new()
					var b: MeshInstance3D = m.box(Vector3(1.0, 1.4, 1.0), grey)
					b.position = Vector3(0, 0.7, 0)
					g.add_child(b)
					var r2: MeshInstance3D = m.box(Vector3(0.36, 0.36, 0.06), violet)
					r2.position = Vector3(0, 0.9, 0.52)
					g.add_child(r2)
					g.position = Vector3(w.x, 0, w.y)
					m.add_child(g)
					gate_nodes.append(g)
				"h":
					path_tiles.append(w)
					for k in 2: # a pair of pale footprints
						var fp: MeshInstance3D = m.box(Vector3(0.22, 0.04, 0.34), step)
						fp.position = Vector3(w.x - 0.16 + k * 0.32, 0.02, w.y + (0.15 if k == 0 else -0.15))
						fp.visible = false
						m.add_child(fp)
						path_nodes.append(fp)
	var pit: StandardMaterial3D = m.mat_color(Color("#16121e"))
	pit.disable_fog = true # far below, the haze would paint it pale and it would read as more floor
	var deep: MeshInstance3D = m.box(Vector3(W - 2.0, 0.1, 14.0), pit) # wide to the north: the camera looks down through the gap at a slant
	deep.position = Vector3(GARDEN_X + W / 2.0 - 0.5, -2.6, 25.0)
	m.add_child(deep)
	# the camp: a pole with an empty lantern hook, the diary on a stand, a folded blanket by a cold fire
	var wood: Material = m.mat_color(Color("#3b2a1e"))
	var pole: MeshInstance3D = m.box(Vector3(0.12, 1.6, 0.12), wood)
	pole.position = Vector3(road_marks.k.x, 0.8, road_marks.k.y)
	m.add_child(pole)
	var arm: MeshInstance3D = m.box(Vector3(0.4, 0.08, 0.08), wood)
	arm.position = Vector3(road_marks.k.x + 0.15, 1.58, road_marks.k.y)
	m.add_child(arm)
	var hook: MeshInstance3D = m.box(Vector3(0.1, 0.16, 0.1), m.mat_color(Color("#2a2a30")))
	hook.position = Vector3(road_marks.k.x + 0.3, 1.46, road_marks.k.y)
	m.add_child(hook)
	var stand: MeshInstance3D = m.box(Vector3(0.5, 0.45, 0.4), m.mat_color(Color("#5a4632")))
	stand.position = Vector3(road_marks.j.x, 0.22, road_marks.j.y)
	m.add_child(stand)
	var book: MeshInstance3D = m.box(Vector3(0.42, 0.08, 0.32), m.glow_mat(Color("#f2ead8"), 1.0))
	book.position = Vector3(road_marks.j.x, 0.5, road_marks.j.y)
	m.add_child(book)
	blanket = Node3D.new()
	for part in [[Vector3(0.8, 0.22, 0.55), Vector3(0, 0.11, 0), m.mat_color(Color("#8a6a9a"))], [Vector3(0.6, 0.08, 0.6), Vector3(0.0, 0.04, 0.75), m.mat_color(Color("#3a3434"))]]:
		var bb: MeshInstance3D = m.box(part[0], part[2])
		bb.position = part[1]
		blanket.add_child(bb)
	blanket.position = Vector3(road_marks.c.x, 0, road_marks.c.y)
	m.add_child(blanket)

func open_roots() -> void:
	roots_open = true
	for r in roots:
		(r[1] as Node3D).visible = false

func open_gate() -> void:
	gate_open = true
	for g in gate_nodes:
		g.visible = false

func reveal(on: bool) -> void:
	for n in path_nodes:
		n.visible = on

func blanket_look() -> void:
	for b in blanket.get_children():
		b.transparency = 0.45

# light the first n ring posts (0 = all dark)
func set_posts(n: int) -> void:
	for i in posts.size():
		var l: OmniLight3D = posts[i]
		var g: MeshInstance3D = l.get_meta("glass")
		var on := i < n
		l.visible = on
		l.set_meta("dark", not on)
		g.material_override = g.get_meta("lit_mat") if on else StandardMaterial3D.new()
		if not on:
			(g.material_override as StandardMaterial3D).albedo_color = Color("#3a3428")

# the mold: a huge crescent of grey bricks with a glowing violet heart below it (the heart is the target)
func mold(m: Node) -> Node3D:
	var root := Node3D.new()
	var crescent := Node3D.new()
	crescent.name = "crescent"
	root.add_child(crescent)
	var grey: Material = m.glow_mat(Color("#6e6c78"), 0.35) # faintly lit so it reads at night
	var seam: Material = m.glow_mat(Color("#b48cff"), 2.0)
	for k in 15:
		var a := lerpf(-2.2, 2.2, k / 14.0)
		var thick := 1.0 - absf(a) / 2.6
		var b: MeshInstance3D = m.box(Vector3(0.9 * thick + 0.3, 0.9 * thick + 0.3, 0.7), grey)
		b.position = Vector3(sin(a) * 2.6, 2.8 + cos(a) * 2.0, 0)
		b.rotation.z = -a
		crescent.add_child(b)
		if k % 3 == 1:
			var s: MeshInstance3D = m.box(Vector3(0.12, 0.6 * thick + 0.2, 0.74), seam)
			s.position = b.position
			s.rotation.z = -a
			crescent.add_child(s)
	var heart: MeshInstance3D = m.box(Vector3(0.7, 0.7, 0.7), m.glow_mat(Color("#c08cff"), 3.0))
	heart.name = "heart"
	heart.position = Vector3(0, 1.0, 0)
	root.add_child(heart)
	var glow := OmniLight3D.new()
	glow.light_color = Color("#c8a0ff")
	glow.light_energy = 1.6
	glow.omni_range = 6.0
	glow.position = Vector3(0, 1.4, 0)
	root.add_child(glow)
	m.add_child(root)
	return root

func map_tex(width: int) -> ImageTexture:
	var img := Image.create(width, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for z in H:
		for x in W:
			var c := char_at(GARDEN_X + x, z)
			var col := Color("#5a5a50")
			match c:
				"#": continue
				".", "X", "w", "s", "a", "Y": col = Color("#3a3846")
				",", "h": col = Color("#1a1826")
				"R": col = Color("#3a3846") if roots_open else Color("#c8322a")
				"G": col = Color("#3a3846") if gate_open else Color("#9a9aa0")
				"j", "k", "c": col = Color("#bcd6ff")
				"A": col = Color("#ffd27a")
				"L": col = Color("#ffd060")
			img.set_pixel(GARDEN_X + x, z, col)
	return ImageTexture.create_from_image(img)
