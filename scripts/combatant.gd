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
	BLOCK_STUN,         # After blocking an attack
	DEFLECT_STUN,       # After deflecting perfectly
	DEFLECT_PUNISHED,   # Got deflected (vulnerable!)
	STAGGERED,
	KNOCKDOWN,
	DEFENDING,          # NEW: Single defense state (replaces PARRY + GUARD_RECOVERY)
	DODGE,
	DEAD
}

## Parry Results
enum ParryResult {
	NO_PARRY,
	BLOCKED,
	DEFLECTED
}

## Combat Resources
@export_group("Resources")
@export var max_health: float = 100.0
@export var max_posture: float = 100.0
@export var max_stamina: float = 100.0

## Movement & Timing
@export_group("Movement & Timing")
@export var base_move_speed: float = 2.5
@export var base_sprint_multiplier: float = 1.8
@export var defend_move_speed_mult: float = 0.3  # Move speed while defending (30%)
@export var hit_stun_duration: float = 0.6
@export var block_stun_duration: float = 0.3    # After blocking
@export var deflect_stun_duration: float = 0.1  # After deflecting
@export var deflect_punish_duration: float = 0.5  # After being deflected
@export var stagger_duration: float = 2.0
@export var knockdown_duration: float = 3.0
@export var deflect_window: float = 0.2         # First 0.2s = deflect, after = block
@export var dodge_duration: float = 0.5
@export var dodge_iframes: float = 0.3
@export var allow_attack_movement: bool = true

## Action Costs (Posture primary, Stamina secondary)
@export_group("Action Costs")
@export var parry_stamina_cost: float = 5.0     # Legacy variable (for enemy AI compatibility)
@export var deflect_posture_cost: float = 5.0   # Very cheap
@export var block_posture_cost: float = 20.0    # More expensive
@export var block_health_cost: float = 5.0      # NEW: Chip damage
@export var dodge_posture_cost: float = 30.0
@export var dodge_stamina_cost: float = 5.0
@export var sprint_posture_drain: float = 15.0
@export var sprint_stamina_drain: float = 3.0

## Recovery Rates (NEW: Hybrid system)
@export_group("Recovery Rates")
@export var passive_posture_regen: float = 12.0   # Auto-recovery when idle (slow)
@export var active_posture_regen: float = 50.0    # Manual recovery when guarding (fast)
@export var out_of_combat_stamina_regen: float = 2.0
@export var in_combat_stamina_regen: float = 0.0

## Posture/Stamina Thresholds
@export_group("Resource Thresholds")
@export var posture_high_threshold: float = 70.0
@export var posture_low_threshold: float = 30.0
@export var stamina_high_threshold: float = 60.0
@export var stamina_low_threshold: float = 30.0

## Dodge Settings
@export_group("Dodge")
@export var dodge_distance: float = 3.0

## Current Resource Values
var health: float = 100.0
var posture: float = 100.0
var stamina: float = 100.0  # NEW: Can go to 0, provides penalties only

var current_state: State = State.IDLE
var previous_state: State = State.IDLE
var facing_angle: float = 0.0

## State timing
var state_timer: float = 0.0
var defend_timer: float = 0.0  # Tracks time spent defending (for deflect window)
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
signal deflect_success()     # NEW
signal block_occurred()      # NEW
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
	if current_state != State.MOVE and current_state != State.DEFENDING and current_state != State.DODGE:
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
	
	# Track time spent defending
	if current_state == State.DEFENDING:
		defend_timer += delta
	
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
		
		State.BLOCK_STUN:
			if state_timer <= 0:
				change_state(State.IDLE)
		
		State.DEFLECT_STUN:
			if state_timer <= 0:
				change_state(State.IDLE)
		
		State.DEFLECT_PUNISHED:
			if state_timer <= 0:
				change_state(State.IDLE)
		
		State.STAGGERED:
			if state_timer <= 0:
				change_state(State.IDLE)
				posture = min(posture + 30.0, max_posture)
				posture_changed.emit(posture)
		
		State.KNOCKDOWN:
			if state_timer <= 0:
				change_state(State.IDLE)
				posture = min(posture + 50.0, max_posture)
				posture_changed.emit(posture)
		
		State.DEFENDING:
			# Stay in defending state until player releases button
			pass
		
		State.DODGE:
			if state_timer <= (dodge_duration - dodge_iframes):
				is_invulnerable = false
			
			if state_timer <= 0:
				change_state(State.IDLE)
		
		State.DEAD:
			pass

