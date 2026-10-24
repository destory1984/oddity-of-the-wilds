# 갈대늪 side quest (chapter 1): three scraps of the moonkeepers' old map lie in far corners of the marsh.
# Walking over a scrap picks it up. Nothing here carries an OmniLight3D: the marsh ground is one mesh and the
# web renderer lights a mesh with at most 8 lights, so glow comes from emissive materials and bloom only.
# With all three the map shows where a moonkeeper buried a chest;
# the chest rises out of the ground there and Space opens it for a lasting reward.
# Errand 5 (Kongal's kid): fireflies come out over the marsh at night; catch five to fill the kid's jar.
extends RefCounted

const STORY := preload("res://story_lines.gd")

const SCRAPS := [Vector2(41, 4), Vector2(4, 33), Vector2(44, 43)] # NE plateau, west reeds, south-east bank
const CHEST_AT := Vector2(36, 31)
const REWARD_ATK := 4
const REWARD_HP := 20
const REWARD_GOLD := 150

var found := [false, false, false]
var nodes: Array = []
var chest: Node3D
var chest_open := false

const FLIES := [Vector2(6, 24), Vector2(14, 30), Vector2(34, 33), Vector2(38, 21), Vector2(19, 13), Vector2(11, 41)]
const FLIES_NEEDED := 5
var flies: Array = []      # [{"home": Vector2, "node": Node3D, "caught": bool}]
var flies_on := false      # Sora is on the firefly errand

# moonflowers open only on nights when the moon is more than half full (5 of every 8 nights)
const FLOWERS := [Vector2(35, 22), Vector2(12, 43), Vector2(40, 36)]
var flowers: Array = []    # Node3D per flower
var picked := [false, false, false]

# ---- 깨어난 물가 (chapter 1): from where Sora woke a line of pressed reeds runs to a reed basket stuck in the mud at
# the river's edge, the moonkeepers' lantern basket the crown came down in. After the Brick King, at night, Bori's
# never-lit lantern floats in it down the river to the lake's island; three brick snags hold it on the way.
const BASKET_AT := Vector2(20, 19)
const REEDS := [Vector2(16, 20), Vector2(17, 20), Vector2(18, 19), Vector2(19, 19)]
const SHORE_WAVES := [[Vector2(17, 18), Vector2(18, 22)], [Vector2(16, 19), Vector2(14, 21)]] # the second ends with an archer
const FLOAT_END := Vector2(24, 36.3)
const SNAGS := [Vector2(19.6, 23.5), Vector2(19.4, 28.5), Vector2(21.9, 32.5)]
const SNAG_FOES := [[Vector2(16, 23), Vector2(15, 25)], [Vector2(16, 28), Vector2(16, 30)], [Vector2(18, 31), Vector2(15, 33)]] # the last ends with an archer
const WATER_Y := -0.22
var basket: Node3D         # the basket half sunk in the mud at B, with its mud bricks
var float_node: Node3D     # the same basket with Bori's lantern, floating
var glint_node: Node3D     # 3 short glints on the water behind it
var float_glass: MeshInstance3D
var glass_dull: Material
var glass_lit: StandardMaterial3D
var snag_nodes: Array = []
var path: Array = []       # points the basket floats along
var path_d: Array = []     # distance along the path at each point
var snag_d: Array = []     # distance along the path where each snag holds it
var landed := false        # the lantern rests off the island

func count() -> int:
	return found.filter(func(f): return f).size()

