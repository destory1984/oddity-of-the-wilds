# 굳은 숲 (story step 10): a separate 36x22 area at x >= FOREST_X, built from blocks like the village.
# The trees have hardened into grey brick columns. Three brick walls (W) block the path until the crown
# unwinds them (벽돌 풀기); Noeul waits in the clearing at N for the second duel.
# North-west grove (side puzzle): four moon stones (1-4) are turned with E; when they read crescent to full
# from east to west, as the tablet (t) says, the brick wall V opens onto a niche with a moonkeeper chest (c).
# South valley (rows 22 - 39, after Noeul joins): the grey gate G under her clearing, a live stream (~) crossed
# with the water skip, three memory lamps (o), the empty cloak at C, and three picture doors (B) unwound with
# the crown onto the squirrels' store (m), Noeul's hollow (h) and Hangyeol's pack (k).
extends RefCounted

const FOREST_X := 180
const W := 36
const H := 40
const ROWS := """####################################
#TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT#
#TT..c..TTT.......g..T........TTTTT#
#TTTVTTTTTT.....L....W...L....TTTTT#
#T.1.2.3.4...........T........TTTTT#
#T.t....L.T...TTTTTTTTTTTTT...TTTTT#
#TTTTTTTTTT...TTTTTTTTTTTTT...TTTTT#
#TTTTTTTTTT...TTTTTTTTTTTTT...TTTTT#
#TTTTTTTT.......TTTTTTTTTTT.g.TTTTT#
#TTTTTTTT.L....gTTTTTTTTTTT...TTTTT#
#.......T.......TTTTTTTTTTT.L.TTTTT#
S=======W....g..TTTTTTTTTTT...TTTTT#
#.......T.......TTTTTTTTTTT...TTTTT#
#TTTTTTTT.....L.TTTTTTTTTTT...TTTTT#
#TTTTTTTT.......TTTTTTTTTTT...TTTTT#
#TTTTTTTTT...TTTTTTTTTTTTTTTWTTTTTT#
#TTTTTTTTT...TTTTTTTTTTT.....w....T#
#TTTTTTTTT.g.TTTTTTTTTTT..gw......T#
#TTTTTTTTT.L.TTTTTTTTTTT.......N...E
#TTTTTTTTT...TTTTTTTTTTT.L.....w..T#
#TTTTTTTTTTTTTTTTTTTTTTT........g.T#
############################G#######
#TTTTTTTTTTTTTTTTTTTTTTTTTT...TTTTT#
#TT.....TTTTTTTTTTTTTTTTTT.....TTTT#
#T..o...TTTTTTTTTTTTTTTTT...g...TTT#
#T......===============......j..TTT#
#T..L...TTTTTTTTTTTTTTTT..g......TT#
#TT.....TTTTTTTTTTTTTTTTT........TT#
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
#......TTTTTT...........TTTT.......#
#..o...TTTTTT.....a.....TTTT...w...#
#..j...TTTTTT.....C.....TTTT.......#
#......======...s.......====w...o..#
#L.....TTTTTT...........TTTT.....L.#
#TTTTTTTTTTTTTTBTTBTTBTTTTTTTTTTTTT#
#TTTTTTTTTTTT...TT.TT...TTTTTTTTTTT#
#TTTTTTTTTTTT.m.T.h.T.k.TTTTTTTTTTT#
#TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT#
####################################"""

var grid: Array = []
var marks := {}          # S (entry from the village), N (Noeul's clearing) -> world Vector2
var walls: Array = []    # [{"pos": Vector2, "node": Node3D, "open": bool}]
var goblins: Array = []  # world Vector2 where brick goblins stand guard
var wolves: Array = []   # world Vector2 where brick wolves prowl (w)
const CAGES := [Vector2(12, 4), Vector2(28, 2), Vector2(13, 13), Vector2(10, 19), Vector2(30, 20)] # forest tiles of the squirrel cages
var freed := [false, false, false, false, false]
var stones: Array = []   # [{"pos": Vector2, "phase": int, "top": MeshInstance3D}], west to east
const STONE_START := [1, 3, 0, 2] # phases as found; solved reads 3, 2, 1, 0 (full in the west, crescent in the east)
var solved := false
var gate: Node3D         # the brick wall V in front of the niche
var chest: Node3D
var chest_open := false
var south: Array = []      # [{"pos", "kind"}] the valley's monsters (g a s j w), woken when the grey gate opens
var gate_open := false     # the grey gate G
var grey_gate: Node3D
var mem_lamps: Array = []  # [{"pos", "light", "glass", "lit"}] west-north, west-south, east-south
var doors: Array = []      # [{"pos", "node", "open", "pic"}] squirrel, sunset, moon (west to east)
var boxes: Array = []      # [{"pos", "node", "open"}] the squirrels' store, Noeul's hollow, Hangyeol's pack
const DOOR_PICS := ["다람쥐 꼬리 그림", "해 지는 그림", "초승달 그림"]

