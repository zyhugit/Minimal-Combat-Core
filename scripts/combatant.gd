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
@export var max_posture: float = 100.0    # SHORT-TERM: Actions per "breath"
@export var max_stamina: float = 100.0    # LONG-TERM: Fighting endurance

## Movement & Timing
@export_group("Movement & Timing")
@export var base_move_speed: float = 2.0
@export var base_sprint_multiplier: float = 1.8  # How much faster sprinting is
@export var hit_stun_duration: float = 0.4
@export var stagger_duration: float = 2.0
@export var knockdown_duration: float = 3.0
@export var parry_window: float = 0.5
@export var dodge_duration: float = 0.5
@export var dodge_iframes: float = 0.3
@export var allow_attack_movement: bool = true

## Action Costs (REDESIGNED: Posture primary, Stamina secondary)
@export_group("Action Costs")
@export var parry_posture_cost: float = 25.0    # Main cost
@export var parry_stamina_cost: float = 5.0     # Secondary cost
@export var dodge_posture_cost: float = 30.0    # Main cost
@export var dodge_stamina_cost: float = 5.0     # Secondary cost
@export var sprint_posture_drain: float = 15.0  # Per second (main cost)
@export var sprint_stamina_drain: float = 3.0   # Per second (secondary cost)

## Posture Thresholds (affect success rates)
@export_group("Posture Effects")
@export var posture_high_threshold: float = 70.0   # Above this = bonuses
@export var posture_low_threshold: float = 30.0    # Below this = penalties

## Stamina Thresholds (affect success rates)
@export_group("Stamina Effects")
@export var stamina_high_threshold: float = 60.0
@export var stamina_low_threshold: float = 30.0

## Dodge Settings
@export_group("Dodge")
@export var dodge_distance: float = 3.0

## Current Resource Values
var health: float = 100.0
var posture: float = 100.0
var stamina: float = 100.0

var current_state: State = State.IDLE
var previous_state: State = State.IDLE
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

## Sprint tracking
var is_sprinting: bool = false

## Combat tracking
var is_in_combat: bool = false
var combat_timer: float = 0.0
var out_of_combat_delay: float = 3.0

## Node references
@onready var mesh_instance: MeshInstance3D = get_node_or_null("MeshInstance3D")
@onready var attack_detector: Area3D = $AttackDetector

## Animation references
var animation_player: AnimationPlayer
var animation_tree: AnimationTree
var state_machine

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
			pass
		
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
			if state_timer <= (dodge_duration - dodge_iframes):
				is_invulnerable = false
			
			if state_timer <= 0:
				change_state(State.IDLE)
		
		State.DEAD:
			pass

## NEW: Resource management with posture as primary action resource
func update_resources(delta: float):
	var posture_regen_rate = calculate_posture_regen_rate()
	
	match current_state:
		State.IDLE:
			# Best regen when idle
			posture = min(posture + posture_regen_rate * delta, max_posture)
			posture_changed.emit(posture)
			
			# Stamina regen
			if is_in_combat:
				stamina = min(stamina + 0.5 * delta, max_stamina)  # Slightly faster in combat
			else:
				stamina = min(stamina + 2.0 * delta, max_stamina)  # Fast out of combat
			stamina_changed.emit(stamina)
		
		State.MOVE:
			# Reduced posture regen when moving
			posture = min(posture + posture_regen_rate * 0.5 * delta, max_posture)
			posture_changed.emit(posture)
			
			# NEW: Sprint drains both posture and stamina
			if is_sprinting:
				posture = max(posture - sprint_posture_drain * delta, 0.0)
				stamina = max(stamina - sprint_stamina_drain * delta, 0.0)
				posture_changed.emit(posture)
				stamina_changed.emit(stamina)
			
			# Small stamina regen when not sprinting
			if not is_sprinting:
				if is_in_combat:
					stamina = min(stamina + 2.0 * delta, max_stamina)
				stamina_changed.emit(stamina)
		
		State.ATTACK_RECOVERY, State.HIT_STUN, State.STAGGERED, State.KNOCKDOWN:
			# No posture regen during vulnerable states
			pass
		
		State.PARRY, State.DODGE:
			# Minimal posture regen during defensive actions
			posture = min(posture + posture_regen_rate * 0.2 * delta, max_posture)
			posture_changed.emit(posture)

func calculate_posture_regen_rate() -> float:
	var stamina_percent = stamina / max_stamina
	
	# NEW: More aggressive scaling
	# 100% stamina = 60 posture/sec (1.67s to full)
	# 50% stamina = 30 posture/sec (3.3s to full)
	# 0% stamina = 10 posture/sec (10s to full!)
	var base_rate = 60.0
	var min_rate = 10.0
	
	return lerp(min_rate, base_rate, stamina_percent)

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

func exit_combat():
	if is_in_combat:
		is_in_combat = false
		combat_timer = 0.0
		exited_combat.emit()

func reset_combat_timer():
	combat_timer = 0.0

func change_state(new_state: State):
	match current_state:
		State.DODGE:
			is_invulnerable = false
	
	previous_state = current_state
	current_state = new_state
	state_changed.emit(new_state)
	play_animation_for_state(new_state)
	
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

