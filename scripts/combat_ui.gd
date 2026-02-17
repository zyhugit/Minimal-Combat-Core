# res://ui/combat_ui.gd
extends Control

@onready var health_bar: ProgressBar = $MarginContainer/VBoxContainer/HealthBar
@onready var posture_bar: ProgressBar = $MarginContainer/VBoxContainer/PostureBar
@onready var stamina_bar: ProgressBar = $MarginContainer/VBoxContainer/StaminaBar
@onready var status_label: Label = $MarginContainer/VBoxContainer/StatusLabel

var player: Combatant

func _ready():
	player = get_tree().get_first_node_in_group("player")
	
	if player:
		# Connect signals
		player.health_changed.connect(_on_health_changed)
		player.posture_changed.connect(_on_posture_changed)
		player.stamina_changed.connect(_on_stamina_changed)
		player.state_changed.connect(_on_state_changed)
		player.posture_broken.connect(_on_posture_broken)
		player.entered_combat.connect(_on_entered_combat)
		player.exited_combat.connect(_on_exited_combat)
		
		# Initialize bars
		_on_health_changed(player.health)
		_on_posture_changed(player.posture)
		_on_stamina_changed(player.stamina)
		
		# Style bars
		setup_bar_styles()

func setup_bar_styles():
	# Health bar - Red
	health_bar.modulate = Color.RED
	
	# Posture bar - Starts cyan
	posture_bar.modulate = Color.CYAN
	
	# Stamina bar - Yellow
	stamina_bar.modulate = Color.YELLOW

func _on_health_changed(new_health: float):
	health_bar.value = (new_health / player.max_health) * 100

func _on_posture_changed(new_posture: float):
	posture_bar.value = (new_posture / player.max_posture) * 100
	
	var posture_percent = new_posture / player.max_posture
	
	# Color coding based on posture level
	if posture_percent >= 0.8:
		posture_bar.modulate = Color.CYAN  # High - good
	elif posture_percent >= 0.4:
		posture_bar.modulate = Color.LIGHT_BLUE  # Medium - okay
	else:
		posture_bar.modulate = Color.ORANGE  # Low - danger!

func _on_stamina_changed(new_stamina: float):
	stamina_bar.value = (new_stamina / player.max_stamina) * 100
	
	var stamina_percent = new_stamina / player.max_stamina
	
	# Flash red when critically low
	if stamina_percent < 0.2:
		stamina_bar.modulate = Color.DARK_RED
	elif stamina_percent < 0.4:
		stamina_bar.modulate = Color.ORANGE
	else:
		stamina_bar.modulate = Color.YELLOW

func _on_state_changed(new_state: Combatant.State):
	# Show current state
	var state_names = {
		Combatant.State.IDLE: "",
		Combatant.State.MOVE: "",
		Combatant.State.ATTACK_WINDUP: "Attacking...",
		Combatant.State.ATTACK_ACTIVE: "Attacking!",
		Combatant.State.ATTACK_RECOVERY: "Recovering...",
		Combatant.State.HIT_STUN: "Hit!",
		Combatant.State.STAGGERED: "STAGGERED!",
		Combatant.State.KNOCKDOWN: "KNOCKED DOWN!",
		Combatant.State.DEFENDING: "Parrying...",
		Combatant.State.DODGE: "Dodging!",
		Combatant.State.DEAD: "DEAD"
	}
	
	status_label.text = state_names.get(new_state, "")
	
	# Color code status
	match new_state:
		Combatant.State.STAGGERED, Combatant.State.KNOCKDOWN:
			status_label.modulate = Color.RED
		Combatant.State.DEFENDING:
			status_label.modulate = Color.CYAN
		Combatant.State.DODGE:
			status_label.modulate = Color.GREEN
		_:
			status_label.modulate = Color.WHITE

func _on_posture_broken():
	# Flash the screen or show warning
	flash_screen(Color(0, 1, 1, 0.3))  # Cyan flash
	
	# Play sound
	# $BreakSound.play()

func _on_entered_combat():
	# Maybe show combat indicators
	print("⚔️ COMBAT START")

func _on_exited_combat():
	# Maybe hide combat indicators
	print("🛡️ COMBAT END - Stamina regen boost!")

func flash_screen(color: Color):
	var flash = ColorRect.new()
	flash.color = color
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	var tween = create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, 0.5)
	tween.tween_callback(flash.queue_free)