func build(m: Node) -> void:
	var paper: Material = m.glow_mat(Color("#f2e2b0"), 0.6) # a faint glow so it shows above the grass
	var ink: Material = m.mat_color(Color("#5a3a22"))
	for i in SCRAPS.size():
		var p: Vector2 = SCRAPS[i]
		var g := Node3D.new()
		m.clear_vegetation(p, 0.9)
		var sheet: MeshInstance3D = m.box(Vector3(0.7, 0.03, 0.52), paper)
		g.add_child(sheet)
		var mark: MeshInstance3D = m.box(Vector3(0.14, 0.035, 0.14), ink) # the crescent mark, a dark square from above
		mark.position = Vector3(0.1, 0.01, -0.06)
		g.add_child(mark)
		g.position = Vector3(p.x, m.height_at(p.x, p.y) + 0.25, p.y)
		g.rotation = Vector3(0.5, 0.4 + i, 0) # tipped toward the camera
		m.add_child(g)
		nodes.append(g)
	chest = Node3D.new()
	var wood: Material = m.mat_color(Color("#3a3a5a"))
	var gold: Material = m.glow_mat(Color("#e8d27a"), 1.6)
	for part in [[Vector3(0.9, 0.5, 0.6), Vector3(0, 0.25, 0), wood], [Vector3(0.94, 0.12, 0.64), Vector3(0, 0.55, 0), gold],
			[Vector3(0.16, 0.16, 0.04), Vector3(0, 0.36, 0.31), gold]]:
		var b: MeshInstance3D = m.box(part[0], part[2])
		b.position = part[1]
		chest.add_child(b)
	chest.position = Vector3(CHEST_AT.x, m.height_at(CHEST_AT.x, CHEST_AT.y), CHEST_AT.y)
	chest.visible = false
	m.add_child(chest)
	var fly_mat: Material = m.glow_mat(Color("#b8f040"), 1.6) # green, not white, so they stand out from the drifting motes
	for p in FLIES:
		var f := Node3D.new()
		var dot: MeshInstance3D = m.box(Vector3(0.16, 0.16, 0.16), fly_mat)
		f.add_child(dot)
		f.visible = false
		m.add_child(f)
		flies.append({"home": p, "node": f, "caught": false})
	build_flowers(m)
	build_shore(m)

func build_flowers(m: Node) -> void:
	var petal := StandardMaterial3D.new()
	petal.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	petal.albedo_color = Color("#eef4ff")
	var heart: Material = m.glow_mat(Color("#ffe89a"), 1.0)
	var stem: Material = m.mat_color(Color("#4a7a3a"))
	for p in FLOWERS:
		m.clear_vegetation(p, 0.8)
		var g := Node3D.new()
		var st: MeshInstance3D = m.box(Vector3(0.06, 0.5, 0.06), stem)
		st.position = Vector3(0, 0.25, 0)
		g.add_child(st)
		for k in 5:
			var a := k * TAU / 5.0
			var pt: MeshInstance3D = m.box(Vector3(0.18, 0.04, 0.1), petal)
			pt.position = Vector3(cos(a) * 0.12, 0.52, sin(a) * 0.12)
			pt.rotation.y = -a
			g.add_child(pt)
		var c: MeshInstance3D = m.box(Vector3(0.08, 0.06, 0.08), heart)
		c.position = Vector3(0, 0.55, 0)
		g.add_child(c)
		g.position = Vector3(p.x, m.height_at(p.x, p.y), p.y)
		g.visible = false
		m.add_child(g)
		flowers.append(g)

func picked_count() -> int:
	return picked.count(true)

func update_flowers(m: Node, blooming: bool) -> void:
	for i in flowers.size():
		var f: Node3D = flowers[i]
		f.visible = blooming and not picked[i]
		if not f.visible:
			continue
		f.rotation.y += 0.004
		if Vector2(m.player.x, m.player.z).distance_to(FLOWERS[i]) < 0.9:
			picked[i] = true
			f.visible = false
			m.burst(f.position + Vector3(0, 0.5, 0), Color("#eef4ff"), 14, 1.2)
			m.sfx(880 + picked_count() * 110, 0.2, "sine", 0.2)
			if picked_count() == 1:
				m.show_story("", STORY.MOONFLOWER_FIRST)
			elif picked_count() == FLOWERS.size():
				m.toast("달꽃 세 송이를 모았다. 보리 할머니께 가져가자")
			else:
				m.toast(m.tr("달꽃 %d/3") % picked_count())
			m.save_game()

func caught() -> int:
	return flies.filter(func(f): return f.caught).size()

# fireflies drift in slow loops around their spot; only at night and only while the errand is on
func update_flies(m: Node, night_now: bool) -> void:
	for i in flies.size():
		var f: Dictionary = flies[i]
		var n: Node3D = f.node
		n.visible = flies_on and night_now and not f.caught
		if not n.visible:
			continue
		var a: float = m.t * 0.7 + i * 1.3
		var at: Vector2 = f.home + Vector2(cos(a), sin(a * 1.3)) * 1.2
		n.position = Vector3(at.x, m.height_at(at.x, at.y) + 0.8 + sin(m.t * 3.0 + i) * 0.2, at.y)
		if Vector2(m.player.x, m.player.z).distance_to(at) < 1.0:
			f.caught = true
			n.visible = false
			m.burst(n.position, Color("#d8ff7a"), 10, 1.0)
			m.sfx(1046 + caught() * 60, 0.12, "triangle", 0.18)
			var k := caught()
			if k >= FLIES_NEEDED:
				flies_on = false
				m.fly_q = 2
				m.toast("반딧불을 모두 잡았다. 마을의 콩알에게 가져가자")
			else:
				m.toast(m.tr("반딧불 %d/%d") % [k, FLIES_NEEDED])
			m.save_game()

