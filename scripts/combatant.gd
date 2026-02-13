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
	STAGGERED,      # Posture broken
	KNOCKDOWN,      # Hit while staggered at 0 posture
	PARRY,
	DODGE,
	DEAD
}

## Combat Resources
@export_group("Resources")
@export var max_health: float = 100.0
@export var max_posture: float = 100.0    # Short-term combat resource
@export var max_stamina: float = 100.0    # Long-term recovery engine

## Movement & Timing
@export_group("Movement & Timing")
@export var base_move_speed: float = 5.0
@export var hit_stun_duration: float = 0.4
@export var stagger_duration: float = 2.0
@export var knockdown_duration: float = 3.0
@export var parry_window: float = 0.2
@export var dodge_duration: float = 0.5
@export var dodge_iframes: float = 0.3
@export var allow_attack_movement: bool = true

## Action Costs
@export_group("Action Costs")
@export var parry_stamina_cost: float = 10.0
@export var dodge_stamina_cost: float = 15.0
@export var sprint_stamina_drain: float = 5.0  # Per second
@export var walk_stamina_drain: float = 0.5    # Per second

## Posture Thresholds
@export_group("Posture Effects")
@export var posture_high_threshold: float = 80.0   # Above this = peak performance
@export var posture_low_threshold: float = 40.0    # Below this = major penalties

## Dodge Settings
@export_group("Dodge")
@export var dodge_distance: float = 3.0

## Current Resource Values
var health: float = 100.0
var posture: float = 100.0
var stamina: float = 100.0

var current_state: State = State.IDLE
var facing_angle: float = 0.0

## State timing
var state_timer: float = 0.0
var current_attack: AttackData = null

## Attack movement tracking
var attack_move_progress: float = 0.0
var attack_start_pos: Vector3 = Vector3.ZERO

## Dodge tracking
var dodge_direction: Vector3 = Vector3.ZERO
var is_invulnerable: bool = false

## Combat tracking
var is_in_combat: bool = false
var combat_timer: float = 0.0
var out_of_combat_delay: float = 6.0  # Seconds without taking/dealing damage

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
signal posture_changed(new_posture: float)
signal stamina_changed(new_stamina: float)
signal posture_broken()
signal entered_combat()
signal exited_combat()
signal died()

func _ready():
	health = max_health
	posture = max_posture
	stamina = max_stamina
	setup_animations()

func _physics_process(delta: float):
	update_state(delta)
	update_resources(delta)
	update_combat_state(delta)
	
	# Stop movement during most states
	if current_state != State.MOVE and current_state != State.DODGE:
		velocity.x = 0
		velocity.z = 0
	
	# Attack movement
	if allow_attack_movement and (current_state == State.ATTACK_WINDUP or current_state == State.ATTACK_ACTIVE):
		apply_attack_movement(delta)
	
	# Dodge movement
	if current_state == State.DODGE:
		apply_dodge_movement(delta)
	
	# Apply facing rotation
	rotation.y = -facing_angle + PI/2
	
	move_and_slide()

func update_state(delta: float):
	state_timer -= delta
	
	match current_state:
		State.IDLE, State.MOVE:
			pass  # Resource regen handled in update_resources()
		
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
		
		State.STAGGERED:
			if state_timer <= 0:
				change_state(State.IDLE)
				# Restore some posture after stagger ends
				posture = min(posture + 30.0, max_posture)
				posture_changed.emit(posture)
		
		State.KNOCKDOWN:
			if state_timer <= 0:
				change_state(State.IDLE)
				# Restore more posture after knockdown ends
				posture = min(posture + 50.0, max_posture)
				posture_changed.emit(posture)
		
		State.PARRY:
			if state_timer <= 0:
				change_state(State.IDLE)
		
		State.DODGE:
			# Check if i-frames have ended
			if state_timer <= (dodge_duration - dodge_iframes):
				is_invulnerable = false
			
			if state_timer <= 0:
				change_state(State.IDLE)
		
		State.DEAD:
			pass

