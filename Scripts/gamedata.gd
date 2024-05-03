extends Node

#This autoload singleton loads all game data required to run the game
#It can be accessed by using Gamedata.property
var data: Dictionary = {}


# Dictionary keys for game data categories
const DATA_CATEGORIES = {
	"tiles": {"dataPath": "./Mods/Core/Tiles/Tiles.json", "spritePath": "./Mods/Core/Tiles/"},
	"mobs": {"dataPath": "./Mods/Core/Mobs/Mobs.json", "spritePath": "./Mods/Core/Mobs/"},
	"items": {"dataPath": "./Mods/Core/Items/Items.json", "spritePath": "./Mods/Core/Items/"},
	"furniture": {"dataPath": "./Mods/Core/Furniture/Furniture.json", "spritePath": "./Mods/Core/Furniture/"},
	"overmaptiles": {"spritePath": "./Mods/Core/OvermapTiles/"},
	"tacticalmaps": {"dataPath": "./Mods/Core/TacticalMaps/"},
	"maps": {"dataPath": "./Mods/Core/Maps/", "spritePath": "./Mods/Core/Maps/"},
	"itemgroups": {"dataPath": "./Mods/Core/Itemgroups/Itemgroups.json", "spritePath": "./Mods/Core/Items/"}
}

# We write down the associated paths for the files to load
# Next, sprites are loaded from spritesPath into the .sprites property
# Finally, the data is loaded from dataPath into the .data property
# Maps tile sprites and map data are different so they 
# are loaded in using their respective functions
func _ready():
	initialize_data_structures()
	load_sprites()
	load_tile_sprites()
	load_data()
	update_item_protoset_json_data("res://ItemProtosets.tres",JSON.stringify(data.items.data,"\t"))
	data.maps.data = Helper.json_helper.file_names_in_dir(data.maps.dataPath, ["json"])
	data.tacticalmaps.data = Helper.json_helper.file_names_in_dir(\
	data.tacticalmaps.dataPath, ["json"])


func initialize_data_structures():
	for category in DATA_CATEGORIES.keys():
		data[category] = {"data": [], "sprites": {}}
		if DATA_CATEGORIES[category].has("dataPath"):
			data[category]["dataPath"] = DATA_CATEGORIES[category]["dataPath"]
		if DATA_CATEGORIES[category].has("spritePath"):
			data[category]["spritePath"] = DATA_CATEGORIES[category]["spritePath"]


#Loads json data. If no json file exists, it will create an empty array in a new file
func load_data() -> void:
	for dict in data.keys():
		if data[dict].has("dataPath"):
			var dataPath: String = data[dict].dataPath
			if FileAccess.file_exists(dataPath):
				Helper.json_helper.create_new_json_file(dataPath)
				data[dict].data = Helper.json_helper.load_json_array_file(dataPath)
			else:
				data[dict].data = []


#This loads all the sprites and assigns them to the proper dictionary
func load_sprites() -> void:
	for dict in data.keys():
		if data[dict].has("spritePath"):
			var loaded_sprites: Dictionary = {} # Materials used to represent mobs
			var spritesDir: String = data[dict].spritePath
			var png_files: Array = Helper.json_helper.file_names_in_dir(spritesDir, ["png"])
			for png_file in png_files:
				# Load the .png file as a texture
				var texture := load(spritesDir + png_file) 
				# Add the material to the dictionary
				loaded_sprites[png_file] = texture
			data[dict].sprites = loaded_sprites


# This function reads all the files in "res://Mods/Core/Tiles/". It will check if the file is a .png file. If the file is a .png file, it will create a new material with that .png image as the texture. It will put all of the created materials in a dictionary with the name of the file as the key and the material as the value.
func load_tile_sprites() -> void:
	var tile_materials: Dictionary = {} # Materials used to represent tiles
	var tilesDir = data.tiles.spritePath
	var png_files: Array = Helper.json_helper.file_names_in_dir(tilesDir, ["png"])
	for png_file in png_files:
		var texture := load(tilesDir + png_file) # Load the .png file as a texture
		var material := StandardMaterial3D.new() 
		material.albedo_texture = texture # Set the texture of the material
		material.uv1_scale = Vector3(3,2,1)
		tile_materials[png_file] = material # Add the material to the dictionary
	data.tiles.sprites = tile_materials


