# res://scripts/enemy_ai.gd
extends Combatant

## AI Parameters
@export var light_attack: AttackData
@export var heavy_attack: AttackData  # Optional
@export var detection_range: float = 10.0
@export var attack_range: float = 2.5
@export var retreat_threshold: float = 0.3

## AI Personality
@export_enum("Aggressive", "Defensive", "Balanced") var personality: String = "Balanced"

## AI State
var target: Combatant = null
var decision_timer: float = 0.0
var chosen_action: String = "idle"
var circling_direction: float = 1.0

func _ready():
	super._ready()
	
	add_to_group("enemy")
	setup_animations()
	
	# Find player
	await get_tree().process_frame
	target = get_tree().get_first_node_in_group("player")
	
	if not target:
		print("Warning: Enemy could not find player!")
	
	circling_direction = 1.0 if randf() > 0.5 else -1.0

func setup_animations():
	var enemy_model = find_child("EnemyModel", true, false)
	if not enemy_model:
		enemy_model = find_child("*Model", true, false)
	
	if enemy_model:
		animation_player = enemy_model.find_child("AnimationPlayer", true, false)
		animation_tree = enemy_model.find_child("AnimationTree", true, false)
		
		if animation_tree:
			state_machine = animation_tree.get("parameters/playback")
			# Make sure AnimationTree is active
			animation_tree.active = true
		
		if animation_player:
			print("Enemy animations found!")
			print("Available animations: ", animation_player.get_animation_list())
		else:
			print("Warning: Enemy AnimationPlayer not found")

func _process(delta: float):
	if current_state == State.DEAD:
		return
	
	decision_timer -= delta
	if decision_timer <= 0:
		decide_action()
		decision_timer = randf_range(0.5, 1.5)
	
	execute_action(delta)

func decide_action():
	if not target:
		chosen_action = "idle"
		return
	
	if not light_attack:
		print("Warning: Enemy has no light_attack assigned!")
		chosen_action = "idle"
		return
	
	var distance = global_position.distance_to(target.global_position)
	var player_state = target.current_state
	var health_percent = health / max_health
	var stamina_percent = stamina / max_stamina
	var posture_percent = posture / max_posture
	
	# PRIORITY 1: Punish player recovery
	if player_state == State.ATTACK_RECOVERY:
		if distance <= attack_range + 1.0 and posture >= 10.0:
			chosen_action = "punish"
			return
	
	# PRIORITY 2: Parry incoming attacks (Defensive personality)
	if personality == "Defensive":
		if player_state == State.ATTACK_WINDUP:
			if distance <= attack_range and stamina >= parry_stamina_cost:
				if randf() < 0.5:
					chosen_action = "parry"
					return
	
	# PRIORITY 3: Dodge heavy attacks
	if player_state == State.ATTACK_WINDUP:
		if target.current_attack and target.current_attack.stamina_cost > 20.0:
			if distance <= attack_range and stamina >= dodge_stamina_cost:
				if randf() < 0.3:
					chosen_action = "dodge"
					return
	
	# PRIORITY 4: Retreat if in danger
	if health_percent < retreat_threshold or (posture_percent < 0.2 and stamina_percent < 0.3):
		if distance < attack_range + 3.0:
			chosen_action = "retreat"
			return
	
	# PRIORITY 5: Attack
	if distance <= attack_range:
		if posture < 10.0:
			chosen_action = "retreat"
			return
		
		if stamina < light_attack.stamina_cost:
			chosen_action = "retreat"
			return
		
		match personality:
			"Aggressive":
				if heavy_attack and stamina >= heavy_attack.stamina_cost and randf() < 0.4:
					chosen_action = "attack_heavy"
				else:
					chosen_action = "attack_light"
			"Defensive":
				chosen_action = "attack_light"
			"Balanced":
				if heavy_attack and stamina > 60.0 and randf() < 0.25:
					chosen_action = "attack_heavy"
				else:
					chosen_action = "attack_light"
		return
	
	# PRIORITY 6: Approach or circle
	if distance > attack_range and distance < detection_range:
		if stamina_percent < 0.4 or posture_percent < 0.5:
			chosen_action = "circle"
		else:
			chosen_action = "approach"
		return
	
	chosen_action = "idle"

func execute_action(delta: float):
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
		
		"attack_heavy":
			face_target()
			if heavy_attack:
				try_attack(heavy_attack)
			else:
				if light_attack:
					try_attack(light_attack)
		
		"punish":
			face_target()
			if light_attack:
				try_attack(light_attack)
		
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
	
	var speed = get_modified_move_speed() * 0.7
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
	
	facing_angle = atan2(-direction.z, -direction.x)
	
	if current_state == State.IDLE:
		change_state(State.MOVE)

func circle_target():
	if not target:
		return
	
	var to_target = target.global_position - global_position
	to_target.y = 0
	var distance = to_target.length()
	
	var tangent = Vector3(-to_target.z, 0, to_target.x).normalized() * circling_direction
	
	var radial = to_target.normalized()
	if distance > attack_range + 1.5:
		tangent += radial * 0.3
	elif distance < attack_range - 0.5:
		tangent -= radial * 0.3
	
	tangent = tangent.normalized()
	
	var speed = get_modified_move_speed() * 0.6
	velocity.x = tangent.x * speed
	velocity.z = tangent.z * speed
	
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
	
	var perpendicular = Vector3(-to_player.z, 0, to_player.x)
	if randf() < 0.5:
		perpendicular = -perpendicular
	
	return perpendicular

func play_parry_effect():
	print(name, " PARRIED!")

func play_deflected_effect():
	print(name, " got DEFLECTED!")

func play_animation_for_state(state: State):
	if not state_machine:
		return
	
	# CRITICAL FIX: Don't use animation_player.play() - only use state_machine
	# The AnimationTree controls the AnimationPlayer
	
	match state:
		State.IDLE:
			state_machine.travel("idle")
		
		State.MOVE:
			state_machine.travel("walk")
		
		State.ATTACK_WINDUP:
			# Use start() to force restart
			if current_attack == heavy_attack and heavy_attack:
				state_machine.start("heavy attack")
			else:
				state_machine.start("light attack")
		
		State.ATTACK_ACTIVE, State.ATTACK_RECOVERY:
			# Let attack animation finish
			pass
		
		State.HIT_STUN:
			state_machine.start("hit reaction")
		
		State.STAGGERED:
			state_machine.start("hit reaction")
		
		State.KNOCKDOWN:
			state_machine.start("death")
		
		State.PARRY:
			state_machine.travel("idle")
		
		State.DODGE:
			state_machine.travel("walk")
		
		State.DEAD:
			state_machine.start("death")
			# Sink into ground
			set_physics_process(false)
			var tween = create_tween()
			tween.tween_property(self, "global_position:y", global_position.y - 2.0, 2.0)
			tween.tween_callback(queue_free)
