class_name DItems
extends RefCounted

# There's a D in front of the class name to indicate this class only handles item data, nothing more
# This script is intended to be used inside the GameData autoload singleton
# This script handles the list of items. You can access it trough Gamedata.items


var dataPath: String = "./Mods/Core/Items/Items.json"
var spritePath: String = "./Mods/Core/Items/"
var itemdict: Dictionary = {}
var sprites: Dictionary = {}


func _init():
	load_sprites()
	load_items_from_disk()


# Load all itemdata from disk into memory
func load_items_from_disk() -> void:
	var itemlist: Array = Helper.json_helper.load_json_array_file(dataPath)
	for myitem in itemlist:
		var item: DItem = DItem.new(myitem)
		item.sprite = sprites[item.spriteid]
		itemdict[item.id] = item


# Loads sprites and assigns them to the proper dictionary
func load_sprites() -> void:
	var png_files: Array = Helper.json_helper.file_names_in_dir(spritePath, ["png"])
	for png_file in png_files:
		# Load the .png file as a texture
		var texture := load(spritePath + png_file) 
		# Add the material to the dictionary
		sprites[png_file] = texture


func on_data_changed():
	save_items_to_disk()


# Saves all items to disk
func save_items_to_disk() -> void:
	var save_data: Array = []
	for item in itemdict.values():
		save_data.append(item.get_data())
	Helper.json_helper.write_json_file(dataPath, JSON.stringify(save_data, "\t"))


func get_items() -> Dictionary:
	return itemdict


func duplicate_item_to_disk(itemid: String, newitemid: String) -> void:
	var itemdata: Dictionary = itemdict[itemid].get_data().duplicate(true)
	itemdata.id = newitemid
	var newitem: DItem = DItem.new(itemdata)
	itemdict[newitemid] = newitem
	save_items_to_disk()


func add_new_item(newid: String) -> void:
	var newitem: DItem = DItem.new({"id":newid})
	itemdict[newitem.id] = newitem
	save_items_to_disk()


func delete_item(itemid: String) -> void:
	itemdict[itemid].delete()
	itemdict.erase(itemid)
	save_items_to_disk()


func by_id(itemid: String) -> DItem:
	return itemdict[itemid]


# Returns the sprite of the item
# itemid: The id of the item to return the sprite of
func sprite_by_id(itemid: String) -> Texture:
	return itemdict[itemid].sprite

# Returns the sprite of the item
# itemid: The id of the item to return the sprite of
func sprite_by_file(spritefile: String) -> Texture:
	return sprites[spritefile]


# Removes the reference from the selected item
func remove_reference_from_item(itemid: String, module: String, type: String, refid: String):
	var myitem: DItem = itemdict[itemid]
	myitem.remove_reference(module, type, refid)


# Adds a reference to the references list
# For example, add "grass_field" to references.Core.maps
# itemid: The id of the item to add the reference to
# module: the mod that the entity belongs to, for example "Core"
# type: The type of entity, for example "maps"
# refid: The id of the entity to reference, for example "grass_field"
func add_reference_to_item(itemid: String, module: String, type: String, refid: String):
	var myitem: DItem = itemdict[itemid]
	myitem.add_reference(module, type, refid)