func _init() -> void:
	for line in ROWS.split("\n"):
		grid.append(line)

func char_at(x: float, z: float) -> String:
	var tx := int(round(x)) - FOREST_X
	var tz := int(round(z))
	if tx < 0 or tz < 0 or tx >= W or tz >= H:
		return "#"
	return grid[tz][tx]

func wall_at(x: float, z: float) -> Dictionary:
	var p := Vector2(round(x), round(z))
	for w in walls:
		if w.pos == p:
			return w
	return {}

# hardened trees, the fence and closed brick walls block; everything else is walkable ground
func blocked(x: float, z: float) -> bool:
	var c := char_at(x, z)
	if c == "W":
		return not wall_at(x, z).get("open", false)
	if c == "V":
		return not solved
	if c == "G":
		return not gate_open
	if c == "B":
		var dr := door_at(x, z)
		return dr.is_empty() or not dr.open
	return c == "#" or c == "T" or c in "1234tc~omhk"

func door_at(x: float, z: float) -> Dictionary:
	var p := Vector2(round(x), round(z))
	for d in doors:
		if d.pos == p:
			return d
	return {}

func build(m: Node) -> void:
	var blocks: Array = [] # [Transform3D, Color]
	var lamp_spots: Array = []
	for z in H:
		for x in W:
			var c: String = grid[z][x]
			var w := Vector2(FOREST_X + x, z)
			if c in "SNEVtcGCmhk":
				marks[c] = w
			if z > 21 and c in "gwasj": # the valley wakes later, with the grey gate
				south.append({"pos": w, "kind": c})
			elif c == "g":
				goblins.append(w)
			elif c == "w":
				wolves.append(w)
			if c == "L":
				lamp_spots.append(w)
			var col := Color("#6f7a62") # moss gone dull, half turned to stone
			var hgt := 0.4
			match c:
				"=": col = Color("#a39c90")
				"#": col = Color("#3e3a36")
				"T": col = Color("#5d6352")
				"~": col = Color("#2a4a5e") # the stream bed, under its glowing face
			if c == "#":
				hgt = 0.9
			if c == "~":
				hgt = 0.1
			col = col.lightened(m.rnd(0, 0.08))
			blocks.append([Transform3D(Basis().scaled(Vector3(1, hgt, 1)), Vector3(w.x, hgt / 2.0 - 0.4, w.y)), col])
			if c == "T":
				# a tree hardened into toy brick: a dark trunk and a blocky grey crown; a few keep a little green
				var top: float = m.rnd(1.0, 1.5)
				blocks.append([Transform3D(Basis().scaled(Vector3(0.3, 0.9, 0.3)), Vector3(w.x, 0.45, w.y)), Color("#4a4038")])
				var crown := Color("#9a9ca4") if m.rng.randf() < 0.8 else Color("#6f8f5e")
				var cs: float = m.rnd(0.8, 1.05)
				blocks.append([Transform3D(Basis().scaled(Vector3(cs, 0.7, cs)), Vector3(w.x + m.rnd(-0.08, 0.08), top, w.y + m.rnd(-0.08, 0.08))), crown.lightened(m.rnd(0, 0.1))])
				blocks.append([Transform3D(Basis().scaled(Vector3(cs * 0.55, 0.35, cs * 0.55)), Vector3(w.x, top + 0.5, w.y)), crown.darkened(0.08)])
	# chunked 6x6 so each chunk sees only its nearby lanterns (the web renderer lights a mesh with at most 8)
	var chunks := {}
	for bl in blocks:
		var o: Vector3 = bl[0].origin
		var key := Vector2i(int(o.x - FOREST_X) / 6, int(o.z) / 6)
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
	for w in lamp_spots:
		m.lantern(w.x - 0.3, w.y, post_mat, glass)
	for z in H:
		for x in W:
			if grid[z][x] == "W":
				var p := Vector2(FOREST_X + x, z)
				walls.append({"pos": p, "node": brick_wall(m, p), "open": false})
	build_grove(m)
	build_hollow(m, post_mat, glass)