## Resource management system
func update_resources(delta: float):
	# Calculate posture regeneration rate based on stamina
	var posture_regen_rate = calculate_posture_regen_rate()
	
	match current_state:
		State.IDLE:
			# Best regen when idle
			posture = min(posture + posture_regen_rate * delta, max_posture)
			posture_changed.emit(posture)
			
			# Stamina regen (in/out of combat)
			if is_in_combat:
				stamina = min(stamina + 2.0 * delta, max_stamina)
			else:
				stamina = min(stamina + 20.0 * delta, max_stamina)
			stamina_changed.emit(stamina)
		
		State.MOVE:
			# Reduced posture regen when moving
			posture = min(posture + posture_regen_rate * 0.5 * delta, max_posture)
			posture_changed.emit(posture)
			
			# Stamina drain from movement (walk)
			stamina = max(stamina - walk_stamina_drain * delta, 0.0)
			stamina_changed.emit(stamina)
			
			# Small stamina regen in combat even while moving
			if is_in_combat:
				stamina = min(stamina + 1.0 * delta, max_stamina)
				stamina_changed.emit(stamina)
		
		State.ATTACK_RECOVERY, State.HIT_STUN, State.STAGGERED, State.KNOCKDOWN:
			# No posture regen during vulnerable states
			pass
		
		State.PARRY, State.DODGE:
			# Minimal posture regen during defensive actions
			posture = min(posture + posture_regen_rate * 0.2 * delta, max_posture)
			posture_changed.emit(posture)

## Calculate posture regen based on stamina level
func calculate_posture_regen_rate() -> float:
	var stamina_percent = stamina / max_stamina
	
	# Stamina-based scaling:
	# 100% stamina = 50 posture/sec
	# 50% stamina = 25 posture/sec
	# 0% stamina = 5 posture/sec (minimal recovery!)
	var base_rate = 50.0
	var min_rate = 5.0
	
	return lerp(min_rate, base_rate, stamina_percent)

## Combat state tracking
func update_combat_state(delta: float):
	if is_in_combat:
		combat_timer += delta
		if combat_timer >= out_of_combat_delay:
			exit_combat()

func enter_combat():
	if not is_in_combat:
		is_in_combat = true
		combat_timer = 0.0
		entered_combat.emit()
		print(name, " entered combat")

func exit_combat():
	if is_in_combat:
		is_in_combat = false
		combat_timer = 0.0
		exited_combat.emit()
		print(name, " exited combat")

func reset_combat_timer():
	combat_timer = 0.0

func change_state(new_state: State):
	# Exit logic for old state
	match current_state:
		State.DODGE:
			is_invulnerable = false
	
	current_state = new_state
	state_changed.emit(new_state)
	play_animation_for_state(new_state)
	
	# Set state duration
	match new_state:
		State.ATTACK_WINDUP:
			state_timer = get_modified_windup_time()
		State.ATTACK_ACTIVE:
			state_timer = current_attack.active_time
			check_hit()
		State.ATTACK_RECOVERY:
			state_timer = current_attack.recovery_time
		State.HIT_STUN:
			state_timer = hit_stun_duration
		State.STAGGERED:
			state_timer = stagger_duration
		State.KNOCKDOWN:
			state_timer = knockdown_duration
		State.PARRY:
			state_timer = parry_window
		State.DODGE:
			state_timer = dodge_duration
			is_invulnerable = true

## Get windup time modified by posture
func get_modified_windup_time() -> float:
	if not current_attack:
		return 0.3
	
	var posture_percent = posture / max_posture
	var penalty_multiplier = 1.0
	
	# Low posture = slower attacks
	if posture < posture_low_threshold:
		# At 0 posture: 1.5x slower
		# At 40 posture: 1.0x normal
		penalty_multiplier = lerp(1.5, 1.0, posture_percent / (posture_low_threshold / 100.0))
	
	return current_attack.windup_time * penalty_multiplier

