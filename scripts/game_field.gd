class_name GameField
extends Control
## Игровое поле аукциона — сетка строго квадратных клеток (20 колонок).
##
## СОКРОВИЩА СКРЫТЫ: изначально игрок видит только закрытую сетку лота
## и не знает, какие предметы на ней лежат и сколько клеток занимают.
##
## СИСТЕМНОЕ ОТКРЫТИЕ (публичная информация): в начале каждого раунда
## reveal_for_round() автоматически вскрывает несколько случайных клеток
## сразу для всех игроков. Чем позже раунд — тем больше открытых клеток.
## По открытым фрагментам (цветным пятнам предметов и пустым клеткам)
## игроки оценивают реальную стоимость лота и делают ставку.
## Предмет с подписью появляется, когда открыты ВСЕ его клетки.

signal cell_clicked(row: int, col: int)

const FIELD_COLS: int = 20          # клеток по оси X (фиксировано)
const MIN_ROWS: int = 20            # минимум 20×20; при избытке предметов высота растёт

## Сколько НОВЫХ клеток вскрывается в начале каждого раунда.
## Накопительно: 12, 30, 54, 84, 120 — к финалу поле раскрыто сильнее.
const REVEAL_PER_ROUND: Array[int] = [12, 18, 24, 30, 36]

const FOG_COLOR: Color = Color(0.16, 0.15, 0.23, 1.0)      # закрытая клетка
const FOG_MARK_COLOR: Color = Color(0.5, 0.47, 0.68, 0.55) # знак «?»
const EMPTY_REVEALED_COLOR: Color = Color(0.20, 0.20, 0.26, 1.0) # открытая пустая
const GRID_LINE_COLOR: Color = Color(0.25, 0.25, 0.32, 1.0)
const FIELD_BACK_COLOR: Color = Color(0.035, 0.04, 0.075, 1.0)
const TILE_PALETTE: Array[Color] = [
	Color(0.24, 0.18, 0.48, 1.0), Color(0.29, 0.22, 0.58, 1.0),
	Color(0.22, 0.26, 0.58, 1.0), Color(0.34, 0.22, 0.60, 1.0),
]
const TILE_BORDER: Color = Color(0.58, 0.52, 0.88, 0.9)
const TILE_HIGHLIGHT: Color = Color(0.86, 0.72, 1.0, 0.3)

## Текущий раунд аукциона (0 — торгов ещё не было).
var current_round: int = 0
## Пул предметов: [{row, col, w, h, title, color}].
var items: Array = []
## Открытые клетки: ключ Vector2i(колонка, ряд) -> true.
var revealed: Dictionary = {}

var _cell: float = 40.0
var _rows: int = MIN_ROWS
var _occupancy: Dictionary = {}   # Vector2i(колонка, ряд) -> индекс предмета


func _ready() -> void:
	clip_contents = true
	resized.connect(_on_resized)
	_recalculate()


func _on_resized() -> void:
	_recalculate()
	queue_redraw()


## Пересчёт: сторона квадратной клетки и число видимых рядов.
func _recalculate() -> void:
	if size.x > 0.0:
		_cell = size.x / float(FIELD_COLS)
	else:
		_cell = 40.0
	var visible_rows := int(floor(size.y / _cell))
	var required_rows := 0
	for item: Dictionary in items:
		required_rows = maxi(required_rows, int(item.get("row", 0)) + int(item.get("h", 1)))
	_rows = maxi(MIN_ROWS, required_rows if not items.is_empty() else visible_rows)


## Сторона квадратной клетки (ширина == высота).
func cell_size() -> float:
	return _cell


## Сколько рядов клеток сейчас влезает в поле.
func rows_visible() -> int:
	return _rows


## Заменяет пул предметов и перестраивает карту занятости клеток.
func set_items(new_items: Array) -> void:
	items = new_items.duplicate(true)
	_rebuild_occupancy()
	_recalculate()
	queue_redraw()


## Добавляет предмет размером w × h клеток (левый верхний угол — row/col).
func add_item(row: int, col: int, w: int, h: int, title: String,
		color: Color = Color(0.60, 0.60, 0.70)) -> void:
	items.append({"row": row, "col": col, "w": w, "h": h, "title": title, "color": color})
	_rebuild_occupancy()
	queue_redraw()