#This function will take two strings called ID and newID
#It will find an item with this ID in a json file specified by the source variable
#It will then duplicate that item into the json file and change the ID to newID
func duplicate_item_in_data(contentData: Dictionary, id: String, newID: String):
	if contentData.data.is_empty():
		return

	if contentData.dataPath.ends_with((".json")):
		# Check if an item with the given ID exists in the file.
		var item_index: int = get_array_index_by_id(contentData,id)
		if item_index == -1:
			return
		
		# Duplicate the found item recursively
		var item_to_duplicate = contentData.data[item_index].duplicate(true)
		
		# If there is no item to duplicate, return without doing anything.
		if item_to_duplicate == null:
			return
		# Change the ID of the duplicated item.
		item_to_duplicate["id"] = newID
		# Add the duplicated item to the JSON data.
		contentData.data.append(item_to_duplicate)
		Helper.json_helper.write_json_file(contentData.dataPath,JSON.stringify(contentData.data,"\t"))
	else:
		print_debug("There should be code here for when a file in the gets duplicated")


# This function will duplicate a file with the provided original ID
# and save it under a new ID within the same directory.
func duplicate_file_in_data(contentData: Dictionary, original_id: String, new_id: String) -> void:
	var data_path: String = contentData.dataPath
	var original_file_path: String = data_path + original_id + ".json"
	var new_file_path: String = data_path + new_id + ".json"

	if not FileAccess.file_exists(original_file_path):
		print_debug("Original file not found: " + original_file_path)
		return

	# Load the original file content.
	var original_content = Helper.json_helper.load_json_dictionary_file(original_file_path)

	# Write the original content to a new file with the new ID.
	var save_result = Helper.json_helper.write_json_file(new_file_path, JSON.stringify(original_content))
	if save_result == OK:
		print_debug("File duplicated successfully: " + new_file_path)
		# Add the new ID to the data array if it's managed as an array of IDs.
		if contentData.data is Array and typeof(contentData.data[0]) == TYPE_STRING:
			contentData.data.append(new_id)
			save_data_to_file(contentData)  # Save the updated data array to file.
	else:
		print_debug("Failed to duplicate file to: " + new_file_path)



# This function appends a new object to an existing array
# Pass the contentData dictionary to this function and the value of the ID
# If the data directory ends in .json, it will append an object
# The object that will be appended will be nothing more then {"id": id}
# if the data directory does not end in .json, a new file will be added
# This file will get the name as specified by id, so for example "myhouse"
# After the ID is added, the data array will be saved to disk
func add_id_to_data(contentData: Dictionary, id: String):
	if !contentData.has("data"):
		return
	if contentData.dataPath.ends_with((".json")):
		if get_array_index_by_id(contentData,id) != -1:
			print_debug("Tried to add an existing id to an array")
			return
		contentData.data.append({"id": id})
		save_data_to_file(contentData)
	else:
		if id in contentData.data:
			print_debug("Tried to add an existing file to a file array")
			return
		contentData.data.append(id)
		#Create a new json file in the directory with only {} in the file
		Helper.json_helper.create_new_json_file(contentData.dataPath + id + ".json", false)


# Will remove an item from the data
# If the first item in data is a dictionary, we remove an item that has the provided id
# If the first item in data is a string, we remove the string and the associated json file
func remove_item_from_data(contentData: Dictionary, id: String):
	if contentData.data.is_empty():
		return
	if contentData.data[0] is Dictionary:
		remove_relations_of_deleted_id(contentData, id)
		contentData.data.remove_at(get_array_index_by_id(contentData, id))
		save_data_to_file(contentData)
	elif contentData.data[0] is String:
		contentData.data.erase(id)
		Helper.json_helper.delete_json_file(contentData.dataPath, id)
	else:
		print_debug("Tried to remove item from data, but the data contains \
		neither Dictionary nor String")


