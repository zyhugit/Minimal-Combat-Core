# res://scripts/player.gd
extends Combatant

## Attack data
@export var light_attack: AttackData
@export var heavy_attack: AttackData

## Camera reference
var camera: Camera3D
var camera_controller  # Reference to camera script for shake

## Input buffering
var buffered_attack: AttackData = null

func _ready():
	super._ready()
	
	# Add to player group
	add_to_group("player")
	
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
	if Input.is_action_pressed("face_mouse"):  # Changed to pressed for continuous tracking
		update_facing_from_mouse()
	
	# Movement (only in IDLE or MOVE states)
	if current_state == State.IDLE or current_state == State.MOVE:
		handle_movement(delta)
	
	# Parry
	if Input.is_action_just_pressed("parry"):
		try_parry()
	
	# Dodge
	if Input.is_action_just_pressed("dodge"):
		var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var dodge_dir = Vector3.ZERO
		
		if input_dir.length() > 0:
			# Dodge in movement direction (camera-relative)
			var cam_forward = -camera.global_transform.basis.z
			var cam_right = camera.global_transform.basis.x
			cam_forward.y = 0
			cam_right.y = 0
			cam_forward = cam_forward.normalized()
			cam_right = cam_right.normalized()
			dodge_dir = (cam_forward * -input_dir.y + cam_right * input_dir.x).normalized()
		
		try_dodge(dodge_dir)
	
	# Heavy attack (check FIRST - has priority)
	if Input.is_action_just_pressed("attack_heavy"):
		update_facing_from_mouse()
		if heavy_attack:  # Safety check
			if not try_attack(heavy_attack):
				if current_state == State.ATTACK_RECOVERY:
					buffered_attack = heavy_attack
		else:
			print("Warning: Heavy attack not assigned!")
	
	# Light attack
	elif Input.is_action_just_pressed("attack_light"):
		update_facing_from_mouse()
		if light_attack:  # Safety check
			if not try_attack(light_attack):
				if current_state == State.ATTACK_RECOVERY:
					buffered_attack = light_attack
		else:
			print("Warning: Light attack not assigned!")
	
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
		
		# Use modified move speed (affected by posture)
		var speed = get_modified_move_speed()
		velocity.x = move_dir.x * speed
		velocity.z = move_dir.z * speed
		
		if current_state == State.IDLE:
			change_state(State.MOVE)
	else:
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

func on_hit_landed(target: Combatant):
	# Screen shake on hit
	if camera_controller:
		if current_attack == heavy_attack:
			camera_controller.shake_heavy()  # BIG shake
		else:
			camera_controller.shake_light()  # Small shake

func play_parry_effect():
	# Flash effect or particle
	print("⚔️ PERFECT PARRY!")
	
	# TODO: Add visual/audio feedback
	# if mesh_instance:
	#     flash_material(Color.CYAN)
	# $ParrySound.play()

func play_deflected_effect():
	print("❌ ATTACK DEFLECTED!")
	
	# TODO: Add visual/audio feedback
	# if mesh_instance:
	#     flash_material(Color.RED)

func play_animation_for_state(state: State):
	if not state_machine:
		return
	
	match state:
		State.IDLE:
			state_machine.travel("idle")
		
		State.MOVE:
			state_machine.travel("walk")
		
		State.ATTACK_WINDUP, State.ATTACK_ACTIVE, State.ATTACK_RECOVERY:
			# Different animation based on attack type
			if current_attack == heavy_attack:
				state_machine.travel("heavy attack")
			else:
				state_machine.travel("light attack")
		
		State.HIT_STUN:
			state_machine.travel("hit reaction")
		
		State.STAGGERED:
			# Use hit reaction if no stagger animation
			state_machine.travel("hit reaction")
		
		State.KNOCKDOWN:
			# Use death animation temporarily if no knockdown animation
			state_machine.travel("death")
		
		State.PARRY:
			# Use idle if no parry animation yet
			state_machine.travel("idle")
		
		State.DODGE:
			# Use walk if no dodge animation yet
			state_machine.travel("walk")
		
		State.DEAD:
			state_machine.travel("death")
