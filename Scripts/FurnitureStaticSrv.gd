class_name FurnitureStaticSrv
extends Node3D # Has to be Node3D. Changing it to RefCounted doesn't work

# Variables to store furniture data
var furniture_transform: FurnitureTransform
var furniture_position: Vector3
var furniture_rotation: int
var furnitureJSON: Dictionary # The json that defines this furniture on the map
var dfurniture: DFurniture # The json that defines this furniture's basics in general
var collider: RID
var shape: RID
var mesh_instance: RID  # Variable to store the mesh instance RID
var quad_instance: RID # RID to the quadmesh that displays the sprite
var myworld3d: World3D

# We have to keep a reference or it will be auto deleted
var support_mesh: PrimitiveMesh
var sprite_texture: Texture2D  # Variable to store the sprite texture
var quad_mesh: PlaneMesh

# Variables to manage door functionality
var is_door: bool = false
var door_state: String = "Closed"  # Default state


# Inner class to keep track of position, rotation and size and keep it central
class FurnitureTransform:
	var posx: float
	var posy: float
	var posz: float
	var rot: int
	var width: float
	var depth: float
	var height: float

	func _init(myposition: Vector3, myrotation: int, size: Vector3):
		width = size.x
		depth = size.z
		height = size.y
		posx = myposition.x
		posy = myposition.y
		posz = myposition.z
		rot = myrotation

	func get_position() -> Vector3:
		return Vector3(posx, posy, posz)

	func set_position(new_position: Vector3):
		posx = new_position.x
		posy = new_position.y
		posz = new_position.z

	func get_rotation() -> int:
		return rot

	func set_rotation(new_rotation: int):
		rot = new_rotation

	func get_sizeV3() -> Vector3:
		return Vector3(width, height, depth)

	func get_sizeV2() -> Vector2:
		return Vector2(width, depth)

	func set_size(new_size: Vector3):
		width = new_size.x
		height = new_size.y
		depth = new_size.z

	func update_transform(new_position: Vector3, new_rotation: int, new_size: Vector3):
		set_position(new_position)
		set_rotation(new_rotation)
		set_size(new_size)
	
	# New method to create a Transform3D
	func get_sprite_transform() -> Transform3D:
		var adjusted_position = get_position() + Vector3(0, 0.5*height+0.01, 0)
		return Transform3D(Basis(Vector3(0, 1, 0), deg_to_rad(rot)), adjusted_position)
	
	func get_cylinder_shape_data() -> Dictionary:
		return {"radius": width / 4.0, "height": height}
	
	# New method to create a Transform3D for visual instances
	func get_visual_transform() -> Transform3D:
		return Transform3D(Basis(Vector3(0, 1, 0), deg_to_rad(rot)), get_position())
	
	func get_box_shape_size() -> Vector3:
		return Vector3(width / 2.0, height / 2.0, depth / 2.0)
		
	func correct_new_position():
		# We have to compensate for the fact that the physicsserver and
		# renderingserver place the furniture lower then the intended height
		posy += 0.5+(0.5*height)
		


# Function to initialize the furniture object
func _init(furniturepos: Vector3, newFurnitureJSON: Dictionary, world3d: World3D):
	furniture_position = furniturepos
	furnitureJSON = newFurnitureJSON
	furniture_rotation = furnitureJSON.get("rotation", 0)
	dfurniture = Gamedata.furnitures.by_id(furnitureJSON.id)
	myworld3d = world3d

	sprite_texture = dfurniture.sprite
	var furniture_size: Vector3 = calculate_furniture_size()

	furniture_transform = FurnitureTransform.new(furniturepos, furniture_rotation, furniture_size)

	if is_new_furniture():
		furniture_transform.correct_new_position()
		apply_edge_snapping_if_needed()

	check_door_functionality()  # Check if this furniture is a door

	set_new_rotation(furniture_rotation) # Apply rotation after setting up the shape and visual instance
	if dfurniture.support_shape.shape == "Box":
		create_box_shape()
		create_visual_instance("Box")
	elif dfurniture.support_shape.shape == "Cylinder":
		create_cylinder_shape()
		create_visual_instance("Cylinder")

	create_sprite_instance()
	update_door_visuals()  # Set initial door visuals based on its state


# Function to calculate the size of the furniture
func calculate_furniture_size() -> Vector3:
	if sprite_texture:
		var sprite_width = sprite_texture.get_width() / 100.0 # Convert pixels to meters
		var sprite_depth = sprite_texture.get_height() / 100.0 # Convert pixels to meters
		var height = dfurniture.support_shape.height
		return Vector3(sprite_width, height, sprite_depth)  # Use height from support shape
	return Vector3(0.5, dfurniture.support_shape.height, 0.5)  # Default size if texture is not set


