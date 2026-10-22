# 굳은 숲 (story step 10): a separate 36x22 area at x >= FOREST_X, built from blocks like the village.
# The trees have hardened into grey brick columns. Three brick walls (W) block the path until the crown
# unwinds them (벽돌 풀기); Noeul waits in the clearing at N for the second duel.
extends RefCounted

const FOREST_X := 180
const W := 36
const H := 22
const ROWS := """####################################
#TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT#
#TTTTTTTTTT.......g..T........TTTTT#
#TTTTTTTTTT.....L....W...L....TTTTT#
#TTTTTTTTTT..........T........TTTTT#
#TTTTTTTTTT...TTTTTTTTTTTTT...TTTTT#
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
#TTTTTTTTT...TTTTTTTTTTT..........T#
#TTTTTTTTT.g.TTTTTTTTTTT..g.......T#
#TTTTTTTTT.L.TTTTTTTTTTT.......N...E
#TTTTTTTTT...TTTTTTTTTTT.L........T#
#TTTTTTTTTTTTTTTTTTTTTTT........g.T#
####################################"""

var grid: Array = []
var marks := {}          # S (entry from the village), N (Noeul's clearing) -> world Vector2
var walls: Array = []    # [{"pos": Vector2, "node": Node3D, "open": bool}]
var goblins: Array = []  # world Vector2 where brick goblins stand guard

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
	return c == "#" or c == "T"

func build(m: Node) -> void:
	var blocks: Array = [] # [Transform3D, Color]
	var lamp_spots: Array = []
	for z in H:
		for x in W:
			var c: String = grid[z][x]
			var w := Vector2(FOREST_X + x, z)
			if c in "SNE":
				marks[c] = w
			if c == "g":
				goblins.append(w)
			if c == "L":
				lamp_spots.append(w)
			var col := Color("#6f7a62") # moss gone dull, half turned to stone
			var hgt := 0.4
			match c:
				"=": col = Color("#a39c90")
				"#": col = Color("#3e3a36")
				"T": col = Color("#5d6352")
			if c == "#":
				hgt = 0.9
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

# a wall of studded toy bricks, red and grey, filling one tile of the path
func brick_wall(m: Node, at: Vector2) -> Node3D:
	var g := Node3D.new()
	var red: Material = m.mat_color(Color("#a8322a"))
	var grey: Material = m.mat_color(Color("#8a8a90"))
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
			img.set_pixel(FOREST_X + x, z, col)
	return ImageTexture.create_from_image(img)