## NEW: Hybrid recovery system - active regen only out of combat!
func update_resources(delta: float):
	var stamina_percent = stamina / max_stamina
	var stamina_modifier = calculate_stamina_modifier()
	
	match current_state:
		State.IDLE:
			# Passive posture recovery
			var passive_rate = passive_posture_regen * stamina_modifier
			posture = min(posture + passive_rate * delta, max_posture)
			posture_changed.emit(posture)
			
			# Stamina regen
			if is_in_combat:
				stamina = min(stamina + in_combat_stamina_regen * delta, max_stamina)
			else:
				stamina = min(stamina + out_of_combat_stamina_regen * delta, max_stamina)
			stamina_changed.emit(stamina)
		
		State.MOVE:
			# Reduced passive posture regen when moving
			var passive_rate = passive_posture_regen * stamina_modifier * 0.5
			posture = min(posture + passive_rate * delta, max_posture)
			posture_changed.emit(posture)
			
			# Sprint costs
			if is_sprinting:
				posture = max(posture - sprint_posture_drain * delta, 0.0)
				stamina = max(stamina - sprint_stamina_drain * delta, 0.0)
				posture_changed.emit(posture)
				stamina_changed.emit(stamina)
			
			# Small stamina regen when not sprinting
			if not is_sprinting and is_in_combat:
				stamina = min(stamina + in_combat_stamina_regen * delta, max_stamina)
				stamina_changed.emit(stamina)
		
		State.DEFENDING:
			# Active posture recovery ONLY when out of combat!
			if not is_in_combat:
				var active_rate = active_posture_regen * stamina_modifier
				posture = min(posture + active_rate * delta, max_posture)
				posture_changed.emit(posture)
			else:
				# In combat: just passive regen
				var passive_rate = passive_posture_regen * stamina_modifier
				posture = min(posture + passive_rate * delta, max_posture)
				posture_changed.emit(posture)
			
			# Small stamina regen while defending
			if is_in_combat:
				stamina = min(stamina + in_combat_stamina_regen * 0.5 * delta, max_stamina)
				stamina_changed.emit(stamina)
		
		State.ATTACK_RECOVERY, State.HIT_STUN, State.BLOCK_STUN, State.DEFLECT_STUN, State.DEFLECT_PUNISHED, State.STAGGERED, State.KNOCKDOWN:
			# No posture regen during vulnerable states
			pass
		
		State.DODGE:
			# Minimal posture regen
			var passive_rate = passive_posture_regen * stamina_modifier * 0.2
			posture = min(posture + passive_rate * delta, max_posture)
			posture_changed.emit(posture)

## NEW: Stamina affects regeneration and success rates, but doesn't gate actions
func calculate_stamina_modifier() -> float:
	var stamina_percent = stamina / max_stamina
	
	# Stamina affects regen rate:
	# 100% stamina = 1.0x regen
	# 50% stamina = 0.65x regen
	# 0% stamina = 0.3x regen (very slow but not zero!)
	return lerp(0.3, 1.0, stamina_percent)

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
		State.DEFENDING:
			defend_timer = 0.0  # Reset when leaving defense
	
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
		State.BLOCK_STUN:
			state_timer = block_stun_duration
		State.DEFLECT_STUN:
			state_timer = deflect_stun_duration
		State.DEFLECT_PUNISHED:
			state_timer = deflect_punish_duration
		State.STAGGERED:
			state_timer = stagger_duration
		State.KNOCKDOWN:
			state_timer = knockdown_duration
		State.DEFENDING:
			defend_timer = 0.0  # Reset when entering defense
		State.DODGE:
			state_timer = dodge_duration
			is_invulnerable = true

