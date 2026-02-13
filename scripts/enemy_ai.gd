# res://scripts/enemy_ai.gd
extends Combatant

## AI Parameters
@export var light_attack: AttackData
@export var heavy_attack: AttackData  # Optional
@export var detection_range: float = 10.0
@export var attack_range: float = 2.5
@export var retreat_threshold: float = 0.3  # Health percent to retreat

## AI Personality
@export_enum("Aggressive", "Defensive", "Balanced") var personality: String = "Balanced"

## AI State
var target: Combatant = null
var decision_timer: float = 0.0
var chosen_action: String = "idle"
var circling_direction: float = 1.0  # 1 or -1

func _ready():
	super._ready()
	
	# Add to enemy group
	add_to_group("enemy")
	
	# Set up animations
	setup_animations()
	
	# Find player
	await get_tree().process_frame
	target = get_tree().get_first_node_in_group("player")
	
	if not target:
		print("Warning: Enemy could not find player!")
	
	# Random circling direction
	circling_direction = 1.0 if randf() > 0.5 else -1.0

func setup_animations():
	# Find the enemy model instance
	var enemy_model = find_child("EnemyModel", true, false)
	if not enemy_model:
		enemy_model = find_child("*Model", true, false)  # Try any model
	
	if enemy_model:
		animation_player = enemy_model.find_child("AnimationPlayer", true, false)
		animation_tree = enemy_model.find_child("AnimationTree", true, false)
		
		if animation_tree:
			state_machine = animation_tree.get("parameters/playback")
		
		if animation_player:
			print("Enemy animations found!")
		else:
			print("Warning: Enemy AnimationPlayer not found")

func _process(delta: float):
	if current_state == State.DEAD:
		return
	
	# AI decision making
	decision_timer -= delta
	if decision_timer <= 0:
		decide_action()
		decision_timer = randf_range(0.5, 1.5)
	
	# Execute chosen action
	execute_action(delta)

func decide_action():
	if not target:
		chosen_action = "idle"
		return
	
	# Safety check for attack data
	if not light_attack:
		print("Warning: Enemy has no light_attack assigned!")
		chosen_action = "idle"
		return
	
	var distance = global_position.distance_to(target.global_position)
	var player_state = target.current_state
	var health_percent = health / max_health
	var stamina_percent = stamina / max_stamina
	var posture_percent = posture / max_posture
	
	# Debug
	# print(name, " - Distance: %.1f, Posture: %.0f, Stamina: %.0f" % [distance, posture, stamina])
	
	# PRIORITY 1: Punish player recovery
	if player_state == State.ATTACK_RECOVERY:
		if distance <= attack_range + 1.0 and posture >= 10.0:
			chosen_action = "punish"
			return
	
	# PRIORITY 2: Parry incoming attacks (Defensive personality)
	if personality == "Defensive":
		if player_state == State.ATTACK_WINDUP:
			if distance <= attack_range and stamina >= parry_stamina_cost:
				if randf() < 0.5:  # 50% parry chance
					chosen_action = "parry"
					return
	
	# PRIORITY 3: Dodge heavy attacks
	if player_state == State.ATTACK_WINDUP:
		if target.current_attack and target.current_attack.stamina_cost > 20.0:
			if distance <= attack_range and stamina >= dodge_stamina_cost:
				if randf() < 0.3:  # 30% dodge chance
					chosen_action = "dodge"
					return
	
	# PRIORITY 4: Retreat if in danger
	if health_percent < retreat_threshold or (posture_percent < 0.2 and stamina_percent < 0.3):
		if distance < attack_range + 3.0:
			chosen_action = "retreat"
			return
	
	# PRIORITY 5: Attack based on resources and distance
	if distance <= attack_range:
		# Check if we have enough posture to attack
		if posture < 10.0:
			chosen_action = "retreat"  # Too exhausted to attack
			return
		
		# Check stamina for attack
		if stamina < light_attack.stamina_cost:
			chosen_action = "retreat"  # Need to regen
			return
		
		match personality:
			"Aggressive":
				# Prefer heavy attacks if available
				if heavy_attack and stamina >= heavy_attack.stamina_cost and randf() < 0.4:
					chosen_action = "attack_heavy"
				else:
					chosen_action = "attack_light"
			
			"Defensive":
				# Only light attacks
				chosen_action = "attack_light"
			
			"Balanced":
				# Mix based on stamina
				if heavy_attack and stamina > 60.0 and randf() < 0.25:
					chosen_action = "attack_heavy"
				else:
					chosen_action = "attack_light"
		return
	
	# PRIORITY 6: Approach or circle
	if distance > attack_range and distance < detection_range:
		# If low resources, circle to regen
		if stamina_percent < 0.4 or posture_percent < 0.5:
			chosen_action = "circle"
		else:
			chosen_action = "approach"
		return
	
	# Default: idle
	chosen_action = "idle"

