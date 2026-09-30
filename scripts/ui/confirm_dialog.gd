class_name ConfirmDialog
extends Control
## A question before something that can't be undone (a new career, selling a car):
## the screen dimmed, a kicker, the question large, a line on what it means, and the two
## answers side by side. ←→ (or the pointer) pick, Enter or a click answers, Esc is always
## "no". It takes all input while it's up and frees itself when answered.

signal answered(yes: bool)

var _kicker := ""
var _title := ""
var _body := ""
var _list: ActionList
var _t := 0.0


## Puts the question over `host` (a full-screen Control); `on_yes` runs on a yes. `yes_first`:
## the yes has the focus to begin with, else the no does.
static func ask(host: Control, kicker: String, title: String, body: String, yes: String, no: String, on_yes: Callable,
		yes_first := false) -> ConfirmDialog:
	var d := ConfirmDialog.new()
	d._kicker = kicker
	d._title = title
	d._body = body
	d._list = ActionList.new(PackedStringArray([yes, no]), true)
	d._list.set_item_size(Vector2(210, 50))
	d._list.focus = 0 if yes_first else 1
	d._list.activated.connect(func(i: int): d._answer(i == 0))
	d.answered.connect(func(ok: bool): if ok: on_yes.call())
	d.add_child(d._list)
	host.add_child(d)
	return d


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	resized.connect(_layout)


func _ready() -> void:
	_layout()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.15)


func _layout() -> void:
	if _list:
		_list.position = Vector2(size.x * 0.5 - _list.size.x * 0.5, size.y * 0.5 + 60)


func _answer(yes: bool) -> void:
	if is_queued_for_deletion():
		return
	answered.emit(yes)
	queue_free()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel") or (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT):
		_answer(false)
	# Nothing gets past it to the screen underneath.
	if e is InputEventKey or e is InputEventJoypadButton or e is InputEventJoypadMotion:
		get_viewport().set_input_as_handled()


func _gui_input(e: InputEvent) -> void:
	# A click outside the answers: no.
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		_answer(false)
		accept_event()


func _process(dt: float) -> void:
	_t += dt
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.012, 0.02, 0.8))
	var c := size * 0.5
	var w := minf(620.0, size.x - 80)
	var x := c.x - w * 0.5
	var kw := UiKit.text_width("cond", _kicker.to_upper(), 13, 2)
	UiKit.kicker(self, Vector2(c.x - kw * 0.5, c.y - 82), _kicker)
	var fs := UiKit.fit("display", _title.to_upper(), w, 52, 28)
	draw_string(UiKit.font("display"), Vector2(x, c.y - 30), _title.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, w, fs, UiKit.INK)
	draw_multiline_string(UiKit.font("body"), Vector2(x, c.y + 6), _body, HORIZONTAL_ALIGNMENT_CENTER, w, 16, 2, UiKit.INK_DIM)
	UiKit.draw_hints(self, Vector2(c.x - 120, c.y + 150), [["←→", "CHOOSE"], ["ENTER", "ANSWER"], ["ESC", "NO"]], 12)