# the south valley: grey gate, stream face, memory lamps (dark until the crown wakes them), picture doors, boxes
func build_hollow(m: Node, post_mat: Material, glass: Material) -> void:
	grey_gate = brick_wall(m, marks.G, Color("#8a8a90"), Color("#9a9aa0"))
	var wet: Material = m.glow_mat(Color("#2f78b8"), 0.6)
	wet.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	wet.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	var face: MeshInstance3D = m.box(Vector3(W - 2.0, 0.02, 2.0), wet)
	face.position = Vector3(FOREST_X + W / 2.0 - 0.5, -0.28, 28.5)
	m.add_child(face)
	for z in H:
		for x in W:
			var c: String = grid[z][x]
			var w := Vector2(FOREST_X + x, z)
			if c == "o":
				m.lantern(w.x - 0.3, w.y, post_mat, glass)
				var l: OmniLight3D = m.lanterns[m.lanterns.size() - 1]
				var g: MeshInstance3D = l.get_meta("glass")
				g.set_meta("lit_mat", g.material_override)
				g.material_override = m.mat_color(Color("#3a3428"))
				l.set_meta("dark", true)
				mem_lamps.append({"pos": w, "light": l, "glass": g, "lit": false})
			elif c == "B":
				var k := doors.size()
				var node := brick_wall(m, w)
				# the picture on a little plaque above the bricks: a squirrel's tail, a sunset, a crescent moon
				var pic: Array = [[Color("#c8783a"), Vector3(0.18, 0.34, 0.04), Vector3(0.12, 0.08, 0)],
					[Color("#ff8a4a"), Vector3(0.5, 0.22, 0.04), Vector3(0, -0.04, 0)],
					[Color("#f4e7b0"), Vector3(0.12, 0.34, 0.04), Vector3(-0.08, 0, 0)]][k]
				var plaque: MeshInstance3D = m.box(Vector3(0.62, 0.42, 0.06), m.mat_color(Color("#3e3a36")))
				plaque.position = Vector3(0, 1.8, 0)
				node.add_child(plaque)
				var mark: MeshInstance3D = m.box(pic[1], m.glow_mat(pic[0], 1.2))
				mark.position = Vector3(0, 1.8, 0.05) + pic[2]
				node.add_child(mark)
				if k == 1: # the sunset's horizon line
					var hz: MeshInstance3D = m.box(Vector3(0.56, 0.04, 0.04), m.mat_color(Color("#5a2a1e")))
					hz.position = Vector3(0, 1.66, 0.06)
					node.add_child(hz)
				doors.append({"pos": w, "node": node, "open": false, "pic": DOOR_PICS[k]})
			elif c in "mhk":
				boxes.append({"pos": w, "node": make_box(m, w, Color("#c8783a") if c == "m" else (Color("#ff8a4a") if c == "h" else Color("#e8d27a"))), "open": false})

func make_box(m: Node, at: Vector2, lid_col: Color) -> Node3D:
	var b := Node3D.new()
	var lid: Material = m.glow_mat(lid_col, 1.2)
	for part in [[Vector3(0.7, 0.4, 0.5), Vector3(0, 0.2, 0), m.mat_color(Color("#4a3a2e"))], [Vector3(0.74, 0.1, 0.54), Vector3(0, 0.45, 0), lid]]:
		var bb: MeshInstance3D = m.box(part[0], part[2])
		bb.position = part[1]
		b.add_child(bb)
	b.position = Vector3(at.x, 0, at.y)
	m.add_child(b)
	return b

func open_gate_look() -> void:
	gate_open = true
	grey_gate.visible = false

func open_door(d: Dictionary) -> void:
	d.open = true
	for ch in d.node.get_children():
		ch.visible = ch.position.y > 1.5 # the plaque stays up, the bricks go

func open_box_look(b: Dictionary) -> void:
	b.open = true
	for ch in b.node.get_children():
		ch.transparency = 0.45

func light_mem(l: Dictionary) -> void:
	l.lit = true
	l.light.set_meta("dark", false)
	l.glass.material_override = l.glass.get_meta("lit_mat")