func get_array_index_by_id(contentData: Dictionary, id: String) -> int:
	# Iterate through the array
	for i in range(len(contentData.data)):
		# Check if the current item is a dictionary
		if typeof(contentData.data[i]) == TYPE_DICTIONARY:
			# Check if it has the 'id' key and matches the given ID
			if contentData.data[i].has("id") and contentData.data[i]["id"] == id:
				return i
		# Check if the current item is a string and matches the given ID
		elif typeof(contentData.data[i]) == TYPE_STRING and contentData.data[i] == id:
			return i
	# Return -1 if the ID is not found
	return -1


func save_data_to_file(contentData: Dictionary):
	var datapath: String = contentData.dataPath
	if datapath.ends_with(".json"):
		Helper.json_helper.write_json_file(datapath,JSON.stringify(contentData.data,"\t"))


# Takes contentdata and an id and returns the json that belongs to an id
# For example, contentData can be Gamedata.data.tiles
# and id can be "plain_grass" and it will return the json data for plain_grass
func get_data_by_id(contentData: Dictionary, id: String) -> Dictionary:
	var idnr: int = get_array_index_by_id(contentData,id)
	if idnr < 0:
		return {}
	return contentData.data[idnr]


#Takes contentData and an id and returns the sprite associated with the id
# For example, contentData can be Gamedata.data.tiles
# and id can be "plain_grass" and it will return the sprite for plain_grass
func get_sprite_by_id(contentData: Dictionary, id: String) -> Resource:
	if not contentData.sprites.size() > 0 or not contentData.data.size() > 0:
		return null
	var sprite
	# First, check if the contentData.data is structured as an array
	if contentData.data[0] is String:
		sprite = contentData.sprites[id + ".png"]
	else:
		var item_json = get_data_by_id(contentData, id)
		sprite = contentData.sprites[item_json.sprite]
	return sprite


# This functino is called when an editor has changed data
# The contenteditor (that initializes the individual editors)
# connects the changed_data signal to this function
# and binds the appropriate data array so it can be saved in this function
func on_data_changed(contentData: Dictionary, newEntityData: Dictionary, oldEntityData: Dictionary):
	if contentData == Gamedata.data.itemgroups:
		on_itemgroup_changed(newEntityData, oldEntityData)
	if contentData == Gamedata.data.mobs:
		on_mob_changed(newEntityData, oldEntityData)
	if contentData == Gamedata.data.furniture:
		on_furniture_changed(newEntityData, oldEntityData)
	save_data_to_file(contentData)


# This will update the given resource file with the provided json data
# It is intended to save item data from json to the res://ItemProtosets.tres file
# So we can use the item json data in-game
func update_item_protoset_json_data(tres_path: String, new_json_data: String) -> void:
	# Load the ItemProtoset resource
	var item_protoset = load(tres_path) as ItemProtoset
	if not item_protoset:
		print_debug("Failed to load ItemProtoset resource from:", tres_path)
		return

	# Update the json_data property
	item_protoset.json_data = new_json_data

	# Save the resource back to the .tres file
	var save_result = ResourceSaver.save(item_protoset, tres_path)
	if save_result != OK:
		print_debug("Failed to save updated ItemProtoset resource to:", tres_path)
	else:
		print_debug("ItemProtoset resource updated and saved successfully to:", tres_path)


# Function to filter items by type
func get_items_by_type(item_type: String) -> Array:
	var filtered_items = []
	
	# Check if the items data exists and is an array
	if Gamedata.data.has("items") and Gamedata.data.items.has("data") and typeof(Gamedata.data.items.data) == TYPE_ARRAY:
		# Iterate through each item in the items data
		for item in Gamedata.data.items.data:
			# Check if the item is a dictionary and has the specified type
			if item is Dictionary and item.has(item_type):
				# Add the item to the filtered items list
				filtered_items.append(item)

	return filtered_items