# Function to create a BoxShape3D collider based on the given size
func create_box_shape():
	shape = PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(shape, furniture_transform.get_box_shape_size())
	
	collider = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(collider, PhysicsServer3D.BODY_MODE_STATIC)
	# Set space, so it collides in the same space as current scene.
	PhysicsServer3D.body_set_space(collider, myworld3d.space)
	PhysicsServer3D.body_add_shape(collider, shape)

	var mytransform = furniture_transform.get_visual_transform()
	PhysicsServer3D.body_set_state(collider, PhysicsServer3D.BODY_STATE_TRANSFORM, mytransform)
	set_collision_layers_and_masks()


# Function to create a visual instance with a mesh to represent the shape
func create_visual_instance(shape_type: String):
	var color = Color.html(dfurniture.support_shape.color)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	if dfurniture.support_shape.transparent:
		material.flags_transparent = true
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	
	if shape_type == "Box":
		support_mesh = BoxMesh.new()
		(support_mesh as BoxMesh).size = furniture_transform.get_sizeV3()
	elif shape_type == "Cylinder":
		support_mesh = CylinderMesh.new()
		(support_mesh as CylinderMesh).height = furniture_transform.height
		(support_mesh as CylinderMesh).top_radius = furniture_transform.width / 4.0
		(support_mesh as CylinderMesh).bottom_radius = furniture_transform.width / 4.0

	support_mesh.material = material

	mesh_instance = RenderingServer.instance_create()
	RenderingServer.instance_set_base(mesh_instance, support_mesh)
	
	RenderingServer.instance_set_scenario(mesh_instance, myworld3d.scenario)
	var mytransform = furniture_transform.get_visual_transform()
	RenderingServer.instance_set_transform(mesh_instance, mytransform)


# Function to create a QuadMesh to display the sprite texture on top of the furniture
func create_sprite_instance():
	quad_mesh = PlaneMesh.new()
	quad_mesh.size = furniture_transform.get_sizeV2()
	var material = StandardMaterial3D.new()
	material.albedo_texture = sprite_texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	#material.flags_unshaded = true  # Optional: make the sprite unshaded
	quad_mesh.material = material
	
	quad_instance = RenderingServer.instance_create()
	RenderingServer.instance_set_base(quad_instance, quad_mesh)
	RenderingServer.instance_set_scenario(quad_instance, myworld3d.scenario)
	
	# Set the transform for the quad instance to be slightly above the box mesh
	RenderingServer.instance_set_transform(quad_instance, furniture_transform.get_sprite_transform())


# Now, update methods that involve position, rotation, and size
func apply_edge_snapping_if_needed():
	if not dfurniture.edgesnapping == "None":
		var new_position = apply_edge_snapping(
			dfurniture.edgesnapping
		)
		furniture_transform.set_position(new_position)


# Function to create a CylinderShape3D collider based on the given size
func create_cylinder_shape():
	shape = PhysicsServer3D.cylinder_shape_create()
	PhysicsServer3D.shape_set_data(shape, furniture_transform.get_cylinder_shape_data())
	
	collider = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(collider, PhysicsServer3D.BODY_MODE_STATIC)
	# Set space, so it collides in the same space as current scene.
	PhysicsServer3D.body_set_space(collider, myworld3d.space)
	PhysicsServer3D.body_add_shape(collider, shape)
	var mytransform = furniture_transform.get_visual_transform()
	PhysicsServer3D.body_set_state(collider, PhysicsServer3D.BODY_STATE_TRANSFORM, mytransform)
	set_collision_layers_and_masks()


# Function to set collision layers and masks
func set_collision_layers_and_masks():
	# Set collision layer to layer 3 (static obstacles layer)
	var collision_layer = 1 << 2  # Layer 3 is 1 << 2

	# Set collision mask to include layers 1, 2, 3, 4, 5, and 6
	var collision_mask = (1 << 0) | (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4) | (1 << 5)
	# Explanation:
	# - 1 << 0: Layer 1 (player layer)
	# - 1 << 1: Layer 2 (enemy layer)
	# - 1 << 2: Layer 3 (movable obstacles layer)
	# - 1 << 3: Layer 4 (static obstacles layer)
	# - 1 << 4: Layer 5 (friendly projectiles layer)
	# - 1 << 5: Layer 6 (enemy projectiles layer)
	
	PhysicsServer3D.body_set_collision_layer(collider, collision_layer)
	PhysicsServer3D.body_set_collision_mask(collider, collision_mask)


