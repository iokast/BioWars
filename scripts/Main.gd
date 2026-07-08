extends Node2D

const TILE_W := 64.0
const TILE_H := 34.0
const HALF_TILE_W := TILE_W * 0.5
const HALF_TILE_H := TILE_H * 0.5
const GRID_W := 6
const GRID_H := 5
const SCREEN_W := 1024.0
const SCREEN_H := 600.0
const QUAD_W := SCREEN_W * 0.5
const QUAD_H := SCREEN_H * 0.5
const LUNGS := "Lungs"
const BLOOD := "Bloodstream"

var field_data := {
	LUNGS: {
		"origin": Vector2(246, 88),
		"panel": Rect2(Vector2(0, 0), Vector2(QUAD_W, QUAD_H)),
		"title": "LUNGS",
		"subtitle": "Air sacs, mucus, cough shockwaves",
		"bg": Color("#2e1426"),
		"tile_a": Color("#653048"),
		"tile_b": Color("#723a54"),
		"accent": Color("#ff7898")
	},
	BLOOD: {
		"origin": Vector2(246, 386),
		"panel": Rect2(Vector2(0, QUAD_H), Vector2(QUAD_W, QUAD_H)),
		"title": "BLOODSTREAM",
		"subtitle": "Fast current, mobile reinforcements",
		"bg": Color("#241628"),
		"tile_a": Color("#6d2435"),
		"tile_b": Color("#7f2c3e"),
		"accent": Color("#ff3b54")
	}
}

var lungs_background: Texture2D
var bloodstream_background: Texture2D
var host_sheet: Texture2D

var units: Array[Dictionary] = []
var selected_id := -1
var next_unit_id := 1
var phase := "player"
var turn := 1
var cough_charge := 2
var bloodflow_reinforcements := 0
var infection_score := 18
var symptom_cough := 0.0
var symptom_fever := 0.12
var symptom_oxygen := 0.82
var message := "Pick a germ. Move, bite immune cells, and use Cough to affect both battles."
var buttons: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()
	lungs_background = load("res://assets/backgrounds/lungs_battlefield.png")
	bloodstream_background = load("res://assets/backgrounds/bloodstream_battlefield.png")
	host_sheet = load("res://assets/sprites/host_sickness_sheet.png")
	get_viewport().size_changed.connect(Callable(self, "queue_redraw"))
	_spawn_starting_units()
	queue_redraw()

func _process(delta: float) -> void:
	symptom_cough = maxf(0.0, symptom_cough - delta * 0.45)
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_handle_click(event.position)

func _spawn_starting_units() -> void:
	units.clear()
	next_unit_id = 1
	_add_unit("Spore", "infection", LUNGS, Vector2i(0, 2))
	_add_unit("Puff", "infection", LUNGS, Vector2i(1, 3))
	_add_unit("Coccus", "infection", BLOOD, Vector2i(0, 1))
	_add_unit("Neutro", "immune", LUNGS, Vector2i(4, 1))
	_add_unit("Macro", "immune", LUNGS, Vector2i(5, 3))
	_add_unit("T-Cell", "immune", BLOOD, Vector2i(4, 2))
	_add_unit("B-Cell", "immune", BLOOD, Vector2i(5, 4))

func _add_unit(unit_name: String, side: String, field: String, cell: Vector2i) -> void:
	units.append({
		"id": next_unit_id,
		"name": unit_name,
		"side": side,
		"field": field,
		"cell": cell,
		"hp": 3 if side == "infection" else 4,
		"max_hp": 3 if side == "infection" else 4,
		"acted": false,
		"bob": rng.randf_range(0.0, TAU)
	})
	next_unit_id += 1

func _handle_click(pos: Vector2) -> void:
	for button in buttons:
		if button.rect.has_point(pos):
			_press_button(button.action)
			return

	if phase != "player":
		return

	for field in [LUNGS, BLOOD]:
		var cell := _screen_to_cell(field, pos)
		if cell.x >= 0:
			_click_cell(field, cell)
			return