# after a load: hide the scraps already taken, raise the chest if the map is whole
func restore(saved_found: Array, saved_open: bool) -> void:
	for i in mini(saved_found.size(), found.size()):
		found[i] = bool(saved_found[i])
		nodes[i].visible = not found[i]
	chest_open = saved_open
	chest.visible = count() == 3
	if chest_open:
		open_look()

func open_look() -> void:
	for b in chest.get_children():
		if b is MeshInstance3D:
			b.transparency = 0.45

# called every frame while Sora is outside in the marsh
func update(m: Node) -> void:
	for i in nodes.size():
		var n: Node3D = nodes[i]
		if found[i]:
			continue
		var p: Vector2 = SCRAPS[i]
		n.position.y = m.height_at(p.x, p.y) + 0.5 + sin(m.t * 2.0 + i) * 0.05
		n.rotation.y += 0.01
		if Vector2(m.player.x, m.player.z).distance_to(p) < 1.0:
			pick(m, i)
	if chest.visible and not chest_open:
		chest.rotation.y = sin(m.t * 0.8) * 0.05

func pick(m: Node, i: int) -> void:
	found[i] = true
	nodes[i].visible = false
	m.burst(Vector3(m.player.x, m.height_at(m.player.x, m.player.z) + 0.6, m.player.z), Color("#ffe2a0"), 18, 1.5)
	m.sfx(698, 0.2, "triangle", 0.22)
	var n := count()
	if n == 1:
		m.show_story("", STORY.SCRAP_FIRST)
	elif n == 3:
		chest.visible = true
		m.burst(Vector3(CHEST_AT.x, m.height_at(CHEST_AT.x, CHEST_AT.y) + 0.6, CHEST_AT.y), Color("#bcd6ff"), 30, 2.5)
		m.show_story("", STORY.SCRAP_ALL)
	else:
		m.toast(m.tr("지도 조각 %d/3") % n)
	m.save_game()

func near_chest(m: Node) -> bool:
	return chest.visible and not chest_open and Vector2(m.player.x, m.player.z).distance_to(CHEST_AT) < 1.6

func open_chest(m: Node) -> void:
	chest_open = true
	open_look()
	m.player.atk += REWARD_ATK
	m.player.max_hp += REWARD_HP
	m.player.hp = float(m.player.max_hp)
	m.player.gold += REWARD_GOLD
	m.burst(Vector3(CHEST_AT.x, m.height_at(CHEST_AT.x, CHEST_AT.y) + 0.8, CHEST_AT.y), Color("#e8d27a"), 40, 3.0)
	m.sfx(784, 0.12, "triangle", 0.25)
	m.show_story("", STORY.MOON_CHEST)
	m.toast(m.tr("공격력 +%d, 최대 체력 +%d, 금화 %d") % [REWARD_ATK, REWARD_HP, REWARD_GOLD])
	m.save_game()

# ---- 깨어난 물가: everything is boxes and self-lit glass; no OmniLight3D (the ground mesh takes 8 lights at most)
func float_path() -> Array:
	var pts: Array = [Vector2(21, 19)]
	var z := 19.5
	while z <= 34.01:
		pts.append(Vector2(24.0 + sin(z * 0.18) * 5.0, z)) # the river's middle line
		z += 0.5
	pts.append(FLOAT_END)
	return pts

func path_len() -> float:
	return path_d[path_d.size() - 1]

func float_at(d: float) -> Vector2:
	for i in range(1, path.size()):
		if d <= path_d[i]:
			var a: Vector2 = path[i - 1]
			var b: Vector2 = path[i]
			var k: float = (d - path_d[i - 1]) / maxf(0.001, path_d[i] - path_d[i - 1])
			return a.lerp(b, clampf(k, 0.0, 1.0))
	return path[path.size() - 1]

