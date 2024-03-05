extends Control

#This scene is intended to be used inside the content editor
#It is supposed to edit exactly one tile
#It expects to save the data to a JSON file that contains all tile data from a mod
#To load data, provide the name of the tile data file and an ID


@export var tileBrush: PackedScene
@export var tileImageDisplay: TextureRect = null
@export var IDTextLabel: Label = null
@export var NameTextEdit: TextEdit = null
@export var DescriptionTextEdit: TextEdit = null
@export var CategoriesList: Control = null
@export var tileSelector: Popup = null
@export var tileBrushList: HFlowContainer = null
@export var tilePathStringLabel: Label = null
# This signal will be emitted when the user presses the save button
# This signal should alert Gamedata that the tile data array should be saved to disk
# The content editor has connected this signal to Gamedata already
signal data_changed()

# The data that represents this tile
# The data is selected from the Gamedata.all_tiles array
# based on the ID that the user has selected in the content editor
var contentData: Dictionary = {}:
	set(value):
		contentData = value
		load_tile_data()
		tileSelector.sprites_collection = Gamedata.tile_materials

# This function updates the form based on the contentData that has been loaded
func load_tile_data():
	if tileImageDisplay != null and contentData.has("imagePath"):
		tileImageDisplay.texture = load(contentData["imagePath"])
		tilePathStringLabel.text = contentData["imagePath"]
	if IDTextLabel != null:
		IDTextLabel.text = str(contentData["id"])
	if NameTextEdit != null and contentData.has("name"):
		NameTextEdit.text = contentData["name"]
	if DescriptionTextEdit != null and contentData.has("description"):
		DescriptionTextEdit.text = contentData["description"]
	if CategoriesList != null and contentData.has("categories"):
		CategoriesList.clear_list()
		for category in contentData["categories"]:
			CategoriesList.add_item_to_list(category)

#The editor is closed, destroy the instance
#TODO: Check for unsaved changes
func _on_close_button_button_up():
	queue_free()

# This function takes all data fro the form elements stores them in the contentData
# Since contentData is a reference to an item in Gamedata.all_tiles
# the central array for tiledata is updated with the changes as well
# The function will signal to Gamedata that the data has changed and needs to be saved
func _on_save_button_button_up():
	contentData["imagePath"] = tilePathStringLabel.text
	contentData["name"] = NameTextEdit.text
	contentData["description"] = DescriptionTextEdit.text
	contentData["categories"] = CategoriesList.get_items()
	data_changed.emit()

#When the tileImageDisplay is clicked, the user will be prompted to select an image from 
# "res://Mods/Core/Tiles/". The texture of the tileImageDisplay will change to the selected image
func _on_tile_image_display_gui_input(event):
	if event is InputEventMouseButton and event.pressed:
		tileSelector.show()

func _on_sprite_selector_sprite_selected_ok(clicked_sprite) -> void:
	var tileTexture: Resource = clicked_sprite.get_texture()
	tileImageDisplay.texture = tileTexture
	var imagepath: String = tileTexture.resource_path
	tilePathStringLabel.text = imagepath.replace("res://", "")
