# res://scripts/enemy_ai.gd
extends Combatant

## AI State
enum AIState {
	OBSERVE,
	DECIDE,
	COMMIT
}

## AI Parameters
@export var detection_range: float = 10.0
@export var attack_range: float = 2.5
@export var light_attack: AttackData

var ai_state: AIState = AIState.OBSERVE
var target: Combatant = null
var decision_timer: float = 0.0
var chosen_action: String = ""

func _ready():
	super._ready()
	
	# Set up animations
	setup_animations()
	
	# Find player
	await get_tree().process_frame
	target = get_tree().get_first_node_in_group("player")

func setup_animations():
	# Find the enemy model instance (adjust name if different)
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

func _physics_process(delta: float):
	if current_state == State.DEAD:
		return
	
	# Always run AI when not in attack states
	if target and current_state != State.ATTACK_WINDUP and current_state != State.ATTACK_ACTIVE and current_state != State.ATTACK_RECOVERY and current_state != State.HIT_STUN:
		run_ai(delta)
	
	super._physics_process(delta)

func run_ai(delta: float):
	match ai_state:
		AIState.OBSERVE:
			observe_target()
		
		AIState.DECIDE:
			decision_timer -= delta
			if decision_timer <= 0:
				decide_action()
		
		AIState.COMMIT:
			execute_action()

func observe_target():
	if not target:
		print("Enemy: No target found!")
		return
	
	var distance = global_position.distance_to(target.global_position)
	
	# Face target
	var to_target = target.global_position - global_position
	facing_angle = atan2(to_target.z, to_target.x)
	
	# Debug
	# print("Enemy observing. Distance: ", distance)
	
	if distance < detection_range:
		# Start decision process
		ai_state = AIState.DECIDE
		decision_timer = randf_range(0.5, 1.0)

func decide_action():
	if not target:
		ai_state = AIState.OBSERVE
		return
	
	var distance = global_position.distance_to(target.global_position)
	
	# Debug
	print("Enemy deciding. Distance: %.2f, Attack range: %.2f, Stamina: %.2f" % [distance, attack_range, stamina])
	
	# Simple decision tree
	if distance <= attack_range and stamina >= light_attack.stamina_cost:
		chosen_action = "attack"
		print("Enemy chose: ATTACK")
	elif distance > attack_range + 1.0:
		chosen_action = "approach"
		print("Enemy chose: APPROACH")
	else:
		chosen_action = "wait"
		print("Enemy chose: WAIT")
	
	ai_state = AIState.COMMIT

func execute_action():
	print("Enemy executing: ", chosen_action)
	
	match chosen_action:
		"attack":
			if try_attack(light_attack):
				print("Enemy attack started!")
			else:
				print("Enemy attack FAILED - state: ", State.keys()[current_state], " stamina: ", stamina)
			ai_state = AIState.OBSERVE
		
		"approach":
			if target:
				var direction = (target.global_position - global_position).normalized()
				velocity.x = direction.x * move_speed * 0.7
				velocity.z = direction.z * move_speed * 0.7
				print("Enemy approaching. Velocity: ", velocity)
				
				# Change to MOVE state if not already
				if current_state == State.IDLE:
					change_state(State.MOVE)
			ai_state = AIState.OBSERVE
		
		"wait":
			velocity = Vector3.ZERO
			if current_state == State.MOVE:
				change_state(State.IDLE)
			ai_state = AIState.OBSERVE

func _on_died():
	# Disable collision and sink into ground
	set_physics_process(false)
	var tween = create_tween()
	tween.tween_property(self, "global_position:y", global_position.y - 2.0, 1.0)
	tween.tween_callback(queue_free)

func play_animation_for_state(state: State):
	# Play animations based on state
	if not state_machine:
		return
	
	match state:
		State.IDLE:
			state_machine.travel("idle")
		State.MOVE:
			state_machine.travel("walk")
		State.ATTACK_WINDUP:
			state_machine.travel("light attack")
		State.ATTACK_ACTIVE:
			pass  # Continue same animation
		State.ATTACK_RECOVERY:
			pass  # Continue same animation
		State.HIT_STUN:
			state_machine.travel("hit reaction")
		State.DEAD:
			state_machine.travel("death")