## NEW: Calculate success chance for actions based on BOTH resources
func get_action_success_chance() -> float:
	var posture_percent = posture / max_posture
	var stamina_percent = stamina / max_stamina
	
	# Base success rate
	var base_chance = 1.0
	
	# Posture affects success more (70% weight)
	var posture_modifier = 1.0
	if posture_percent < (posture_low_threshold / 100.0):
		# Low posture: 30% → 70% success
		posture_modifier = lerp(0.3, 0.7, posture_percent / (posture_low_threshold / 100.0))
	elif posture_percent > (posture_high_threshold / 100.0):
		# High posture: 100% → 110% success (can exceed 100%)
		posture_modifier = lerp(1.0, 1.1, (posture_percent - posture_high_threshold / 100.0) / (1.0 - posture_high_threshold / 100.0))
	
	# Stamina affects success less (30% weight)
	var stamina_modifier = 1.0
	if stamina_percent < (stamina_low_threshold / 100.0):
		# Low stamina: 80% → 90% success
		stamina_modifier = lerp(0.8, 0.9, stamina_percent / (stamina_low_threshold / 100.0))
	
	# Weighted combination: 70% posture, 30% stamina
	return base_chance * (posture_modifier * 0.7 + stamina_modifier * 0.3)

func get_modified_windup_time() -> float:
	if not current_attack:
		return 0.3
	
	var success_chance = get_action_success_chance()
	
	# Lower success = slower attacks
	# 30% success = 1.7x slower
	# 100% success = 1.0x normal
	var speed_modifier = lerp(1.7, 1.0, success_chance)
	
	return current_attack.windup_time * speed_modifier

func get_modified_damage() -> float:
	if not current_attack:
		return 0.0
	
	var success_chance = get_action_success_chance()
	
	# Damage scales with success chance
	# 30% success = 0.4x damage
	# 100% success = 1.0x damage
	# 110% success = 1.1x damage (bonus!)
	return current_attack.health_damage * lerp(0.4, 1.0, success_chance)

## NEW: Movement speed affected by both posture and stamina
func get_modified_move_speed() -> float:
	var posture_percent = posture / max_posture
	var stamina_percent = stamina / max_stamina
	
	var speed = base_move_speed
	
	# Posture affects speed more (60% weight)
	var posture_modifier = 1.0
	if posture_percent < (posture_low_threshold / 100.0):
		# Low posture: 0.5x → 1.0x speed
		posture_modifier = lerp(0.5, 1.0, posture_percent / (posture_low_threshold / 100.0))
	
	# Stamina affects speed (40% weight)
	var stamina_modifier = 1.0
	if stamina_percent < (stamina_low_threshold / 100.0):
		# Low stamina: 0.7x → 1.0x speed
		stamina_modifier = lerp(0.7, 1.0, stamina_percent / (stamina_low_threshold / 100.0))
	
	# Weighted combination
	var total_modifier = posture_modifier * 0.6 + stamina_modifier * 0.4
	
	# Apply sprint multiplier if sprinting
	if is_sprinting:
		# Can only sprint at full speed if resources are good
		speed *= base_sprint_multiplier * total_modifier
	else:
		speed *= total_modifier
	
	return speed

## NEW: Attack now costs BOTH posture and stamina
func try_attack(attack_data: AttackData) -> bool:
	if current_state != State.IDLE and current_state != State.MOVE:
		return false
	
	# NEW: Check BOTH resources
	if posture < attack_data.posture_cost:
		print(name, " not enough posture to attack!")
		return false
	
	if stamina < attack_data.stamina_cost:
		print(name, " not enough stamina to attack!")
		return false
	
	# Minimum posture required
	if posture < 10.0:
		print(name, " too exhausted to attack!")
		return false
	
	current_attack = attack_data
	
	# NEW: Drain BOTH resources
	posture -= attack_data.posture_cost
	stamina -= attack_data.stamina_cost
	posture_changed.emit(posture)
	stamina_changed.emit(stamina)
	
	enter_combat()
	reset_combat_timer()
	
	change_state(State.ATTACK_WINDUP)
	return true

## NEW: Parry costs BOTH resources
func try_parry() -> bool:
	if current_state != State.IDLE and current_state != State.MOVE:
		return false
	
	# NEW: Check BOTH resources
	if posture < parry_posture_cost:
		print(name, " not enough posture to parry!")
		return false
	
	if stamina < parry_stamina_cost:
		print(name, " not enough stamina to parry!")
		return false
	
	# NEW: Drain BOTH resources
	posture -= parry_posture_cost
	stamina -= parry_stamina_cost
	posture_changed.emit(posture)
	stamina_changed.emit(stamina)
	
	# NEW: Roll for parry success based on resources
	var success_chance = get_action_success_chance()
	var parry_succeeded = randf() < success_chance
	
	if not parry_succeeded:
		print(name, " parry FAILED (chance was ", success_chance * 100, "%)")
		# Failed parry - just waste resources and go back to idle
		change_state(State.IDLE)
		return false
	
	enter_combat()
	reset_combat_timer()
	
	change_state(State.PARRY)
	return true

