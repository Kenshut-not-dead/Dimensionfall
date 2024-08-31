extends CharacterBody3D

signal update_doll

signal update_stamina_HUD

var is_alive = true

var rng = RandomNumberGenerator.new()

var speed = 2  # speed in meters/sec
var current_speed

var run_multiplier = 1.1
var is_running = false

var left_arm_health = 100
var current_left_arm_health
var right_arm_health = 100
var current_right_arm_health
var head_health = 100
var current_head_health
var torso_health = 100
var current_torso_health
var left_leg_health = 100
var current_left_leg_health
var right_leg_health = 100
var current_right_leg_health

var stamina = 100
var current_stamina
var stamina_lost_while_running_persec = 15
var stamina_regen_while_standing_still = 3

var nutrition = 100
var current_nutrition

var pain
var current_pain = 0

var stats = {}
var skills = {}
# Dictionary that holds instances of PlayerAttribute. For example food, water, mood
var attributes = {}

var time_since_ready = 0.0
var delay_before_movement = 2.0  # 2 second delay
# Variable to store the last recorded y level
var last_y_level: int = 0

@export var sprite : Sprite3D
@export var collisionDetector : Area3D # Used for detecting collision with furniture

@export var interact_range : float = 10

#@export var progress_bar : NodePath
#@export var progress_bar_filling : NodePath
#@export var progress_bar_timer : NodePath

@export var foostep_player : AudioStreamPlayer
@export var foostep_stream_randomizer : AudioStreamRandomizer


# Variables for furniture pushing
var pushing_furniture = false
var furniture_body: RID
#var progress_bar_timer_max_time : float

#var is_progress_bar_well_progressing_i_guess = false


func _ready():
	initialize_health()
	initialize_condition()
	initialize_attributes()
	initialize_stats_and_skills()
	Helper.save_helper.load_player_state(self)
	Helper.signal_broker.food_item_used.connect(_on_food_item_used)
	Helper.signal_broker.medical_item_used.connect(_on_medical_item_used)
	ItemManager.craft_successful.connect(_on_craft_successful)
	# Connect signals for collisionDetector to detect furniture
	collisionDetector.body_shape_entered.connect(_on_body_entered)
	collisionDetector.body_shape_exited.connect(_on_body_exited)
	Helper.signal_broker.player_spawned.emit(self)
	initialize_y_level_check()


func initialize_health():
	current_left_arm_health = left_arm_health
	current_right_arm_health = right_arm_health
	current_left_leg_health = left_leg_health
	current_right_leg_health = right_leg_health
	current_head_health = head_health
	current_torso_health = torso_health


func initialize_condition():
	current_stamina = stamina
	current_nutrition = nutrition
	current_pain = pain


# Initializes the playerattributes based on the DPlayerAttribute
# The PlayerAttribute manages the actual control of the attribute while
# DPlayerAttribute only provides the data
func initialize_attributes():
	var playerattributes: Dictionary = Gamedata.playerattributes.get_all()
	for attribute: DPlayerAttribute in playerattributes.values():
		attributes[attribute.id] = PlayerAttribute.new(attribute, self)


# Initialize skills with level and XP
func initialize_stats_and_skills():
	# Initialize all stats with a value of 5
	for stat in Gamedata.stats.get_all().values():
		stats[stat.id] = 5
	Helper.signal_broker.player_stat_changed.emit(self)
	
	# Initialize all skills with a value of level 1 and 0 XP
	for skill in Gamedata.skills.get_all().values():
		skills[skill.id] = {"level": 1, "xp": 0}
	Helper.signal_broker.player_skill_changed.emit(self)


func _process(_delta):
	# Get the 2D screen position of the player
	var camera = get_tree().get_first_node_in_group("Camera")
	var player_screen_pos = camera.unproject_position(global_position)

	# Get the mouse position in 2D screen space
	var mouse_pos_2d = get_viewport().get_mouse_position()

	# Calculate the direction vector from the player to the mouse position
	var dir = (mouse_pos_2d - player_screen_pos).normalized()

	# Calculate the angle between the player and the mouse position
	# Since the sprite is rotating in the opposite direction, change the sign of the angle
	var angle = atan2(-dir.y, -dir.x)  # This negates both components of the direction vector

	sprite.rotation.y = -angle  # Inverts the angle for rotation
	$CollisionShape3D.rotation.y = -angle  # Inverts the angle for rotation


