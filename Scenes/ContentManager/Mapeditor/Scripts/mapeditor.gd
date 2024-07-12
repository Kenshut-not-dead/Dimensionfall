extends Control

@export var panWindow: Control = null
@export var mapScrollWindow: ScrollContainer = null
@export var gridContainer: ColorRect = null
@export var tileGrid: GridContainer = null
@export var map_preview: Popup = null

# Settings controls:
@export var name_text_edit: TextEdit
@export var description_text_edit: TextEdit
@export var categories_list: Control
@export var weight_spin_box: SpinBox



signal zoom_level_changed(value: int)
var tileSize: int = 128
var mapHeight: int = 32
var mapWidth: int = 32
var contentSource: String = "":
	set(newSource):
		contentSource = newSource
		tileGrid.load_map_json_file()


var zoom_level: int = 20:
	set(val):
		zoom_level = val
		zoom_level_changed.emit(zoom_level)


func _ready():
	setPanWindowSize()
	zoom_level = 20
	
func setPanWindowSize():
	var panWindowWidth: float = 0.8*tileSize*mapWidth
	var panWindowHeight: float = 0.8*tileSize*mapHeight
	panWindow.custom_minimum_size = Vector2(panWindowWidth, panWindowHeight)


var mouse_button_pressed: bool = false

func _input(event):
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_MIDDLE: 
				if event.pressed:
					mouse_button_pressed = true
				else:
					mouse_button_pressed = false
	
	#When the users presses and holds the mouse wheel, we scoll the grid
	if event is InputEventMouseMotion:
		if mouse_button_pressed:
			mapScrollWindow.scroll_horizontal = mapScrollWindow.scroll_horizontal - event.relative.x
			mapScrollWindow.scroll_vertical = mapScrollWindow.scroll_vertical - event.relative.y


#Scroll to the center when the scroll window is ready
func _on_map_scroll_window_ready():
	await get_tree().create_timer(0.5).timeout
	mapScrollWindow.scroll_horizontal = int(panWindow.custom_minimum_size.x/3.5)
	mapScrollWindow.scroll_vertical = int(panWindow.custom_minimum_size.y/3.5)

func _on_zoom_scroller_zoom_level_changed(value):
	zoom_level = value

func _on_tile_grid_zoom_level_changed(value):
	zoom_level = value

#The editor is closed, destroy the instance
#TODO: Check for unsaved changes
func _on_close_button_button_up():
	queue_free()


func _on_rotate_map_button_up():
	tileGrid.rotate_map()


# When the user presses the map preview button
func _on_preview_map_button_up():
	map_preview.mapData = tileGrid.mapData
	map_preview.show()


# Function to get the values of the controls
func get_settings_values() -> Dictionary:
	var values = {
		"name": name_text_edit.text,
		"description": description_text_edit.text,
		"categories": categories_list.get_items(),
		"weight": weight_spin_box.value
	}
	return values


# Function to set the values of the controls
func set_settings_values(values: Dictionary) -> void:
	if values.has("name"):
		name_text_edit.text = values["name"]
	if values.has("description"):
		description_text_edit.text = values["description"]
	if values.has("categories"):
		categories_list.set_items(values["categories"])
	if values.has("weight"):
		weight_spin_box.value = values["weight"]