func _click_cell(field: String, cell: Vector2i) -> void:
	var clicked := _unit_at(field, cell)
	if not clicked.is_empty() and clicked.side == "infection" and not clicked.acted:
		selected_id = clicked.id
		message = "%s is ready." % clicked.name
		queue_redraw()
		return

	var selected: Dictionary = _unit_by_id(selected_id)
	if selected.is_empty() or selected.acted or selected.field != field:
		return

	if not clicked.is_empty() and clicked.side == "immune" and _is_adjacent(selected.cell, cell):
		_damage_unit(clicked.id, 1)
		selected.acted = true
		selected_id = -1
		infection_score += 4
		symptom_fever = minf(1.0, symptom_fever + 0.05)
		message = "Bite landed. Immune pressure drops, fever creeps up."
		_check_outcome()
	elif clicked.is_empty() and _is_adjacent(selected.cell, cell):
		selected.cell = cell
		selected.acted = true
		selected_id = -1
		message = "Germ repositioned."
	queue_redraw()

func _press_button(action: String) -> void:
	match action:
		"end":
			_end_player_turn()
		"cough":
			_trigger_cough()
		"reset":
			turn = 1
			cough_charge = 2
			bloodflow_reinforcements = 0
			infection_score = 18
			symptom_cough = 0.0
			symptom_fever = 0.12
			symptom_oxygen = 0.82
			phase = "player"
			selected_id = -1
			message = "New host, fresh run. Infect both fronts."
			_spawn_starting_units()
			queue_redraw()

func _end_player_turn() -> void:
	if phase != "player":
		return
	phase = "immune"
	selected_id = -1
	message = "The immune system responds."
	queue_redraw()
	await get_tree().create_timer(0.35).timeout
	_immune_turn()
	_start_player_turn()

func _start_player_turn() -> void:
	turn += 1
	phase = "player"
	cough_charge = mini(3, cough_charge + 1)
	for unit in units:
		unit.acted = false
	if bloodflow_reinforcements > 0:
		_add_reinforcement(BLOOD)
		bloodflow_reinforcements -= 1
		message = "Bloodflow delivered a germ reinforcement into the bloodstream."
	else:
		message = "Your turn. Cough charge builds each round."
	_update_symptoms()
	_check_outcome()
	queue_redraw()

func _immune_turn() -> void:
	for immune in units.filter(func(unit): return unit.side == "immune"):
		var target := _nearest_enemy(immune)
		if target.is_empty():
			continue
		if _is_adjacent(immune.cell, target.cell) and immune.field == target.field:
			_damage_unit(target.id, 1)
			infection_score -= 3
		elif immune.field == target.field:
			_move_toward(immune, target.cell)
	_update_symptoms()

func _trigger_cough() -> void:
	if cough_charge < 3:
		message = "Cough needs a full charge."
		queue_redraw()
		return
	if units.filter(func(unit): return unit.side == "infection" and unit.field == LUNGS).is_empty():
		message = "You need a germ in the lungs to trigger a cough."
		queue_redraw()
		return

	cough_charge = 0
	symptom_cough = 1.0
	symptom_oxygen = maxf(0.18, symptom_oxygen - 0.12)
	infection_score += 7
	bloodflow_reinforcements += 1
	message = "Cough shockwave! Lung units slide right; bloodflow queues a bloodstream reinforcement."

	var to_remove: Array[int] = []
	for unit in units:
		if unit.field != LUNGS:
			continue
		var new_x: int = unit.cell.x + 1
		if new_x >= GRID_W:
			to_remove.append(unit.id)
		elif _unit_at(LUNGS, Vector2i(new_x, unit.cell.y)).is_empty():
			var cell: Vector2i = unit.cell
			cell.x = new_x
			unit.cell = cell
	for id in to_remove:
		_remove_unit(id)

	for unit in units:
		if unit.field == BLOOD:
			var cell: Vector2i = unit.cell
			cell.x = mini(GRID_W - 1, cell.x + 1)
			unit.cell = cell

	_check_outcome()
	queue_redraw()

func _add_reinforcement(field: String) -> void:
	for y in range(GRID_H):
		var cell := Vector2i(0, y)
		if _unit_at(field, cell).is_empty():
			_add_unit("Viro", "infection", field, cell)
			return

