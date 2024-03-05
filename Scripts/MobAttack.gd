extends State
class_name MobAttack

@export var attack_timer: Timer
@export var mob: CharacterBody3D
@export var mob_sprite: NodePath

var tween: Tween

var targeted_player

var is_in_attack_mode = false

func Enter():
	attack_timer.start()
	print("ENTERING BATTLE MODE")
	
func Exit():
	pass
	
func Physics_Update(_delta: float):
	
	
	# Rotation towards target using look_at
	if targeted_player:
		var mesh_instance = $"../../MeshInstance3D"
		var target_position = targeted_player.global_position
		target_position.y = mesh_instance.global_position.y  # Align y-axis to avoid tilting
		mesh_instance.look_at(target_position, Vector3.UP)

	var space_state = get_world_3d().direct_space_state
	# TO-DO Change playerCol to group of players
	var query = PhysicsRayQueryParameters3D.create(mob.global_position, targeted_player.global_position, int(pow(2, 1-1) + pow(2, 3-1)), [self])
	var result = space_state.intersect_ray(query)
	

	if result:

		if result.collider.is_in_group("Players") && Vector3(mob.global_position).distance_to(targeted_player.global_position) <= mob.melee_range:

			if !is_in_attack_mode:
				is_in_attack_mode = true
				try_to_attack()			
		else:
			is_in_attack_mode = false
			stop_attacking()
	else:
		is_in_attack_mode = false
		stop_attacking()
		
func try_to_attack():
	print("Trying to attack...")
	attack_timer.start()


func attack():
	print("Attacking!")
#	print(Vector2(targeted_player.position))
#	print(Vector2(targeted_player.global_position))
#	print(Vector2(to_local(targeted_player.position)))
#	print(Vector2(to_local(targeted_player.global_position)))
#	print(Vector2(targeted_player.position - get_node(mob).global_position))

	#3d
#	tween = create_tween()
#	tween.tween_property(get_node(mob_sprite), "position", targeted_player.position - get_node(mob).global_position, 0.1 )
#	tween.tween_property(get_node(mob_sprite), "position", Vector2(0,0), 0.1 )
	
	if targeted_player.has_method("_get_hit"):
		targeted_player._get_hit(mob.melee_damage)
	
	
func stop_attacking():
	print("I stopped attacking")
	attack_timer.stop()
	Transistioned.emit(self, "mobfollow")


func _on_detection_player_spotted(player):
	targeted_player = player # Replace with function body.


func _on_attack_cooldown_timeout():
	attack()
