# 달의 계단 (chapter 8, before the heart of the garden): a 24x30 climb at x >= STAIRS_X from the castle's east gate (S)
# up to the garden (N). Four landings, each asking for a different power of the crown: a brick wall (W) to unwind,
# a deep channel (~) for the water skip, a broken drop (_) crossed by the vent (^, and v back down), and a moon door (D)
# that opens once the three lanterns (o) on the top landing are lit. Sora counts as "on the hill" here.
extends RefCounted

const STAIRS_X := 500
const W := 24
const H := 30
const ROWS := """###########NN###########
##########....##########
##########DDDD##########
###..................###
###..o............o..###
###L..s....o..v.s...L###
###..................###
###__________________###
###__________________###
###__________________###
###__________________###
###........^.........###
###...............a..###
###L.a..............L###
###.........g........###
###..................###
###~~~~~~~~~~~~~~~~~~###
###~~~~~~~~~~~~~~~~~~###
###~~~~~~~~~~~~~~~~~~###
###..................###
###............w.....###
###L..w.............L###
###......b.......w...###
###..................###
##########WWWW##########
###..................###
###...........g......###
###L................L###
###..................###
###########SS###########"""
const VENTS := {"^": Vector2(0, -1), "v": Vector2(0, 1)}

var grid: Array = []
var marks := {}          # S foot (from the castle), N top (to the garden) -> world Vector2
var foes: Array = []     # [world Vector2, kind]
var wall_open := false
var lamps: Array = []    # [{"pos": Vector2, "lit": bool, "glass": MeshInstance3D, "light": OmniLight3D}]
var door_open := false
var wall_nodes: Array = []
var door: Node3D

func _init() -> void:
	for line in ROWS.split("\n"):
		grid.append(line)

func char_at(x: float, z: float) -> String:
	var tx := int(round(x)) - STAIRS_X
	var tz := int(round(z))
	if tx < 0 or tz < 0 or tx >= W or tz >= H:
		return "#"
	return grid[tz][tx]

func vent_at(x: float, z: float) -> Vector2:
	return VENTS.get(char_at(x, z), Vector2.ZERO)

func blocked(x: float, z: float) -> bool:
	var c := char_at(x, z)
	if c == "W":
		return not wall_open
	if c == "D":
		return not door_open
	return c == "#" or c == "~" or c == "_" or c == "o"

func lamps_lit() -> int:
	return lamps.filter(func(l): return l.lit).size()

