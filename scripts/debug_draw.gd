# res://scripts/debug_draw.gd
# Add this as a CHILD NODE (Node3D) to Player or Enemy
extends Node3D

@export var show_facing: bool = true
@export var show_attack_arc: bool = true
@export var show_state_label: bool = true

var combatant: Combatant
var label_3d: Label3D

func _ready():
	combatant = get_parent() as Combatant
	
	if not combatant:
		push_error("DebugDraw must be child of Combatant")
		return
	
	# Create 3D label for state
	if show_state_label:
		label_3d = Label3D.new()
		label_3d.pixel_size = 0.01
		label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label_3d.position = Vector3(0, 3.5, 0)
		add_child(label_3d)

func _process(_delta):
	if not combatant:
		return
	
	# Update state label
	if label_3d:
		label_3d.text = "%s\nHP: %.0f\nPost: %.0f\nStam: %.0f" % [
			Combatant.State.keys()[combatant.current_state],
			combatant.health,
			combatant.posture,
			combatant.stamina
		]
	
	# Update debug visuals (they're in local space, so they follow the character automatically)
	update_debug_visuals()

func update_debug_visuals():
	# Clear previous debug meshes
	for child in get_children():
		if child is MeshInstance3D and child.has_meta("debug_mesh"):
			child.queue_free()
	
	# Draw facing direction arrow
	if show_facing:
		draw_arrow(
			Vector3.ZERO,
			Vector3(cos(combatant.facing_angle), 0, sin(combatant.facing_angle)) * 1.5,
			Color.YELLOW
		)
	
	# Draw attack arc during attack
	if show_attack_arc and combatant.current_attack:
		if combatant.current_state == Combatant.State.ATTACK_ACTIVE:
			draw_attack_arc(combatant.current_attack)

func draw_arrow(from: Vector3, to: Vector3, color: Color):
	var mesh_instance = MeshInstance3D.new()
	var immediate_mesh = ImmediateMesh.new()
	var material = StandardMaterial3D.new()
	
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.flags_transparent = true
	
	# Convert to local space by removing parent rotation
	var local_angle = combatant.facing_angle + combatant.rotation.y
	var local_to = Vector3(cos(local_angle), 0, sin(local_angle)) * 1.5
	
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	immediate_mesh.surface_add_vertex(from)
	immediate_mesh.surface_add_vertex(local_to)
	immediate_mesh.surface_end()
	
	mesh_instance.mesh = immediate_mesh
	mesh_instance.material_override = material
	mesh_instance.set_meta("debug_mesh", true)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)

func draw_attack_arc(attack: AttackData):
	var mesh_instance = MeshInstance3D.new()
	var immediate_mesh = ImmediateMesh.new()
	var material = StandardMaterial3D.new()
	
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1, 0, 0, 0.3)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Draw cone/sector in local space
	var segments = 16
	var half_arc = deg_to_rad(attack.arc_angle / 2.0)
	
	# Convert facing angle to local space
	var local_facing = combatant.facing_angle + combatant.rotation.y
	
	for i in range(segments):
		var angle1 = local_facing - half_arc + (i * (attack.arc_angle / segments) * PI / 180.0)
		var angle2 = local_facing - half_arc + ((i + 1) * (attack.arc_angle / segments) * PI / 180.0)
		
		var p1 = Vector3(cos(angle1), 0.5, sin(angle1)) * attack.reach
		var p2 = Vector3(cos(angle2), 0.5, sin(angle2)) * attack.reach
		
		# Triangle fan from origin
		immediate_mesh.surface_add_vertex(Vector3(0, 0.5, 0))
		immediate_mesh.surface_add_vertex(p1)
		immediate_mesh.surface_add_vertex(p2)
	
	immediate_mesh.surface_end()
	
	mesh_instance.mesh = immediate_mesh
	mesh_instance.material_override = material
	mesh_instance.set_meta("debug_mesh", true)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)