func _move_toward(unit: Dictionary, target_cell: Vector2i) -> void:
	var dx: int = clampi(target_cell.x - unit.cell.x, -1, 1)
	var dy: int = clampi(target_cell.y - unit.cell.y, -1, 1)
	var options := [
		Vector2i(unit.cell.x + dx, unit.cell.y),
		Vector2i(unit.cell.x, unit.cell.y + dy)
	]
	for option in options:
		if _cell_open(unit.field, option):
			unit.cell = option
			return

func _nearest_enemy(unit: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_dist := 999
	for other in units:
		if other.side == unit.side or other.field != unit.field:
			continue
		var dist: int = absi(other.cell.x - unit.cell.x) + absi(other.cell.y - unit.cell.y)
		if dist < best_dist:
			best = other
			best_dist = dist
	return best if not best.is_empty() else {}

func _damage_unit(id: int, amount: int) -> void:
	var unit := _unit_by_id(id)
	if unit.is_empty():
		return
	unit.hp -= amount
	if unit.hp <= 0:
		_remove_unit(id)

func _remove_unit(id: int) -> void:
	for i in range(units.size() - 1, -1, -1):
		if units[i].id == id:
			units.remove_at(i)
			if selected_id == id:
				selected_id = -1
			return

func _check_outcome() -> void:
	var immune_left := units.any(func(unit): return unit.side == "immune")
	var infection_left := units.any(func(unit): return unit.side == "infection")
	if not immune_left:
		message = "Host overwhelmed. MVP run won: infection controls lungs and bloodstream."
		phase = "over"
	elif not infection_left:
		message = "Immune system cleared the infection. Reset for another run."
		phase = "over"

func _update_symptoms() -> void:
	var infection_units := units.filter(func(unit): return unit.side == "infection").size()
	var immune_units := units.filter(func(unit): return unit.side == "immune").size()
	symptom_fever = clampf(0.10 + infection_units * 0.07, 0.0, 1.0)
	symptom_oxygen = clampf(0.94 - infection_units * 0.05 + immune_units * 0.015 - symptom_cough * 0.18, 0.12, 1.0)

func _unit_by_id(id: int) -> Dictionary:
	for unit in units:
		if unit.id == id:
			return unit
	return {}

func _unit_at(field: String, cell: Vector2i) -> Dictionary:
	for unit in units:
		if unit.field == field and unit.cell == cell:
			return unit
	return {}

func _cell_open(field: String, cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < GRID_W and cell.y < GRID_H and _unit_at(field, cell).is_empty()

func _is_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return absi(a.x - b.x) + absi(a.y - b.y) == 1

func _screen_to_cell(field: String, pos: Vector2) -> Vector2i:
	for y in range(GRID_H - 1, -1, -1):
		for x in range(GRID_W - 1, -1, -1):
			var cell := Vector2i(x, y)
			if _point_in_iso_tile(field, cell, pos):
				return cell
	return Vector2i(-1, -1)

func _cell_center(field: String, cell: Vector2i) -> Vector2:
	var origin: Vector2 = field_data[field].origin
	return origin + Vector2((cell.x - cell.y) * HALF_TILE_W, (cell.x + cell.y) * HALF_TILE_H)

func _tile_points(field: String, cell: Vector2i) -> PackedVector2Array:
	var center := _cell_center(field, cell)
	return PackedVector2Array([
		center + Vector2(0, -HALF_TILE_H),
		center + Vector2(HALF_TILE_W, 0),
		center + Vector2(0, HALF_TILE_H),
		center + Vector2(-HALF_TILE_W, 0)
	])

func _point_in_iso_tile(field: String, cell: Vector2i, pos: Vector2) -> bool:
	var center := _cell_center(field, cell)
	var local := pos - center
	return absf(local.x) / HALF_TILE_W + absf(local.y) / HALF_TILE_H <= 1.0

func _draw() -> void:
	buttons.clear()
	_draw_background()
	_draw_field(LUNGS)
	_draw_field(BLOOD)
	_draw_units()
	_draw_connection()
	_draw_pip()
	_draw_empty_third_battle()

func _draw_background() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color("#16131d"))
	draw_line(Vector2(QUAD_W, 0), Vector2(QUAD_W, SCREEN_H), Color("#4c3946"), 2.0)
	draw_line(Vector2(0, QUAD_H), Vector2(SCREEN_W, QUAD_H), Color("#4c3946"), 2.0)
	for i in range(18):
		var x := 20 + i * 58
		var y := 58 + sin(Time.get_ticks_msec() * 0.001 + i) * 6.0
		draw_circle(Vector2(x, y), 2.0, Color("#3c2335"))

func _draw_field(field: String) -> void:
	var data: Dictionary = field_data[field]
	var origin: Vector2 = data.origin
	var panel: Rect2 = data.panel
	draw_rect(panel, data.bg)
	var background: Texture2D = lungs_background if field == LUNGS else bloodstream_background
	_draw_texture_cover(background, panel.grow(-8), Color(1, 1, 1, 0.95))
	draw_rect(panel.grow(-8), Color(0.06, 0.04, 0.07, 0.34))
	draw_rect(panel.grow(-8), data.accent, false, 2.0)
	draw_string(ThemeDB.fallback_font, panel.position + Vector2(22, 34), data.title, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#f6e7d8"))
	draw_string(ThemeDB.fallback_font, panel.position + Vector2(22, 54), data.subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#d4b7bf"))

	for sum in range(GRID_W + GRID_H - 1):
		for y in range(GRID_H):
			var x := sum - y
			if x < 0 or x >= GRID_W:
				continue
			var cell := Vector2i(x, y)
			var points := _tile_points(field, cell)
			var color: Color = data.tile_a if (x + y) % 2 == 0 else data.tile_b
			if field == BLOOD:
				color = color.lerp(Color("#b73145"), float(x) / float(GRID_W) * 0.24)
			if selected_id != -1:
				var selected: Dictionary = _unit_by_id(selected_id)
				if not selected.is_empty() and selected.field == field and _is_adjacent(selected.cell, cell):
					color = color.lerp(Color("#f6d25d"), 0.35)
			color.a = 0.72
			draw_colored_polygon(points, color)
			draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[3], points[0]]), Color("#f6e7d8", 0.45), 1.0)

	if field == LUNGS and symptom_cough > 0.02:
		for y in range(GRID_H):
			var start := _cell_center(field, Vector2i(0, y)) + Vector2(-20, -8)
			var end := _cell_center(field, Vector2i(GRID_W - 1, y)) + Vector2(30, -8)
			draw_line(start, end, _alpha(Color("#ffd7e5"), symptom_cough), 3.0)
			draw_line(end, end - Vector2(10, 7), _alpha(Color("#ffd7e5"), symptom_cough), 3.0)
			draw_line(end, end - Vector2(10, -7), _alpha(Color("#ffd7e5"), symptom_cough), 3.0)
	elif field == BLOOD:
		for y in range(GRID_H):
			var start := _cell_center(field, Vector2i(0, y)) + Vector2(-16, 7)
			var end := _cell_center(field, Vector2i(GRID_W - 1, y)) + Vector2(20, 7)
			draw_line(start, end, _alpha(Color("#ff9aae"), 0.28), 2.0)