# If edge snapping has been set in the furniture editor, we will apply it here.
# The direction refers to the 'backside' of the furniture, which will be facing the edge of the block
# This is needed to put furniture against the wall, or get a fence at the right edge
func apply_edge_snapping(direction: String) -> Vector3:
	# Block size, a block is 1x1 meters
	var blockSize = Vector3(1.0, 1.0, 1.0)
	var newpos = furniture_transform.get_position()
	var size: Vector3 = furniture_transform.get_sizeV3()
	
	# Adjust position based on edgesnapping direction and rotation
	match direction:
		"North":
			newpos.z -= blockSize.z / 2 - size.z / 2
		"South":
			newpos.z += blockSize.z / 2 - size.z / 2
		"East":
			newpos.x += blockSize.x / 2 - size.x / 2
		"West":
			newpos.x -= blockSize.x / 2 - size.x / 2
		# Add more cases if needed
	
	# Consider rotation if necessary
	newpos = rotate_position_around_block_center(newpos, furniture_transform.get_position())
	
	return newpos


# Called when applying edge-snapping so it's put into the right position
func rotate_position_around_block_center(newpos: Vector3, block_center: Vector3) -> Vector3:
	# Convert rotation to radians for trigonometric functions
	var radians = deg_to_rad(furniture_transform.get_rotation())
	
	# Calculate the offset from the block center
	var offset = newpos - block_center
	
	# Apply rotation matrix transformation
	var rotated_offset = Vector3(
		offset.x * cos(radians) - offset.z * sin(radians),
		offset.y,
		offset.x * sin(radians) + offset.z * cos(radians)
	)
	
	# Return the new position
	return block_center + rotated_offset


# Function to set the rotation for this furniture
func set_new_rotation(amount: int):
	var rotation_amount = amount
	if amount == 270:
		rotation_amount = amount - 180
	elif amount == 90:
		rotation_amount = amount + 180
	furniture_transform.set_rotation(rotation_amount)


# Function to get the current rotation of this furniture
func get_my_rotation() -> int:
	return furniture_transform.get_rotation()


# Helper function to determine if the furniture is new
func is_new_furniture() -> bool:
	return not furnitureJSON.has("global_position_x")


# Function to free all resources like the RIDs
func free_resources():
	# Free the mesh instance RID if it exists
	RenderingServer.free_rid(mesh_instance)
	RenderingServer.free_rid(quad_instance)

	# Free the collider shape and body RIDs if they exist
	PhysicsServer3D.free_rid(shape)
	PhysicsServer3D.free_rid(collider)

	# Clear the reference to the DFurniture data if necessary
	dfurniture = null


# Function to check if this furniture acts as a door
func check_door_functionality():
	is_door = not dfurniture.function.door == "None"
	door_state = dfurniture.function.door

# Function to interact with the furniture (e.g., toggling door state)
func interact():
	if is_door:
		toggle_door()

# Function to toggle the door state
func toggle_door():
	door_state = "Open" if door_state == "Closed" else "Closed"
	furnitureJSON["Function"] = {"door": door_state}
	update_door_visuals()

# Update the visuals and physics of the door
func update_door_visuals():
	if not is_door:
		return

	# Adjust rotation based on door state
	var base_rotation = furniture_transform.get_rotation()
	var rotation_angle: int
	var position_offset: Vector3

	# Adjust rotation direction and position offset based on base_rotation
	if base_rotation == 0:
		rotation_angle = base_rotation + (-90 if door_state == "Open" else 0)
		position_offset = Vector3(0.5, 0, 0.5) if door_state == "Open" else Vector3.ZERO  # Move to the right
	elif base_rotation == 90:
		rotation_angle = base_rotation + (-90 if door_state == "Open" else 0)
		position_offset = Vector3(0.5, 0, 0.5) if door_state == "Open" else Vector3.ZERO  # Move backward
	else:
		rotation_angle = base_rotation + (90 if door_state == "Open" else 0)
		position_offset = Vector3(-0.5, 0, -0.5) if door_state == "Open" else Vector3.ZERO  # Standard offset

	apply_transform_to_instance(rotation_angle, position_offset)

# Function to apply the door's transformation
func apply_transform_to_instance(rotation_angle: int, position_offset: Vector3):
	var door_transform = Transform3D(Basis(Vector3(0, 1, 0), deg_to_rad(rotation_angle)), furniture_transform.get_position() + position_offset)
	RenderingServer.instance_set_transform(mesh_instance, door_transform)
	RenderingServer.instance_set_transform(quad_instance, door_transform)
	PhysicsServer3D.body_set_state(collider, PhysicsServer3D.BODY_STATE_TRANSFORM, door_transform)


# Returns this furniture's data for saving, including door state if applicable
func get_data() -> Dictionary:
	var newfurniturejson = {
		"id": furnitureJSON.id,
		"moveable": false,
		"global_position_x": furniture_position.x,
		"global_position_y": furniture_position.y,
		"global_position_z": furniture_position.z,
		"rotation": get_my_rotation(),
	}

	if is_door:
		newfurniturejson["Function"] = {"door": door_state}

	return newfurniturejson