func _rebuild_occupancy() -> void:
	_occupancy = {}
	for i in items.size():
		var item: Dictionary = items[i]
		for r: int in range(int(item.row), int(item.row) + int(item.h)):
			for c: int in range(int(item.col), int(item.col) + int(item.w)):
				_occupancy[Vector2i(c, r)] = i


## Сброс раскрытия (новый аукцион): сокровища снова полностью скрыты.
func reset_reveal() -> void:
	revealed = {}
	current_round = 0
	queue_redraw()


## СИСТЕМНОЕ ОТКРЫТИЕ: в начале раунда вскрывает порцию случайных
## закрытых клеток — одинаковую для всех игроков. Каждый следующий
## раунд открывает больше клеток, чем предыдущий.
func reveal_for_round(round: int, reveal_seed: int = -1) -> void:
	current_round = clampi(round, 1, 5)
	var total_cells: int = FIELD_COLS * _rows
	var to_reveal: int = mini(REVEAL_PER_ROUND[current_round - 1], total_cells)

	# Собираем ещё закрытые клетки видимой области.
	var hidden_cells: Array[Vector2i] = []
	for r: int in _rows:
		for c: int in FIELD_COLS:
			var key := Vector2i(c, r)
			if not revealed.has(key):
				hidden_cells.append(key)

	# Открываем случайные из них.
	if reveal_seed >= 0:
		var reveal_rng := RandomNumberGenerator.new()
		reveal_rng.seed = reveal_seed + current_round * 7919
		for index in range(hidden_cells.size() - 1, 0, -1):
			var swap_index := reveal_rng.randi_range(0, index)
			var cell := hidden_cells[index]
			hidden_cells[index] = hidden_cells[swap_index]
			hidden_cells[swap_index] = cell
	else:
		hidden_cells.shuffle()
	for i: int in mini(to_reveal, hidden_cells.size()):
		revealed[hidden_cells[i]] = true
	queue_redraw()


## Сколько клеток уже открыто (публичная информация раунда).
func revealed_count() -> int:
	return revealed.size()


## Полностью ли открыт предмет (все его клетки видимы) — тогда видна подпись.
func is_item_fully_revealed(index: int) -> bool:
	var item: Dictionary = items[index]
	for r: int in range(int(item.row), int(item.row) + int(item.h)):
		for c: int in range(int(item.col), int(item.col) + int(item.w)):
			if not revealed.has(Vector2i(c, r)):
				return false
	return true