# An itemgroup has been changed. Update items that were added or removed from the list
# oldlist and newlist are arrays with item id strings in them
func on_itemgroup_changed(newdata: Dictionary, olddata: Dictionary):
	var changes_made = false
	var oldlist: Array = get_nested_data(olddata, "items")
	var newlist: Array = get_nested_data(newdata, "items")
	var itemgroup: String = newdata.id
	# Remove itemgroup from items in the old list that are not in the new list
	for item_id in oldlist:
		if item_id not in newlist:
			# Call remove_reference to remove the itemgroup from this item
			changes_made = remove_reference(Gamedata.data.items, "core", "itemgroups", \
			item_id, itemgroup) or changes_made

	# Add itemgroup to items in the new list that were not in the old list
	for item_id in newlist:
		if item_id not in oldlist:
			# Call add_reference to add the itemgroup to this item
			changes_made = add_reference(Gamedata.data.items, "core", "itemgroups", \
			item_id, itemgroup) or changes_made

	# Save changes if any items were updated
	if changes_made:
		save_data_to_file(Gamedata.data.items)


# An itemgroup is being deleted from the data
# We have to loop over all the items in the itemgroup
# We can get the items by calling get_data_by_id(contentData, id) 
# and getting the items property, which will return an array of item id's
# For each item, we have to get the item's data, and delete the itemgroup from the item's itemgroups property if it is present
func on_itemgroup_deleted(itemgroup_id: String):
	var changes_made = false
	var itemgroup_data = get_data_by_id(Gamedata.data.itemgroups, itemgroup_id)

	if itemgroup_data.is_empty():
		print_debug("Itemgroup with ID", itemgroup_id, "not found.")
		return

	# This callable will remove this itemgroups from every furniture that reference this itemgroup.
	var myfunc: Callable = func (furn_id):
		if erase_property_by_path(Gamedata.data.furniture, furn_id, "Function.container.itemgroup"):
			changes_made = true
	# Pass the callable to every furniture in the itemgroup's references
	# It will call myfunc on every furniture in itemgroup_data.references.core.furniture
	execute_callable_on_references_of_type(itemgroup_data, "core", "furniture", myfunc)

	# The itemgroup data contains a list of item IDs in an 'items' attribute
	# Loop over all the items in the list and remove the reference to this itemgroup
	if "items" in itemgroup_data:
		var item_ids = itemgroup_data["items"]
		for item_id in item_ids:
			# Use remove_reference to handle deletion of itemgroup references
			changes_made = remove_reference(Gamedata.data.items, "core", "itemgroups", \
			item_id, itemgroup_id) or changes_made


	# Save changes to the data file if any changes were made
	if changes_made:
		save_data_to_file(Gamedata.data.items)
		save_data_to_file(Gamedata.data.furniture)
		print_debug("Itemgroup", itemgroup_id, "has been successfully deleted from all items.")
	else:
		print_debug("No changes needed for itemgroup", itemgroup_id)


# Adds a reference to an entity
# data = any data group, like Gamedata.data.itemgroups
# type = the type of reference, for example furniture
# onid = where to add the reference to
# refid = The reference to add on the fromid
# Example usage: var changes_made = add_reference(Gamedata.data.itemgroups, "core", 
# "furniture", itemgroup_id, furniture_id)
# This example will add the specified furniture from the itemgroup's references
func add_reference(mydata: Dictionary, module: String, type: String, onid: String, refid: String) -> bool:
	var changes_made: bool = false
	if onid != "":
		var entitydata = get_data_by_id(mydata, onid)
		if not entitydata.has("references"):
			entitydata["references"] = {}
		if not entitydata["references"].has(module):
			entitydata["references"][module] = {}
		if not entitydata["references"][module].has(type):
			entitydata["references"][module][type] = []
		
		if refid not in entitydata["references"][module][type]:
			entitydata["references"][module][type].append(refid)
			changes_made = true
	return changes_made