## NEW: Calculate success chance (stamina affects but doesn't prevent)
func get_action_success_chance() -> float:
	var posture_percent = posture / max_posture
	var stamina_percent = stamina / max_stamina
	
	var base_chance = 1.0
	
	# Posture affects success more (70% weight)
	var posture_modifier = 1.0
	if posture_percent < (posture_low_threshold / 100.0):
		posture_modifier = lerp(0.3, 0.7, posture_percent / (posture_low_threshold / 100.0))
	elif posture_percent > (posture_high_threshold / 100.0):
		posture_modifier = lerp(1.0, 1.1, (posture_percent - posture_high_threshold / 100.0) / (1.0 - posture_high_threshold / 100.0))
	
	# NEW: Stamina affects success less (30% weight), but can go very low
	var stamina_modifier = 1.0
	if stamina_percent < (stamina_low_threshold / 100.0):
		# At 0% stamina: 50% success (still usable but unreliable!)
		# At 30% stamina: 85% success
		stamina_modifier = lerp(0.5, 0.85, stamina_percent / (stamina_low_threshold / 100.0))
	elif stamina_percent < (stamina_high_threshold / 100.0):
		stamina_modifier = lerp(0.85, 1.0, (stamina_percent - stamina_low_threshold / 100.0) / ((stamina_high_threshold - stamina_low_threshold) / 100.0))
	return base_chance * (posture_modifier * 0.7 + stamina_modifier * 0.3)

func get_modified_windup_time() -> float:
	if not current_attack:
		return 0.3
	
	var success_chance = get_action_success_chance()
	var speed_modifier = lerp(1.7, 1.0, success_chance)
	
	return current_attack.windup_time * speed_modifier

func get_modified_damage() -> float:
	if not current_attack:
		return 0.0
	
	var success_chance = get_action_success_chance()
	return current_attack.health_damage * lerp(0.4, 1.0, success_chance)

func get_modified_move_speed() -> float:
	var posture_percent = posture / max_posture
	var stamina_percent = stamina / max_stamina
	
	var speed = base_move_speed
	
	var posture_modifier = 1.0
	if posture_percent < (posture_low_threshold / 100.0):
		posture_modifier = lerp(0.5, 1.0, posture_percent / (posture_low_threshold / 100.0))
	
	var stamina_modifier = 1.0
	if stamina_percent < (stamina_low_threshold / 100.0):
		stamina_modifier = lerp(0.6, 1.0, stamina_percent / (stamina_low_threshold / 100.0))
	
	var total_modifier = posture_modifier * 0.6 + stamina_modifier * 0.4
	
	# Slow movement while defending
	if current_state == State.DEFENDING:
		speed *= defend_move_speed_mult * total_modifier
	elif is_sprinting:
		speed *= base_sprint_multiplier * total_modifier
	else:
		speed *= total_modifier
	
	return speed

## NEW: Attack only requires posture (no stamina gate!)
func try_attack(attack_data: AttackData) -> bool:
	if current_state != State.IDLE and current_state != State.MOVE:
		return false
	
	# NEW: Only check posture (stamina provides penalties, not prevention)
	if posture < attack_data.posture_cost:
		print(name, " not enough posture to attack!")
		return false
	
	if posture < 10.0:
		print(name, " too exhausted to attack!")
		return false
	
	current_attack = attack_data
	
	# Drain both resources
	posture -= attack_data.posture_cost
	stamina = max(stamina - attack_data.stamina_cost, 0.0)  # NEW: Can go to 0
	posture_changed.emit(posture)
	stamina_changed.emit(stamina)
	
	enter_combat()
	reset_combat_timer()
	
	change_state(State.ATTACK_WINDUP)
	return true

## Simplified: Start defending (single function)
func try_defend() -> bool:
	if current_state != State.IDLE and current_state != State.MOVE:
		return false
	
	reset_combat_timer()
	
	change_state(State.DEFENDING)
	return true

## Stop defending
func stop_defend():
	if current_state == State.DEFENDING:
		change_state(State.IDLE)