## Get damage modified by posture
func get_modified_damage() -> float:
	if not current_attack:
		return 0.0
	
	var posture_percent = posture / max_posture
	var damage_multiplier = 1.0
	
	# High posture bonus
	if posture >= posture_high_threshold:
		damage_multiplier = 1.2  # +20% damage when fresh
	# Low posture penalty
	elif posture < posture_low_threshold:
		# At 0 posture: 0.5x damage (half)
		# At 40 posture: 1.0x normal
		damage_multiplier = lerp(0.5, 1.0, posture_percent / (posture_low_threshold / 100.0))
	
	return current_attack.health_damage * damage_multiplier

## Get movement speed modified by posture
func get_modified_move_speed() -> float:
	var posture_percent = posture / max_posture
	var speed_multiplier = 1.0
	
	# Low posture = slower movement
	if posture < posture_low_threshold:
		# At 0 posture: 0.6x speed (40% slower)
		# At 40 posture: 1.0x normal
		speed_multiplier = lerp(0.6, 1.0, posture_percent / (posture_low_threshold / 100.0))
	
	return base_move_speed * speed_multiplier

func try_attack(attack_data: AttackData) -> bool:
	# Can only attack from IDLE or MOVE
	if current_state != State.IDLE and current_state != State.MOVE:
		return false
	# Check stamina cost
	if stamina < attack_data.stamina_cost:
		print(name, " not enough stamina to attack!")
		return false
	
	# Check if posture is too low (can't attack effectively)
	if posture < 10.0:
		print(name, " too exhausted to attack!")
		return false
	
	# Start attack
	current_attack = attack_data
	
	# Drain stamina
	stamina -= attack_data.stamina_cost
	stamina_changed.emit(stamina)
	
	# Enter combat
	enter_combat()
	reset_combat_timer()
	
	change_state(State.ATTACK_WINDUP)
	return true

func try_parry() -> bool:
	# Can only parry from IDLE or MOVE
	if current_state != State.IDLE and current_state != State.MOVE:
		return false
	
	# Check stamina
	if stamina < parry_stamina_cost:
		print(name, " not enough stamina to parry!")
		return false
	
	# Drain stamina
	stamina -= parry_stamina_cost
	stamina_changed.emit(stamina)
	
	# Enter combat
	enter_combat()
	reset_combat_timer()
	
	change_state(State.PARRY)
	return true

func try_dodge(input_direction: Vector3) -> bool:
	# Can only dodge from IDLE or MOVE
	if current_state != State.IDLE and current_state != State.MOVE:
		return false
	
	# Check stamina
	if stamina < dodge_stamina_cost:
		print(name, " not enough stamina to dodge!")
		return false
	
	# Determine dodge direction
	if input_direction.length() > 0.1:
		dodge_direction = input_direction.normalized()
	else:
		# No input - dodge backward
		dodge_direction = Vector3(cos(facing_angle + PI), 0, sin(facing_angle + PI))
	
	# Drain stamina
	stamina -= dodge_stamina_cost
	stamina_changed.emit(stamina)
	
	# Enter combat
	enter_combat()
	reset_combat_timer()
	
	change_state(State.DODGE)
	return true

func apply_dodge_movement(delta: float):
	var dodge_speed = dodge_distance / dodge_duration
	velocity = dodge_direction * dodge_speed

func check_hit():
	if not current_attack or not attack_detector:
		return
	
	var bodies = attack_detector.get_overlapping_bodies()
	
	if bodies.size() > 0:
		print(name, " attack detector found ", bodies.size(), " bodies")
	
	for body in bodies:
		if body == self:
			continue
		
		if body is Combatant:
			# Check if target is in attack arc
			if is_in_attack_arc(body):
				print(name, " HIT ", body.name)
				
				# Check if target is parrying
				if body.current_state == State.PARRY:
					# Check if parry is facing the right direction
					if body.is_attack_within_parry_arc(self):
						print(body.name, " PARRIED ", name, "'s attack!")
						body.on_parry_success(self)
						on_attack_parried(body)
						continue  # Attack was parried, no damage
				
				# Normal hit - use modified damage
				var damage = get_modified_damage()
				body.take_damage(damage)
				body.take_posture_damage(current_attack.posture_damage)
				
				# OFFENSIVE BONUS: Restore stamina on successful hit
				stamina = min(stamina + 8.0, max_stamina)
				stamina_changed.emit(stamina)
				print(name, " restored 8 stamina from hit!")
				
				on_hit_landed(body)
			else:
				print(name, " detected ", body.name, " but NOT in attack arc")