# Removes a reference from an entity. 
# data = any data group, like Gamedata.data.itemgroups
# type = the type of reference, for example furniture
# fromid = where to remove the reference from
# refid = The reference to remove from the fromid
# Example usage: var changes_made = remove_reference(Gamedata.data.itemgroups, "core", 
# "furniture", itemgroup_id, furniture_id)
# This example will remove the specified furniture from the itemgroup's references
func remove_reference(mydata: Dictionary, module: String, type: String, fromid: String, refid: String) -> bool:
	var changes_made: bool = false
	if fromid != "":
		var entitydata = get_data_by_id(mydata, fromid)
		if entitydata.has("references") and entitydata["references"].has(module) and entitydata["references"][module].has(type):
			var refs = entitydata["references"][module][type]
			if refid in refs:
				refs.erase(refid)
				changes_made = true
				# Clean up if necessary
				if refs.size() == 0:
					entitydata["references"][module].erase(type)
				if entitydata["references"][module].is_empty():
					entitydata["references"].erase(module)
				if entitydata["references"].is_empty():
					entitydata.erase("references")
	return changes_made


func remove_relations_of_deleted_id(contentData: Dictionary, id: String):
	if contentData == Gamedata.data.itemgroups:
		on_itemgroup_deleted(id)
	if contentData == Gamedata.data.items:
		on_item_deleted(id)
	if contentData == Gamedata.data.furniture:
		on_furniture_deleted(id)


# Erases a nested property from a given dictionary based on a dot-separated path
func erase_property_by_path(mydata: Dictionary, item_id: String, property_path: String):
	var entity_data = get_data_by_id(mydata, item_id)
	if entity_data.is_empty():
		print_debug("Entity with ID", item_id, "not found.")
		return false

	# Split the path and process the nesting
	var path_parts = property_path.split(".")
	var current_dict = entity_data
	for i in range(path_parts.size() - 1):  # Navigate to the last dictionary
		if path_parts[i] in current_dict:
			current_dict = current_dict[path_parts[i]]
		else:
			print_debug("Path not found:", path_parts[i])
			return false

	# Last part of the path is the key to erase
	var last_key = path_parts[-1]
	if last_key in current_dict:
		current_dict.erase(last_key)
		print_debug("Property", last_key, "erased successfully.")
		return true
	else:
		print_debug("Property", last_key, "not found.")
		return false


# An item is being deleted from the data
# We have to remove it from everything that references it
func on_item_deleted(item_id: String):
	var changes_made = false
	var item_data = get_data_by_id(Gamedata.data.items, item_id)
	
	if item_data.is_empty():
		print_debug("Item with ID", item_data, "not found.")
		return
	
	# This callable will remove this item from itemgroups that reference this item.
	var myfunc: Callable = func (itemgroup_id):
		var itemlist: Array = get_property_by_path(Gamedata.data.itemgroups, "items", itemgroup_id)
		if item_id in itemlist:
			itemlist.erase(item_id)
			changes_made = true
	# Pass the callable to every itemgroup in the item's references
	# It will call myfunc on every itemgroup in item_data.references.core.itemgroups
	execute_callable_on_references_of_type(item_data, "core", "itemgroups", myfunc)

	# Save changes to the data file if any changes were made
	if changes_made:
		save_data_to_file(Gamedata.data.itemgroups)
	else:
		print_debug("No changes needed for item", item_id)


# Some furniture is being deleted from the data
# We have to remove it from everything that references it
func on_furniture_deleted(furniture_id: String):
	var changes_made = false
	var furniture_data = get_data_by_id(Gamedata.data.furniture, furniture_id)
	
	if furniture_data.is_empty():
		print_debug("Item with ID", furniture_data, "not found.")
		return

	var itemgroup: String = get_property_by_path(Gamedata.data.furniture, \
	"Function.container.itemgroup", furniture_id)
	# Handle the old itemgroup
	changes_made = remove_reference(Gamedata.data.itemgroups, "core", "furniture", \
	itemgroup, furniture_id) or changes_made

	# Save changes to the data file if any changes were made
	if changes_made:
		save_data_to_file(Gamedata.data.itemgroups)
	else:
		print_debug("No changes needed for item", furniture_id)