# the moon-stone grove: four stone posts with a glowing moon on top, a tablet, a wall and a chest
func build_grove(m: Node) -> void:
	var stone: Material = m.mat_color(Color("#8c8a84"))
	var moon: Material = m.glow_mat(Color("#f4e7b0"), 0.8)
	var night: Material = m.mat_color(Color("#1c2338"))
	for k in 4:
		var at := Vector2(FOREST_X + 3 + k * 2, 4)
		var g := Node3D.new()
		var post: MeshInstance3D = m.box(Vector3(0.5, 1.1, 0.5), stone)
		post.position = Vector3(0, 0.55, 0)
		g.add_child(post)
		var plate: MeshInstance3D = m.box(Vector3(0.66, 0.1, 0.66), night) # the dark side of the moon
		plate.position = Vector3(0, 1.15, 0)
		g.add_child(plate)
		var top: MeshInstance3D = m.box(Vector3(0.6, 0.06, 0.6), moon)
		top.position = Vector3(0, 1.22, 0)
		g.add_child(top)
		g.position = Vector3(at.x, 0, at.y)
		m.add_child(g)
		stones.append({"pos": at, "phase": STONE_START[k], "top": top})
		show_phase(stones[k])
	var tab: MeshInstance3D = m.box(Vector3(0.9, 0.7, 0.18), m.mat_color(Color("#6e6a60")))
	tab.position = Vector3(marks.t.x, 0.35, marks.t.y)
	tab.rotation.x = -0.25
	m.add_child(tab)
	gate = brick_wall(m, marks.V)
	chest = Node3D.new()
	var lid: Material = m.glow_mat(Color("#e8d27a"), 1.4)
	for part in [[Vector3(0.8, 0.45, 0.55), Vector3(0, 0.22, 0), m.mat_color(Color("#3a3a5a"))], [Vector3(0.84, 0.1, 0.59), Vector3(0, 0.5, 0), lid]]:
		var b: MeshInstance3D = m.box(part[0], part[2])
		b.position = part[1]
		chest.add_child(b)
	chest.position = Vector3(marks.c.x, 0, marks.c.y)
	m.add_child(chest)

# a moon phase is drawn as how much of the top plate is lit: a sliver, a half, three quarters, whole
func show_phase(st: Dictionary) -> void:
	var w: float = [0.16, 0.3, 0.45, 0.6][st.phase]
	var top: MeshInstance3D = st.top
	top.scale = Vector3(w / 0.6, 1, 1)
	top.position.x = (0.6 - w) / 2.0 # the lit part grows from the east edge

func is_solved() -> bool:
	for k in 4:
		if stones[k].phase != 3 - k:
			return false
	return true

func open_gate() -> void:
	solved = true
	gate.visible = false

func open_chest_look() -> void:
	chest_open = true
	for b in chest.get_children():
		b.transparency = 0.45

# a wall of studded toy bricks, red and grey, filling one tile of the path
func brick_wall(m: Node, at: Vector2, col_a := Color("#a8322a"), col_b := Color("#8a8a90")) -> Node3D:
	var g := Node3D.new()
	var red: Material = m.mat_color(col_a)
	var grey: Material = m.mat_color(col_b)
	for row in 4:
		for k in 2:
			var b: MeshInstance3D = m.box(Vector3(0.48, 0.34, 0.9), red if (row + k) % 2 == 0 else grey)
			b.position = Vector3(-0.25 + k * 0.5 + (0.12 if row % 2 == 1 else 0.0), 0.17 + row * 0.35, 0)
			g.add_child(b)
	for k in 2: # studs on top
		var s: MeshInstance3D = m.box(Vector3(0.16, 0.1, 0.16), red)
		s.position = Vector3(-0.2 + k * 0.4, 1.45, 0)
		g.add_child(s)
	g.position = Vector3(at.x, 0, at.y)
	m.add_child(g)
	return g

func open_wall(w: Dictionary) -> void:
	w.open = true
	w.node.visible = false

func map_tex(width: int) -> ImageTexture:
	var img := Image.create(width, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for z in H:
		for x in W:
			var c: String = grid[z][x]
			var col := Color("#1e2a24")
			match c:
				"#", "T": col = Color(0, 0, 0, 0)
				"=": col = Color("#3a4a44")
				"W": col = Color("#c8322a")
				"L": col = Color("#ffd060")
				"N": col = Color("#9a9aa0")
				"1", "2", "3", "4", "t": col = Color("#8c8a84")
				"V": col = Color("#c8322a")
				"c", "m", "h", "k": col = Color("#bcd6ff")
				"~": col = Color("#2f78b8")
				"G": col = Color("#9a9aa0")
				"B": col = Color("#c8322a")
				"o": col = Color("#ffd060")
			img.set_pixel(FOREST_X + x, z, col)
	return ImageTexture.create_from_image(img)
