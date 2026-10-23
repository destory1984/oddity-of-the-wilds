# 구름 둔덕 (chapter 6 side area): brick islands floating over clouds at x >= CLOUD_X, reached from the updraft (U)
# on the hill's north edge once the hawk is beaten. The gaps (_) cannot be walked; stepping onto a wind vent
# (> < ^ v) blows Sora across to the next island. The brick scarecrow (K) waits on the big east island and
# guards the wind feather; a chest (c) sits on the small north island. Sora counts as "on the hill" up here.
# South of the entry island an unseen cloud path (h) crosses open air (,): E shows it for 3 s, and a step off it
# drops Sora back onto the entry island. The islet at its end holds the cloud shard (q).
extends RefCounted

const CLOUD_X := 390
const W := 32
const H := 20
const ROWS := """################################
#________........______________#
#________......c.______________#
#________..v.....______________#
#___________________...........#
#___________________...........#
#___________________........a..#
#_________..^...____...........#
#.....____....a.____...........#
#.....____......____...........#
#.S..>____...g.>____.....K.....#
#.....____......____...........#
#.....____<.....____<..........#
#,h,,,,___......____...........#
#,hhh,,_____________....g......#
#,,,h,,_____________...........#
#,hhh,,_____________...........#
#.....,________________________#
#..q..,________________________#
################################"""
const VENTS := {">": Vector2(1, 0), "<": Vector2(-1, 0), "^": Vector2(0, -1), "v": Vector2(0, 1)}

var grid: Array = []
var marks := {}          # S entry/exit, K scarecrow, c chest -> world Vector2
var foes: Array = []     # [world Vector2, archer]
var chest: Node3D
var updraft: Node3D      # the glowing vent on the hill that lifts Sora up here
var path_tiles: Array = []  # world Vector2 of the unseen path
var path_nodes: Array = []  # their glowing slabs, shown only while revealed
var reveal_t := 0.0
var shard_chest: Node3D
var shard_open := false

func _init() -> void:
	for line in ROWS.split("\n"):
		grid.append(line)

func char_at(x: float, z: float) -> String:
	var tx := int(round(x)) - CLOUD_X
	var tz := int(round(z))
	if tx < 0 or tz < 0 or tx >= W or tz >= H:
		return "#"
	return grid[tz][tx]

func vent_at(x: float, z: float) -> Vector2:
	return VENTS.get(char_at(x, z), Vector2.ZERO)

# the fence, the open sky between islands and the chest block; vents are floor
func blocked(x: float, z: float) -> bool:
	var c := char_at(x, z)
	return c == "#" or c == "_" or c == "c" or c == "q"

