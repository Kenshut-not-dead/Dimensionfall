extends RigidBody3D

var velocity = Vector3()
var damage = 10
var lifetime = 5.0

func _ready():
	# Call a function to destroy the projectile after its lifetime expires
	set_lifetime(lifetime)

func _process(_delta):
	# Update the projectile's velocity each frame
	#set_linear_velocity(velocity)
	pass

func set_direction_and_speed(direction: Vector3, speed: float):
	velocity = direction.normalized() * speed
	# Rotate the bullet to match the direction
	rotate_bullet_to_match_direction(direction)
	set_linear_velocity(velocity)

func rotate_bullet_to_match_direction(direction: Vector3):
	# Ensure the direction vector is not zero
	if direction.length() == 0:
		return
	# Calculate the rotation needed to align the bullet's forward direction (usually -Z) with the velocity direction
	var target_rotation = Quaternion(Vector3(0, 0, -1), direction.normalized())
	# Apply the rotation to the bullet
	rotation = target_rotation.get_euler()


func set_lifetime(time: float):
	await get_tree().create_timer(time).timeout
	queue_free()  # Destroy the projectile after the timer

func _on_Projectile_body_entered(body):
	if body.has_method("get_hit"):
		body.get_hit(damage)
	queue_free()  # Destroy the projectile upon collision


func _on_body_shape_entered(_body_rid, _body, _body_shape_index, _local_shape_index):
	queue_free()  # Destroy the projectile upon collision
