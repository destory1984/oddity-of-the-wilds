# 남쪽 호수 (story step 9.5): a separate 30x24 area at x >= LAKE_X, south of the village.
# The lake has hardened into grey brick spikes. Unwinding the brick sluice (D) turns it back to water;
# then Mulgyeol rows Sora from the pier (P) to his island (Q), where a brick turtle (T) guards his hut (h).
# Rows 23 - 39: the water keeper's lower pond below the island (DESIGN.md "물지기의 아랫못", chapter 4): a brick
# weir (Y), the keeper's boat shed (B), two rope posts (R) whose chains (o) only Mulgyeol can swim down to, four sunk
# stepping stones (-), a yard behind a grate (H) with a bricked latch (l), the water clockwork's key (K), the keeper's
# tin (c) and the spillway's brick dam (W).
extends RefCounted

const LAKE_X := 270
const W := 30
const H := 40
const SOUTH_Z := 23 # the weir's row; the lower pond lies below it
const ROWS := """###############S##############
#..............=.............#
#....L.........=.........L...#
#..............=.............#
#...D..........P..........f..#
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
#XXXXXXXXXXiiiiGiiiiXXXXXXXXX#
#XXXXXXXXXXXXXiiiXXXXXXXXXXXX#
##############Y###############
#XXXXXXXXXXXXX.XXXXXXXXXXXXXX#
#XXXXXXXXXXXXX.XXXXXXXXXXXXXX#
#X........L....XXXXXXX########
#X..B..........XXXXXXX#......#
#X.......XXXXXXXXXXXXX#.....L#
#X.......XXXXXXXXXXXXX#l.....#
#X.......XXXX......XXX#...g..#
#X...g...XXXX......===H......#
#X......RXXXX..s..RXXX#......#
#X.......----......XXX#....g.#
#X.g.....XXXX......XXX#....c.#
#X.......XXXX.L.g..XoX#..K...#
#X....a..XXoX......XXX#.XXX.a#
#X.......XXXXXXXXXXXXX#.XXX..#
#XXXXXXXXXXXXXXXXXXXXX###X####
#########################W####"""

var grid: Array = []
var marks := {}          # S entry, P pier, Q island pier, T turtle, h hut, D sluice, G steps down to the grotto, f the fishing spot -> world Vector2
var thawed := false      # the sluice is unwound and the lake is water again
var spikes: MultiMeshInstance3D
var water: MeshInstance3D
var sluice: Node3D
# the lower pond
var ropes: Array = []      # world Vector2 of the rope posts R, west (R1) first
var chains: Array = []     # world Vector2 of the chains o, west (o1) first
var stones: Array = []     # world Vector2 of the four sunk stepping stones
var south_foes: Array = [] # [world Vector2, kind] below the weir; the yard's ambush is x >= 296
var weir_open := false
var stones_up := false
var grate_held := false    # Mulgyeol holds the grate's chain
var latch_open := false    # the bricked latch broke: the grate stays up
var spring_on := false     # the water clockwork turns again
var tin_open := false
var weir: Node3D
var stone_nodes: Array = []
var stone_rims: Node3D
var chain_nodes: Array = []
var grate: Node3D
var pass_glow: Node3D      # lit edges and a lamp along the open grate's way, shown while the grate is up
var latch: Node3D
var spring_key: Node3D
var spring_wheel: Node3D
var tin: Node3D
var dam: Node3D
var flecks: Array = []

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
	match c:
		"-": return not stones_up
		"Y": return not weir_open
		"H": return not (grate_held or latch_open)
		"o", "B", "R", "l", "K", "c", "W": return true
	return c == "#" or c == "X" or (c == "D" and not thawed)

