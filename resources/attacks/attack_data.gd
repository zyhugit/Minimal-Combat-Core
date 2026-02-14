# res://resources/attack_data.gd
class_name AttackData
extends Resource

## Timing
@export var windup_time: float = 0.3
@export var active_time: float = 0.2
@export var recovery_time: float = 0.5

## Damage
@export var health_damage: float = 25.0
@export var posture_damage: float = 20.0    # Damages target's posture

## NEW: Costs (attacks now cost BOTH resources)
@export var posture_cost: float = 30.0      # PRIMARY cost (large)
@export var stamina_cost: float = 5.0       # SECONDARY cost (small)

## Range
@export var reach: float = 2.0
@export var arc_angle: float = 90.0

## Movement
@export var movement_distance: float = 0.0

## Descriptions
@export var attack_name: String = "Basic Attack"
@export_multiline var description: String = ""
