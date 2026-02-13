# res://scripts/player.gd
extends Combatant

## Attack data
@export var light_attack: AttackData
@export var heavy_attack: AttackData  # ADD THIS
## Camera reference (set in main scene)
var camera: Camera3D
var camera_controller  # Reference to camera script for shake

## Input buffering
var buffered_attack: AttackData = null

func _ready():
	super._ready()
	
	# Set up animations
	setup_animations()
	
	# Find camera
	camera = get_viewport().get_camera_3d()
	if camera and camera.has_method("add_trauma"):
		camera_controller = camera

func setup_animations():
	# Get the PlayerModel instance and find animation components
	var player_model = find_child("PlayerModel", true, false)
	if not player_model:
		player_model = find_child("*Model", true, false)  # Try any model
	
	if player_model:
		animation_player = player_model.find_child("AnimationPlayer", true, false)
		animation_tree = player_model.find_child("AnimationTree", true, false)
		
		if animation_tree:
			state_machine = animation_tree.get("parameters/playback")
		
		if animation_player:
			print("Player animations found!")
		else:
			print("Warning: Player AnimationPlayer not found")

func _physics_process(delta: float):
	if current_state != State.DEAD:
		handle_input(delta)
	
	super._physics_process(delta)

func handle_input(delta: float):
	# Right-click to set facing direction
	if Input.is_action_just_pressed("face_mouse"):
		update_facing_from_mouse()
	
	# Movement (only in IDLE or MOVE states)
	if current_state == State.IDLE or current_state == State.MOVE:
		handle_movement(delta)
	
	# Heavy attack (check FIRST - has priority)
	if Input.is_action_just_pressed("attack_heavy"):
		update_facing_from_mouse()
		if not try_attack(heavy_attack):
			if current_state == State.ATTACK_RECOVERY:
				buffered_attack = heavy_attack
	
	# Light attack
	elif Input.is_action_just_pressed("attack_light"):
		update_facing_from_mouse()
		if not try_attack(light_attack):
			if current_state == State.ATTACK_RECOVERY:
				buffered_attack = light_attack
	
	# Process buffered attack
	if buffered_attack and (current_state == State.IDLE or current_state == State.MOVE):
		try_attack(buffered_attack)
		buffered_attack = null

func handle_movement(delta: float):
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	
	if input_dir.length() > 0:
		# Move relative to CAMERA, not character
		var cam_forward = -camera.global_transform.basis.z
		var cam_right = camera.global_transform.basis.x
		cam_forward.y = 0
		cam_right.y = 0
		cam_forward = cam_forward.normalized()
		cam_right = cam_right.normalized()
		
		var move_dir = (cam_forward * -input_dir.y + cam_right * input_dir.x).normalized()
		
		velocity.x = move_dir.x * move_speed
		velocity.z = move_dir.z * move_speed
		
		# Optional: Face movement direction when not in combat
		# Uncomment this if you want character to turn while walking
		# if current_state == State.IDLE or current_state == State.MOVE:
		#     facing_angle = atan2(move_dir.z, move_dir.x)
		
		if current_state == State.IDLE:
			change_state(State.MOVE)
	else:
		velocity.x = 0
		velocity.z = 0
		
		if current_state == State.MOVE:
			change_state(State.IDLE)

func update_facing_from_mouse():
	if not camera:
		return
	
	# Get mouse position in 3D world
	var mouse_pos = get_viewport().get_mouse_position()
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * 1000.0
	
	# Raycast to ground plane
	var plane = Plane(Vector3.UP, global_position.y)
	var intersection = plane.intersects_ray(from, to - from)
	
	if intersection:
		var look_dir = intersection - global_position
		facing_angle = atan2(look_dir.z, look_dir.x)

func _on_state_changed(new_state: State):
	# Additional visual feedback specific to player
	match new_state:
		State.ATTACK_ACTIVE:
			if attack_detector:
				attack_detector.visible = true
		State.ATTACK_RECOVERY, State.IDLE:
			if attack_detector:
				attack_detector.visible = false
		State.DEAD:
			if mesh_instance:
				mesh_instance.material_override.albedo_color = Color.DARK_RED

func play_animation_for_state(state: State):
	if not state_machine:
		return
	
	match state:
		State.IDLE:
			state_machine.travel("idle")
		State.MOVE:
			state_machine.travel("walk")
		State.ATTACK_WINDUP:
			# Different animation based on attack type
			if current_attack == heavy_attack:
				state_machine.travel("heavy attack")
			else:
				state_machine.travel("light attack")
		State.HIT_STUN:
			state_machine.travel("hit reaction")
		State.DEAD:
			state_machine.travel("death")

func on_hit_landed(target: Combatant):
	if not camera_controller:
		return
	
	# Different shake based on attack type
	if current_attack == heavy_attack:
		camera_controller.shake_heavy()  # BIG shake
	else:
		camera_controller.shake_light()  # Small shake