func build(m: Node) -> void:
	var blocks: Array = []
	var spike_list: Array = []
	var lamp_spots: Array = []
	for z in H:
		for x in W:
			var c: String = grid[z][x]
			var w := Vector2(LAKE_X + x, z)
			if c in "SPQThDGfYBlKcWH":
				marks[c] = w
			if c == "L":
				lamp_spots.append(w)
			if c == "R":
				ropes.append(w)
			if c == "o":
				chains.append(w)
			if c == "-":
				stones.append(w)
			if z > SOUTH_Z and c in "gas":
				south_foes.append([w, c])
			if c == "X" or c == "-" or c == "o":
				# hardened water: jagged blue-grey brick, sunk below the shore
				var hgt: float = m.rnd(0.2, 0.7)
				spike_list.append([Transform3D(Basis().scaled(Vector3(0.95, hgt, 0.95)), Vector3(w.x, hgt / 2.0 - 0.45, w.y)), Color("#6f7d8c").lightened(m.rnd(0, 0.12))])
				continue
			var col := Color("#6a9a48")
			var hgt := 0.4
			match c:
				"=", "P", "Q": col = Color("#8a6a44") # boardwalk and piers
				"#": col = Color("#4a3a2a")
				"i", "T", "h", "L", "G", "f": col = Color("#7aa850")
				"g", "a", "s", "R", "B", "l", "K", "c", "H", "Y": col = Color("#7aa850")
				"W": col = Color("#4a3a2a")
			if c == "#" or c == "W":
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
	ropes.sort_custom(func(a, b): return a.x < b.x)
	chains.sort_custom(func(a, b): return a.x < b.x)
	build_pond(m)

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