func build(m: Node) -> void:
	var blocks: Array = []
	var lamp_spots: Array = []
	for z in H:
		for x in W:
			var c: String = grid[z][x]
			var w := Vector2(STAIRS_X + x, z)
			if c == "S" or c == "N":
				if not marks.has(c):
					marks[c] = w + Vector2(0.5, 0)
			if c in "wagsb":
				foes.append([w, c])
			if c == "L":
				lamp_spots.append(w)
			match c:
				"#":
					var near := false
					for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						var nx: int = x + d.x
						var nz: int = z + d.y
						if nx >= 0 and nz >= 0 and nx < W and nz < H and grid[nz][nx] != "#":
							near = true
					if near:
						blocks.append([Transform3D(Basis().scaled(Vector3(1, 1.0, 1)), Vector3(w.x, 0.1, w.y)), Color("#6e6a78").lightened(m.rnd(0, 0.06))])
				"~":
					blocks.append([Transform3D(Basis().scaled(Vector3(1, 0.05, 1)), Vector3(w.x, -0.38, w.y)), Color("#2a5a8a").lightened(m.rnd(0, 0.06))])
				"_":
					if m.rng.randf() < 0.25:
						blocks.append([Transform3D(Basis().scaled(Vector3(0.8, 0.3, 0.8)), Vector3(w.x, -2.4, w.y)), Color("#3a3646")])
				_:
					# pale stone steps that grow lighter, as if moonlit, toward the top
					var up := 1.0 - z / float(H)
					var col := Color("#8a8494").lerp(Color("#c8c4d8"), up)
					if (x + z) % 2 == 0:
						col = col.darkened(0.05)
					blocks.append([Transform3D(Basis().scaled(Vector3(1, 0.4, 1)), Vector3(w.x, -0.2, w.y)), col.lightened(m.rnd(0, 0.04))])
					if VENTS.has(c):
						vent_pad(m, w, VENTS[c])
	m.add_chunks(blocks, STAIRS_X)
	# a stair of three steps at the foot and the top of each landing's way through
	var step: Material = m.mat_color(Color("#b8b4c4"))
	for at in [Vector2(STAIRS_X + 11.5, 28.6), Vector2(STAIRS_X + 11.5, 1.4)]:
		for k in 3:
			var st: MeshInstance3D = m.box(Vector3(2.2, 0.08 + k * 0.08, 0.3), step)
			st.position = Vector3(at.x, (0.08 + k * 0.08) / 2.0, at.y - 0.3 + k * 0.3 * (1 if at.y > 10 else -1))
			m.add_child(st)
	var post_mat: Material = m.mat_color(Color("#3b2a1e"))
	var glass: Material = m.glow_mat(Color("#ffc46a"), 4.0)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	glass.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	for w in lamp_spots:
		m.lantern(w.x - 0.3, w.y, post_mat, glass)
	for z in H:
		for x in W:
			if grid[z][x] == "W":
				wall_nodes.append(m.forest.brick_wall(m, Vector2(STAIRS_X + x, z)))
			if grid[z][x] == "o":
				lamps.append(moon_lamp(m, Vector2(STAIRS_X + x, z)))
	door = Node3D.new()
	var slab: MeshInstance3D = m.box(Vector3(4.0, 1.8, 0.5), m.mat_color(Color("#5a5a66")))
	slab.position = Vector3(0, 0.9, 0)
	door.add_child(slab)
	var moon: MeshInstance3D = m.box(Vector3(0.6, 0.6, 0.1), m.glow_mat(Color("#dfe8ff"), 1.2))
	moon.position = Vector3(0, 1.2, 0.28)
	door.add_child(moon)
	door.position = Vector3(STAIRS_X + 11.5, 0, 2)
	m.add_child(door)

# a tall dark lantern post for the top landing; E lights it
func moon_lamp(m: Node, at: Vector2) -> Dictionary:
	var g := Node3D.new()
	var post: MeshInstance3D = m.box(Vector3(0.3, 1.6, 0.3), m.mat_color(Color("#5a5060")))
	post.position = Vector3(0, 0.8, 0)
	g.add_child(post)
	var glass: MeshInstance3D = m.box(Vector3(0.45, 0.45, 0.45), m.mat_color(Color("#2a2838")))
	glass.position = Vector3(0, 1.8, 0)
	g.add_child(glass)
	var light := OmniLight3D.new()
	light.light_color = Color("#bcd6ff")
	light.light_energy = 2.0
	light.omni_range = 5.0
	light.position = Vector3(0, 2.0, 0)
	light.visible = false
	g.add_child(light)
	g.position = Vector3(at.x, 0, at.y)
	m.add_child(g)
	return {"pos": at, "lit": false, "glass": glass, "light": light, "lit_mat": m.glow_mat(Color("#dfe8ff"), 2.0)}

func light_lamp(l: Dictionary) -> void:
	l.lit = true
	(l.glass as MeshInstance3D).material_override = l.lit_mat
	(l.light as OmniLight3D).visible = true

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

func open_wall() -> void:
	wall_open = true
	for n in wall_nodes:
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
			var col := Color("#4a4658")
			match c:
				"#", "_": col = Color(0, 0, 0, 0)
				"~": col = Color("#2c5a8a")
				"^", "v": col = Color("#bfe6ff")
				"W": col = Color("#4a4658") if wall_open else Color("#c8322a")
				"D": col = Color("#4a4658") if door_open else Color("#dfe8ff")
				"o": col = Color("#ffd27a")
				"N", "S": col = Color("#ffd27a")
				"L": col = Color("#ffd060")
			img.set_pixel(STAIRS_X + x, z, col)
	return ImageTexture.create_from_image(img)