# a reed basket: a flat octagon, a dark rim, a darker inside so it reads as something that holds, 6 weave strips
func make_basket(m: Node) -> Node3D:
	var g := Node3D.new()
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.36
	cm.bottom_radius = 0.3
	cm.height = 0.2
	cm.radial_segments = 8
	cm.rings = 1
	body.mesh = cm
	body.material_override = m.mat_color(Color("#b89a5a"))
	g.add_child(body)
	var rim := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.38
	rm.bottom_radius = 0.38
	rm.height = 0.04
	rm.radial_segments = 8
	rm.rings = 1
	rim.mesh = rm
	rim.material_override = m.mat_color(Color("#8a6e3a"))
	rim.position.y = 0.1
	g.add_child(rim)
	var inner := MeshInstance3D.new()
	var im := CylinderMesh.new()
	im.top_radius = 0.3
	im.bottom_radius = 0.3
	im.height = 0.012
	im.radial_segments = 8
	im.rings = 1
	inner.mesh = im
	inner.material_override = m.mat_color(Color("#59472e"))
	inner.position.y = 0.124
	g.add_child(inner)
	var strip: Material = m.mat_color(Color("#8a6e3a"))
	for k in 6:
		var a := k * TAU / 6.0 + TAU / 16.0
		var s: MeshInstance3D = m.box(Vector3(0.05, 0.2, 0.02), strip)
		s.position = Vector3(sin(a) * 0.335, 0, cos(a) * 0.335)
		s.rotation = Vector3(0, a, 0)
		s.rotate_object_local(Vector3.RIGHT, 0.29) # along the slope of the side
		g.add_child(s)
	return g

# Bori's old lantern: glass, four corner posts and a lid, a small brass handle, dust on top
func make_lantern(m: Node) -> Node3D:
	var g := Node3D.new()
	var dark: Material = m.mat_color(Color("#3b2a1e"))
	glass_dull = m.mat_color(Color("#ffc46a").darkened(0.55), 1.0) # cloudy while unlit
	glass_lit = m.glow_mat(Color("#ffc46a"), 3.0)
	glass_lit.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED # solid gold, not washed white
	glass_lit.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	float_glass = m.box(Vector3(0.18, 0.22, 0.18), glass_dull)
	float_glass.position.y = 0.11
	g.add_child(float_glass)
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var post: MeshInstance3D = m.box(Vector3(0.03, 0.24, 0.03), dark)
		post.position = Vector3(c.x * 0.095, 0.12, c.y * 0.095)
		g.add_child(post)
	var lid: MeshInstance3D = m.box(Vector3(0.22, 0.04, 0.22), dark)
	lid.position.y = 0.26
	g.add_child(lid)
	var dust: MeshInstance3D = m.box(Vector3(0.2, 0.012, 0.2), m.mat_color(Color("#8a7a6a")))
	dust.position.y = 0.285
	g.add_child(dust)
	var brass: Material = m.mat_color(Color("#9b783e"), 0.5)
	for x in [-0.06, 0.06]:
		var leg: MeshInstance3D = m.box(Vector3(0.02, 0.08, 0.02), brass)
		leg.position = Vector3(x, 0.32, 0)
		g.add_child(leg)
	var bar: MeshInstance3D = m.box(Vector3(0.14, 0.02, 0.02), brass)
	bar.position.y = 0.36
	g.add_child(bar)
	return g

# a brick snag in the river: low two lumps, three staggered, a wide low heap (each its own outline)
func make_snag(m: Node, i: int) -> Node3D:
	var g := Node3D.new()
	var red := Color("#c8322a")
	var yellow := Color("#e8b018")
	var blue := Color("#2f5fb8")
	var green := Color("#3f8a3a")
	var parts: Array = [
		[[Vector3(0.5, 0.26, 0.4), Vector3(-0.2, 0, 0), red], [Vector3(0.4, 0.2, 0.34), Vector3(0.28, -0.03, 0.12), blue]],
		[[Vector3(0.42, 0.24, 0.32), Vector3(-0.3, 0, -0.1), yellow], [Vector3(0.42, 0.24, 0.32), Vector3(0.05, 0.12, 0.12), red],
			[Vector3(0.42, 0.24, 0.32), Vector3(0.38, 0.0, -0.08), green]],
		[[Vector3(0.6, 0.16, 0.42), Vector3(-0.4, 0, 0), blue], [Vector3(0.6, 0.18, 0.44), Vector3(0.18, 0.01, 0.1), green],
			[Vector3(0.5, 0.14, 0.4), Vector3(0.7, -0.01, -0.06), yellow], [Vector3(0.36, 0.14, 0.3), Vector3(0.1, 0.13, -0.05), red]],
	][i]
	for p in parts:
		m.brick(g, [], p[0], p[1], p[2])
	g.rotation.y = [0.5, -0.4, 0.25][i]
	return g