#	if is_progress_bar_well_progressing_i_guess:
#		get_node(progress_bar_filling).scale.x = lerp(1, 0, get_node(progress_bar_timer).time_left / progress_bar_timer_max_time)



func _physics_process(delta):
	time_since_ready += delta
	if time_since_ready < delay_before_movement:
		# Skip movement updates during the delay period to prevent 
		# the player from falling into the ground while the ground is spawning.
		return

	# Added an arbitrary multiplier because without it, the player will fall slowly
	var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
	velocity.y -= gravity * 12 * delta
	move_and_slide()

	if is_alive:
		var input_dir = Input.get_vector("left", "right", "up", "down")
		var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

		# Athletics skill level
		var athletics_level = get_skill_level("athletics")

		# Calculate run multiplier based on athletics skill level
		run_multiplier = 1.1 + (athletics_level / 100.0) * (2.0 - 1.1)

		# Calculate stamina lost while running based on athletics skill level
		stamina_lost_while_running_persec = 15 - (athletics_level / 100.0) * (15 - 5)

		# Calculate stamina regeneration while standing still based on athletics skill level
		stamina_regen_while_standing_still = 3 + (athletics_level / 100.0) * (8 - 3)

		# Check if the player is pushing furniture
		if pushing_furniture and furniture_body:
			# Apply resistance based on the mass of the furniture collider
			var mass = PhysicsServer3D.body_get_param(furniture_body, PhysicsServer3D.BODY_PARAM_MASS)
			var resistance = 1.0 / mass
			velocity = direction * speed * resistance
		else:
			if not is_running or current_stamina <= 0:
				velocity = direction * speed
			elif is_running and current_stamina > 0:
				velocity = direction * speed * run_multiplier

				if velocity.length() > 0:
					current_stamina -= delta * stamina_lost_while_running_persec
					# Add XP for running
					add_skill_xp("athletics", 0.01)

		if velocity.length() < 0.1:
			current_stamina += delta * stamina_regen_while_standing_still
			if current_stamina > stamina:
				current_stamina = stamina

		update_stamina_HUD.emit(current_stamina)

		move_and_slide()


# When a body enters the CollisionDetector area
# This will be a FurniturePhysicsSrv since it's only detecting layer 4
# Layer 4 is the moveable furniture layer
# Since FurniturePhysicsSrv is not in the scene tree, we will have an RID but no body
func _on_body_entered(body_rid: RID, body: Node3D, _body_shape_index: int, _local_shape_index: int):
	if body_rid and not body:
		pushing_furniture = true
		furniture_body = body_rid


func _on_body_exited(body_rid: RID, body: Node3D, _body_shape_index: int, _local_shape_index: int):
	if body_rid and not body:
		pushing_furniture = false


func _input(event):
	if event.is_action_pressed("run"):
		is_running = true
	if event.is_action_released("run"):
		is_running = false
		
	#checking if we can interact with the object
	if event.is_action_pressed("interact"):
		var layer = pow(2, 1-1) + pow(2, 2-1) + pow(2, 3-1)
		var mouse_pos : Vector2 = get_viewport().get_mouse_position()
		var raycast: Dictionary = Helper.raycast_from_mouse(mouse_pos, layer)
		if not raycast.has("position"):
			return
		var world_mouse_position = raycast.position
		var result = Helper.raycast(global_position, global_position + (Vector3(world_mouse_position.x - global_position.x, 0, world_mouse_position.z - global_position.z)).normalized() * interact_range, layer, [self])

		print_debug("Interact button pressed")
		if result:
			print_debug("Found object with collider")
			Helper.signal_broker.player_interacted.emit(result.position, result.rid)
				