func _draw_units() -> void:
	var ordered_units := units.duplicate()
	ordered_units.sort_custom(func(a, b): return a.cell.x + a.cell.y < b.cell.x + b.cell.y)
	for unit in ordered_units:
		var tile_center: Vector2 = _cell_center(unit.field, unit.cell)
		var selected: bool = unit.id == selected_id
		var acted: bool = unit.acted
		var body: Color = Color("#82dc5f") if unit.side == "infection" else Color("#dfefff")
		var outline: Color = Color("#eaff7a") if selected else Color("#21151f")
		var unit_alpha := 0.42 if acted else 1.0
		body = _alpha(body, unit_alpha)
		outline = _alpha(outline, maxf(unit_alpha, 0.62))
		var bob: float = sin(Time.get_ticks_msec() * 0.004 + unit.bob) * 2.0
		var center := tile_center + Vector2(0, -22 + bob)
		var rect := Rect2(center - Vector2(15, 17), Vector2(30, 34))

		if acted:
			draw_circle(tile_center + Vector2(0, 1), 18.0, Color(0.03, 0.02, 0.03, 0.38))
		draw_rect(rect, outline)
		draw_rect(rect.grow(-3), body)
		if unit.side == "infection":
			draw_circle(center + Vector2(-8, -6), 3, _alpha(Color("#21151f"), unit_alpha))
			draw_circle(center + Vector2(8, -6), 3, _alpha(Color("#21151f"), unit_alpha))
			draw_line(center + Vector2(-8, 8), center + Vector2(8, 8), _alpha(Color("#21151f"), unit_alpha), 2.0)
			draw_line(center + Vector2(-15, -15), center + Vector2(-22, -22), body, 3.0)
			draw_line(center + Vector2(15, -15), center + Vector2(22, -22), body, 3.0)
		else:
			draw_circle(center + Vector2(-7, -5), 3, _alpha(Color("#21151f"), unit_alpha))
			draw_circle(center + Vector2(7, -5), 3, _alpha(Color("#21151f"), unit_alpha))
			draw_line(center + Vector2(-8, 8), center + Vector2(8, 5), _alpha(Color("#21151f"), unit_alpha), 2.0)
			draw_rect(Rect2(rect.position + Vector2(10, -4), Vector2(14, 8)), _alpha(Color("#8cc7ff"), unit_alpha))

		for i in range(unit.max_hp):
			var hp_color: Color = Color("#ff4e68") if i < unit.hp else Color("#442536")
			hp_color = _alpha(hp_color, maxf(unit_alpha, 0.55))
			draw_rect(Rect2(tile_center + Vector2(-14 + i * 9, 4), Vector2(7, 4)), hp_color)