func build_shore(m: Node) -> void:
	# pressed reeds from where Sora woke to the basket, lying a little askew; the standing reeds along them go
	var line: Array = [Vector2(15, 20)] + REEDS + [BASKET_AT] # START
	for p in REEDS + [BASKET_AT]:
		m.clear_vegetation(p, 0.6 if p != BASKET_AT else 1.1)
	var reed: Material = m.mat_color(Color("#9aa860"))
	for i in 10:
		var f := (i + 0.5) / 10.0 * (line.size() - 1)
		var k := int(f)
		var a: Vector2 = line[k]
		var b: Vector2 = line[mini(k + 1, line.size() - 1)]
		var at := a.lerp(b, f - k)
		var dir := (b - a).normalized()
		at += Vector2(-dir.y, dir.x) * sin(i * 2.3) * 0.18
		var r: MeshInstance3D = m.box(Vector3(0.08, 0.03, 0.6), reed)
		r.position = Vector3(at.x, m.height_at(at.x, at.y) + 0.02, at.y)
		r.rotation.y = atan2(dir.x, dir.y) + sin(i * 1.7) * 0.3
		m.add_child(r)
	# the basket half sunk at the water's edge, tipped south, ringed by hardened mud like toy bricks
	basket = Node3D.new()
	var bk := make_basket(m)
	bk.rotation.x = 0.3
	bk.position.y = -0.04
	basket.add_child(bk)
	var side: Material = m.mat_color(Color("#62564b"))
	var top: Material = m.mat_color(Color("#8a7a6a"))
	for mud in [[Vector2(-0.4, 0.1), 0.18, 0.2, 0.1], [Vector2(0.32, 0.3), 0.22, -0.5, -0.12], [Vector2(0.02, -0.42), 0.14, 0.9, 0.06],
			[Vector2(0.4, -0.22), 0.2, 0.3, 0.16]]:
		var mg := Node3D.new()
		var h: float = mud[1]
		var sb: MeshInstance3D = m.box(Vector3(0.3, h, 0.24), side)
		mg.add_child(sb)
		var tb: MeshInstance3D = m.box(Vector3(0.31, 0.03, 0.25), top)
		tb.position.y = h / 2.0
		mg.add_child(tb)
		mg.position = Vector3(mud[0].x, h / 2.0 - 0.06, mud[0].y)
		mg.rotation = Vector3(0, mud[2], mud[3])
		basket.add_child(mg)
	basket.scale = Vector3.ONE * 1.4
	basket.position = Vector3(BASKET_AT.x, m.height_at(BASKET_AT.x, BASKET_AT.y), BASKET_AT.y)
	m.add_child(basket)
	m.rocks.append({"x": BASKET_AT.x, "z": BASKET_AT.y, "r": 0.4, "basket": true})
	# the floating basket with Bori's lantern, hidden until it is floated
	float_node = Node3D.new()
	float_node.add_child(make_basket(m))
	var lamp := make_lantern(m)
	lamp.position.y = 0.12
	lamp.scale = Vector3.ONE * 1.4 # reads at the camera's distance
	float_node.add_child(lamp)
	float_node.scale = Vector3.ONE * 1.25
	float_node.visible = false
	m.add_child(float_node)
	glint_node = Node3D.new()
	var gm: StandardMaterial3D = m.glow_mat(Color("#ffd27a"), 1.6)
	gm.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED # gold on the blue water, not a white add
	gm.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	for k in 3:
		var gl: MeshInstance3D = m.box(Vector3(0.36, 0.01, 0.07), gm)
		gl.position = Vector3([-0.62, 0.64, 0.12][k], 0, [0.1, -0.08, -0.62][k]) # short glints around it on the water
		glint_node.add_child(gl)
	glint_node.visible = false
	m.add_child(glint_node)
	# the snags sit in the river where the basket stops
	path = float_path()
	path_d = [0.0]
	for i in range(1, path.size()):
		path_d.append(path_d[i - 1] + (path[i] as Vector2).distance_to(path[i - 1]))
	for i in SNAGS.size():
		var best := 0
		for j in path.size():
			if (path[j] as Vector2).distance_to(SNAGS[i]) < (path[best] as Vector2).distance_to(SNAGS[i]):
				best = j
		snag_d.append(path_d[best])
		var ahead: Vector2 = float_at(path_d[best] + 0.55) # just downstream of where it holds
		var sn := make_snag(m, i)
		sn.position = Vector3(ahead.x, WATER_Y + 0.02, ahead.y)
		sn.visible = false
		m.add_child(sn)
		snag_nodes.append(sn)
	# the night walk along the west bank: the grass kept low, grey-green stones at the edge of the ground
	var edge := StandardMaterial3D.new()
	edge.albedo_color = Color("#87967b")
	edge.emission_enabled = true # a faint glow, so the bank reads at night apart from the water
	edge.emission = Color("#87967b")
	edge.emission_energy_multiplier = 0.25
	for z in [21.0, 23.0, 27.5, 29.5, 31.5]:
		var x: float = 24.0 + sin(z * 0.18) * 5.0 - 2.9
		lower_vegetation(m, Vector2(x - 0.6, z), 1.3)
		var st: MeshInstance3D = m.box(Vector3(0.34, 0.05, 0.26), edge)
		st.position = Vector3(x, m.height_at(x, z) + 0.03, z)
		st.rotation.y = sin(z) * 0.6
		m.add_child(st)
	# nothing tall by the last stop, so the lantern shows from the island
	m.clear_vegetation(Vector2(24, 37.2), 1.4)
	m.clear_vegetation(Vector2(22.6, 36.8), 0.9)
	m.clear_vegetation(Vector2(25.4, 36.8), 0.9)