# The player gets hit by an attack
# attributeid: The PlayerAttribute that is targeted by this attack
# damage: The amount to subtract from the target attribute
func _get_hit(attributeid: String, damage: float):
	attributes[attributeid].reduce_amount(damage)
	var limb_number = rng.randi_range(0,5)
	
	match limb_number:
		0:
			current_head_health -= damage
			if current_head_health <= 0:
				current_head_health = 0
				check_if_alive()
		1:
			if current_right_arm_health <= 0:
				transfer_damage_to_torso(damage)
			else: 
				current_right_arm_health -= damage
				if current_right_arm_health < 0:
					current_right_arm_health = 0
		2:
			if current_left_arm_health <= 0:
				transfer_damage_to_torso(damage)
			else: 
				current_left_arm_health -= damage
				if current_left_arm_health < 0:
					current_left_arm_health = 0
		3:
			current_torso_health -= damage
			if current_torso_health <= 0:
				current_torso_health = 0
				check_if_alive()
		4:
			if current_right_leg_health <= 0:
				transfer_damage_to_torso(damage)
			else: 
				current_right_leg_health -= damage
				if current_right_leg_health < 0:
					current_right_leg_health = 0
		5:
			if current_left_leg_health <= 0:
				transfer_damage_to_torso(damage)
			else: 
				current_left_leg_health -= damage
				if current_left_leg_health < 0:
					current_left_leg_health = 0
			
	update_doll.emit(current_head_health, current_right_arm_health, current_left_arm_health, current_torso_health, current_right_leg_health, current_left_leg_health)

func check_if_alive():
	if current_torso_health <= 0:
		current_torso_health = 0
		die()
	elif current_head_health <= 0:
		current_head_health = 0
		die()

#
#func check_if_visible(target_position: Vector3):
	#
	#var space_state = get_world_3d().direct_space_state
	## TO-DO Change playerCol to group of players
	#var query = PhysicsRayQueryParameters3D.create(global_position, target_position, pow(2, 1-1) + pow(2, 3-1) + pow(2, 2-1),[self])
	#var result = space_state.intersect_ray(query)
	#
	#if result:
		#print("I see something!")
		#return false
	#else:
		#print("I see nothing!")
		#return true

func die():
	if is_alive:
		print("Player died")
		is_alive = false
		$"../../../HUD".get_node("GameOver").show()

func transfer_damage_to_torso(damage: float):
	current_torso_health -= damage
	check_if_alive()


func play_footstep_audio():
	foostep_player.stream = foostep_stream_randomizer
	foostep_player.play()


# The player has selected one or more items in the inventory and selected
# 'use' from the context menu.
func _on_food_item_used(usedItem: InventoryItem) -> void:
	var food = DItem.Food.new(usedItem.get_property("Food"))
	var was_used: bool = false

	for attribute in food.attributes:
		attributes[attribute.id].modify_current_amount(attribute.amount)
		was_used = true

	if was_used:
		var stack_size: int = InventoryStacked.get_item_stack_size(usedItem)
		InventoryStacked.set_item_stack_size(usedItem,stack_size-1)


# The player has selected one or more items in the inventory and selected
# 'use' from the context menu.
func _on_medical_item_used(usedItem: InventoryItem) -> void:
	
	var medical = DItem.Medical.new(usedItem.get_property("Medical"))
	var was_used: bool = false

	# Step 1: Apply specific amounts to each attribute
	# example of medical.attributes: [{"id":"torso","amount":10}]
	was_used = _apply_specific_attribute_amounts(medical.attributes) or was_used

	# Step 2: Apply the general medical amount from the pool
	was_used = _apply_general_medical_amount(medical) or was_used

	# If any attribute was modified, reduce the item stack size by 1
	if was_used:
		var stack_size: int = InventoryStacked.get_item_stack_size(usedItem)
		InventoryStacked.set_item_stack_size(usedItem, stack_size - 1)