# ---- the lower pond's props: plain boxes in the lake's colours, with the keeper's brass on the clockwork
# and lamp-coloured glow (#ffc46a) at the shed door, the posts and the grate (GPT's notes, 2026-10-24)
func build_pond(m: Node) -> void:
	var lamp: Material = m.glow_mat(Color("#ffc46a"), 1.6)
	lamp.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	lamp.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	weir = brick_sluice(m, marks.Y)
	boat_shed(m, marks.B, lamp)
	var post_mat: Material = m.mat_color(Color("#5a3a26"))
	var rope_mat: Material = m.mat_color(Color("#d8c08a"))
	for i in ropes.size():
		var r: Vector2 = ropes[i]
		var post: MeshInstance3D = m.box(Vector3(0.2, 1.0, 0.2), post_mat)
		post.position = Vector3(r.x, 0.5, r.y)
		m.add_child(post)
		var ring: MeshInstance3D = m.box(Vector3(0.3, 0.08, 0.3), rope_mat)
		ring.position = Vector3(r.x, 0.75, r.y)
		m.add_child(ring)
		var glow: MeshInstance3D = m.box(Vector3(0.14, 0.14, 0.14), lamp)
		glow.position = Vector3(r.x, 1.08, r.y)
		m.add_child(glow)
		# the rope runs from the post down to its chain, so the post points at it
		var to: Vector2 = chains[i] - r
		var from3 := Vector3(r.x, 0.72, r.y)
		var end3 := Vector3(chains[i].x, -0.2, chains[i].y)
		var mid := (from3 + end3) / 2.0
		var rope: MeshInstance3D = m.box(Vector3(0.05, 0.05, from3.distance_to(end3)), rope_mat)
		rope.position = mid
		rope.rotation = Vector3(-asin((end3.y - from3.y) / from3.distance_to(end3)), atan2(to.x, to.y), 0)
		m.add_child(rope)
	var iron: Material = m.mat_color(Color("#5a5a64"))
	var top: Material = m.mat_color(Color("#9fb4c8"))
	for o in chains:
		var g := Node3D.new()
		for k in 2: # two square links, the second turned a quarter, each four thin boxes with a pale top bar
			var link := Node3D.new()
			link.position = Vector3(0.0, 0.05 + k * 0.28, 0.0)
			link.rotation.y = k * PI / 2.0
			for part in [[Vector3(0.06, 0.36, 0.06), Vector3(-0.15, 0, 0), iron], [Vector3(0.06, 0.36, 0.06), Vector3(0.15, 0, 0), iron],
					[Vector3(0.36, 0.06, 0.06), Vector3(0, -0.15, 0), iron], [Vector3(0.36, 0.07, 0.07), Vector3(0, 0.15, 0), top]]:
				var b: MeshInstance3D = m.box(part[0], part[2])
				b.position = part[1]
				link.add_child(b)
			g.add_child(link)
		g.position = Vector3(o.x, -0.25, o.y)
		m.add_child(g)
		chain_nodes.append(g)
	var stone_top: Material = m.mat_color(Color("#a8a8ae"))
	var stone_side: Material = m.mat_color(Color("#5a5a60"))
	stone_rims = Node3D.new()
	var rim: Material = m.mat_color(Color("#6f8aa0"))
	for s in stones:
		var g := Node3D.new()
		var body: MeshInstance3D = m.box(Vector3(0.9, 0.26, 0.9), stone_side)
		body.position = Vector3(0, -0.15, 0)
		g.add_child(body)
		var face: MeshInstance3D = m.box(Vector3(0.86, 0.04, 0.86), stone_top)
		face.position = Vector3(0, 0.0, 0)
		g.add_child(face)
		g.position = Vector3(s.x, -0.6, s.y)
		m.add_child(g)
		stone_nodes.append(g)
		for part in [[Vector3(0.9, 0.02, 0.06), Vector3(0, 0, -0.42)], [Vector3(0.9, 0.02, 0.06), Vector3(0, 0, 0.42)],
				[Vector3(0.06, 0.02, 0.9), Vector3(-0.42, 0, 0)], [Vector3(0.06, 0.02, 0.9), Vector3(0.42, 0, 0)]]:
			var e: MeshInstance3D = m.box(part[0], rim) # the faint outline of a stone under the water
			e.position = Vector3(s.x, -0.28, s.y) + part[1]
			stone_rims.add_child(e)
	m.add_child(stone_rims)
	# the grate: three thin bars and a crossbar, so the yard shows through the gaps
	grate = Node3D.new()
	var bar: Material = m.mat_color(Color("#7a7468"))
	for k in 3:
		var b: MeshInstance3D = m.box(Vector3(0.1, 1.3, 0.1), bar)
		b.position = Vector3(0, 0.65, -0.32 + k * 0.32)
		grate.add_child(b)
	var cross: MeshInstance3D = m.box(Vector3(0.12, 0.12, 1.0), bar)
	cross.position = Vector3(0, 0.95, 0)
	grate.add_child(cross)
	var gl: MeshInstance3D = m.box(Vector3(0.14, 0.14, 0.14), lamp)
	gl.position = Vector3(-0.45, 1.25, 0.55)
	grate.add_child(gl)
	grate.position = Vector3(marks.H.x, 0, marks.H.y)
	m.add_child(grate)
	# the way through at night (GPT playtest 2026-10-24: bridge, grate and wall read as one black band): self-lit
	# pale edges along the three bridge tiles and the grate's tile, a sill at the yard side and a small lamp box
	pass_glow = Node3D.new()
	var edge: Material = m.glow_mat(Color("#f0d49a"), 0.9)
	edge.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	edge.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	var hx: float = marks.H.x
	var hz: float = marks.H.y
	for side in [-0.43, 0.43]:
		var e: MeshInstance3D = m.box(Vector3(4.0, 0.03, 0.07), edge)
		e.position = Vector3(hx - 1.5, 0.02, hz + side)
		pass_glow.add_child(e)
	var sill: MeshInstance3D = m.box(Vector3(0.07, 0.03, 0.86), edge)
	sill.position = Vector3(hx + 0.46, 0.02, hz)
	pass_glow.add_child(sill)
	var lpost: MeshInstance3D = m.box(Vector3(0.1, 0.8, 0.1), m.mat_color(Color("#5a3a26")))
	lpost.position = Vector3(hx + 0.7, 0.4, hz - 0.62)
	pass_glow.add_child(lpost)
	var lbox: MeshInstance3D = m.box(Vector3(0.22, 0.22, 0.22), lamp)
	lbox.position = Vector3(hx + 0.7, 0.9, hz - 0.62)
	pass_glow.add_child(lbox)
	pass_glow.visible = false
	m.add_child(pass_glow)
	latch = Node3D.new()
	var lb: MeshInstance3D = m.box(Vector3(0.4, 0.4, 0.4), m.mat_color(Color("#8a8a90")))
	lb.position = Vector3(0, 0.2, 0)
	latch.add_child(lb)
	latch.position = Vector3(marks.l.x, 0, marks.l.y)
	m.add_child(latch)
	# the water clockwork's key: a low base, a brass shaft and two wings, with a big cross wheel under the pond
	var brass: Material = m.mat_color(Color("#c8962a"))
	spring_key = Node3D.new()
	var base: MeshInstance3D = m.box(Vector3(0.6, 0.16, 0.6), m.mat_color(Color("#6a6a74")))
	base.position = Vector3(0, 0.08, 0)
	spring_key.add_child(base)
	var spin := Node3D.new()
	spin.name = "spin"
	spring_key.add_child(spin)
	var shaft: MeshInstance3D = m.box(Vector3(0.2, 1.4, 0.2), brass)
	shaft.position = Vector3(0, 0.7, 0)
	spin.add_child(shaft)
	for side in [-1.0, 1.0]:
		var wing: MeshInstance3D = m.box(Vector3(0.8, 0.5, 0.12), brass)
		wing.position = Vector3(side * 0.5, 1.2, 0)
		spin.add_child(wing)
	spring_key.position = Vector3(marks.K.x, 0, marks.K.y)
	m.add_child(spring_key)
	spring_wheel = Node3D.new()
	var dull: Material = m.mat_color(Color("#c8962a").darkened(0.35))
	for k in 2:
		var spoke: MeshInstance3D = m.box(Vector3(2.4, 0.05, 0.18), dull)
		spoke.rotation.y = k * PI / 2.0
		spring_wheel.add_child(spoke)
	spring_wheel.position = Vector3(marks.K.x, -0.28, marks.K.y + 1.5)
	m.add_child(spring_wheel)
	# the keeper's tin, tied to a short post with a string
	tin = Node3D.new()
	var tpost: MeshInstance3D = m.box(Vector3(0.1, 0.9, 0.1), post_mat)
	tpost.position = Vector3(0.2, 0.45, 0)
	tin.add_child(tpost)
	var tbody: MeshInstance3D = m.box(Vector3(0.3, 0.3, 0.3), m.mat_color(Color("#9fb4c8")))
	tbody.position = Vector3(-0.05, 0.15, 0)
	tin.add_child(tbody)
	var lid: MeshInstance3D = m.box(Vector3(0.34, 0.05, 0.34), m.mat_color(Color("#c8d4e0")))
	lid.position = Vector3(-0.05, 0.33, 0)
	lid.name = "lid"
	tin.add_child(lid)
	var string: MeshInstance3D = m.box(Vector3(0.24, 0.03, 0.03), rope_mat)
	string.position = Vector3(0.08, 0.5, 0)
	string.rotation.z = -0.9
	tin.add_child(string)
	tin.position = Vector3(marks.c.x, 0, marks.c.y)
	m.add_child(tin)
	dam = m.forest.brick_wall(m, marks.W)
	dam.scale = Vector3(1, 0.5, 1)
	var white: Material = m.mat_color(Color("#f2f4f8"))
	for k in 6: # white flecks on the spillway once the water runs
		var f: MeshInstance3D = m.box(Vector3(0.14, 0.03, 0.1), white)
		f.visible = false
		m.add_child(f)
		flecks.append(f)

