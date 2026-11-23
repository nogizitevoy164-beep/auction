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
const MIN_ROWS: int = 4             # минимум рядов, если поле низкое

## Сколько НОВЫХ клеток вскрывается в начале каждого раунда.
## Накопительно: 12, 30, 54, 84, 120 — к финалу поле раскрыто сильнее.
const REVEAL_PER_ROUND: Array[int] = [12, 18, 24, 30, 36]

const FOG_COLOR: Color = Color(0.16, 0.15, 0.23, 1.0)      # закрытая клетка
const FOG_MARK_COLOR: Color = Color(0.5, 0.47, 0.68, 0.55) # знак «?»
const EMPTY_REVEALED_COLOR: Color = Color(0.20, 0.20, 0.26, 1.0) # открытая пустая
const GRID_LINE_COLOR: Color = Color(0.25, 0.25, 0.32, 1.0)

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
func reveal_for_round(round: int) -> void:
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
	# 1) Клетки: открытые (предмет/пусто) или закрытые (туман с «?»).
	for r: int in _rows:
		for c: int in FIELD_COLS:
			var key := Vector2i(c, r)
			var rect := Rect2(c * _cell, r * _cell, _cell, _cell)
			if revealed.has(key):
				if _occupancy.has(key):
					draw_rect(rect, items[_occupancy[key]].color, true)
				else:
					draw_rect(rect, EMPTY_REVEALED_COLOR, true)
			else:
				draw_rect(rect, FOG_COLOR, true)

	# 2) Подписи полностью раскрытых предметов.
	var font := ThemeDB.fallback_font
	for i in items.size():
		if is_item_fully_revealed(i):
			var item: Dictionary = items[i]
			var rect := Rect2(
					int(item.col) * _cell, int(item.row) * _cell,
					int(item.w) * _cell, int(item.h) * _cell)
			var font_size := maxi(10, int(_cell * 0.9))
			var baseline := rect.position.y + rect.size.y * 0.5 + font_size * 0.35
			draw_string(font, Vector2(rect.position.x, baseline), String(item.title),
					HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, font_size, Color.WHITE)

	# 3) Сетка поверх.
	for c in FIELD_COLS + 1:
		var x := c * _cell
		draw_line(Vector2(x, 0.0), Vector2(x, _rows * _cell), GRID_LINE_COLOR, 1.0)
	for r in _rows + 1:
		var y := r * _cell
		draw_line(Vector2(0.0, y), Vector2(FIELD_COLS * _cell, y), GRID_LINE_COLOR, 1.0)

	# 4) Знаки «?» на закрытых клетках (поверх сетки).
	if revealed.size() < FIELD_COLS * _rows:
		var font_size := maxi(9, int(_cell * 0.45))
		for r: int in _rows:
			for c: int in FIELD_COLS:
				if revealed.has(Vector2i(c, r)):
					continue
				var baseline := r * _cell + _cell * 0.5 + font_size * 0.35
				draw_string(font, Vector2(c * _cell, baseline), "?",
						HORIZONTAL_ALIGNMENT_CENTER, _cell, font_size, FOG_MARK_COLOR)


## Клик по клетке -> координаты (пригодится для ставок по клеткам).
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var col := int(event.position.x / _cell)
		var row := int(event.position.y / _cell)
		if row >= 0 and row < _rows and col >= 0 and col < FIELD_COLS:
			cell_clicked.emit(row, col)