## NEW: Dodge costs BOTH resources
func try_dodge(input_direction: Vector3) -> bool:
	if current_state != State.IDLE and current_state != State.MOVE:
		return false
	
	# NEW: Check BOTH resources
	if posture < dodge_posture_cost:
		print(name, " not enough posture to dodge!")
		return false
	
	if stamina < dodge_stamina_cost:
		print(name, " not enough stamina to dodge!")
		return false
	
	# Determine dodge direction
	if input_direction.length() > 0.1:
		dodge_direction = input_direction.normalized()
	else:
		dodge_direction = Vector3(cos(facing_angle + PI), 0, sin(facing_angle + PI))
	
	# NEW: Drain BOTH resources
	posture -= dodge_posture_cost
	stamina -= dodge_stamina_cost
	posture_changed.emit(posture)
	stamina_changed.emit(stamina)
	
	# NEW: Roll for dodge success
	var success_chance = get_action_success_chance()
	var dodge_succeeded = randf() < success_chance
	
	if not dodge_succeeded:
		print(name, " dodge FAILED (chance was ", success_chance * 100, "%)")
		# Failed dodge - movement but no i-frames!
		is_invulnerable = false
	
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
	
	for body in bodies:
		if body == self:
			continue
		
		if body is Combatant:
			if is_in_attack_arc(body):
				# Check if target is parrying
				if body.current_state == State.PARRY:
					if body.is_attack_within_parry_arc(self):
						print(body.name, " PARRIED ", name, "'s attack!")
						body.on_parry_success(self)
						on_attack_parried(body)
						continue
				
				# NEW: Roll for hit success
				var success_chance = get_action_success_chance()
				var hit_succeeded = randf() < success_chance
				
				if not hit_succeeded:
					print(name, " attack MISSED! (chance was ", success_chance * 100, "%)")
					continue
				
				# Hit succeeded!
				var damage = get_modified_damage()
				body.take_damage(damage)
				body.take_posture_damage(current_attack.posture_damage)
				
				# NEW: Smaller stamina restore (attacks cost posture primarily now)
				stamina = min(stamina + 5.0, max_stamina)
				stamina_changed.emit(stamina)
				
				on_hit_landed(body)

func is_attack_within_parry_arc(attacker: Combatant) -> bool:
	var to_attacker = attacker.global_position - global_position
	var angle_to_attacker = atan2(to_attacker.z, to_attacker.x)
	var angle_diff = abs(angle_difference(facing_angle, angle_to_attacker))
	return angle_diff <= deg_to_rad(60.0)

func on_parry_success(attacker: Combatant):
	print(name, " successfully parried!")
	
	# NEW: Restore more posture on successful parry
	posture = min(posture + 35.0, max_posture)
	stamina = min(stamina + 10.0, max_stamina)
	posture_changed.emit(posture)
	stamina_changed.emit(stamina)
	
	attacker.force_stagger()
	play_parry_effect()

func on_attack_parried(defender: Combatant):
	# Lose extra resources when parried
	posture = max(posture - 30.0, 0.0)
	stamina = max(stamina - 10.0, 0.0)
	posture_changed.emit(posture)
	stamina_changed.emit(stamina)
	
	play_deflected_effect()

func force_stagger():
	if current_state == State.DEAD:
		return
	
	posture = max(posture - 40.0, 0.0)
	posture_changed.emit(posture)
	change_state(State.STAGGERED)

func on_hit_landed(target: Combatant):
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
	
	if is_invulnerable:
		print(name, " dodged the attack!")
		return
	
	var damage_multiplier = 1.0
	if current_state == State.STAGGERED:
		damage_multiplier = 1.5
	elif current_state == State.KNOCKDOWN:
		damage_multiplier = 2.0
	
	var final_damage = damage * damage_multiplier
	
	health -= final_damage
	health_changed.emit(health)
	
	enter_combat()
	reset_combat_timer()
	
	if apply_hitstop:
		apply_hit_freeze(0.05)
	
	if health <= 0:
		health = 0
		change_state(State.DEAD)
		died.emit()
	else:
		if current_state != State.ATTACK_RECOVERY and current_state != State.STAGGERED and current_state != State.KNOCKDOWN:
			change_state(State.HIT_STUN)

func take_posture_damage(damage: float):
	if current_state == State.DEAD:
		return
	
	posture -= damage
	posture_changed.emit(posture)
	
	enter_combat()
	reset_combat_timer()
	
	if posture <= 0:
		posture = 0
		
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
	pass

func play_animation_for_state(state: State):
	pass

func play_parry_effect():
	pass

func play_deflected_effect():
	pass

func apply_attack_movement(delta: float):
	if not current_attack:
		return
	
	var total_time = current_attack.windup_time + current_attack.active_time
	var forward_dir = Vector3(cos(facing_angle), 0, sin(facing_angle))
	var move_speed_val = current_attack.movement_distance / total_time
	
	global_position += forward_dir * move_speed_val * delta