# Function to apply specific amounts to each attribute
# medattributes: Attributes assigned to the medical item
# For example: [{"id":"torso","amount":10}] would add 10 to the "torso" attribute
func _apply_specific_attribute_amounts(medattributes: Array) -> bool:
	var was_used: bool = false

	for medattribute in medattributes:
		# Get the values from the current player's attribute
		var playerattribute: PlayerAttribute = attributes[medattribute.id]
		var current_amount = playerattribute.current_amount
		var max_amount = playerattribute.max_amount
		var min_amount = playerattribute.min_amount

		# Make sure we don't add or subtract more then the min and max amount
		var new_amount = clamp(current_amount + medattribute.amount, min_amount, max_amount)

		# If the new amount is different from the current amount, apply the change
		if new_amount != current_amount:
			playerattribute.modify_current_amount(new_amount - current_amount)
			was_used = true
	
	return was_used

# Function to apply the general medical amount from the pool
# See the DItem class and its Medical subclass for the properties of DItem.Medical
func _apply_general_medical_amount(medical: DItem.Medical) -> bool:
	var was_used: bool = false
	var pool = medical.amount
	
	# Get the matching PlayerAttributes based on medical attributes
	var matching_player_attributes = get_matching_player_attributes(medical.attributes)
	
	# Separate attributes based on depletion_effect == "death"
	var death_effect_attributes: Array[PlayerAttribute] = []
	var other_attributes: Array[PlayerAttribute] = []

	for playerattribute in matching_player_attributes:
		if playerattribute.depletion_effect == "death":
			death_effect_attributes.append(playerattribute)
		else:
			other_attributes.append(playerattribute)
	
	# First, apply the pool to attributes with the death effect
	var sorted_death_attributes = _sort_player_attributes_by_order(death_effect_attributes, medical.order)
	pool = _apply_pool_to_attributes(sorted_death_attributes, pool, was_used)
	
	# Then, apply the remaining pool to the other attributes
	var sorted_other_attributes = _sort_player_attributes_by_order(other_attributes, medical.order)
	pool = _apply_pool_to_attributes(sorted_other_attributes, pool, was_used)
	
	return was_used

# Helper function to apply the pool to a given array of PlayerAttributes
func _apply_pool_to_attributes(attributes: Array[PlayerAttribute], pool: float, was_used: bool) -> float:
	for playerattribute in attributes:
		var current_amount = playerattribute.current_amount
		var max_amount = playerattribute.max_amount
		var min_amount = playerattribute.min_amount
		
		# Calculate how much can actually be added from the pool
		var additional_amount = min(pool, max_amount - current_amount)
		
		# Make sure that amount is not more or less than the min and max amount for the attribute
		var new_amount = clamp(current_amount + additional_amount, min_amount, max_amount)
		
		# Update the pool after applying the additional amount
		pool -= (new_amount - current_amount)
		
		# If the new amount is different from the current amount, apply the change
		if not new_amount == current_amount:
			playerattribute.modify_current_amount(new_amount - current_amount)
			was_used = true
		
		# If the pool is exhausted, break out of the loop
		if pool <= 0:
			break

	return pool


# Sort PlayerAttributes based on the specified order
func _sort_player_attributes_by_order(myattributes: Array[PlayerAttribute], order: String) -> Array[PlayerAttribute]:
	match order:
		"Ascending":
			# Reverse the array and return it
			myattributes.reverse()
			return myattributes
		"Descending":
			# Use the original order of medical.attributes
			return myattributes
		"Lowest first":
			myattributes.sort_custom(_compare_player_attributes_by_current_amount_ascending)
		"Highest first":
			myattributes.sort_custom(_compare_player_attributes_by_current_amount_descending)
		"Random":
			myattributes.shuffle()
		_:
			# Default to no sorting if an invalid order is provided
			pass
	return myattributes

# Custom sorting functions for PlayerAttributes
func _compare_player_attributes_by_current_amount_ascending(a: PlayerAttribute, b: PlayerAttribute) -> bool:
	return a.current_amount < b.current_amount

func _compare_player_attributes_by_current_amount_descending(a: PlayerAttribute, b: PlayerAttribute) -> bool:
	return a.current_amount > b.current_amount


