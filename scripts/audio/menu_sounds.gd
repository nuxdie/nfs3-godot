class_name MenuSounds
extends Node
## NFS3's front-end clicks (gamedata/audio/sfx/fesfx.bnk, or High Stakes' Audio/Sfx), put on
## the menu widgets as they enter the tree, so no menu has to know about them:
##   0 a click: an option, tab or picker stepped
##   1 a select: a list entry or browser item picked
##   2 a tick: the highlight moving through a browser
## Game owns one.

const CLICK := 0
const SELECT := 1
const TICK := 2

var _bank: EaBnk
var _player: AudioStreamPlayer
var _last_ms := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.max_polyphony = 3
	_player.bus = Game.BUS_SFX
	add_child(_player)
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(n: Node) -> void:
	if n is OptionRow:
		n.changed.connect(func(_i: int) -> void: play(CLICK))
	elif n is TabStrip:
		n.changed.connect(func(_i: int) -> void: play(CLICK))
	elif n is PickCard:
		n.pressed.connect(func() -> void: play(SELECT))
	elif n is BigButton:
		n.pressed.connect(func() -> void: play(SELECT))
	elif n is TournamentPanel:
		n.focus_changed.connect(func() -> void: play(TICK))
		n.chosen.connect(func(_t: Dictionary, _c: int) -> void: play(SELECT))
	elif n is GaragePanel:
		n.focus_changed.connect(func(_i: int) -> void: play(TICK))
		n.transacted.connect(func() -> void: play(SELECT))
		n.chosen.connect(func(_i: int) -> void: play(SELECT))
	elif n is ActionList:
		n.activated.connect(func(_i: int) -> void: play(SELECT))
	elif n is BrowserBase:
		n.focus_changed.connect(func(_i: int) -> void: play(TICK))
		n.previewed.connect(func(_i: int) -> void: play(TICK))
		n.confirmed.connect(func(_i: int) -> void: play(SELECT))


func play(patch: int) -> void:
	# Several widgets can react to one input (a browser confirming closes onto a picker): one sound.
	var now := Time.get_ticks_msec()
	if now - _last_ms < 40:
		return
	_last_ms = now
	if _bank == null:
		var s := GameSounds.shared()
		_bank = s.fe if s else null
		if _bank == null:
			return
	var st := _bank.stream(patch)
	if st:
		_player.stream = st
		_player.play()
