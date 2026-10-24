# 굳은 숲 (story step 10): a separate 36x22 area at x >= FOREST_X, built from blocks like the village.
# The trees have hardened into grey brick columns. Three brick walls (W) block the path until the crown
# unwinds them (벽돌 풀기); Noeul waits in the clearing at N for the second duel.
# North-west grove (side puzzle): four moon stones (1-4) are turned with E; when they read crescent to full
# from east to west, as the tablet (t) says, the brick wall V opens onto a niche with a moonkeeper chest (c).
# South valley (rows 22 - 39, after Noeul joins): the grey gate G under her clearing, a live stream (~) crossed
# with the water skip, three memory lamps (o), the empty cloak at C, and three picture doors (B) unwound with
# the crown onto the squirrels' store (m), Noeul's hollow (h) and Hangyeol's pack (k).
# Centre: the old acorn oak (O) behind the squirrel gap (Q), its roots tied by three brick knots (K).
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
#TTTTTTTTTT...TTTTT.....TTT...TTTTT#
#TTTTTTTT.......TT.......TT.g.TTTTT#
#TTTTTTTT.L....gTT..OOO..TT...TTTTT#
#.......T.......TT.KOOOK.TT.L.TTTTT#
S=======W....g..TT..OOO..TT...TTTTT#
#.......T.......Q....K..LTT...TTTTT#
#TTTTTTTT.....L.TTT.j.j.TTT...TTTTT#
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
# the hidden clearing (DESIGN.md "다람쥐 나무"): the gap tree steps aside, the oak's knots come loose one by one
const OAK_C := Vector2(201, 10)
const SQUIRREL_AT := Vector2(195, 12)
const GAP_SHIFT := Vector3(0, 0, -0.62) # the gap tree leans north, off the one-tile path (GPT's note)
const GAP_TILT := -0.25
const ROOT_IN := 0.62                   # a loose root's bar slides this far in toward the trunk
const OAK_SEATS := [Vector2(-1.35, 0.95), Vector2(-0.45, 1.45), Vector2(0.45, 1.45), Vector2(1.35, 0.95), Vector2(1.45, -0.25)] # on the crown's rim
var oak_open := false
var oak_green := false
var oak_gap: Node3D
var oak: Node3D            # metas: crown (Node3D), crown_parts, bark, leaf, branch, twigs
var knots: Array = []      # [{"pos", "node", "root", "seam", "clamps", "open"}] west, east, south
# crowns that fade while Sora stands behind them (GPT playtest 2: the grove's south row hid the stones' floor and
# the tablet): trees in "trees" (forest tiles) go see-through while she is inside "near" (forest tiles)
const FADES := [{"trees": Rect2i(1, 6, 10, 3), "near": Rect2(0.5, 1.5, 10.0, 4.2)}]
var fade_groups: Array = [] # [{"mat", "near", "a"}], one per FADES entry
var oak_hogs: Array = []   # world Vector2 where two brick hedgehogs roll out from under the roots (j, north half)
var warm: Array = []       # narrow glowing seams between the roots, shown once the gap is open

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
	if c == "Q":
		return not oak_open
	if c == "K":
		var k := knot_at(x, z)
		return k.is_empty() or not k.open
	return c == "#" or c == "T" or c in "1234tc~omhkO"

func knot_at(x: float, z: float) -> Dictionary:
	var p := Vector2(round(x), round(z))
	for k in knots:
		if k.pos == p:
			return k
	return {}

func door_at(x: float, z: float) -> Dictionary:
	var p := Vector2(round(x), round(z))
	for d in doors:
		if d.pos == p:
			return d
	return {}