# grass and reeds in a circle kept to half height
func lower_vegetation(m: Node, at: Vector2, r: float) -> void:
	for mm in m.veg_meshes:
		for i in mm.instance_count:
			var tf: Transform3D = mm.get_instance_transform(i)
			if Vector2(tf.origin.x, tf.origin.z).distance_to(at) < r:
				tf.basis = tf.basis.scaled(Vector3(1.0, 0.45, 1.0))
				mm.set_instance_transform(i, tf)

# the basket comes out of the mud (shore_q 2)
func free_basket(m: Node) -> void:
	basket.visible = false
	m.rocks = m.rocks.filter(func(r): return not r.get("basket", false))

func set_float(at: Vector2, lit: bool) -> void:
	float_node.visible = true
	glint_node.visible = lit
	float_glass.material_override = glass_lit if lit else glass_dull
	float_node.position = Vector3(at.x, WATER_Y + 0.02, at.y)
	glint_node.position = Vector3(at.x, WATER_Y + 0.05, at.y)

func move_float(at: Vector2) -> void:
	float_node.position.x = at.x
	float_node.position.z = at.y
	glint_node.position.x = at.x
	glint_node.position.z = at.y

func hide_float() -> void:
	if landed:
		set_float(FLOAT_END, true)
		return
	float_node.visible = false
	glint_node.visible = false

# the lantern comes to rest off the island's north tip and stays there
func land_float() -> void:
	landed = true
	set_float(FLOAT_END, true)

# every frame in the marsh: a slow side sway and bob (no spinning), the glints flicker; brighter by night off the island
func shore_tick(m: Node, night: float, snags_shown: int) -> void:
	for i in snag_nodes.size():
		snag_nodes[i].visible = i >= 3 - snags_shown
	if not float_node.visible:
		return
	var t: float = m.t
	float_node.position.y = WATER_Y + 0.02 + sin(t * 2.0) * 0.04
	float_node.rotation = Vector3(sin(t * 0.8) * 0.06, 0.3, sin(t * 1.1) * 0.12)
	for k in glint_node.get_child_count():
		var gl: Node3D = glint_node.get_child(k)
		var s := 0.5 + 0.5 * sin(t * 3.0 + k * 2.1)
		gl.scale = Vector3(0.5 + s, 1, 1)
		gl.visible = s > 0.25
	if landed and float_glass.material_override == glass_lit:
		glass_lit.emission_energy_multiplier = 2.4 if night > 0.5 else 0.6
	elif glass_lit != null:
		glass_lit.emission_energy_multiplier = 3.0 # 2.0 read too faint at the camera distance

# after a load or a new round: the basket in the mud or not, the lantern off the island or not
func shore_look(m: Node, q: int) -> void:
	landed = q >= 4
	basket.visible = q < 2
	m.rocks = m.rocks.filter(func(r): return not r.get("basket", false))
	if q < 2:
		m.rocks.append({"x": BASKET_AT.x, "z": BASKET_AT.y, "r": 0.4, "basket": true})
	hide_float()