func execute_action(delta: float):
	# Can only execute actions when not locked in animation
	if current_state != State.IDLE and current_state != State.MOVE:
		return
	
	match chosen_action:
		"idle":
			if current_state == State.MOVE:
				change_state(State.IDLE)
		
		"approach":
			move_towards_target()
		
		"retreat":
			move_away_from_target()
		
		"circle":
			circle_target()
		
		"attack_light":
			face_target()
			if light_attack:
				try_attack(light_attack)
			else:
				print("Error: light_attack not assigned!")
		
		"attack_heavy":
			face_target()
			if heavy_attack:
				try_attack(heavy_attack)
			else:
				# Fallback to light attack
				if light_attack:
					try_attack(light_attack)
		
		"punish":
			face_target()
			if light_attack:
				try_attack(light_attack)
				print(name, " PUNISHING RECOVERY!")
		
		"parry":
			face_target()
			try_parry()
		
		"dodge":
			var dodge_dir = get_dodge_direction()
			try_dodge(dodge_dir)

func move_towards_target():
	if not target:
		return
	
	var direction = (target.global_position - global_position).normalized()
	direction.y = 0
	
	var speed = get_modified_move_speed() * 0.7  # Slower approach
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	
	facing_angle = atan2(direction.z, direction.x)
	
	if current_state == State.IDLE:
		change_state(State.MOVE)

func move_away_from_target():
	if not target:
		return
	
	var direction = (global_position - target.global_position).normalized()
	direction.y = 0
	
	var speed = get_modified_move_speed()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	
	# Face target while retreating
	facing_angle = atan2(-direction.z, -direction.x)
	
	if current_state == State.IDLE:
		change_state(State.MOVE)

func circle_target():
	if not target:
		return
	
	var to_target = target.global_position - global_position
	to_target.y = 0
	var distance = to_target.length()
	
	# Move tangent to circle around player
	var tangent = Vector3(-to_target.z, 0, to_target.x).normalized() * circling_direction
	
	# Add slight inward/outward bias to maintain distance
	var radial = to_target.normalized()
	if distance > attack_range + 1.5:
		tangent += radial * 0.3  # Move closer
	elif distance < attack_range - 0.5:
		tangent -= radial * 0.3  # Move away
	
	tangent = tangent.normalized()
	
	var speed = get_modified_move_speed() * 0.6  # Slower circling
	velocity.x = tangent.x * speed
	velocity.z = tangent.z * speed
	
	# Always face target while circling
	facing_angle = atan2(to_target.z, to_target.x)
	
	if current_state == State.IDLE:
		change_state(State.MOVE)

func face_target():
	if not target:
		return
	
	var direction = target.global_position - global_position
	direction.y = 0
	facing_angle = atan2(direction.z, direction.x)

func get_dodge_direction() -> Vector3:
	if not target:
		return Vector3.BACK
	
	var to_player = (target.global_position - global_position).normalized()
	to_player.y = 0
	
	# Dodge perpendicular to player
	var perpendicular = Vector3(-to_player.z, 0, to_player.x)
	if randf() < 0.5:
		perpendicular = -perpendicular
	
	return perpendicular

func play_parry_effect():
	print(name, " PARRIED!")
	# TODO: Add enemy parry VFX

func play_deflected_effect():
	print(name, " got DEFLECTED!")
	# TODO: Add enemy deflect VFX

func play_animation_for_state(state: State):
	if not state_machine:
		return
	
	match state:
		State.IDLE:
			state_machine.travel("idle")
		
		State.MOVE:
			state_machine.travel("walk")
		
		State.ATTACK_WINDUP, State.ATTACK_ACTIVE, State.ATTACK_RECOVERY:
			# Use current_attack to determine animation
			if current_attack == heavy_attack and heavy_attack:
				state_machine.travel("heavy attack")
			else:
				state_machine.travel("light attack")
		
		State.HIT_STUN:
			state_machine.travel("hit reaction")
		
		State.STAGGERED:
			# Use hit reaction if no stagger animation
			state_machine.travel("hit reaction")
		
		State.KNOCKDOWN:
			# Use death animation temporarily if no knockdown
			state_machine.travel("death")
		
		State.PARRY:
			# Use idle if no parry animation
			state_machine.travel("idle")
		
		State.DODGE:
			# Use walk if no dodge animation
			state_machine.travel("walk")
		
		State.DEAD:
			state_machine.travel("death")
			# Disable and sink into ground
			set_physics_process(false)
			var tween = create_tween()
			tween.tween_property(self, "global_position:y", global_position.y - 2.0, 2.0)
			tween.tween_callback(queue_free)