func build(m: Node) -> void:
	var blocks: Array = [] # [Transform3D, Color]
	var fade_blocks: Array = [] # one list per FADES entry
	for f in FADES:
		fade_blocks.append([])
	var lamp_spots: Array = []
	for z in H:
		for x in W:
			var c: String = grid[z][x]
			var w := Vector2(FOREST_X + x, z)
			if c in "SNEVtcGCmhkQ":
				marks[c] = w
			if z > 21 and c in "gwasj": # the valley wakes later, with the grey gate
				south.append({"pos": w, "kind": c})
			elif c == "g":
				goblins.append(w)
			elif c == "w":
				wolves.append(w)
			elif c == "j":
				oak_hogs.append(w)
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
				var tree: Array = blocks
				for k in FADES.size():
					if (FADES[k].trees as Rect2i).has_point(Vector2i(x, z)):
						tree = fade_blocks[k]
				var top: float = m.rnd(1.0, 1.5)
				tree.append([Transform3D(Basis().scaled(Vector3(0.3, 0.9, 0.3)), Vector3(w.x, 0.45, w.y)), Color("#4a4038")])
				var crown := Color("#9a9ca4") if m.rng.randf() < 0.8 else Color("#6f8f5e")
				var cs: float = m.rnd(0.8, 1.05)
				tree.append([Transform3D(Basis().scaled(Vector3(cs, 0.7, cs)), Vector3(w.x + m.rnd(-0.08, 0.08), top, w.y + m.rnd(-0.08, 0.08))), crown.lightened(m.rnd(0, 0.1))])
				tree.append([Transform3D(Basis().scaled(Vector3(cs * 0.55, 0.35, cs * 0.55)), Vector3(w.x, top + 0.5, w.y)), crown.darkened(0.08)])
			elif x >= 16 and x <= 26 and z >= 7 and z <= 13:
				for k in 6: # the clearing was trees: draw as many numbers so everything built after looks as before
					m.rnd()
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
	for k in FADES.size(): # each fade group is its own mesh with its own material, so only it goes see-through
		var fm := StandardMaterial3D.new()
		fm.vertex_color_use_as_albedo = true
		fm.roughness = 0.9
		fm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
		var list: Array = fade_blocks[k]
		var fmm := MultiMesh.new()
		fmm.transform_format = MultiMesh.TRANSFORM_3D
		fmm.use_colors = true
		fmm.mesh = BoxMesh.new()
		fmm.instance_count = list.size()
		for i in list.size():
			fmm.set_instance_transform(i, list[i][0])
			fmm.set_instance_color(i, (list[i][1] as Color).srgb_to_linear())
		var fmi := MultiMeshInstance3D.new()
		fmi.multimesh = fmm
		fmi.material_override = fm
		m.add_child(fmi)
		var near: Rect2 = FADES[k].near
		fade_groups.append({"mat": fm, "near": Rect2(near.position + Vector2(FOREST_X, 0), near.size), "a": 1.0})
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
				walls.append({"pos": p, "node": brick_wall(m, p), "open": false, "glow": approach_glow(m, x, z)})
	build_grove(m)
	build_hollow(m, post_mat, glass)
	build_oak(m)

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