func is_attack_within_parry_arc(attacker: Combatant) -> bool:
	var to_attacker = attacker.global_position - global_position
	var angle_to_attacker = atan2(to_attacker.z, to_attacker.x)
	var angle_diff = abs(angle_difference(facing_angle, angle_to_attacker))
	
	# Parry works in front 120° arc
	return angle_diff <= deg_to_rad(60.0)

func on_parry_success(attacker: Combatant):
	print(name, " successfully parried!")
	
	# Restore stamina on successful parry
	stamina = min(stamina + 15.0, max_stamina)
	stamina_changed.emit(stamina)
	
	# Stagger the attacker
	attacker.force_stagger()
	
	# Visual feedback
	play_parry_effect()

func on_attack_parried(defender: Combatant):
	# Lose extra stamina when parried
	stamina = max(stamina - 10.0, 0.0)
	stamina_changed.emit(stamina)
	
	# Lose posture
	posture = max(posture - 20.0, 0.0)
	posture_changed.emit(posture)
	
	play_deflected_effect()

func force_stagger():
	if current_state == State.DEAD:
		return
	
	# Drop posture significantly
	posture = max(posture - 40.0, 0.0)
	posture_changed.emit(posture)
	
	change_state(State.STAGGERED)

func on_hit_landed(target: Combatant):
	# Override in child classes for specific effects
	pass

func is_in_attack_arc(target: Combatant) -> bool:
	var to_target = target.global_position - global_position
	var distance = to_target.length()
	
	if distance > current_attack.reach:
		return false
	
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
	
	# Check invulnerability (dodge i-frames)
	if is_invulnerable:
		print(name, " dodged the attack!")
		return
	
	# Vulnerability multipliers
	var damage_multiplier = 1.0
	if current_state == State.STAGGERED:
		damage_multiplier = 1.5
	elif current_state == State.KNOCKDOWN:
		damage_multiplier = 2.0
	
	var final_damage = damage * damage_multiplier
	
	health -= final_damage
	health_changed.emit(health)
	
	# Enter combat
	enter_combat()
	reset_combat_timer()
	
	if apply_hitstop:
		apply_hit_freeze(0.05)
	
	if health <= 0:
		health = 0
		change_state(State.DEAD)
		died.emit()
	else:
		# Enter hit stun if not in vulnerable state
		if current_state != State.ATTACK_RECOVERY and current_state != State.STAGGERED and current_state != State.KNOCKDOWN:
			change_state(State.HIT_STUN)

func take_posture_damage(damage: float):
	if current_state == State.DEAD:
		return
	
	# Even parried attacks damage posture!
	posture -= damage
	posture_changed.emit(posture)
	
	# Enter combat
	enter_combat()
	reset_combat_timer()
	
	if posture <= 0:
		posture = 0
		
		# Check if already staggered - if so, knockdown!
		if current_state == State.STAGGERED:
			posture_broken.emit()
			change_state(State.KNOCKDOWN)
			print(name, " KNOCKED DOWN!")
		else:
			posture_broken.emit()
			change_state(State.STAGGERED)
			print(name, " STAGGERED!")

func apply_hit_freeze(duration: float):
	get_tree().paused = true
	var timer = get_tree().create_timer(duration, true, false, true)
	await timer.timeout
	get_tree().paused = false

func set_facing_angle(angle: float):
	facing_angle = angle

func setup_animations():
	# Override in child classes
	pass

func play_animation_for_state(state: State):
	# Override in child classes
	pass

func play_parry_effect():
	# Override in child classes
	pass

func play_deflected_effect():
	# Override in child classes
	pass

func apply_attack_movement(delta: float):
	if not current_attack:
		return
	
	var total_time = current_attack.windup_time + current_attack.active_time
	var forward_dir = Vector3(cos(facing_angle), 0, sin(facing_angle))
	var move_speed_val = current_attack.movement_distance / total_time
	
	global_position += forward_dir * move_speed_val * delta
