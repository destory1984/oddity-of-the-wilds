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
			if picked_count() == FLOWERS.size():
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