# the clearing: the gap tree, the old oak (thick trunk, grey brick bark, a wide low crown in two layers, a low branch),
# three root knots (a grey root bar clamped by two bricks with red studs), dirt slabs on the way in, warm seams
func build_oak(m: Node) -> void:
	var part := func(size: Vector3, pos: Vector3, mat: Material, parent: Node) -> MeshInstance3D:
		var b: MeshInstance3D = m.box(size, mat)
		b.position = pos
		parent.add_child(b)
		return b
	var trunk_col := Color("#4a4038")
	var grey := Color("#8a8a90")
	oak_gap = Node3D.new()
	part.call(Vector3(0.3, 0.9, 0.3), Vector3(0, 0.45, 0), m.mat_color(tree_col(trunk_col)), oak_gap)
	part.call(Vector3(0.95, 0.7, 0.95), Vector3(0, 1.25, 0), m.mat_color(tree_col(Color("#9a9ca4"))), oak_gap)
	part.call(Vector3(0.52, 0.35, 0.52), Vector3(0, 1.75, 0), m.mat_color(tree_col(Color("#8e9098"))), oak_gap)
	oak_gap.position = Vector3(marks.Q.x, 0, marks.Q.y)
	m.add_child(oak_gap)
	oak = Node3D.new()
	oak.position = Vector3(OAK_C.x, 0, OAK_C.y)
	m.add_child(oak)
	part.call(Vector3(2.0, 1.8, 2.0), Vector3(0, 0.9, 0), m.mat_color(tree_col(trunk_col)), oak)
	var bark_mat: Material = m.mat_color(tree_col(grey))
	var bark: Array = []
	for b in [[Vector3(2.08, 0.62, 0.5), Vector3(0, 1.32, 0.8)], [Vector3(2.08, 0.7, 0.5), Vector3(0, 1.4, -0.8)],
			[Vector3(0.5, 0.56, 1.3), Vector3(0.8, 1.48, 0.1)], [Vector3(0.5, 0.66, 1.3), Vector3(-0.8, 1.38, -0.1)]]:
		bark.append(part.call(b[0], b[1], bark_mat, oak))
	var crown := Node3D.new()
	crown.position = Vector3(0, 2.0, 0) # its base: it breathes by scaling from here
	oak.add_child(crown)
	var low: MeshInstance3D = part.call(Vector3(3.4, 0.6, 3.4), Vector3(0, 0.3, 0), m.mat_color(tree_col(Color("#9a9ca4"))), crown)
	var top: MeshInstance3D = part.call(Vector3(2.2, 0.3, 2.2), Vector3(0, 0.75, 0), m.mat_color(tree_col(Color("#8e9098"))), crown)
	var leaf: MeshInstance3D = part.call(Vector3(0.2, 0.1, 0.2), Vector3(0.55, 1.0, 1.06), m.mat_color(tree_col(Color("#9ad46a"))), oak)
	leaf.visible = false
	var branch := Node3D.new()
	branch.position = Vector3(0.75, 1.1, 0.85)
	branch.rotation.y = atan2(0.6, 0.8) # reaching south-east, toward the camera
	oak.add_child(branch)
	part.call(Vector3(0.16, 0.16, 1.3), Vector3(0, 0, 0.65), m.mat_color(tree_col(trunk_col)), branch)
	var twigs: Array = []
	for k in 2: # two hardened leaves at the tip; they stir after the last knot
		twigs.append(part.call(Vector3(0.22, 0.06, 0.16), Vector3(-0.1 + k * 0.2, 0.08, 1.22), m.mat_color(tree_col(Color("#8a9a80"))), branch))
	oak.set_meta("crown", crown)
	oak.set_meta("crown_parts", [low, top])
	oak.set_meta("bark", bark)
	oak.set_meta("leaf", leaf)
	oak.set_meta("branch", branch)
	oak.set_meta("twigs", twigs)
	var seam_mat: Material = m.glow_mat(Color("#ffb070"), 0.25)
	for z in H:
		for x in W:
			if grid[z][x] != "K":
				continue
			var p := Vector2(FOREST_X + x, z)
			var to := (OAK_C - p).normalized()
			var g := Node3D.new()
			g.position = Vector3(p.x, 0, p.y)
			g.rotation.y = atan2(to.x, to.y) # local +z points at the trunk
			m.add_child(g)
			var root: MeshInstance3D = part.call(Vector3(0.22, 0.2, 1.4), Vector3(0, 0.1, 0.35), m.mat_color(grey), g)
			var seam: MeshInstance3D = part.call(Vector3(0.07, 0.02, 1.1), Vector3(0.17, 0.012, 0.4), seam_mat, g)
			seam.visible = false
			var clamps: Array = []
			for cz in [-0.18, 0.24]:
				clamps.append(part.call(Vector3(0.66, 0.42, 0.3), Vector3(0, 0.21, cz), m.mat_color(grey), g))
				clamps.append(part.call(Vector3(0.14, 0.08, 0.14), Vector3(0, 0.46, cz), m.mat_color(Color("#a8322a")), g))
			knots.append({"pos": p, "node": g, "root": root, "seam": seam, "clamps": clamps, "open": false})
	# narrow broken seams of warmth between the roots, out to the edge of where Sora rests (not one wide plate)
	for a in [40.0, 135.0, 180.0, 225.0, 320.0]:
		var d := Vector2(sin(deg_to_rad(a)), cos(deg_to_rad(a)))
		for seg in [[1.25, 1.95], [2.25, 2.95]]:
			var r: float = (seg[0] + seg[1]) / 2.0
			var s: MeshInstance3D = part.call(Vector3(0.07, 0.02, seg[1] - seg[0]), Vector3(OAK_C.x + d.x * r, 0.012, OAK_C.y + d.y * r), seam_mat, m)
			s.rotation.y = deg_to_rad(a)
			s.visible = false
			warm.append(s)
	# low dirt slabs from the gap to the tree, their tops faintly self-lit so the way shows at night
	var dirt := StandardMaterial3D.new()
	dirt.albedo_color = Color("#827653")
	dirt.roughness = 1.0
	dirt.emission_enabled = true
	dirt.emission = Color("#827653")
	dirt.emission_energy_multiplier = 0.12
	for s in [Vector2(197.1, 12.0), Vector2(197.9, 12.1), Vector2(198.6, 11.7), Vector2(198.3, 10.9), Vector2(199.7, 12.5),
			Vector2(200.6, 12.8), Vector2(202.3, 12.6), Vector2(203.1, 11.8), Vector2(203.6, 10.8)]:
		part.call(Vector3(0.46, 0.03, 0.34), Vector3(s.x, 0.015, s.y), dirt, m)

# the forest's trees are multimesh vertex colours, which read as linear: the oak's own boxes match them this way
func tree_col(c: Color) -> Color:
	return c.srgb_to_linear()

# the clearing's whole look, for loading and tests: the gap stepped aside or not, which knots are loose, green or grey
func oak_look(open: bool, loose: Array, green: bool) -> void:
	oak_open = open
	oak_gap.position = Vector3(marks.Q.x, 0, marks.Q.y) + (GAP_SHIFT if open else Vector3.ZERO)
	oak_gap.rotation.x = GAP_TILT if open else 0.0
	for i in knots.size():
		set_knot(knots[i], bool(loose[i]))
	for s in warm:
		s.visible = open
	(oak.get_meta("leaf") as Node3D).visible = loose.has(true)
	var crown: Node3D = oak.get_meta("crown")
	crown.scale = Vector3.ONE
	set_green(green)

