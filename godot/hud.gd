# HUD drawn in code after the GPT mock (art/concept/hud_concept.png): navy glass, thin gold line work.
# Top left: round portrait with level badge, slim HP / momentum / stamina bars, an XP hairline and a
# sun-and-moon dial. Top centre: quest ornaments. Bottom right: diamond skill slots and a gold pill.
extends Control

var main: Node
var portrait: Texture2D = preload("res://art/ui/portrait.png")
var icons: Array = [preload("res://art/ui/skill_0.png"), preload("res://art/ui/skill_1.png"),
	preload("res://art/ui/skill_2.png"), preload("res://art/ui/skill_3.png")]

const GOLD := Color("#e8b018")
const GOLD_DIM := Color(0.91, 0.69, 0.09, 0.45)
const NAVY := Color(0.02, 0.04, 0.10, 0.78)
const TEXT := Color("#efe6cf")
const DIM := Color("#a99d84")

func _process(_dt: float) -> void:
	queue_redraw()

func diamond(c: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), col)

func text(at: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	s = tr(s) # drawn text is not auto-translated like Labels are
	draw_string_outline(main.ui_font, at, s, align, width, size, 4, Color(0, 0, 0, 0.7))
	draw_string(main.ui_font, at, s, align, width, size, col)

func bar(at: Vector2, w: float, frac: float, col: Color, label: String, value: String, blink := false) -> void:
	var h := 10.0
	draw_rect(Rect2(at, Vector2(w, h)), NAVY)
	var fw: float = w * clampf(frac, 0.0, 1.0)
	var a := 0.55 + 0.45 * absf(sin(main.t * 6.0)) if blink else 1.0
	draw_rect(Rect2(at, Vector2(fw, h)), Color(col, a))
	draw_rect(Rect2(at, Vector2(fw, h * 0.4)), Color(col.lightened(0.35), a * 0.8)) # glassy top
	draw_rect(Rect2(at - Vector2(1, 1), Vector2(w + 2, h + 2)), GOLD_DIM, false, 1.0)
	diamond(at + Vector2(-6, h / 2.0), 5, GOLD)
	diamond(at + Vector2(w + 6, h / 2.0), 5, GOLD)
	text(at + Vector2(-44, 9), label, 11, DIM)
	text(at + Vector2(w + 16, 10), value, 12, TEXT)

func _draw() -> void:
	if main == null or main.intro:
		return
	var p: Dictionary = main.player
	var vs := get_viewport_rect().size
	# ---- portrait and level
	var c := Vector2(70, 72)
	draw_circle(c, 50, NAVY)
	draw_texture_rect(portrait, Rect2(c - Vector2(44, 44), Vector2(88, 88)), false)
	draw_arc(c, 46, 0, TAU, 64, GOLD, 2.5, true)
	draw_arc(c, 51, 0, TAU, 64, GOLD_DIM, 1.0, true)
	for ang in [-PI / 2, 0.0, PI]:
		diamond(c + Vector2(cos(ang), sin(ang)) * 51, 5, GOLD)
	diamond(c + Vector2(0, -62), 7, GOLD) # crown point
	var lb := c + Vector2(0, 48)
	draw_circle(lb, 14, Color("#0b1530"))
	draw_arc(lb, 14, 0, TAU, 32, GOLD, 2.0, true)
	text(lb + Vector2(-20, 6), str(p.lv), 15, TEXT, HORIZONTAL_ALIGNMENT_CENTER, 40)
	# ---- bars
	var x0 := 170.0
	bar(Vector2(x0, 34), 230, p.hp / p.max_hp, Color("#e03a44"), "체력", "%d/%d" % [ceili(p.hp), p.max_hp])
	bar(Vector2(x0, 56), 230, p.mp / p.max_mp, Color("#f08a2a"), "기세", "%d/%d" % [int(p.mp), p.max_mp], p.mp >= 60.0)
	bar(Vector2(x0, 78), 230, p.sp / 100.0, Color("#f2e2b0"), "기력", "%d/100" % int(p.sp))
	var need: int = p.lv * 25
	bar(Vector2(x0, 100), 230, float(p.xp) / need, Color("#8de07a"), "경험", "%d/%d" % [p.xp, need])
	# crown moon gauge: 8 small diamonds
	text(Vector2(x0 - 44, 129), "달빛", 11, DIM)
	for i in 8:
		var pc := Vector2(x0 + 8 + i * 16, 124)
		var full: bool = i < main.crown_pips
		var flash: bool = main.pip_flash > 0.0 and i == main.crown_pips
		if full:
			diamond(pc, 6, Color("#9fd4ff"))
		elif flash:
			diamond(pc, 6, Color.WHITE)
		else:
			draw_polyline(PackedVector2Array([pc + Vector2(0, -6), pc + Vector2(6, 0), pc + Vector2(0, 6), pc + Vector2(-6, 0), pc + Vector2(0, -6)]), Color("#6a6050"), 1.0)
	var grow: float = 6.0 * minf(1.0, main.rest_t / main.rest_need)
	if grow >= 0.5 and main.crown_pips < 8: # the next pip glows in while resting (too small a diamond cannot be drawn)
		diamond(Vector2(x0 + 8 + main.crown_pips * 16, 124), grow, Color("#9fd4ff"))
	# ---- sun / moon dial hanging under the portrait
	var dc := Vector2(70, 222)
	for i in 14:
		var a0 := PI + PI * i / 14.0
		var pt := dc + Vector2(cos(a0) * 58, sin(a0) * 32)
		draw_circle(pt, 1.2, GOLD_DIM)
	var h: float = main.hour
	var day := h >= 6.0 and h < 18.0
	var prog := (h - 6.0) / 12.0 if day else fmod(h + 6.0, 24.0) / 12.0
	var ang := PI + PI * prog
	var sp := dc + Vector2(cos(ang) * 58, sin(ang) * 32)
	if day:
		draw_circle(sp, 9, Color(1.0, 0.75, 0.3, 0.25))
		draw_circle(sp, 5.5, Color("#ffd25a"))
	else:
		draw_circle(sp, 8, Color(0.75, 0.8, 1.0, 0.2))
		draw_circle(sp, 5.5, Color("#e8ecff"))
		var ph: Vector2 = main.moon_phase()
		if ph.x < 0.98:
			draw_circle(sp + Vector2(5.5 * 2.0 * ph.x * ph.y, -0.5), 5.4, Color("#0b1530"))
	# zone name, small, under the dial
	text(Vector2(22, 254), main.ui.zone_name.text, 14, TEXT)
	text(Vector2(22, 272), main.ui.zone_sub.text, 11, DIM)
	# ---- quest ornaments
	if main.ui.quest.visible:
		var cx := vs.x / 2.0
		var qy: float = main.ui.quest.position.y
		for y in [qy - 8.0, qy + 34.0]:
			var half := 140.0 if y < qy else 80.0
			draw_line(Vector2(cx - half, y), Vector2(cx - 10, y), GOLD_DIM, 1.0)
			draw_line(Vector2(cx + 10, y), Vector2(cx + half, y), GOLD_DIM, 1.0)
			diamond(Vector2(cx, y), 4, GOLD)
			diamond(Vector2(cx - half, y), 2.5, GOLD)
			diamond(Vector2(cx + half, y), 2.5, GOLD)
	# ---- skills
	var keys := ["U", "I", "O", "4"]
	var cds: Array = p.cds
	var cd_max := [main.SKILL_CD[0], main.SKILL_CD[1], main.SKILL_CD[2], 2.0]
	for i in 4:
		var sc := Vector2(vs.x - 300 + i * 74, vs.y - 74)
		draw_texture_rect(icons[i], Rect2(sc - Vector2(34, 34), Vector2(68, 68)), false)
		var frac: float = cds[i] / cd_max[i]
		var cant: bool = i < 3 and p.mp < main.skill_cost(i)
		if frac > 0.0 or cant: # cooldown sweep, or dim when there is not enough momentum
			var pts := PackedVector2Array([sc])
			var sweep := TAU * (frac if frac > 0.0 else 1.0)
			for k in 25:
				var a1: float = -PI / 2 + sweep * k / 24.0
				pts.append(sc + Vector2(cos(a1), sin(a1)) * 22)
			draw_colored_polygon(pts, Color(0, 0, 0, 0.6))
		var kb := sc + Vector2(0, 42)
		draw_rect(Rect2(kb - Vector2(9, 9), Vector2(18, 18)), NAVY)
		draw_rect(Rect2(kb - Vector2(9, 9), Vector2(18, 18)), GOLD_DIM, false, 1.0)
		text(kb + Vector2(-9, 5), keys[i], 12, TEXT, HORIZONTAL_ALIGNMENT_CENTER, 18)
		if i == 3:
			text(sc + Vector2(14, 30), "×%d" % p.pots, 12, TEXT)
	# ---- gold pill
	var gp := Rect2(Vector2(vs.x - 150, vs.y - 158), Vector2(126, 28))
	draw_rect(gp, NAVY)
	draw_rect(gp, GOLD_DIM, false, 1.0)
	diamond(gp.position + Vector2(0, 14), 5, GOLD)
	diamond(gp.position + Vector2(126, 14), 5, GOLD)
	diamond(gp.position + Vector2(24, 14), 6, Color("#ffd84a"))
	text(gp.position + Vector2(40, 20), str(p.gold), 15, TEXT)