func try_dodge(input_direction: Vector3) -> bool:
	if current_state != State.IDLE and current_state != State.MOVE:
		return false
	
	if posture < dodge_posture_cost:
		print(name, " not enough posture to dodge!")
		return false
	
	if input_direction.length() > 0.1:
		dodge_direction = input_direction.normalized()
	else:
		dodge_direction = Vector3(cos(facing_angle + PI), 0, sin(facing_angle + PI))
	
	posture -= dodge_posture_cost
	stamina = max(stamina - dodge_stamina_cost, 0.0)  # NEW: Can go to 0
	posture_changed.emit(posture)
	stamina_changed.emit(stamina)
	
	# Roll for dodge success
	var success_chance = get_action_success_chance()
	var dodge_succeeded = randf() < success_chance
	
	if not dodge_succeeded:
		print(name, " dodge FAILED (chance was ", success_chance * 100, "%)")
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
				print(name, " hitting ", body.name, " who is in state: ", State.keys()[body.current_state])
				
				# Check if defending
				if body.current_state == State.DEFENDING:
					if body.is_attack_within_parry_arc(self):
						print(name, " → Target is DEFENDING! Timer: ", body.defend_timer, " Window: ", body.deflect_window)
						
						# Timing-based result
						if body.defend_timer <= body.deflect_window:
							# DEFLECT (within timing window)
							print(name, " → DEFLECT!")
							body.on_deflect_success(self)
							continue
						else:
							# BLOCK (after timing window)
							print(name, " → BLOCK!")
							body.on_block_occurred(self)
							continue
					else:
						print(name, " → Attack from behind, defense failed")
				
				# Normal hit
				var success_chance = get_action_success_chance()
				var hit_succeeded = randf() < success_chance
				
				if not hit_succeeded:
					print(name, " attack MISSED! (chance was ", success_chance * 100, "%)")
					continue
				
				var damage = get_modified_damage()
				body.take_damage(damage)
				body.take_posture_damage(current_attack.posture_damage)
				
				stamina = min(stamina + 5.0, max_stamina)
				stamina_changed.emit(stamina)
				
				on_hit_landed(body)

func on_deflect_success(attacker: Combatant):
	deflect_success.emit()
	
	# Very cheap for defender
	posture = max(posture - deflect_posture_cost, 0.0)
	posture_changed.emit(posture)
	
	# Brief recovery
	change_state(State.DEFLECT_STUN)
	
	# Punish attacker severely
	attacker.take_posture_damage(40.0)
	attacker.change_state(State.DEFLECT_PUNISHED)
	
	print(name, " PERFECT DEFLECT!")

## NEW: Block occurred (imperfect timing)
func on_block_occurred(attacker: Combatant):
	block_occurred.emit()
	
	# Expensive for defender
	posture = max(posture - block_posture_cost, 0.0)
	health = max(health - block_health_cost, 0.0)
	posture_changed.emit(posture)
	health_changed.emit(health)
	
	# Check for death from chip damage
	if health <= 0:
		change_state(State.DEAD)
		died.emit()
		return
	
	# Medium recovery
	change_state(State.BLOCK_STUN)
	
	# Attacker loses minimal posture
	attacker.take_posture_damage(5.0)
	
	print(name, " blocked but took chip damage")

func force_stagger():
	if current_state == State.DEAD:
		return
	
	posture = max(posture - 40.0, 0.0)
	posture_changed.emit(posture)
	change_state(State.STAGGERED)

func is_attack_within_parry_arc(attacker: Combatant) -> bool:
	var to_attacker = attacker.global_position - global_position
	var angle_to_attacker = atan2(to_attacker.z, to_attacker.x)
	var angle_diff = abs(angle_difference(facing_angle, angle_to_attacker))
	return angle_diff <= deg_to_rad(60.0)

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
	
	# Damage multipliers for vulnerable states
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

## Virtual functions - Override in child classes (Player/Enemy)
func setup_animations():
	# Override to set up AnimationPlayer and AnimationTree references
	pass

func play_animation_for_state(state: State):
	# Override to play appropriate animations for each state
	pass

func on_hit_landed(target: Combatant):
	# Override for hit effects (screen shake, particles, sounds)
	pass

func play_parry_effect():
	# Override for parry visual/audio feedback
	pass

func play_deflected_effect():
	# Override for deflected visual/audio feedback
	pass

func apply_attack_movement(delta: float):
	if not current_attack:
		return
	
	var total_time = current_attack.windup_time + current_attack.active_time
	var forward_dir = Vector3(cos(facing_angle), 0, sin(facing_angle))
	var move_speed_val = current_attack.movement_distance / total_time
	
	global_position += forward_dir * move_speed_val * delta
