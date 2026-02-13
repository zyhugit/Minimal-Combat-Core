# res://resources/attacks/attack_data.gd
class_name AttackData
extends Resource

## Attack timing (in seconds)
@export var windup_time: float = 0.3
@export var active_time: float = 0.2
@export var recovery_time: float = 0.4

## Resource costs and damage
@export var stamina_cost: float = 20.0
@export var health_damage: float = 25.0
@export var posture_damage: float = 30.0
@export var stability_damage: float = 20.0

## Hit detection
@export var reach: float = 2.0
@export var arc_angle: float = 90.0  # Degrees (total arc)
@export_enum("High", "Mid", "Low") var height: String = "Mid"

## Flags
@export var causes_unstable: bool = false
@export var vulnerable_to_sweep: bool = false
@export var has_forward_movement: bool = false  # Does animation move forward?
@export var movement_distance: float = 0.0  # How far it moves (if has_forward_movement)

func get_total_duration() -> float:
	return windup_time + active_time + recovery_time
