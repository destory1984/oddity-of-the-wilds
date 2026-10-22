# Sky dial: a half-circle sky whose colour follows the clock. The sun crosses
# the arc from 06:00 to 18:00 and the moon from 18:00 to 06:00.
extends Control

var main: Node

const SKY := [ # hour, top colour, bottom colour
	[0.0, "#0b1230", "#26305a"],
	[5.0, "#0b1230", "#26305a"],
	[6.5, "#6a6aa8", "#f0a070"],
	[9.0, "#6fa8e0", "#cfe6ff"],
	[13.0, "#5f9ee0", "#d8ecff"],
	[16.5, "#c88a5a", "#f2b866"],
	[18.5, "#4a3a6a", "#d8735a"],
	[20.0, "#0b1230", "#26305a"],
	[24.0, "#0b1230", "#26305a"],
]

func _process(_dt: float) -> void:
	queue_redraw()

func sky_colors(h: float) -> Array:
	var i := 0
	while SKY[i + 1][0] <= h:
		i += 1
	var a: Array = SKY[i]
	var b: Array = SKY[i + 1]
	var k: float = (h - a[0]) / (b[0] - a[0])
	return [Color(a[1]).lerp(Color(b[1]), k), Color(a[2]).lerp(Color(b[2]), k)]

func _draw() -> void:
	if main == null:
		return
	var h: float = main.hour
	var cols := sky_colors(h)
	# vertical gradient in a few bands
	var bands := 12
	for i in bands:
		var y0 := size.y * i / bands
		draw_rect(Rect2(0, y0, size.x, size.y / bands + 1), cols[0].lerp(cols[1], float(i) / (bands - 1)))
	var base := Vector2(size.x / 2.0, size.y - 8.0)
	var r := Vector2(size.x / 2.0 - 18.0, size.y - 20.0)
	# dashed arc
	for i in 24:
		if i % 2 == 0:
			var a0 := PI + PI * i / 24.0
			var a1 := PI + PI * (i + 1) / 24.0
			draw_line(base + Vector2(cos(a0) * r.x, sin(a0) * r.y), base + Vector2(cos(a1) * r.x, sin(a1) * r.y), Color(1, 1, 1, 0.35), 1.0)
	draw_line(Vector2(8, base.y), Vector2(size.x - 8, base.y), Color("#b9a273"), 1.0)
	# sun by day, moon by night: progress 0 = east horizon (left), 1 = west (right)
	var is_day := h >= 6.0 and h < 18.0
	var p := (h - 6.0) / 12.0 if is_day else fmod(h + 6.0, 24.0) / 12.0
	var ang := PI + PI * p
	var pos := base + Vector2(cos(ang) * r.x, sin(ang) * r.y)
	if is_day:
		for k in 4:
			draw_circle(pos, 12.0 - k * 2.0, Color(1.0, 0.75, 0.3, 0.12))
		draw_circle(pos, 7.0, Color("#ffd25a"))
		draw_circle(pos, 4.5, Color("#fffbe0"))
	else:
		for k in 3:
			draw_circle(pos, 10.0 - k * 2.0, Color(0.75, 0.8, 1.0, 0.12))
		# phase: a shadow disc slides off the moon as it fills; side flips when waning
		var ph: Vector2 = main.moon_phase()
		var mr := 6.5
		draw_circle(pos, mr, Color("#e8ecff"))
		if ph.x < 0.98:
			var off := mr * 2.0 * ph.x * ph.y
			draw_circle(pos + Vector2(off, -0.5), mr * 0.98, cols[0].lerp(cols[1], 0.3))
		for s in [Vector2(0.15, 0.25), Vector2(0.35, 0.12), Vector2(0.7, 0.2), Vector2(0.85, 0.35), Vector2(0.55, 0.4)]:
			draw_rect(Rect2(size * s, Vector2(1.5, 1.5)), Color(1, 1, 1, 0.7))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.725, 0.635, 0.45, 0.55), false, 1.0)