# Function to retrieve PlayerAttributes that match the IDs in medical.attributes
func get_matching_player_attributes(med_attributes: Array) -> Array[PlayerAttribute]:
	var matching_attributes: Array[PlayerAttribute] = []

	# Loop over each attribute in the medical item's attributes
	for med_attr in med_attributes:
		var attr_id = med_attr.get("id", "")
		
		# Check if the player has an attribute with the same ID
		if attributes.has(attr_id):
			# Add the corresponding PlayerAttribute to the array
			matching_attributes.append(attributes[attr_id])
	
	return matching_attributes



# Heal the player by the specified amount. We prioritize the head and torso for healing
# After that, we prioritize the most damaged part
# It returns the remaining amount that wasn't spent on healing
# You can use this to see if the healing item is depleted or used at all
func heal_player(amount: int) -> int:
	# Create a dictionary with part names and their current/max health
	var body_parts = {
		"head": {"current": current_head_health, "max": head_health},
		"torso": {"current": current_torso_health, "max": torso_health},
		"left_arm": {"current": current_left_arm_health, "max": left_arm_health},
		"right_arm": {"current": current_right_arm_health, "max": right_arm_health},
		"left_leg": {"current": current_left_leg_health, "max": left_leg_health},
		"right_leg": {"current": current_right_leg_health, "max": right_leg_health}
	}

	# Gather keys, filter, and sort. We prioritize the head and torso
	var other_parts = body_parts.keys().filter(
		func(k): return k != "head" and k != "torso"
	)
	other_parts.sort_custom(
		func(a, b): return body_parts[a]["current"] > body_parts[b]["current"]
	)

	# Create a priority list with head and torso first, then the sorted other parts
	var priority_parts = ["head", "torso"] + other_parts

	# Distribute healing points
	for part in priority_parts:
		if amount <= 0:
			break
		var heal = min(amount, body_parts[part]["max"] - body_parts[part]["current"])
		body_parts[part]["current"] += heal
		amount -= heal

	# Update health variables
	current_head_health = body_parts["head"]["current"]
	current_torso_health = body_parts["torso"]["current"]
	current_left_arm_health = body_parts["left_arm"]["current"]
	current_right_arm_health = body_parts["right_arm"]["current"]
	current_left_leg_health = body_parts["left_leg"]["current"]
	current_right_leg_health = body_parts["right_leg"]["current"]

	# Emit signals to update the UI or other systems
	update_doll.emit(
		current_head_health, current_right_arm_health, current_left_arm_health,
		current_torso_health, current_right_leg_health, current_left_leg_health
	)
	return amount


# Method to get the current level of a skill
func get_skill_level(skill_id: String) -> int:
	if skills.has(skill_id):
		return skills[skill_id]["level"]
	else:
		push_error("Skill ID not found: %s" % skill_id)
		return 0  # Return 0 or an appropriate default value if the skill is not found


# Method to get the current amount of XP for a skill
func get_skill_xp(skill_id: String) -> int:
	if skills.has(skill_id):
		return skills[skill_id]["xp"]
	else:
		push_error("Skill ID not found: %s" % skill_id)
		return 0  # Return 0 or an appropriate default value if the skill is not found


# Method to set the level of a skill
func set_skill_level(skill_id: String, level: int) -> void:
	if skills.has(skill_id):
		skills[skill_id]["level"] = level
		Helper.signal_broker.player_skill_changed.emit(self)
	else:
		push_error("Skill ID not found: %s" % skill_id)


# Method to set the amount of XP for a skill
func set_skill_xp(skill_id: String, xp: int) -> void:
	if skills.has(skill_id):
		skills[skill_id]["xp"] = xp
		Helper.signal_broker.player_skill_changed.emit(self)
	else:
		push_error("Skill ID not found: %s" % skill_id)


# Method to add an amount of levels to a skill
func add_skill_level(skill_id: String, levels: int) -> void:
	if skills.has(skill_id):
		skills[skill_id]["level"] += levels
		Helper.signal_broker.player_skill_changed.emit(self)
	else:
		push_error("Skill ID not found: %s" % skill_id)