# the keeper's boat shed: a 1.2x hut with a dark door, a wheel plate over it, an oar under the eaves and a lamp
func boat_shed(m: Node, at: Vector2, lamp: Material) -> void:
	var g := Node3D.new()
	var wall: MeshInstance3D = m.box(Vector3(1.9, 1.2, 1.7), m.mat_color(Color("#8a6a44")))
	wall.position = Vector3(0, 0.6, 0)
	g.add_child(wall)
	var roof: MeshInstance3D = m.box(Vector3(2.4, 0.4, 2.1), m.mat_color(Color("#5a4a3a")))
	roof.position = Vector3(0, 1.4, 0)
	g.add_child(roof)
	var door: MeshInstance3D = m.box(Vector3(0.5, 0.85, 0.06), m.mat_color(Color("#2e241c")))
	door.position = Vector3(0, 0.43, 0.87)
	g.add_child(door)
	var plate := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.2
	disc.bottom_radius = 0.2
	disc.height = 0.04
	plate.mesh = disc
	plate.material_override = m.mat_color(Color("#c8b48a"))
	plate.rotation.x = PI / 2.0
	plate.position = Vector3(0, 1.0, 0.88)
	g.add_child(plate)
	var oar: MeshInstance3D = m.box(Vector3(1.1, 0.06, 0.08), m.mat_color(Color("#a07a4a")))
	oar.position = Vector3(0.1, 1.12, 1.0)
	oar.rotation.z = 0.12
	g.add_child(oar)
	var blade: MeshInstance3D = m.box(Vector3(0.28, 0.14, 0.04), m.mat_color(Color("#a07a4a")))
	blade.position = Vector3(0.7, 1.18, 1.0)
	g.add_child(blade)
	var glow: MeshInstance3D = m.box(Vector3(0.16, 0.2, 0.16), lamp)
	glow.position = Vector3(0.45, 0.95, 0.95)
	g.add_child(glow)
	g.position = Vector3(at.x, 0, at.y)
	m.add_child(g)