func set_knot(k: Dictionary, loose: bool) -> void:
	k.open = loose
	for c in k.clamps:
		c.visible = not loose
	var root: MeshInstance3D = k.root
	(root.material_override as StandardMaterial3D).albedo_color = Color("#6a4a32") if loose else Color("#8a8a90")
	root.position.z = ROOT_IN if loose else 0.35
	k.seam.visible = loose

# a knot comes loose: the bricks go, the root turns brown (main slides it in toward the trunk)
func untie(i: int) -> MeshInstance3D:
	var k: Dictionary = knots[i]
	set_knot(k, true)
	var root: MeshInstance3D = k.root
	root.position.z = 0.35
	return root

func show_leaf() -> void:
	(oak.get_meta("leaf") as Node3D).visible = true

func set_green(green: bool) -> void:
	oak_green = green
	for b in oak.get_meta("bark"):
		b.visible = not green
	var parts: Array = oak.get_meta("crown_parts")
	(parts[0].material_override as StandardMaterial3D).albedo_color = tree_col(Color("#6f8f5e") if green else Color("#9a9ca4"))
	(parts[1].material_override as StandardMaterial3D).albedo_color = tree_col(Color("#7fa86a") if green else Color("#8e9098"))
	for tw in oak.get_meta("twigs"):
		(tw.material_override as StandardMaterial3D).albedo_color = tree_col(Color("#9ad46a") if green else Color("#8a9a80"))
		tw.rotation.z = 0.0
	(oak.get_meta("branch") as Node3D).rotation.x = -0.12 if green else 0.0

# see-through crown while Sora stands north of the trunk
func crown_fade(a: float) -> void:
	for p in oak.get_meta("crown_parts"):
		if p.transparency != a:
			p.transparency = a

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

# night edges on the floor in front of a brick wall (GPT playtest 2: the approach sank into black at night): a sill
# at the wall's foot, pale edges along the two tiles leading up and a faint pool on the first; self-lit, no lights
func approach_glow(m: Node, x: int, z: int) -> Node3D:
	var g := Node3D.new()
	var edge: Material = m.glow_mat(Color("#f0d49a"), 0.9)
	edge.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	edge.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	var pool: Material = m.glow_mat(Color(1.0, 0.85, 0.55, 0.14), 0.5)
	for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var n: Vector2i = Vector2i(x, z) + d
		if n.x < 0 or n.y < 0 or n.x >= W or n.y >= H or grid[n.y][n.x] in "T#W~":
			continue
		var along := Vector3(d.x, 0, d.y)
		var side := Vector3(d.y, 0, d.x) # perpendicular on the floor
		var sill: MeshInstance3D = m.box(side.abs() * 0.86 + along.abs() * 0.07 + Vector3(0, 0.03, 0), edge)
		sill.position = along * 0.52 + Vector3(0, 0.02, 0)
		g.add_child(sill)
		for s in [-0.43, 0.43]:
			var e: MeshInstance3D = m.box(along.abs() * 2.0 + side.abs() * 0.07 + Vector3(0, 0.03, 0), edge)
			e.position = along * 1.5 + side * s + Vector3(0, 0.02, 0)
			g.add_child(e)
		var p: MeshInstance3D = m.box(Vector3(0.84, 0.01, 0.84), pool)
		p.position = along + Vector3(0, 0.015, 0)
		g.add_child(p)
	g.position = Vector3(FOREST_X + x, 0, z)
	g.visible = false
	m.add_child(g)
	return g

# per frame: wall edges only at night while the wall stands; fade groups ease toward see-through near Sora
func update_looks(me: Vector2, night: bool) -> void:
	for w in walls:
		w.glow.visible = night and not w.open
	for f in fade_groups:
		var want: float = 0.3 if (f.near as Rect2).has_point(me) else 1.0
		if f.a == want:
			continue
		f.a = move_toward(f.a, want, 0.06)
		var mat: StandardMaterial3D = f.mat
		mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED if f.a >= 1.0 else BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1, 1, 1, f.a)

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
			if x >= 16 and x <= 26 and z >= 7 and z <= 13 and not oak_open:
				c = "T" # the hidden clearing is not on the map until the gap opens
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
				"Q": col = Color("#c8783a")
				"O": col = Color("#6f8f5e") if oak_green else Color("#5d6352")
				"K": col = Color("#1e2a24") if knot_at(FOREST_X + x, z).get("open", false) else Color("#c8322a")
			img.set_pixel(FOREST_X + x, z, col)
	return ImageTexture.create_from_image(img)
