# 정원 한가운데 (story step 11): a round arena at x >= GARDEN_X where the hardened-moon mold waits.
# Eight dark lantern posts ring the arena; in the last wind the villagers' lights fill them one by one.
extends RefCounted

const GARDEN_X := 230
const W := 26
const H := 22
const CENTER := Vector2(14, 11)
const RADIUS := 9.5

var marks := {}          # S (entry from the forest), C (centre) -> world Vector2
var posts: Array = []    # the 8 ring lanterns: OmniLight3D, dark until the last wind

func char_at(x: float, z: float) -> String:
	var tx := int(round(x)) - GARDEN_X
	var tz := int(round(z))
	if tx < 0 or tz < 0 or tx >= W or tz >= H:
		return "#"
	if tz == int(CENTER.y) and tx <= int(CENTER.x - RADIUS) + 1 and tx >= 1:
		return "=" # the brick road in from the forest
	return "." if Vector2(tx, tz).distance_to(CENTER) <= RADIUS else "#"

func blocked(x: float, z: float) -> bool:
	return char_at(x, z) == "#"

func build(m: Node) -> void:
	marks.S = Vector2(GARDEN_X + 1, CENTER.y)
	marks.C = Vector2(GARDEN_X + CENTER.x, CENTER.y)
	var blocks: Array = []
	for z in H:
		for x in W:
			var w := Vector2(GARDEN_X + x, z)
			var c := char_at(w.x, w.y)
			var col := Color("#8a8a90") # ground pressed flat into grey brick
			var hgt := 0.4
			if c == "#":
				col = Color("#4a4652")
				hgt = m.rnd(1.2, 2.4) # jagged brick cliffs around the arena
			elif c == "=":
				col = Color("#a39c90")
			elif (x + z) % 3 == 0:
				col = Color("#7a7a82") # cracks
			col = col.lightened(m.rnd(0, 0.06))
			blocks.append([Transform3D(Basis().scaled(Vector3(1, hgt, 1)), Vector3(w.x, hgt / 2.0 - 0.4, w.y)), col])
	var chunks := {}
	for bl in blocks:
		var o: Vector3 = bl[0].origin
		var key := Vector2i(int(o.x - GARDEN_X) / 6, int(o.z) / 6)
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
	for k in 8:
		var a := TAU * k / 8.0 + PI / 8.0
		var p: Vector2 = marks.C + Vector2(cos(a), sin(a)) * (RADIUS - 1.5)
		m.lantern(p.x - 0.3, p.y, post_mat, glass)
		var l: OmniLight3D = m.lanterns[m.lanterns.size() - 1]
		var g: MeshInstance3D = l.get_meta("glass")
		g.set_meta("lit_mat", g.material_override)
		posts.append(l)
	set_posts(0)

# light the first n ring posts (0 = all dark)
func set_posts(n: int) -> void:
	for i in posts.size():
		var l: OmniLight3D = posts[i]
		var g: MeshInstance3D = l.get_meta("glass")
		var on := i < n
		l.visible = on
		l.set_meta("dark", not on)
		g.material_override = g.get_meta("lit_mat") if on else StandardMaterial3D.new()
		if not on:
			(g.material_override as StandardMaterial3D).albedo_color = Color("#3a3428")

# the mold: a huge crescent of grey bricks with a glowing violet heart below it (the heart is the target)
func mold(m: Node) -> Node3D:
	var root := Node3D.new()
	var crescent := Node3D.new()
	crescent.name = "crescent"
	root.add_child(crescent)
	var grey: Material = m.glow_mat(Color("#6e6c78"), 0.35) # faintly lit so it reads at night
	var seam: Material = m.glow_mat(Color("#b48cff"), 2.0)
	for k in 15:
		var a := lerpf(-2.2, 2.2, k / 14.0)
		var thick := 1.0 - absf(a) / 2.6
		var b: MeshInstance3D = m.box(Vector3(0.9 * thick + 0.3, 0.9 * thick + 0.3, 0.7), grey)
		b.position = Vector3(sin(a) * 2.6, 2.8 + cos(a) * 2.0, 0)
		b.rotation.z = -a
		crescent.add_child(b)
		if k % 3 == 1:
			var s: MeshInstance3D = m.box(Vector3(0.12, 0.6 * thick + 0.2, 0.74), seam)
			s.position = b.position
			s.rotation.z = -a
			crescent.add_child(s)
	var heart: MeshInstance3D = m.box(Vector3(0.7, 0.7, 0.7), m.glow_mat(Color("#c08cff"), 3.0))
	heart.name = "heart"
	heart.position = Vector3(0, 1.0, 0)
	root.add_child(heart)
	var glow := OmniLight3D.new()
	glow.light_color = Color("#c8a0ff")
	glow.light_energy = 1.6
	glow.omni_range = 6.0
	glow.position = Vector3(0, 1.4, 0)
	root.add_child(glow)
	m.add_child(root)
	return root

func map_tex(width: int) -> ImageTexture:
	var img := Image.create(width, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for z in H:
		for x in W:
			var c := char_at(GARDEN_X + x, z)
			if c != "#":
				img.set_pixel(GARDEN_X + x, z, Color("#3a3846") if c == "." else Color("#5a5a50"))
	return ImageTexture.create_from_image(img)