func open_weir() -> void:
	weir_open = true
	weir.visible = false

func raise_stones(m: Node, slow := true) -> void:
	stones_up = true
	stone_rims.visible = false
	for g in stone_nodes:
		if slow:
			m.create_tween().tween_property(g, "position:y", 0.0, 0.6)
		else:
			g.position.y = 0.0

func set_grate(m: Node, open: bool) -> void:
	m.create_tween().tween_property(grate, "position:y", 1.4 if open else 0.0, 0.5)
	pass_glow.visible = open or latch_open

func break_latch(m: Node) -> void:
	latch_open = true
	latch.visible = false
	set_grate(m, true)

func turn_spring() -> void:
	spring_on = true
	dam.visible = false
	(water.material_override as StandardMaterial3D).albedo_color = Color("#2a5a8a")
	for f in flecks:
		f.visible = true

# set every lower-pond prop for a saved step at once (loads, scenes and tests; both ways)
func south_look(q: int) -> void:
	weir_open = q >= 1
	weir.visible = not weir_open
	stones_up = q >= 2
	stone_rims.visible = not stones_up
	for g in stone_nodes:
		g.position.y = 0.0 if stones_up else -0.6
	grate_held = false
	latch_open = q >= 3
	latch.visible = not latch_open
	grate.position.y = 1.4 if latch_open else 0.0
	pass_glow.visible = latch_open
	spring_on = q >= 4
	dam.visible = not spring_on
	if water != null:
		(water.material_override as StandardMaterial3D).albedo_color = Color("#2a5a8a") if spring_on else Color("#1c4470")
	for f in flecks:
		f.visible = spring_on
	tin_open = q >= 5
	tin.get_node("lid").position = Vector3(-0.25, 0.08, 0.15) if tin_open else Vector3(-0.05, 0.33, 0)

func tin_look() -> void:
	tin_open = true
	tin.get_node("lid").position = Vector3(-0.25, 0.08, 0.15)

# the turning key and wheel, the flecks drifting south over the spillway, the chains bobbing
func tick(dt: float, t: float) -> void:
	if spring_on:
		spring_key.get_node("spin").rotation.y += dt * TAU * 0.8
		spring_wheel.rotation.y += dt * TAU * 0.25
		for k in flecks.size():
			var p := fmod(t * 0.9 + k / float(flecks.size()), 1.0)
			flecks[k].position = Vector3(marks.W.x + sin(k * 2.3) * 0.3, -0.27, marks.W.y - 3.0 + p * 3.0)

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
				"W": col = Color(0, 0, 0, 0)
				"o": col = Color("#2c4a6a")
				"Y": col = col if weir_open else Color("#c8322a")
				"-": col = Color("#8a8a90") if stones_up else Color("#2c4a6a")
				"H": col = Color("#6a5034") if grate_held or latch_open else Color("#9fe0ff")
				"K": col = Color("#f2ead8")
				"B": col = Color("#6a5034")
				"R": col = Color("#6a5034")
				"c": col = col if tin_open else Color("#ff9f5a")
			img.set_pixel(LAKE_X + x, z, col)
	return ImageTexture.create_from_image(img)