func _draw_connection() -> void:
	var a := Vector2(92, 278)
	var b := Vector2(92, 326)
	draw_line(a, b, Color("#f6d25d"), 4.0)
	draw_line(b, b - Vector2(8, 12), Color("#f6d25d"), 4.0)
	draw_line(b, b - Vector2(-8, 12), Color("#f6d25d"), 4.0)
	draw_string(ThemeDB.fallback_font, Vector2(110, 307), "cough -> bloodflow", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#f6d25d"))

func _draw_pip() -> void:
	var x := QUAD_W
	var panel := Rect2(Vector2(x, 0), Vector2(QUAD_W, QUAD_H))
	draw_rect(panel, Color("#201923"))
	draw_rect(panel.grow(-8), Color("#f6e7d8"), false, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(x + 20, 34), "HOST PIP + RUN STATS", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#f6e7d8"))
	draw_string(ThemeDB.fallback_font, Vector2(x + 20, 58), "Turn %d | %s | Infection %d%%" % [turn, phase.capitalize(), clampi(infection_score, 0, 100)], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#c9bac0"))

	var shake := Vector2(rng.randf_range(-4, 4), rng.randf_range(-2, 2)) * symptom_cough
	var host_rect := Rect2(Vector2(x + 40, 68) + shake, Vector2(146, 150))
	_draw_host_frame(host_rect)

	var cough_text := "COUGHING" if symptom_cough > 0.05 else "breathing"
	draw_string(ThemeDB.fallback_font, Vector2(x + 204, 104), cough_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#ffd7e5"))
	_draw_meter(Vector2(x + 204, 130), "Cough", symptom_cough, Color("#ffd7e5"))
	_draw_meter(Vector2(x + 204, 162), "Fever", symptom_fever, Color("#ff7c58"))
	_draw_meter(Vector2(x + 204, 194), "Oxygen", symptom_oxygen, Color("#80d8ff"))
	_draw_controls()
	_draw_message()

func _draw_meter(pos: Vector2, label: String, value: float, color: Color) -> void:
	draw_string(ThemeDB.fallback_font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#c9bac0"))
	draw_rect(Rect2(pos + Vector2(0, 8), Vector2(104, 10)), Color("#3a2a35"))
	draw_rect(Rect2(pos + Vector2(0, 8), Vector2(104 * clampf(value, 0.0, 1.0), 10)), color)

func _draw_host_frame(rect: Rect2) -> void:
	var frame_index := _host_frame_index()
	var frame_w := float(host_sheet.get_width()) / 8.0
	var source := Rect2(Vector2(frame_w * frame_index, 0), Vector2(frame_w, host_sheet.get_height()))
	var source_aspect := source.size.x / source.size.y
	var target_size := rect.size
	if target_size.x / target_size.y > source_aspect:
		target_size.x = target_size.y * source_aspect
	else:
		target_size.y = target_size.x / source_aspect
	var target_rect := Rect2(rect.position + (rect.size - target_size) * 0.5, target_size)
	draw_texture_rect_region(host_sheet, target_rect, source)

func _host_frame_index() -> int:
	if symptom_cough > 0.05:
		var cough_phase := int(Time.get_ticks_msec() / 130) % 4
		return [4, 5, 6, 7][cough_phase]
	if symptom_oxygen < 0.34 or symptom_fever > 0.70:
		return 3
	if symptom_fever > 0.46:
		return 2
	if symptom_fever > 0.22 or symptom_oxygen < 0.70:
		return 1
	return 0

func _draw_controls() -> void:
	var x := QUAD_W + 20.0
	var y := 258.0
	_button(Rect2(Vector2(x, y), Vector2(116, 32)), "End Turn", "end", phase == "player")
	_button(Rect2(Vector2(x + 126, y), Vector2(164, 32)), "Cough Burst %d/3" % cough_charge, "cough", phase == "player")
	_button(Rect2(Vector2(x + 300, y), Vector2(106, 32)), "Reset", "reset", true)

func _button(rect: Rect2, label: String, action: String, enabled: bool) -> void:
	var fill := Color("#f6d25d") if enabled else Color("#5a4a40")
	var text := Color("#1b1620") if enabled else Color("#b2a49c")
	draw_rect(rect, fill)
	draw_rect(rect, Color("#1b1620"), false, 2.0)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(14, 23), label, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 20, 14, text)
	if enabled:
		buttons.append({"rect": rect, "action": action})

func _draw_message() -> void:
	var rect := Rect2(Vector2(QUAD_W + 20, 224), Vector2(QUAD_W - 40, 24))
	draw_rect(rect, Color("#241d28"))
	draw_rect(rect, Color("#6a5362"), false, 1.0)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(8, 16), message, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 16, 11, Color("#f6e7d8"))

func _draw_empty_third_battle() -> void:
	var panel := Rect2(Vector2(QUAD_W, QUAD_H), Vector2(QUAD_W, QUAD_H))
	draw_rect(panel, Color("#171720"))
	draw_rect(panel.grow(-8), Color("#4c3946"), false, 2.0)
	draw_string(ThemeDB.fallback_font, panel.position + Vector2(22, 34), "THIRD BATTLEFIELD", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#f6e7d8"))
	draw_string(ThemeDB.fallback_font, panel.position + Vector2(22, 56), "empty front reserved for future organs", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#9d8f9a"))
	var center := panel.get_center() + Vector2(0, 10)
	for y in range(4):
		for x in range(5):
			var tile_center := center + Vector2((x - y) * 28.0, (x + y) * 14.0) - Vector2(28, 42)
			var points := PackedVector2Array([
				tile_center + Vector2(0, -10),
				tile_center + Vector2(20, 0),
				tile_center + Vector2(0, 10),
				tile_center + Vector2(-20, 0)
			])
			draw_colored_polygon(points, Color("#24202a"))
			draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[3], points[0]]), Color("#3a303b"), 1.0)

func _alpha(color: Color, alpha: float) -> Color:
	color.a = alpha
	return color

func _draw_texture_cover(texture: Texture2D, rect: Rect2, modulate: Color = Color.WHITE) -> void:
	var texture_size := Vector2(texture.get_width(), texture.get_height())
	var scale := maxf(rect.size.x / texture_size.x, rect.size.y / texture_size.y)
	var source_size := rect.size / scale
	var source_pos := (texture_size - source_size) * 0.5
	draw_texture_rect_region(texture, rect, Rect2(source_pos, source_size), modulate)
