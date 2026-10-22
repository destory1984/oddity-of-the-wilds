# 갈대늪 side quest (chapter 1): three scraps of the moonkeepers' old map lie in far corners of the marsh.
# Walking over a scrap picks it up. With all three the map shows where a moonkeeper buried a chest;
# the chest rises out of the ground there and Space opens it for a lasting reward.
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
		var glint := OmniLight3D.new() # a warm glint so it can be spotted in the reeds
		glint.light_color = Color("#ffe2a0")
		glint.light_energy = 1.4
		glint.omni_range = 2.6
		glint.position = Vector3(0, 0.7, 0)
		g.add_child(glint)
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
	var beam := OmniLight3D.new()
	beam.light_color = Color("#bcd6ff")
	beam.light_energy = 2.0
	beam.omni_range = 4.0
	beam.position = Vector3(0, 1.2, 0)
	chest.add_child(beam)
	chest.position = Vector3(CHEST_AT.x, m.height_at(CHEST_AT.x, CHEST_AT.y), CHEST_AT.y)
	chest.visible = false
	m.add_child(chest)

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
		if b is OmniLight3D:
			b.visible = false

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
