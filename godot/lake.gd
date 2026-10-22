# 남쪽 호수 (story step 9.5): a separate 30x24 area at x >= LAKE_X, south of the village.
# The lake has hardened into grey brick spikes. Unwinding the brick sluice (D) turns it back to water;
# then Mulgyeol rows Sora from the pier (P) to his island (Q), where a brick turtle (T) guards his hut (h).
extends RefCounted

const LAKE_X := 270
const W := 30
const H := 24
const ROWS := """###############S##############
#..............=.............#
#....L.........=.........L...#
#..............=.............#
#...D..........P.............#
#XXXXXXXXXXXXXXXXXXXXXXXXXXXX#
#XXXXXXXXXXXXXXXXXXXXXXXXXXXX#
#XXXXXXXXXXXXXXXXXXXXXXXXXXXX#
#XXXXXXXXXXXXXXXXXXXXXXXXXXXX#
#XXXXXXXXXXXXXXXXXXXXXXXXXXXX#
#XXXXXXXXXXXXXXXXXXXXXXXXXXXX#
#XXXXXXXXXXXXXXXXXXXXXXXXXXXX#
#XXXXXXXXXXXXXXXXXXXXXXXXXXXX#
#XXXXXXXXXXXXXiQiXXXXXXXXXXXX#
#XXXXXXXXXXiiiiiiiiiXXXXXXXXX#
#XXXXXXXXiiiiiiiiiiiiiXXXXXXX#
#XXXXXXXiiLiiiiiiiiiLiiXXXXXX#
#XXXXXXXiiiiiiiTiiiiiiiXXXXXX#
#XXXXXXXiiiiiiiiiiiiiiiXXXXXX#
#XXXXXXXiiiihiiiiiiiiiiXXXXXX#
#XXXXXXXXiiiiiiiiiiiiiXXXXXXX#
#XXXXXXXXXXiiiiiiiiiXXXXXXXXX#
#XXXXXXXXXXXXXiiiXXXXXXXXXXXX#
##############################"""

var grid: Array = []
var marks := {}          # S entry, P pier, Q island pier, T turtle, h hut, D sluice -> world Vector2
var thawed := false      # the sluice is unwound and the lake is water again
var spikes: MultiMeshInstance3D
var water: MeshInstance3D
var sluice: Node3D

func _init() -> void:
	for line in ROWS.split("\n"):
		grid.append(line)

func char_at(x: float, z: float) -> String:
	var tx := int(round(x)) - LAKE_X
	var tz := int(round(z))
	if tx < 0 or tz < 0 or tx >= W or tz >= H:
		return "#"
	return grid[tz][tx]

# the fence, the lake (hardened or not: it is deep either way) and the sluice block
func blocked(x: float, z: float) -> bool:
	var c := char_at(x, z)
	return c == "#" or c == "X" or (c == "D" and not thawed)

func build(m: Node) -> void:
	var blocks: Array = []
	var spike_list: Array = []
	var lamp_spots: Array = []
	for z in H:
		for x in W:
			var c: String = grid[z][x]
			var w := Vector2(LAKE_X + x, z)
			if c in "SPQThD":
				marks[c] = w
			if c == "L":
				lamp_spots.append(w)
			if c == "X":
				# hardened water: jagged blue-grey brick, sunk below the shore
				var hgt: float = m.rnd(0.2, 0.7)
				spike_list.append([Transform3D(Basis().scaled(Vector3(0.95, hgt, 0.95)), Vector3(w.x, hgt / 2.0 - 0.45, w.y)), Color("#6f7d8c").lightened(m.rnd(0, 0.12))])
				continue
			var col := Color("#6a9a48")
			var hgt := 0.4
			match c:
				"=", "P", "Q": col = Color("#8a6a44") # boardwalk and piers
				"#": col = Color("#4a3a2a")
				"i", "T", "h", "L": col = Color("#7aa850")
			if c == "#":
				hgt = 0.9
			col = col.lightened(m.rnd(0, 0.08))
			blocks.append([Transform3D(Basis().scaled(Vector3(1, hgt, 1)), Vector3(w.x, hgt / 2.0 - 0.4, w.y)), col])
	m.add_chunks(blocks, LAKE_X)
	spikes = m.multimesh_of(spike_list)
	water = MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(W - 2, 0.1, H - 6)
	water.mesh = plane
	var wm: StandardMaterial3D = m.mat_color(Color("#1c4470"), 0.15)
	wm.metallic_specular = 0.8
	water.material_override = wm
	water.position = Vector3(LAKE_X + W / 2.0 - 0.5, -0.35, 5 + (H - 6) / 2.0 - 0.5)
	water.visible = false
	m.add_child(water)
	var post_mat: Material = m.mat_color(Color("#3b2a1e"))
	var glass: Material = m.glow_mat(Color("#ffc46a"), 4.0)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	glass.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	for w in lamp_spots:
		m.lantern(w.x - 0.3, w.y, post_mat, glass)
	sluice = brick_sluice(m, marks.D)
	hut(m, marks.h)

# the sluice gate, bricked solid like everything else
func brick_sluice(m: Node, at: Vector2) -> Node3D:
	var g := Node3D.new()
	var grey: Material = m.mat_color(Color("#8a8a90"))
	var blue: Material = m.mat_color(Color("#4a6a9a"))
	for row in 4:
		for k in 3:
			var b: MeshInstance3D = m.box(Vector3(0.32, 0.34, 0.9), grey if (row + k) % 2 == 0 else blue)
			b.position = Vector3(-0.33 + k * 0.33, 0.17 + row * 0.35, 0)
			g.add_child(b)
	g.position = Vector3(at.x, 0, at.y)
	m.add_child(g)
	return g

# Mulgyeol's little round hut with a reed roof
func hut(m: Node, at: Vector2) -> void:
	var g := Node3D.new()
	var wall: MeshInstance3D = m.box(Vector3(1.6, 1.0, 1.4), m.mat_color(Color("#c8b48a")))
	wall.position = Vector3(0, 0.5, 0)
	g.add_child(wall)
	var roof: MeshInstance3D = m.box(Vector3(1.9, 0.5, 1.7), m.mat_color(Color("#a8883a")))
	roof.position = Vector3(0, 1.2, 0)
	g.add_child(roof)
	var door: MeshInstance3D = m.box(Vector3(0.4, 0.7, 0.06), m.mat_color(Color("#5a3a26")))
	door.position = Vector3(0, 0.35, 0.72)
	g.add_child(door)
	g.position = Vector3(at.x, 0, at.y - 0.4)
	m.add_child(g)
	m.rocks.append({"x": at.x, "z": at.y - 0.4, "r": 0.95})

func thaw() -> void:
	thawed = true
	sluice.visible = false
	spikes.visible = false
	water.visible = true

func map_tex(width: int) -> ImageTexture:
	var img := Image.create(width, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for z in H:
		for x in W:
			var c: String = grid[z][x]
			var col := Color("#16302e")
			match c:
				"#": col = Color(0, 0, 0, 0)
				"X": col = Color("#2c4a6a") if thawed else Color("#4a5260")
				"=", "P", "Q": col = Color("#6a5034")
				"L": col = Color("#ffd060")
				"T": col = Color("#c8322a")
			img.set_pixel(LAKE_X + x, z, col)
	return ImageTexture.create_from_image(img)