func _draw() -> void:
	# 1) Декоративная основа поля: квадратные плитки с фиолетово-синим
	# магическим узором, визуально близким к референсу.
	draw_rect(Rect2(0.0, 0.0, FIELD_COLS * _cell, _rows * _cell), FIELD_BACK_COLOR, true)
	for r: int in _rows:
		for c: int in FIELD_COLS:
			var key := Vector2i(c, r)
			var rect := Rect2(c * _cell, r * _cell, _cell, _cell)
			_draw_magic_tile(rect, c, r, revealed.has(key))

	# 2) Места предметов затемняются как крупные области на поле. Размер и
	# цвет рамки остаются видимыми даже до полного раскрытия.
	for item: Dictionary in items:
		var item_rect := Rect2(
				int(item.get("col", 0)) * _cell, int(item.get("row", 0)) * _cell,
				int(item.get("w", 1)) * _cell, int(item.get("h", 1)) * _cell)
		draw_rect(item_rect.grow(-3.0), Color(0.035, 0.055, 0.075, 0.88), true)
		draw_rect(item_rect.grow(-2.0), Color(0.45, 0.55, 0.72, 0.38), false, 1.0)

	# 3) Предметы: до полного раскрытия видны только контур, размер,
	# цвет качества и тип. Картинка и подробности появляются только после
	# открытия всех клеток предмета.
	var font := ThemeDB.fallback_font
	for i in items.size():
		var item: Dictionary = items[i]
		var rect := Rect2(
				int(item.get("col", 0)) * _cell, int(item.get("row", 0)) * _cell,
				int(item.get("w", 1)) * _cell, int(item.get("h", 1)) * _cell)
		var quality_color: Color = item.get("color", Color(0.60, 0.60, 0.70))
		var revealed_item := is_item_fully_revealed(i)
		# Неоновая подсветка качества и толстая рамка как у предметных ячеек
		# из референса.
		var glow := quality_color
		glow.a = 0.28
		draw_rect(rect.grow(-1.0), glow, false, 7.0)
		draw_rect(rect.grow(-2.0), Color(quality_color.r, quality_color.g, quality_color.b, 0.16), true)
		draw_rect(rect.grow(-2.0), quality_color, false, 3.5)
		var type_text := _item_type_label(String(item.get("type", "item")))
		var size_text := "%d×%d" % [int(item.get("w", 1)), int(item.get("h", 1))]
		var small_size := maxi(9, int(_cell * 0.28))
		draw_string(font, rect.position + Vector2(4.0, small_size + 3.0), type_text,
				HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 8.0, small_size, Color.WHITE)
		draw_string(font, Vector2(rect.position.x, rect.end.y - 5.0), size_text,
				HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, small_size, quality_color.lightened(0.25))
		if not revealed_item:
			continue
		var icon_path := String(item.get("icon", ""))
		if not icon_path.is_empty():
			var icon := load(icon_path) as Texture2D
			if icon != null:
				draw_texture_rect(icon, rect.grow(-5.0), false, Color(1, 1, 1, 0.92))
		var title_size := maxi(9, int(_cell * 0.34))
		var title_baseline := rect.position.y + rect.size.y * 0.5 + title_size * 0.35
		draw_string(font, Vector2(rect.position.x + 3.0, title_baseline), String(item.get("title", "")),
				HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 6.0, title_size, Color.WHITE)
	# 4) Сетка поверх.
	for c in FIELD_COLS + 1:
		var x := c * _cell
		draw_line(Vector2(x, 0.0), Vector2(x, _rows * _cell), Color(0.08, 0.08, 0.15, 0.7), 1.0)
	for r in _rows + 1:
		var y := r * _cell
		draw_line(Vector2(0.0, y), Vector2(FIELD_COLS * _cell, y), Color(0.08, 0.08, 0.15, 0.7), 1.0)

	# 5) Знаки «?» на закрытых клетках (поверх сетки).
	if revealed.size() < FIELD_COLS * _rows:
		var font_size := maxi(9, int(_cell * 0.45))
		for r: int in _rows:
			for c: int in FIELD_COLS:
				if revealed.has(Vector2i(c, r)):
					continue
				var baseline := r * _cell + _cell * 0.5 + font_size * 0.35
				draw_string(font, Vector2(c * _cell, baseline), "?",
						HORIZONTAL_ALIGNMENT_CENTER, _cell, font_size, FOG_MARK_COLOR)


func _draw_magic_tile(rect: Rect2, col: int, row: int, is_revealed: bool) -> void:
	var tile := StyleBoxFlat.new()
	tile.bg_color = TILE_PALETTE[abs(col * 17 + row * 31) % TILE_PALETTE.size()]
	if not is_revealed:
		tile.bg_color = tile.bg_color.darkened(0.18)
	tile.border_color = TILE_BORDER
	tile.set_border_width_all(1)
	tile.set_corner_radius_all(maxi(3, int(_cell * 0.08)))
	draw_style_box(tile, rect.grow(-1.5))
	var inner := rect.grow(-4.0)
	var arc_color := TILE_HIGHLIGHT if is_revealed else Color(0.65, 0.58, 0.9, 0.16)
	var radius := maxf(4.0, _cell * 0.43)
	draw_arc(inner.get_center() + Vector2(-_cell * 0.28, _cell * 0.28), radius,
			-2.35, -0.65, 12, arc_color, maxf(1.0, _cell * 0.035), true)
	if abs(col * 13 + row * 7) % 5 == 0:
		var star := inner.get_center() + Vector2(_cell * 0.14, -_cell * 0.12)
		draw_line(star - Vector2(_cell * 0.16, 0.0), star + Vector2(_cell * 0.16, 0.0), arc_color, 1.4)
		draw_line(star - Vector2(0.0, _cell * 0.16), star + Vector2(0.0, _cell * 0.16), arc_color, 1.4)


func _item_type_label(item_type: String) -> String:
	match item_type:
		"equipment": return "Снаряжение"
		"weapon": return "Оружие"
		"ingredient": return "Ингредиент"
		"potion": return "Зелье"
		"sellable": return "Предмет"
		_: return item_type.capitalize()


## Клик по клетке -> координаты (пригодится для ставок по клеткам).
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var col := int(event.position.x / _cell)
		var row := int(event.position.y / _cell)
		if row >= 0 and row < _rows and col >= 0 and col < FIELD_COLS:
			cell_clicked.emit(row, col)