# Method to add an amount of XP to a skill
# This also increases the skill level when the XP reaches 100
func add_skill_xp(skill_id: String, xp: float) -> void:
	if skills.has(skill_id):
		var current_xp = skills[skill_id]["xp"]
		var current_level = skills[skill_id]["level"]
		current_xp += xp
		
		# Check if XP exceeds 100 and handle level up
		while current_xp >= 100:
			current_xp -= 100
			current_level += 1
		
		skills[skill_id]["xp"] = current_xp
		skills[skill_id]["level"] = current_level
		Helper.signal_broker.player_skill_changed.emit(self)
	else:
		push_error("Skill ID not found: %s" % skill_id)


# The player has succesfully crafted an item. Get the skill id and xp from
# the recipe and add it to the player's skill xp
func _on_craft_successful(_item: DItem, recipe: DItem.CraftRecipe):
	if recipe.skill_progression:
		add_skill_xp(recipe.skill_progression.id, recipe.skill_progression.xp)


# Function to initialize the timer for checking Y level changes
func initialize_y_level_check():
	var y_check_timer = Timer.new()
	y_check_timer.wait_time = 0.5
	y_check_timer.autostart = true
	y_check_timer.one_shot = false
	y_check_timer.timeout.connect(_emit_y_level)
	add_child(y_check_timer)

# Function to emit the current Y level
func _emit_y_level():
	var current_y_level = global_position.y
	Helper.signal_broker.player_y_level_updated.emit(current_y_level)


# Method to retrieve the current state of the player as a dictionary
func get_state() -> Dictionary:
	var attribute_data = {}
	for attribute_id in attributes.keys():
		attribute_data[attribute_id] = attributes[attribute_id].get_data()

	return {
		"is_alive": is_alive,
		"left_arm_health": current_left_arm_health,
		"right_arm_health": current_right_arm_health,
		"head_health": current_head_health,
		"torso_health": current_torso_health,
		"left_leg_health": current_left_leg_health,
		"right_leg_health": current_right_leg_health,
		"stamina": current_stamina,
		"nutrition": current_nutrition,
		"pain": current_pain,
		"skills": skills,
		"attributes": attribute_data,  # Include the attributes data
		"global_position_x": global_transform.origin.x,
		"global_position_y": global_transform.origin.y,
		"global_position_z": global_transform.origin.z
	}



# Method to set the player's state from a dictionary
func set_state(state: Dictionary) -> void:
	is_alive = state.get("is_alive", is_alive)
	current_left_arm_health = state.get("left_arm_health", current_left_arm_health)
	current_right_arm_health = state.get("right_arm_health", current_right_arm_health)
	current_head_health = state.get("head_health", current_head_health)
	current_torso_health = state.get("torso_health", current_torso_health)
	current_left_leg_health = state.get("left_leg_health", current_left_leg_health)
	current_right_leg_health = state.get("right_leg_health", current_right_leg_health)
	current_stamina = state.get("stamina", current_stamina)
	current_nutrition = state.get("nutrition", current_nutrition)
	current_pain = state.get("pain", current_pain)
	skills = state.get("skills", skills)

	# Set the attributes data. Assumes the attributes 
	# have already been initialized in initialize_attributes
	var attribute_data = state.get("attributes", {})
	for attribute_id in attribute_data.keys():
		if attributes.has(attribute_id):
			attributes[attribute_id].set_data(attribute_data[attribute_id])

	global_transform.origin.x = state.get("global_position_x", global_transform.origin.x)
	global_transform.origin.y = state.get("global_position_y", global_transform.origin.y)
	global_transform.origin.z = state.get("global_position_z", global_transform.origin.z)
	
	# Emit signals to update the HUD
	update_doll.emit(current_head_health, current_right_arm_health, current_left_arm_health, current_torso_health, current_right_leg_health, current_left_leg_health)
	update_stamina_HUD.emit(current_stamina)
