# res://scripts/combatant.gd
class_name Combatant
extends CharacterBody3D

## Combat States
enum State {
	IDLE,
	MOVE,
	ATTACK_WINDUP,
	ATTACK_ACTIVE,
	ATTACK_RECOVERY,
	HIT_STUN,
	STAGGERED,
	KNOCKDOWN,
	DEAD
}

## Combat Variables
@export var max_health: float = 100.0
@export var max_stamina: float = 100.0
@export var move_speed: float = 5.0
@export var hit_stun_duration: float = 0.6  # Adjust to match animation length
@export var allow_attack_movement: bool = true  # Allow attacks to move character

var health: float = 100.0
var stamina: float = 100.0
var current_state: State = State.IDLE
var facing_angle: float = 0.0  # Radians

## State timing
var state_timer: float = 0.0
var current_attack: AttackData = null

## Attack movement tracking
var attack_move_progress: float = 0.0  # 0 to 1 during attack
var attack_start_pos: Vector3 = Vector3.ZERO

## Node references
@onready var mesh_instance: MeshInstance3D = get_node_or_null("MeshInstance3D")
@onready var attack_detector: Area3D = $AttackDetector

## Animation references (optional - override in child classes)
var animation_player: AnimationPlayer
var animation_tree: AnimationTree
var state_machine  # AnimationTree state machine playback

## Signals
signal state_changed(new_state: State)
signal health_changed(new_health: float)
signal died()

func _ready():
	health = max_health
	stamina = max_stamina
	
	# Try to find animation components (optional - child classes can override)
	setup_animations()

func _physics_process(delta: float):
	update_state(delta)
	
	# Stop movement during attack states
	if current_state != State.MOVE:
		velocity.x = 0
		velocity.z = 0
	if allow_attack_movement and (current_state == State.ATTACK_WINDUP or current_state == State.ATTACK_ACTIVE):
		apply_attack_movement(delta)
		
	# Apply facing rotation
	rotation.y = -facing_angle + PI/2
	
	move_and_slide()

func update_state(delta: float):
	state_timer -= delta
	
	match current_state:
		State.IDLE, State.MOVE:
			regen_stamina(delta)
		
		State.ATTACK_WINDUP:
			if state_timer <= 0:
				change_state(State.ATTACK_ACTIVE)
		
		State.ATTACK_ACTIVE:
			if state_timer <= 0:
				change_state(State.ATTACK_RECOVERY)
		
		State.ATTACK_RECOVERY:
			if state_timer <= 0:
				change_state(State.IDLE)
		
		State.HIT_STUN:
			if state_timer <= 0:
				change_state(State.IDLE)
		
		State.DEAD:
			pass  # Stay dead

func change_state(new_state: State):
	current_state = new_state
	state_changed.emit(new_state)
	
	# Play animation for new state
	play_animation_for_state(new_state)
	
	# Set state duration
	match new_state:
		State.ATTACK_WINDUP:
			state_timer = current_attack.windup_time
		State.ATTACK_ACTIVE:
			state_timer = current_attack.active_time
			check_hit()  # Perform hit detection
		State.ATTACK_RECOVERY:
			state_timer = current_attack.recovery_time
		State.HIT_STUN:
			state_timer = hit_stun_duration  # Use configurable duration

func try_attack(attack_data: AttackData) -> bool:
	# Can only attack from IDLE or MOVE
	if current_state != State.IDLE and current_state != State.MOVE:
		return false
	
	# Check stamina
	if stamina < attack_data.stamina_cost:
		return false
	
	# Start attack
	current_attack = attack_data
	stamina -= attack_data.stamina_cost
	change_state(State.ATTACK_WINDUP)
	return true

func check_hit():
	if not current_attack or not attack_detector:
		return
	
	# Get all bodies in attack range
	var bodies = attack_detector.get_overlapping_bodies()
	
	# Debug output
	if bodies.size() > 0:
		print(name, " attack detector found ", bodies.size(), " bodies")
	
	for body in bodies:
		if body == self:
			continue
		
		if body is Combatant:
			# Check if target is in attack arc
			if is_in_attack_arc(body):
				print(name, " HIT ", body.name, " for ", current_attack.health_damage, " damage")
				body.take_damage(current_attack.health_damage)
				on_hit_landed(body)  # Callback for hit effects
			else:
				print(name, " detected ", body.name, " but NOT in attack arc")

func on_hit_landed(target: Combatant):
	# Override this in Player/Enemy for specific effects
	pass

func is_in_attack_arc(target: Combatant) -> bool:
	var to_target = target.global_position - global_position
	var distance = to_target.length()
	
	# Check range
	if distance > current_attack.reach:
		return false
	
	# Check arc angle
	var angle_to_target = atan2(to_target.z, to_target.x)
	var angle_diff = abs(angle_difference(facing_angle, angle_to_target))
	
	var half_arc = deg_to_rad(current_attack.arc_angle / 2.0)
	
	return angle_diff <= half_arc

func angle_difference(a: float, b: float) -> float:
	var diff = b - a
	while diff > PI:
		diff -= TAU
	while diff < -PI:
		diff += TAU
	return diff

func take_damage(damage: float, apply_hitstop: bool = true):
	if current_state == State.DEAD:
		return
	
	health -= damage
	health_changed.emit(health)
	
	# Hit pause effect - freeze the game briefly
	if apply_hitstop:
		apply_hit_freeze(0.05)  # 50ms freeze
	
	if health <= 0:
		health = 0
		change_state(State.DEAD)
		died.emit()
	else:
		# Enter hit stun if not already in attack recovery
		if current_state != State.ATTACK_RECOVERY:
			change_state(State.HIT_STUN)

func apply_hit_freeze(duration: float):
	# Freeze the game for a brief moment
	get_tree().paused = true
	
	# Use a timer that ignores pause
	var timer = get_tree().create_timer(duration, true, false, true)
	await timer.timeout
	
	get_tree().paused = false

func regen_stamina(delta: float):
	stamina = min(stamina + 20.0 * delta, max_stamina)

func set_facing_angle(angle: float):
	facing_angle = angle

func setup_animations():
	# Override this in child classes to set up animation components
	pass

func play_animation_for_state(state: State):
	# Override this in child classes to play appropriate animations
	pass

func apply_attack_movement(delta: float):
	# Apply forward movement during attacks with movement enabled
	if not current_attack:
		return
	
	# Calculate total attack time (windup + active)
	var total_time = current_attack.windup_time + current_attack.active_time
	
	# Calculate forward direction based on facing angle
	var forward_dir = Vector3(cos(facing_angle), 0, sin(facing_angle))
	
	# Calculate movement speed to cover the full distance over attack duration
	var move_speed = current_attack.movement_distance / total_time
	
	# Apply gradual movement
	global_position += forward_dir * move_speed * delta
