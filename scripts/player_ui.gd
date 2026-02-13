# res://scripts/player_ui.gd
# Attach this to a CanvasLayer node in main.tscn
extends CanvasLayer

@onready var health_bar: ProgressBar = $VBoxContainer/HealthBar
@onready var stamina_bar: ProgressBar = $VBoxContainer/StaminaBar
@onready var health_label: Label = $VBoxContainer/HealthBar/Label
@onready var stamina_label: Label = $VBoxContainer/StaminaBar/Label

var player: Combatant

func _ready():
	# Find player in scene
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")
	
	if player:
		# Connect to player signals
		player.health_changed.connect(_on_player_health_changed)
		
		# Initialize bars
		update_health()
		update_stamina()

func _process(_delta):
	if player:
		update_stamina()

func update_health():
	if not player or not health_bar:
		return
	
	var health_percent = (player.health / player.max_health) * 100.0
	health_bar.value = health_percent
	health_label.text = "HP: %.0f / %.0f" % [player.health, player.max_health]
	
	# Color coding
	if health_percent > 60:
		health_bar.modulate = Color.GREEN
	elif health_percent > 30:
		health_bar.modulate = Color.YELLOW
	else:
		health_bar.modulate = Color.RED

func update_stamina():
	if not player or not stamina_bar:
		return
	
	var stamina_percent = (player.stamina / player.max_stamina) * 100.0
	stamina_bar.value = stamina_percent
	stamina_label.text = "Stamina: %.0f / %.0f" % [player.stamina, player.max_stamina]
	
	# Flash when low
	if stamina_percent < 30:
		stamina_bar.modulate = Color.RED
	else:
		stamina_bar.modulate = Color(0.3, 0.8, 1.0)  # Cyan

func _on_player_health_changed(_new_health: float):
	update_health()
