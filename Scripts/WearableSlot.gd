extends Control

# This script is intended to be used with the WearableSlot scene
# This script is expected to work with Gamedata.data.wearableslots
# The wearable will hold one piece of wearable
# The wearable will be represented by en InventoryItem
# The wearable will be visualized by a texture provided by the InventoryItem
# There will be signals for equipping, unequipping and clearing the slot
# The user will be able to drop wearable onto this slot to equip it
# When the item is equipped, it will be removed from the inventory that is 
# currently assigned to the InventoryItem
# If the inventory that is assigned to the InventoryItem is different then the player inventory
# when the item is equipped, we will update the inventory of the InventoryItem to be 
# the player inventory
# There will be functions to serialize and deserialize the inventoryitem


# The inventory to pull ammo from and to drop items into
@export var myInventory: InventoryStacked
@export var myInventoryCtrl: Control
@export var backgroundColor: ColorRect
@export var myIcon: TextureRect

var myInventoryItem: InventoryItem = null
# The node that will actually operate the item
var equippedItem: Sprite3D = null

# Signals to commmunicate with the equippedItem node inside the Player node
signal item_was_equipped(equippedItem: InventoryItem, wearableSlot: Control)
signal item_was_cleared(equippedItem: InventoryItem, wearableSlot: Control)

# Called when the node enters the scene tree for the first time.
func _ready():
	item_was_equipped.connect(Helper.signal_broker.on_item_equipped)
	item_was_cleared.connect(Helper.signal_broker.on_item_slot_cleared)


# Handle GUI input events
func _gui_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# Check if there's an item equipped and the click is inside the slot
		if myInventoryItem:
			unequip()


# Equip an item
func equip(item: InventoryItem) -> void:
	# First unequip any currently equipped item
	if myInventoryItem:
		unequip()

	if item:
		
		myInventoryItem = item
		update_icon()
		# Remove the item from its original inventory
		# Not applicable if a game is loaded and we re-equip an item that was alread equipped
		var itemInventory = item.get_inventory()
		if itemInventory and itemInventory.has_item(item):
			item.get_inventory().remove_item(item)	

		item_was_equipped.emit(item, self)


# Unequip the current item and keep the magazine in the weapon
func unequip() -> void:
	if myInventoryItem:
		item_was_cleared.emit(myInventoryItem, self)
		myInventory.add_item(myInventoryItem)
		myInventoryItem = null
		update_icon()


# Update the icon of the equipped item
func update_icon() -> void:
	if myInventoryItem:
		myIcon.texture = myInventoryItem.get_texture()
	else:
		myIcon.texture = null


# Serialize the equipped item and the magazine into one dictionary
# This will happen when the player pressed the travel button on the overmap
func serialize() -> Dictionary:
	var data: Dictionary = {}
	if myInventoryItem:
		# We will separate the magazine from the weapon during serialization
		if myInventoryItem.get_property("current_magazine"):
			var myMagazine: InventoryItem = myInventoryItem.get_property("current_magazine")
			data["magazine"] = myMagazine.serialize()  # Serialize magazine
			myInventoryItem.clear_property("current_magazine")
		data["item"] = myInventoryItem.serialize()  # Serialize equipped item
	return data


# Deserialize and equip an item and a magazine from the provided data
# This will happen when a game is loaded or the player has travelled to a different map
func deserialize(data: Dictionary) -> void:
	# Deserialize and equip an item
	if data.has("item"):
		var itemData: Dictionary = data["item"]
		var item = InventoryItem.new()
		item.deserialize(itemData)
		equip(item)  # Equip the deserialized item

		# If there is a magazine, we create an InventoryItem instance
		# We assign a reference to it in the curretn_magazine of the weapon
		if data.has("magazine"):
			var magazineData: Dictionary = data["magazine"]
			var myMagazine = InventoryItem.new()
			myMagazine.deserialize(magazineData)
			item.set_property("current_magazine", myMagazine)
			equippedItem.on_magazine_inserted()


# Get the currently equipped item
func get_item() -> InventoryItem:
	return myInventoryItem


# This function should return true if the dragged data can be dropped here
func _can_drop_data(_newpos, data) -> bool:
	return data is Array[InventoryItem]


# This function handles the data being dropped
func _drop_data(newpos, data):
	if _can_drop_data(newpos, data):
		if data is Array and data.size() > 0 and data[0] is InventoryItem:
			var first_item = data[0]
			# Check if the dropped item is a magazine
			if first_item.get_property("Magazine"):
				_handle_magazine_drop(first_item)
			else:
				# Equip the item if it's not a magazine
				equip(first_item)


# When the user has dropped a magaziene from the inventory
func _handle_magazine_drop(magazine: InventoryItem):
	if myInventoryItem and myInventoryItem.get_property("Ranged"):
		ItemManager.start_reload(myInventoryItem, equippedItem.reload_speed, magazine)
	else:
		# Equip the item if no weapon is wielded
		equip(magazine)