# Executes a callable function on each reference of the given type
# data = json data representing one entity
# module = name of the mod. for example "core"
# type = the type of reference we want to handle. For example "furniture"
# callable = a function to execute on each reference ID
# We will check if data has the ["references"] and [type] properties and execute the callable on each found ID
func execute_callable_on_references_of_type(mydata: Dictionary, module: String, type: String, callable: Callable):
	# Check if 'data' contains a 'references' dictionary and if it contains the specified 'type'
	if mydata.has("references") and mydata["references"].has(module) and mydata["references"][module].has(type):
		# If the type exists, execute the callable on each ID found under this type
		for ref_id in mydata["references"][module][type]:
			callable.call(ref_id)


# Retrieves the value of a nested property from a given dictionary based on a dot-separated path
func get_property_by_path(mydata: Dictionary, property_path: String, entity_id: String) -> Variant:
	var entity_data = get_data_by_id(mydata, entity_id)
	if entity_data.is_empty():
		print_debug("Entity with ID", entity_id, "not found.")
		return null
	return get_nested_data(entity_data, property_path)


func get_nested_data(mydata: Dictionary, path: String) -> Variant:
	var parts = path.split(".")
	var current = mydata
	for part in parts:
		if current.has(part):
			current = current[part]
		else:
			return null
	return current


# A mob has been changed.
func on_mob_changed(newdata: Dictionary, olddata: Dictionary):
	var old_loot_group: String = olddata.get("loot_group")
	var new_loot_group: String = newdata.get("loot_group")
	var mob_id: String = newdata.get("id")
	# Exit if old_group and new_group are the same
	if old_loot_group == new_loot_group:
		print_debug("No change in itemgroup. Exiting function.")
		return
	var changes_made = false

	# This furniture will be removed from the old itemgroup's references
	# The 'or' makes sure changes_made does not change back to false
	changes_made = remove_reference(Gamedata.data.itemgroups, "core", "mobs", \
	old_loot_group, mob_id) or changes_made

	# This furniture will be added to the new itemgroup's references
	# The 'or' makes sure changes_made does not change back to false
	changes_made = add_reference(Gamedata.data.itemgroups, "core", "mobs", \
	new_loot_group, mob_id) or changes_made
	
	# Save changes if any modifications were made
	if changes_made:
		if old_loot_group != "":
			save_data_to_file(Gamedata.data.itemgroups)
		if new_loot_group != "" and new_loot_group != old_loot_group:
			save_data_to_file(Gamedata.data.itemgroups)


# Some furniture has been changed
# We need to update the relation between the furniture and the itemgroup
func on_furniture_changed(newdata: Dictionary, olddata: Dictionary):
	var old_group: String = get_nested_data(olddata, "Function.container.itemgroup")
	var new_group: String = get_nested_data(newdata, "Function.container.itemgroup")
	var furniture_id: String = newdata.id
	# Exit if old_group and new_group are the same
	if old_group == new_group:
		print_debug("No change in itemgroup. Exiting function.")
		return
	var changes_made = false

	# This furniture will be removed from the old itemgroup's references
	# The 'or' makes sure changes_made does not change back to false
	changes_made = remove_reference(Gamedata.data.itemgroups, "core", "furniture", \
	old_group, furniture_id) or changes_made

	# This furniture will be added to the new itemgroup's references
	# The 'or' makes sure changes_made does not change back to false
	changes_made = add_reference(Gamedata.data.itemgroups, "core", "furniture", \
	new_group, furniture_id) or changes_made

	# Save changes if any modifications were made
	if changes_made:
		if old_group != "":
			save_data_to_file(Gamedata.data.itemgroups)
		if new_group != "" and new_group != old_group:
			save_data_to_file(Gamedata.data.itemgroups)

	if changes_made:
		print_debug("Furniture itemgroup changes saved successfully.")
	else:
		print_debug("No changes were made to furniture itemgroups.")