func build(m: Node) -> void:
	var blocks: Array = []
	var clouds: Array = []
	var vent_mat: Material = m.glow_mat(Color("#8fc8f0"), 0.5)
	var arrow_mat: Material = m.mat_color(Color("#1e3a66")) # dark chevrons read best on the pale pad
	for z in H:
		for x in W:
			var c: String = grid[z][x]
			var w := Vector2(CLOUD_X + x, z)
			if c in "SKcq":
				marks[c] = w
			if c == "h":
				path_tiles.append(w)
			if c == "g" or c == "a":
				foes.append([w, c == "a"])
			if c == "_" or c == "#" or c == "," or c == "h":
				if m.rng.randf() < 0.3: # puffs of cloud far below
					var s: float = m.rnd(0.8, 1.6)
					clouds.append([Transform3D(Basis().scaled(Vector3(s * 1.4, s * 0.5, s)), Vector3(w.x + m.rnd(-0.3, 0.3), m.rnd(-3.2, -2.2), w.y)), Color("#f4f6fa")])
				continue
			# an island tile: grass on top of a thick clod of earth hanging in the air
			blocks.append([Transform3D(Basis().scaled(Vector3(1, 0.4, 1)), Vector3(w.x, -0.2, w.y)), Color("#6a9448").lightened(m.rnd(0, 0.06))])
			blocks.append([Transform3D(Basis().scaled(Vector3(0.96, 1.2, 0.96)), Vector3(w.x, -1.0, w.y)), Color("#8a6a48").darkened(m.rnd(0, 0.1))])
			if VENTS.has(c):
				var d: Vector2 = VENTS[c]
				var pad: MeshInstance3D = m.box(Vector3(0.9, 0.06, 0.9), vent_mat)
				pad.position = Vector3(w.x, 0.03, w.y)
				m.add_child(pad)
				# an arrow the way the wind blows: a shaft and two head strokes (a box's long side is its x axis)
				var tip := w + d * 0.3
				for part in [[w - d * 0.05, d, 0.55], [tip + d.rotated(2.36) * 0.14, d.rotated(2.36), 0.3], [tip + d.rotated(-2.36) * 0.14, d.rotated(-2.36), 0.3]]:
					var at: Vector2 = part[0]
					var dir: Vector2 = part[1]
					var bar: MeshInstance3D = m.box(Vector3(part[2], 0.05, 0.1), arrow_mat)
					bar.position = Vector3(at.x, 0.08, at.y)
					bar.rotation.y = atan2(-dir.y, dir.x)
					m.add_child(bar)
	m.add_chunks(blocks, CLOUD_X)
	m.multimesh_of(clouds)
	chest = Node3D.new()
	var lid: Material = m.glow_mat(Color("#f2ead8"), 1.2)
	for part in [[Vector3(0.8, 0.45, 0.55), Vector3(0, 0.22, 0), m.mat_color(Color("#6a8ab0"))], [Vector3(0.84, 0.1, 0.59), Vector3(0, 0.5, 0), lid]]:
		var b: MeshInstance3D = m.box(part[0], part[2])
		b.position = part[1]
		chest.add_child(b)
	chest.position = Vector3(marks.c.x, 0, marks.c.y)
	m.add_child(chest)
	var slab_mat: Material = m.glow_mat(Color("#bfe6ff"), 0.6)
	for w in path_tiles:
		var sl: MeshInstance3D = m.box(Vector3(0.96, 0.08, 0.96), slab_mat)
		sl.position = Vector3(w.x, 0.0, w.y)
		sl.visible = false
		m.add_child(sl)
		path_nodes.append(sl)
	shard_chest = Node3D.new()
	for part in [[Vector3(0.8, 0.45, 0.55), Vector3(0, 0.22, 0), m.mat_color(Color("#e8eef8"))], [Vector3(0.84, 0.1, 0.59), Vector3(0, 0.5, 0), m.glow_mat(Color("#bfe6ff"), 1.0)]]:
		var b: MeshInstance3D = m.box(part[0], part[2])
		b.position = part[1]
		shard_chest.add_child(b)
	shard_chest.position = Vector3(marks.q.x, 0, marks.q.y)
	m.add_child(shard_chest)

# the updraft on the hill: a pale ring of light at the hill's U
func build_updraft(m: Node, at: Vector2) -> void:
	updraft = Node3D.new()
	var pad: MeshInstance3D = m.box(Vector3(1.0, 0.06, 1.0), m.glow_mat(Color("#bfe6ff"), 1.4))
	pad.position = Vector3(0, 0.03, 0)
	updraft.add_child(pad)
	for k in 3:
		var wisp: MeshInstance3D = m.box(Vector3(0.08, 0.6, 0.08), m.glow_mat(Color("#ffffff"), 1.0))
		wisp.position = Vector3(cos(k * 2.1) * 0.3, 0.5 + k * 0.3, sin(k * 2.1) * 0.3)
		updraft.add_child(wisp)
	updraft.position = Vector3(at.x, 0, at.y)
	m.add_child(updraft)

func reveal(on: bool) -> void:
	for n in path_nodes:
		n.visible = on

func shard_look() -> void:
	shard_open = true
	for b in shard_chest.get_children():
		b.transparency = 0.45

func opened_look() -> void:
	for b in chest.get_children():
		b.transparency = 0.45

func map_tex(width: int) -> ImageTexture:
	var img := Image.create(width, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for z in H:
		for x in W:
			var c: String = grid[z][x]
			var col := Color("#3a5a30")
			match c:
				"#", "_": col = Color(0, 0, 0, 0)
				">", "<", "^", "v": col = Color("#bfe6ff")
				",", "h": col = Color(0, 0, 0, 0) # the unseen path stays off the map too
				"q": col = Color("#e8eef8")
				"c": col = Color("#f2ead8")
				"K": col = Color("#c8322a")
			img.set_pixel(CLOUD_X + x, z, col)
	return ImageTexture.create_from_image(img)
