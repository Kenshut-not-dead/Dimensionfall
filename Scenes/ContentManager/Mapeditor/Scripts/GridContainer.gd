extends GridContainer

# This script is intended to work with the map editor.
# It contains a grid of tiles that make up a map.

@export var tileScene: PackedScene
@export var mapEditor: Control
@export var LevelScrollBar: VScrollBar
@export var levelgrid_below: GridContainer
@export var levelgrid_above: GridContainer
@export var mapScrollWindow: ScrollContainer
@export var brushPreviewTexture: TextureRect
@export var buttonRotateRight: Button
@export var checkboxDrawRectangle: CheckBox
@export var checkboxCopyRectangle: CheckBox
@export var checkboxCopyAllLevels: CheckBox
@export var checkboxDrawarea: CheckBox
@export var brushcomposer: Control # Contains one or more selected brushes to paint with

# Constants and enums for better readability
const DEFAULT_MAP_WIDTH = 32
const DEFAULT_MAP_HEIGHT = 32
const DEFAULT_LEVELS_COUNT = 21

enum EditorMode {
	NONE,
	DRAW_RECTANGLE, # When the user has clicked the DrawRectangle checkbox
	COPY_RECTANGLE, # When the user has clicked the CopyRectangle checkbox
	COPY_ALL_LEVELS, # When the user has clicked the CopyAllLevels checkbox
	DRAW_AREA # When the user has clicked the draw area checkbox
}

# Variables
var currentLevel: int = 10
var currentLevelData: Array = []
var selected_brush: Control
var currentMode: EditorMode = EditorMode.NONE # Track the current editor mode
var erase: bool = false
var showBelow: bool = false
var showAbove: bool = false
var snapAmount: float
var defaultMapData: Dictionary = {"mapwidth": DEFAULT_MAP_WIDTH, "mapheight": DEFAULT_MAP_HEIGHT, "levels": [[],[],[],[],[],[],[],[],[],[],[],[],[],[],[],[],[],[],[],[],[]]}
var rotationAmount: int = 0
var start_point = Vector2()
var end_point = Vector2()
var is_drawing = false
var snapLevel: Vector2 = Vector2(snapAmount, snapAmount).round()
# Variable to hold copied tile data along with dimensions. Used for copy-pasting.
var copied_tiles_info: Dictionary = {"tiles_data": [], "all_levels_data": [], "width": 0, "height": 0}


var olddata: Dictionary #Used to remember the mapdata before it was changed
#Contains map metadata like size as well as the data on all levels
var mapData: Dictionary = defaultMapData.duplicate():
	set(data):
		if data.is_empty():
			mapData = defaultMapData.duplicate()
		else:
			mapData = data.duplicate()
		loadLevelData(currentLevel)
		load_area_data()
signal zoom_level_changed(zoom_level: int)
signal data_changed(map_path: String, new_data: Dictionary, old_data: Dictionary)

# This function is called when the parent mapeditor node is ready
func _on_mapeditor_ready() -> void:
	columns = mapEditor.mapWidth
	levelgrid_below.columns = mapEditor.mapWidth
	levelgrid_above.columns = mapEditor.mapWidth
	create_tiles()
	snapAmount = 1.28 * mapEditor.zoom_level
	levelgrid_below.hide()
	levelgrid_above.hide()
	_on_zoom_level_changed(mapEditor.zoom_level)
	data_changed.connect(Gamedata.map_references.on_mapdata_changed)
	brushcomposer.brush_added.connect(_on_composer_brush_added)
	brushcomposer.brush_removed.connect(_on_composer_brush_removed)

# This function will fill this GridContainer with a grid of 32x32 instances of "tileScene"
func create_tiles():
	create_level_tiles(self, true)
	create_level_tiles(levelgrid_below, false)
	create_level_tiles(levelgrid_above, false)

# Helper function to create tiles for a specific level grid
func create_level_tiles(grid: GridContainer, connect_signals: bool):
	for x in range(mapEditor.mapWidth):
		for y in range(mapEditor.mapHeight):
			var tile_instance = tileScene.instantiate()
			grid.add_child(tile_instance)
			if connect_signals:
				tile_instance.tile_clicked.connect(grid_tile_clicked)
			tile_instance.set_clickable(connect_signals)

# When the user presses and holds the middle mouse button and moves the mouse,
# change the parent's scroll_horizontal and scroll_vertical properties appropriately
func _input(event) -> void:
	if not mapEditor.visible:
		return
	
	# Convert the mouse position to MapScrollWindow's local coordinate system
	var local_mouse_pos = mapScrollWindow.get_local_mouse_position()
	var mapScrollWindowRect = mapScrollWindow.get_rect()
	# Check if the mouse is within the MapScrollWindow's rect
	if not mapScrollWindowRect.has_point(local_mouse_pos):
		return
	
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if Input.is_key_pressed(KEY_CTRL) and event.button_mask == 0:
					zoom_level_changed.emit(mapEditor.zoom_level+2)
				if Input.is_key_pressed(KEY_ALT) and event.button_mask == 0:
					LevelScrollBar.value += 1
				if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_ALT):
					get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_DOWN: 
				if Input.is_key_pressed(KEY_CTRL) and event.button_mask == 0:
					zoom_level_changed.emit(mapEditor.zoom_level-2)
				if Input.is_key_pressed(KEY_ALT) and event.button_mask == 0:
					LevelScrollBar.value -= 1
				if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_ALT):
					get_viewport().set_input_as_handled()
			MOUSE_BUTTON_LEFT:
				if event.is_pressed():
					is_drawing = true
					start_point = event.global_position.snapped(snapLevel)
				else:
					# Finalize drawing/copying operation
					end_point = event.global_position.snapped(snapLevel)
					if is_drawing:
						var drag_threshold: int = 5 # Pixels
						var distance_dragged = start_point.distance_to(end_point)
						
						if distance_dragged <= drag_threshold:
							print_debug("Released the mouse button, but clicked instead of dragged")
						else:
							match currentMode:
								EditorMode.DRAW_RECTANGLE:
									# Paint in the rectangle if drawRectangle is enabled
									paint_in_rectangle()
								EditorMode.COPY_RECTANGLE:
									# Copy selected tiles to memory if copyRectangle is 
									# enabled and not in drawRectangle mode
									copy_selected_tiles_to_memory()
								EditorMode.COPY_ALL_LEVELS:
									# Handle copying all levels
									copy_tiles_from_all_levels(start_point, end_point)
								EditorMode.DRAW_AREA:
									# Paint area in the rectangle if drawarea is enabled
									paint_area_in_rectangle()
					unhighlight_tiles()
					is_drawing = false


	#When the users presses and holds the mouse wheel, we scoll the grid
	if event is InputEventMouseMotion:
		end_point = event.global_position
		if is_drawing:
			if not currentMode == EditorMode.NONE:
				update_rectangle()

		_update_brush_preview_position()


# Function to update the position of the brush preview based on the mouse event
func _update_brush_preview_position() -> void:
	var scale_factor = mapEditor.zoom_level * 0.01
	brushPreviewTexture.scale = Vector2(scale_factor, scale_factor)
	brushPreviewTexture.pivot_offset = calculate_scaled_center_distance()
	var mouse_position = get_viewport().get_mouse_position()
	var constant_offset = Vector2(10, 10)
	var scalediff = brushPreviewTexture.size - brushPreviewTexture.size * brushPreviewTexture.scale.x
	var new_position = mouse_position + constant_offset - scalediff / 2
	var scroll_global_pos = mapScrollWindow.get_global_position()
	var mapScrollWindowRect = mapScrollWindow.get_rect()
	new_position.x = clamp(new_position.x, scroll_global_pos.x, scroll_global_pos.x + mapScrollWindowRect.size.x - brushPreviewTexture.get_rect().size.x)
	new_position.y = clamp(new_position.y, scroll_global_pos.y, scroll_global_pos.y + mapScrollWindowRect.size.y - brushPreviewTexture.get_rect().size.y)
	brushPreviewTexture.global_position = new_position

func _on_zoom_level_changed(zoom_level: int):
	_update_brush_preview_position()
	for tile in get_children():
		tile.set_scale_amount(1.28*zoom_level)
	for tile in levelgrid_below.get_children():
		tile.set_scale_amount(1.28*zoom_level)
	for tile in levelgrid_above.get_children():
		tile.set_scale_amount(1.28*zoom_level)


# Function to calculate the distance from top-left to center based on scaling
func calculate_scaled_center_distance() -> Vector2:
	var scaled_size = brushPreviewTexture.size
	return scaled_size / 2

# When the user releases the mouse button on the rotate right button
func _on_rotate_right_pressed():
	rotationAmount = (rotationAmount + 90) % 360 # Keep rotation within 0-359 degrees
	buttonRotateRight.text = str(rotationAmount)
	brushPreviewTexture.rotation_degrees = rotationAmount
	brushPreviewTexture.pivot_offset = calculate_scaled_center_distance()
	_update_brush_preview_position()
	if copied_tiles_info["tiles_data"].size() > 0 and currentMode == EditorMode.COPY_RECTANGLE:
		rotate_selection_clockwise()
	if copied_tiles_info["all_levels_data"].size() > 0 and currentMode == EditorMode.COPY_ALL_LEVELS:
		rotate_selection_clockwise()

# Highlight tiles that are in the rectangle that the user has drawn with the mouse
func update_rectangle() -> void:
	if is_drawing and not currentMode == EditorMode.NONE:
		highlight_tiles_in_rect()

# When one of the grid tiles is clicked, we paint the tile accordingly
func grid_tile_clicked(clicked_tile: Control) -> void:
	if not clicked_tile or not is_drawing:
		return
	match currentMode:
		EditorMode.DRAW_RECTANGLE:
			return
		EditorMode.DRAW_AREA:
			return
		EditorMode.COPY_RECTANGLE:
			if copied_tiles_info["tiles_data"].size() > 0:
				paste_copied_tile_data(clicked_tile)
		EditorMode.COPY_ALL_LEVELS:
			if copied_tiles_info["all_levels_data"].size() > 0:
				apply_column_tiles_to_all_levels(clicked_tile)
		EditorMode.NONE:
			paint_single_tile(clicked_tile)

# Paint a single tile if draw rectangle is not selected.
# Either erase the tile or paint it if a brush is selected.
func paint_single_tile(clicked_tile: Control) -> void:
	apply_paint_to_tile(clicked_tile, selected_brush, rotationAmount)

# Helper function to apply paint or erase logic to a single tile
func apply_paint_to_tile(tile: Control, brush: Control, tilerotate: int):
	if erase:
		if brush:
			if brush.entityType == "mob":
				tile.set_mob_id("")
			elif brush.entityType == "furniture":
				tile.set_furniture_id("")
			elif brush.entityType == "itemgroup":
				tile.set_tile_itemgroups([]) # erase by passing an empty array
			else:
				tile.set_tile_id("")
				tile.set_rotation_amount(0)
		else:
			tile.set_default()
	elif brush:
		selected_brush = brushcomposer.get_random_brush()
		var tilerotation = brushcomposer.get_tilerotation(tilerotate)
		if brush.entityType == "mob":
			tile.set_mob_id(brush.entityID)
			tile.set_mob_rotation(tilerotation)
		elif brush.entityType == "furniture":
			tile.set_furniture_id(brush.entityID)
			tile.set_furniture_rotation(tilerotation)
			tile.set_tile_itemgroups(brushcomposer.get_itemgroup_entity_ids())
		elif brush.entityType == "itemgroup":
			# The brushcomposer only returns a brush of this type if there are only
			# itemgroup brushes in the brushcomposer. We apply the itemgroups to the tile
			tile.set_tile_itemgroups(brushcomposer.get_itemgroup_entity_ids())
		else:
			tile.set_tile_id(brush.entityID)
			tile.set_rotation_amount(tilerotation)

# Store the data of the current level before changing levels
func storeLevelData() -> void:
	currentLevelData.clear()
	var has_significant_data = false

	# First pass: Check if any tile has significant data
	for child in get_children():
		if child.tileData and (child.tileData.has("id") or \
		child.tileData.has("mob") or child.tileData.has("furniture")\
		or child.tileData.has("itemgroups") or child.tileData.has("areas")):
			has_significant_data = true
			break

	# Second pass: Add all tiles to currentLevelData if any significant data is found
	if has_significant_data:
		for child in get_children():
			currentLevelData.append(child.tileData)
	else:
		# If no tile has significant data, consider adding a special marker or log
		print_debug("No significant tile data found for the current level")

	mapData.levels[currentLevel] = currentLevelData.duplicate()

# Load the level data from the map data. If no data exists, use the default to create a new map.
func loadLevelData(newLevel: int) -> void:
	if newLevel > 0:
		loadLevel(newLevel - 1, levelgrid_below)
	else:
		levelgrid_below.hide()
	if newLevel < 20:
		loadLevel(newLevel + 1, levelgrid_above)
		for tile in levelgrid_above.get_children():
			tile.set_above()
	else:
		levelgrid_above.hide()
	loadLevel(newLevel, self)
	update_area_visibility()

func loadLevel(level: int, grid: GridContainer) -> void:
	if mapData.is_empty():
		print_debug("Tried to load data from an empty mapData dictionary")
		return
	var newLevelData: Array = mapData.levels[level]
	var i: int = 0
	# If any data exists on this level, we load it
	if newLevelData != []:
		for tile in grid.get_children():
			tile.tileData = newLevelData[i]
			i += 1
	else:
		#No data is present on this level. apply the default value for each tile
		for tile in grid.get_children():
			tile.set_default()


# We change from one level to another. For exmple from ground level (0) to 1
# Save the data we currently have in the mapData
# Then load the data from mapData if it exists for that level
# If no data exists for that level, create new level data
func change_level(newlevel: int) -> void:
	storeLevelData()
	loadLevelData(newlevel)
	currentLevel = newlevel
	storeLevelData()


# We need to add 10 since the scrollbar starts at -10
func _on_level_scrollbar_value_changed(value) -> void:
	change_level(10 - value)

# Check if any corner of a tile or its edges are within or on the boundary of the normalized rectangle
func is_tile_in_rect(tile: Control, normalized_start: Vector2, normalized_end: Vector2, zoom_level: float) -> bool:
	var tile_size = tile.get_size() / zoom_level
	var tile_global_pos = tile.global_position / zoom_level
	var tile_bottom_right = tile_global_pos + tile_size

	# Adjusting checks to be inclusive of the boundary conditions
	var overlaps_top_left = tile_global_pos.x <= normalized_end.x and tile_global_pos.y <= normalized_end.y
	var overlaps_bottom_right = tile_bottom_right.x >= normalized_start.x and tile_bottom_right.y >= normalized_start.y
	return overlaps_top_left and overlaps_bottom_right


# This function takes two coordinates representing a rectangle and the current zoom level.
# It will check which of the TileGrid's children's positions fall inside this rectangle.
# It returns all the child tiles that fall inside this rectangle.
func get_tiles_in_rectangle(rect_start: Vector2, rect_end: Vector2) -> Array:
	var tiles_in_rectangle: Array = []

	# Normalize the rectangle coordinates
	var normalized_start = Vector2(min(rect_start.x, rect_end.x), min(rect_start.y, rect_end.y))
	var normalized_end = Vector2(max(rect_start.x, rect_end.x), max(rect_start.y, rect_end.y))

	# Adjust the rectangle coordinates based on the zoom level
	normalized_start /= mapEditor.zoom_level
	normalized_end /= mapEditor.zoom_level
	for tile in get_children():
		if is_tile_in_rect(tile, normalized_start, normalized_end, mapEditor.zoom_level):
			tiles_in_rectangle.append(tile)
	return tiles_in_rectangle


# This function calculates the dimensions of the selected tiles in terms of 
# how many tiles were selected horizontally (width) and vertically (height).
func get_selection_dimensions(rect_start: Vector2, rect_end: Vector2) -> Dictionary:
	var selected_tiles = get_tiles_in_rectangle(rect_start, rect_end)
	var x_positions = []
	var y_positions = []

	# Normalize the rectangle coordinates based on the zoom level
	rect_start /= mapEditor.zoom_level
	rect_end /= mapEditor.zoom_level
	for tile in selected_tiles:
		# Assuming the position is based on the tile's position in the grid container
		var tile_pos = tile.get_position() / (snapAmount * mapEditor.zoom_level)
		var x_position = tile_pos.x
		var y_position = tile_pos.y
		
		# Add the positions to the lists if they're not already there
		if not x_positions.has(x_position):
			x_positions.append(x_position)
		if not y_positions.has(y_position):
			y_positions.append(y_position)

	# Sort the positions in ascending order for consistency
	x_positions.sort()
	y_positions.sort()
	# Return the dimensions as a dictionary
	return {"width": x_positions.size(), "height": y_positions.size()}

# Unhighlight all tiles
func unhighlight_tiles() -> void:
	for tile in get_children():
		tile.unhighlight()

# Highlight tiles in the rectangle
func highlight_tiles_in_rect() -> void:
	unhighlight_tiles()
	var tiles: Array = get_tiles_in_rectangle(start_point, end_point)
	for tile in tiles:
		tile.highlight()

# Paint every tile in the selected rectangle
# If erase is active, it will be handled in apply_paint_to_tile
func paint_in_rectangle():
	var tiles: Array = get_tiles_in_rectangle(start_point, end_point)
	for tile in tiles:
		apply_paint_to_tile(tile, selected_brush, rotationAmount)
	update_rectangle()


# Apply the current area data to each of the tiles or erase the area if erase is active.
func paint_area_in_rectangle():
	# Get the selected area name
	var selected_area_name = brushcomposer.get_selected_area_name()
	
	# If the selected area is "None" and erase is true, only update the rectangle
	if selected_area_name == "None" and erase:
		update_rectangle()
		return

	var tiles: Array = get_tiles_in_rectangle(start_point, end_point)
	var area_data: Dictionary = brushcomposer.generate_area_data()
	var tilerotation = brushcomposer.get_tilerotation(rotationAmount)
	for tile in tiles:
		if erase:
			tile.remove_area_from_tile(area_data["id"])
		else:
			tile.add_area_to_tile(area_data, tilerotation)
	if not erase:
		add_area_to_map_data(area_data)
	update_rectangle()



#The user has pressed the erase toggle button in the editor
func _on_erase_toggled(button_pressed):
	erase = button_pressed


# When the user toggles the draw rectangle button in the toolbar
func _on_draw_rectangle_toggled(toggled_on: bool) -> void:
	if toggled_on:
		checkboxCopyRectangle.set_pressed(false)
		checkboxCopyAllLevels.set_pressed(false)
		checkboxDrawarea.set_pressed(false)
		currentMode = EditorMode.DRAW_RECTANGLE
		if selected_brush:
			set_brush_preview_texture(selected_brush.get_texture())
	else:
		currentMode = EditorMode.NONE
		if selected_brush:
			set_brush_preview_texture(selected_brush.get_texture())
		else:
			set_brush_preview_texture(null)


# When the user toggles the copy all levels button in the toolbar
func _on_copy_all_levels_toggled(toggled_on: bool):
	if toggled_on:
		checkboxDrawRectangle.set_pressed(false)
		checkboxCopyRectangle.set_pressed(false)
		checkboxDrawarea.set_pressed(false)
		currentMode = EditorMode.COPY_ALL_LEVELS
		if copied_tiles_info["all_levels_data"].size() > 0:
			# You might want to update the brush preview to reflect the copied tiles
			update_preview_texture_with_copied_data()
		# If there's nothing to copy, perhaps alert the user
		else:
			set_brush_preview_texture(null)
	else:
		currentMode = EditorMode.NONE
		if selected_brush:
			set_brush_preview_texture(selected_brush.get_texture())
		else:
			set_brush_preview_texture(null)

# Called when the Copy Rectangle ToggleButton's state changes.
func _on_copy_rectangle_toggled(toggled_on: bool) -> void:
	# If it was toggled off, clear the data from copied_tiles_info, clear rotation, and hide the brush preview
	if toggled_on:
		checkboxDrawRectangle.set_pressed(false)
		checkboxCopyAllLevels.set_pressed(false)
		checkboxDrawarea.set_pressed(false)
		currentMode = EditorMode.COPY_RECTANGLE
		if copied_tiles_info["tiles_data"].size() > 0:
			# Update the brush preview to reflect the copied tiles
			update_preview_texture_with_copied_data()
		# If there's nothing to copy, perhaps alert the user
		else:
			set_brush_preview_texture(null)
	else:
		currentMode = EditorMode.NONE
		reset_copied_tiles_info()
		reset_rotation()
		set_brush_preview_texture(null)


# Called when the draw area button's state changes
func _on_draw_area_toggled(toggled_on) -> void:
	if toggled_on:
		checkboxCopyRectangle.set_pressed(false)
		checkboxCopyAllLevels.set_pressed(false)
		checkboxDrawRectangle.set_pressed(false)
		currentMode = EditorMode.DRAW_AREA
		if selected_brush:
			set_brush_preview_texture(selected_brush.get_texture())
		
		# Tiles will show the area sprite if the selected area is in the data
		set_area_visibility_for_all_tiles(true,brushcomposer.get_selected_area_name())
	else:
		currentMode = EditorMode.NONE
		set_area_visibility_for_all_tiles(false,"")
		if selected_brush:
			set_brush_preview_texture(selected_brush.get_texture())
		else:
			set_brush_preview_texture(null)


# When the user has selected one of the tile brushes to paint with
func _on_tilebrush_list_tile_brush_selection_change(tilebrush: Control):
	# Toggle the copy buttons off
	checkboxCopyRectangle.set_pressed(false)
	checkboxCopyAllLevels.set_pressed(false)
	if not currentMode == EditorMode.DRAW_RECTANGLE and not currentMode == EditorMode.DRAW_AREA:
		currentMode = EditorMode.NONE
	# Add the brush if ctrl is held, otherwise replace all
	if Input.is_key_pressed(KEY_CTRL):
		brushcomposer.add_tilebrush_to_container(tilebrush)
	else:
		brushcomposer.replace_all_with_brush(tilebrush)


# The cursor will have a preview of the texture that the user will paint with next to it
func update_preview_texture():
	set_brush_preview_texture(selected_brush.get_texture() if selected_brush else null)

# When the user presses the show below button, we show a transparant view of the level below the current level
func _on_show_below_toggled(button_pressed):
	showBelow = button_pressed
	if showBelow:
		levelgrid_below.show()
	else:
		levelgrid_below.hide()

# Handle the show above button toggle
func _on_show_above_toggled(button_pressed):
	showAbove = button_pressed
	if showAbove:
		levelgrid_above.show()
	else:
		levelgrid_above.hide()


#This function takes the mapData property and saves all of it as a json file.
func save_map_json_file():
	# Convert the TileGrid.mapData to a JSON string
	storeLevelData()
	data_changed.emit(mapEditor.contentSource, mapData, olddata)
	var map_data_json = JSON.stringify(mapData.duplicate(), "\t")
	Helper.json_helper.write_json_file(mapEditor.contentSource, map_data_json)
	olddata = mapData.duplicate(true)

# Load the map data from a JSON file
func load_map_json_file():
	var fileToLoad: String = mapEditor.contentSource
	mapData = Helper.json_helper.load_json_dictionary_file(fileToLoad)
	olddata = mapData.duplicate(true)

# Create a 128x128 miniature map image of the current level
func create_miniature_map_image() -> Image:
	var map_width = mapEditor.mapWidth
	var map_height = mapEditor.mapHeight
	var tile_width = int(128 / map_width)  # Calculate tile width for the miniature map
	var tile_height = int(128 / map_height)  # Calculate tile height for the miniature map

	# Create a new Image with a size of 128x128 pixels
	var image = Image.create(128, 128, false, Image.FORMAT_RGBA8)

	# Iterate through each tile in the current level and draw it into the image
	for x in range(map_width):
		for y in range(map_height):
			var tile = get_child(y * map_width + x)
			var tile_texture = tile.get_tile_texture()
			var tile_image = tile_texture.get_image()
			# Resize the tile image to fit the miniature map
			tile_image.resize(tile_width, tile_height)
			# Convert the tile image to the same format as the main image
			tile_image.convert(Image.FORMAT_RGBA8)
			image.blit_rect(tile_image, Rect2(Vector2(), tile_image.get_size()), Vector2(x * tile_width, y * tile_height))
	return image


# Function to create and save a 128x128 miniature map of the current level
func save_miniature_map_image():
	# Call the function to create the image texture
	var image = create_miniature_map_image()
	# Save the image to a file
	var file_name = mapEditor.contentSource.get_file().replace("json", "png")
	var file_path = Gamedata.data.maps.spritePath + file_name

	# Ensure the image is saved
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		image.save_png(file_path)
		# Create an ImageTexture from the Image
		var image_texture = ImageTexture.create_from_image(image)

		# Add the sprite to the dictionary directly using the ImageTexture
		Gamedata.add_sprite_to_dictionary(Gamedata.data.maps, file_name, image_texture)
	else:
		print("Failed to save image:", file_path)

func _on_create_preview_image_button_button_up():
	save_miniature_map_image()

# Loop over all levels and rotate them if they contain tile data
func rotate_map() -> void:
	# Store the data of the current level before rotating the map
	storeLevelData()
	for i in range(mapData.levels.size()):
		# Load each level's data into currentLevelData
		currentLevelData = mapData.levels[i]
		# Rotate the current level data
		rotate_level_clockwise()
		# Update the rotated data back into the mapData
		mapData.levels[i] = currentLevelData.duplicate()

	# After rotation, reload the current level's data
	loadLevelData(currentLevel)

# Rotate the current level 90 degrees clockwise
func rotate_level_clockwise() -> void:
	# Check if currentLevelData has at least one item
	if !currentLevelData.size() > 0:
		return
	var width = mapEditor.mapWidth
	var height = mapEditor.mapHeight
	var new_level_data: Array[Dictionary] = []

	# Initialize new_level_data with empty dictionaries
	for i in range(width * height):
		new_level_data.append({})

	# Rotate the tile data
	for x in range(width):
		for y in range(height):
			var old_index = y * width + x
			var new_x = width - y - 1
			var new_y = x
			var new_index = new_y * width + new_x
			new_level_data[new_index] = currentLevelData[old_index].duplicate(true)
			rotate_tile_data(new_level_data[new_index])
	
	# Update the current level data
	currentLevelData = new_level_data

# Rotate the data for a single tile
func rotate_tile_data(tile_data: Dictionary):
	# Add rotation to the tile's data if it has an id
	if tile_data.has("id"):
		var tile_rotation = int(tile_data.get("rotation", 0))
		tile_data["rotation"] = (tile_rotation + 90) % 360
	# Rotate furniture if present, initializing rotation to 0 if not set
	if tile_data.has("furniture"):
		var furniture_rotation = int(tile_data["furniture"].get("rotation", 0))
		tile_data["furniture"]["rotation"] = (furniture_rotation + 90) % 360


# Called when the user has drawn a rectangle with the copy button toggled on
# This will store the data of the selected tiles to a variable
func copy_selected_tiles_to_memory():
	reset_rotation() # We want to start with 0 rotation, the user can rotate it later
	reset_copied_tiles_info() # Clear previous copied tiles info
	
	# Get selection dimensions represented by an amount of tiles
	var selection_dimensions = get_selection_dimensions(start_point, end_point)
	# Get all tiles within the selected rectangle
	var selected_tiles = get_tiles_in_rectangle(start_point, end_point)

	# Update copied_tiles_info with the new dimensions
	copied_tiles_info["width"] = selection_dimensions["width"]
	copied_tiles_info["height"] = selection_dimensions["height"]

	# Copy each tile's data to the copied_tiles_info dictionary
	for tile in selected_tiles:
		copied_tiles_info["tiles_data"].append(tile.tileData.duplicate())
	
	# Update a preview texture or other UI element to visualize the copied data
	update_preview_texture_with_copied_data()

# Return the index if the child matches the clicked_tile
func get_index_of_child(clicked_tile: Node) -> int:
	var children = get_children()  # Get all children of this GridContainer
	for i in range(children.size()):
		if children[i] == clicked_tile:
			return i  
	return -1  # Return -1 if the clicked_tile is not found among the children


# We create an image and put it as the brush preview texture
# THe image is made from tiles that were selected previously
# This provides a preview of what will be pasted
func update_preview_texture_with_copied_data():
	var preview_size = Vector2(512, 512)  # Size of the preview texture
	var tiles_width = copied_tiles_info["width"]
	var tiles_height = copied_tiles_info["height"]
	
	# Calculate size for each tile in the preview to fit all copied tiles
	var tile_size_x = preview_size.x / tiles_width
	var tile_size_y = preview_size.y / tiles_height
	var tile_size = Vector2(tile_size_x, tile_size_y)
	
	# Create a new Image with a size of 512x512 pixels
	var image = Image.create(preview_size.x, preview_size.y, false, Image.FORMAT_RGBA8)

	# Determine the source of tile data based on current mode
	var tile_data_source = []
	if currentMode == EditorMode.COPY_ALL_LEVELS and copied_tiles_info["all_levels_data"].size() > currentLevel:
		tile_data_source = copied_tiles_info["all_levels_data"][currentLevel]
	else:
		tile_data_source = copied_tiles_info["tiles_data"]

	var idx = 0  # Tile index for positioning tiles in the preview
	for tile_data in tile_data_source:
		var tile_texture: Texture = get_texture_from_tile_data(tile_data)
		if tile_texture:
			var tile_image = tile_texture.get_image()
			# Calculate position in the preview based on the tile index and copied area dimensions
			tile_image.resize(tile_size.x, tile_size.y)
			tile_image.convert(Image.FORMAT_RGBA8)
			var pos_x = (idx % tiles_width) * tile_size.x
			var pos_y = (idx / tiles_width) * tile_size.y
			var pos_in_preview = Vector2(pos_x, pos_y)
			# Draw the resized tile image onto the main image
			image.blit_rect(tile_image, Rect2(Vector2(), tile_image.get_size()), pos_in_preview)
		idx += 1

	# Update the brushPreviewTexture with the generated image
	set_brush_preview_texture(ImageTexture.create_from_image(image))


# Returns the texture associated with the tile id or the default empty tile if id is missing
func get_texture_from_tile_data(tile_data: Dictionary) -> Texture:
	if tile_data.has("id"):
		var texture_id = tile_data["id"]
		return Gamedata.get_sprite_by_id(Gamedata.data.tiles, texture_id).albedo_texture
	else:
		return load("res://Scenes/ContentManager/Mapeditor/Images/emptyTile.png")

# Rotate the selected tiles in copied_tiles_info 90 degrees clockwise
func rotate_selection_clockwise():
	var new_copied_tiles_info: Dictionary = {"tiles_data": [], "all_levels_data": [[],[],[],[],[],[],[],[],[],[],[],[],[],[],[],[],[],[],[],[],[]], "width": copied_tiles_info["height"], "height": copied_tiles_info["width"]}

	# We'll be rotating the tiles, so we need to change width and height
	var new_width = copied_tiles_info["height"]
	var new_height = copied_tiles_info["width"]
	var current_tiles_data = copied_tiles_info["tiles_data"]
	
	# Rotate single level tiles_data if present
	if copied_tiles_info["tiles_data"].size() > 0 and currentMode == EditorMode.COPY_RECTANGLE:
		new_copied_tiles_info["tiles_data"] = rotate_tiles_data(current_tiles_data, new_width, new_height)
		# Assign the newly rotated tiles to copied_tiles_info
		copied_tiles_info = new_copied_tiles_info
		# Mirror the tiles after rotation. This is required because the rotation function 
		# will mirror them, so we need to mirror them back
		copied_tiles_info["tiles_data"] = mirror_copied_tiles_info(copied_tiles_info["tiles_data"], new_width, new_height)

	# Rotate all levels data if present
	if copied_tiles_info["all_levels_data"].size() > 0 and currentMode == EditorMode.COPY_ALL_LEVELS:
		copied_tiles_info["height"] = new_height
		copied_tiles_info["width"] = new_width
		for i in range(copied_tiles_info["all_levels_data"].size()):
			if copied_tiles_info["all_levels_data"][i].size() > 0:
				copied_tiles_info["all_levels_data"][i] = rotate_tiles_data(copied_tiles_info["all_levels_data"][i], new_width, new_height)
				copied_tiles_info["all_levels_data"][i] = mirror_copied_tiles_info(copied_tiles_info["all_levels_data"][i], new_width, new_height)

# Helper function to rotate an array of tiles data
func rotate_tiles_data(tiles_data: Array, width: int, height: int) -> Array:
	var new_tiles_data: Array = []
	for y in range(height):
		for x in range(width):
			var old_x = height - y - 1
			var old_y = x
			var old_index = old_y * height + old_x
			if old_index < tiles_data.size():
				var tile_data = tiles_data[old_index].duplicate(true)
				rotate_tile_data(tile_data)
				new_tiles_data.append(tile_data)
	return new_tiles_data


# Function to mirror copied_tiles_info in both directions (up, down, left, right)
func mirror_copied_tiles_info(tiles_data: Array, width: int, height: int) -> Array:
	var mirrored_tiles_data: Array = []
	if tiles_data.size() <= 0:
		return mirrored_tiles_data

	# Mirror vertically and horizontally by iterating in reverse order
	for y in range(height - 1, -1, -1):
		for x in range(width - 1, -1, -1):
			var original_index = y * width + x
			var mirrored_data = tiles_data[original_index].duplicate()
			
			# Add the mirrored tile data to the new array
			mirrored_tiles_data.append(mirrored_data)
	return mirrored_tiles_data

# Reset the rotation amount to 0 and update relevant nodes
func reset_rotation() -> void:
	rotationAmount = 0
	brushPreviewTexture.rotation_degrees = rotationAmount
	buttonRotateRight.text = str(rotationAmount)

# Get the tile data from mapData for a given index and level
func get_tile_data_from_mapData(index: int, level: int) -> Dictionary:
	var level_data = mapData.levels[level]
	return level_data[index] if index >= 0 and index < level_data.size() else {}

# Returns the index of tiles in the grid, a number between 0 an 1024
# THe index is the location of the tile in the current level
func get_tile_indexes_in_rectangle(rect_start: Vector2, rect_end: Vector2) -> Array[int]:
	var tile_indexes: Array[int] = []
	for tile in get_tiles_in_rectangle(rect_start, rect_end):
		var index = get_index_of_child(tile)
		if index != -1:
			tile_indexes.append(index)
	return tile_indexes


# Function to copy tiles from all levels based on a selection rectangle
# Copies a column of tiles from all levels
# This column is represented by an array
func copy_tiles_from_all_levels(rect_start: Vector2, rect_end: Vector2) -> void:
	reset_copied_tiles_info() # Clear the previous selection if there is any
	reset_rotation()

	# Calculate the dimensions of the selection as an amount of tiles
	var selection_dimensions = get_selection_dimensions(rect_start, rect_end)
	
	# Update copied_tiles_info with the dimensions of the selection
	copied_tiles_info["width"] = selection_dimensions["width"]
	copied_tiles_info["height"] = selection_dimensions["height"]

	# Keep track of the indexes of the tiles in the mapData level
	var tile_indexes = get_tile_indexes_in_rectangle(rect_start, rect_end)

	# Iterate through all levels to copy tiles
	for level in range(mapData.levels.size()):
		var level_data = mapData.levels[level]
		var level_copied_tiles: Array = []
		if level_data.size() > 0:
			for tile_index in tile_indexes:
				var tile_data = get_tile_data_from_mapData(tile_index, level)
				level_copied_tiles.append(tile_data)

			# Add the copied data for this level to the all_levels_data
			copied_tiles_info["all_levels_data"].append(level_copied_tiles)
		else:
			# To make sure we always have 21 levels, we append an empty array for levels with no tiles
			copied_tiles_info["all_levels_data"].append([])
	update_preview_texture_with_copied_data()


# Function to get tile indexes in range based on the provided start tile index, width, and height
# The level_index does not really matter, as long as it's a level with tiles in it
func get_tile_indexes_in_range(start_tile_index: int, width: int, height: int, level_index: int) -> Array:
	var tile_indexes: Array = []
	
	# Calculate the start row and column based on the tile index and map width
	var start_row: int = start_tile_index / mapData["mapwidth"]
	var start_col: int = start_tile_index % int(mapData["mapwidth"])
	# Ensure the range does not exceed the map boundaries
	var end_row: int = min(start_row + height, mapData["mapheight"])
	var end_col: int = min(start_col + width, mapData["mapwidth"])
	# Loop through the specified range and collect tile indexes
	for row in range(start_row, end_row):
		for col in range(start_col, end_col):
			var tile_index: int = row * mapData["mapwidth"] + col
			# Ensure the tile index is within the map's total number of tiles
			if tile_index < mapData["levels"][level_index].size():
				tile_indexes.append(tile_index)
	return tile_indexes


# This function will apply copied_tiles_info["all_levels_data"] to the map
# starting from the clicked tile and moving left to right, up to down
# The amount of tiles is determined by what was selected in copy_tiles_from_all_levels
# Each level in the data is applied to the same level that it was copied from
func apply_column_tiles_to_all_levels(clicked_tile: Control) -> void:
	# We are using the tiles that were selected earlier
	var copied_column_data = copied_tiles_info["all_levels_data"]
	
	# Loop over all levels in mapData
	for level_index in range(mapData["levels"].size()):
		# Ensure there's corresponding copied data for this level
		if level_index < copied_column_data.size():
			var column_data_for_level = copied_column_data[level_index]
			apply_tiles_data_to_level(clicked_tile, level_index, column_data_for_level)
	reset_copied_tiles_info() # Clear the selection
	set_brush_preview_texture(null)

# Paste copied tile data starting from the clicked tile
func paste_copied_tile_data(clicked_tile: Control):
	if copied_tiles_info.is_empty():
		print_debug("No tile data to paste.")
		return

	# `clicked_tile` is a direct child of this GridContainer
	apply_tiles_data_to_level(clicked_tile,currentLevel,copied_tiles_info["tiles_data"])
	reset_copied_tiles_info() # Clear copied_tiles_info after pasting
	set_brush_preview_texture(null)


# Apply tile data from an array to a specific area in a specified level
# This aids in pasting copied tiledata
func apply_tiles_data_to_level(clicked_tile: Control, level_index: int, tiles_data: Array) -> void:
	# Ensure level_index is within the valid range
	if level_index < 0 or level_index >= mapData.levels.size():
		print_debug("Level index out of range.")
		return

	# Ensure there is data to apply
	if tiles_data.is_empty():
		print_debug("No tiles data to apply.")
		return
	var tile_index = get_index_of_child(clicked_tile)
	var width = copied_tiles_info["width"]
	var height = copied_tiles_info["height"]
	var level_data = mapData.levels[level_index]
	var num_columns = columns

	# Calculate the grid position from the starting tile index
	var start_x = tile_index % num_columns
	var start_y = float(tile_index) / num_columns

	# Loop through the specified width and height to apply tile data
	var data_index = 0  # Index for iterating through tiles_data
	for y in range(start_y, start_y + height):
		for x in range(start_x, start_x + width):
			var current_tile_index = y * num_columns + x
			# Check bounds and ensure we do not exceed the level data or tiles_data size
			if current_tile_index < level_data.size() and data_index < tiles_data.size():
				# Apply the tile data, Duplicate to ensure a deep copy
				level_data[current_tile_index] = tiles_data[data_index].duplicate()
				data_index += 1

	# After applying changes, reload or update the level
	if level_index == currentLevel:
		loadLevelData(currentLevel)
	print_debug("Applied tiles data to level %s." % level_index)

# Reset the copied_tiles_info dictionary to its default values
func reset_copied_tiles_info() -> void:
	copied_tiles_info = {"tiles_data": [], "all_levels_data": [], "width": 0, "height": 0}

# Set the brush preview texture
func set_brush_preview_texture(image: Texture) -> void:
	brushPreviewTexture.rotation_degrees = rotationAmount
	if image:
		brushPreviewTexture.texture = image
		brushPreviewTexture.size = image.get_size()
		brushPreviewTexture.visible = true
	else:
		brushPreviewTexture.texture = null
		brushPreviewTexture.visible = false
		brushPreviewTexture.size = Vector2(128, 128)

# The user has added a brush to the brush composer
func _on_composer_brush_added(composerbrush: Control):
	selected_brush = composerbrush
	update_preview_texture()

# The user has removed a brush from the brush composer
func _on_composer_brush_removed(_composerbrush: Control):
	selected_brush = null if brushcomposer.is_empty() else brushcomposer.get_random_brush()
	update_preview_texture()


# Function to add a area to mapData.areas if it doesn't already exist
func add_area_to_map_data(area: Dictionary) -> void:
	# Return if the dictionary is empty
	if area.is_empty():
		return
	
	# Initialize the areas array if it doesn't exist
	if not mapData.has("areas"):
		mapData["areas"] = []
	
	# Check if a area with the same id already exists
	for existing_area in mapData["areas"]:
		if existing_area["id"] == area["id"]:
			return  # area with this id already exists
	
	# Add the new area to the areas array
	mapData["areas"].append(area)


# Function to remove a area from mapData.areas by its id
func remove_area_from_map_data(area_id: String) -> void:
	# Check if the areas array exists in mapData
	if not mapData.has("areas"):
		return
	
	# Iterate through the areas array to find and remove the area by id
	for i in range(mapData["areas"].size()):
		if mapData["areas"][i]["id"] == area_id:
			mapData["areas"].erase(mapData["areas"][i])
			break
	
	# If the areas array is now empty, remove the areas key from mapData
	if mapData["areas"].is_empty():
		mapData.erase("areas")


# Returns a list of areas in the mapdata
func get_map_areas() -> Array:
	if mapData.has("areas") and not mapData["areas"].is_empty():
		return mapData.areas
	return []


# Function to find tiles with a specific area ID in a given level
func find_tiles_with_area(area_id: String, level: int = currentLevel) -> Array:
	var tiles_with_area: Array = []

	# Check if the level is within valid range
	if level < 0 or level >= mapData.levels.size():
		print_debug("Level index out of range.")
		return tiles_with_area
	
	# Get the level data
	var level_data: Array = mapData.levels[level]
	
	# Iterate through the tiles in the level
	for i in range(level_data.size()):
		var tile_data: Dictionary = level_data[i]
		if tile_data.has("areas"):
			for area in tile_data["areas"]:
				if area["id"] == area_id:
					tiles_with_area.append(tile_data)
					break

	return tiles_with_area


# Function to update mapData.areas based on areas_clone and remove missing areas from tiles
# Function to update mapData.areas based on areas_clone and remove missing areas from tiles
func update_map_areas(areas_clone: Array) -> void:
	# Find area IDs in mapData.areas but not in areas_clone
	var map_areas = get_map_areas()
	var areas_clone_ids = areas_clone.map(func(area): return area["id"])
	var missing_area_ids = []

	for area in map_areas:
		if area["id"] not in areas_clone_ids:
			print("Area ID present in mapData.areas but not in areas_clone: %s" % area["id"])
			missing_area_ids.append(area["id"])

	# Remove missing areas from all tiles on all levels
	for missing_area_id in missing_area_ids:
		for level in range(mapData.levels.size()):
			remove_area_from_tiles(missing_area_id, level)

	# Handle "previd" property for renamed areas
	var renamed_areas = {}
	for area in areas_clone:
		if area.has("previd"):
			var previd = area["previd"]
			var new_id = area["id"]
			renamed_areas[previd] = new_id
			# Update the area ID in map_areas
			for map_area in map_areas:
				if map_area["id"] == previd:
					map_area["id"] = new_id
					break
					
			area.erase("previd") # After renaming we don't need it anymore
			# Update all tiles referencing the old ID
			for level in range(mapData.levels.size()):
				rename_area_in_tiles(previd, new_id, level)

	# Overwrite mapData.areas with areas_clone
	mapData["areas"] = areas_clone.duplicate()

	# Check if mapData["areas"] is an empty array and erase the property if true
	if mapData["areas"].is_empty():
		mapData.erase("areas")

	# Check if the selected area name is in the list of missing area IDs or renamed areas
	# If it is, or if the selected area name is "None", we hide the area sprite for all tiles
	var selected_area_name = brushcomposer.get_selected_area_name()
	if selected_area_name in missing_area_ids or selected_area_name in renamed_areas or selected_area_name == "None":
		for tile in get_children():
			tile.set_area_sprite_visibility(false, "")
			tile.set_tooltip()


# Function to rename an area in all tiles across all levels
func rename_area_in_tiles(previd: String, new_id: String, level: int) -> void:
	if level < 0 or level >= mapData.levels.size():
		print_debug("Level index out of range.")
		return

	var level_data = mapData.levels[level]
	for tile_data in level_data:
		if tile_data.has("areas"):
			var areas = tile_data["areas"]
			for area in areas:
				if area["id"] == previd:
					area["id"] = new_id
					break


# Function to remove a area from all tiles on a specific level
func remove_area_from_tiles(area_id: String, level: int) -> void:
	if level < 0 or level >= mapData.levels.size():
		print_debug("Level index out of range.")
		return

	var level_data = mapData.levels[level]
	for tile_data in level_data:
		if tile_data.has("areas"):
			var areas = tile_data["areas"]
			for i in range(areas.size()):
				if areas[i]["id"] == area_id:
					areas.erase(areas[i])
					break
			
			# If no areas remain, remove the "areas" property
			if areas.size() == 0:
				tile_data.erase("areas")


# When the user selects an option in the areas optionbutton in the brushcomposer
func on_areas_option_button_item_selected(optionbutton: Control, index: int):
	# Get the selected area name
	var selected_area_name = optionbutton.get_item_text(index)
	if selected_area_name == "None":
		set_area_visibility_for_all_tiles(false, selected_area_name)
	else:
		set_area_visibility_for_all_tiles(true, selected_area_name)


# Function to update the visibility of area sprites based on the selected area name
func update_area_visibility() -> void:
	var selected_area_name = brushcomposer.get_selected_area_name()
	if selected_area_name != "None":
		set_area_visibility_for_all_tiles(true, selected_area_name)
	else:
		set_area_visibility_for_all_tiles(false, "")


# Function to set the visibility of area sprites for all tiles in the current level
func set_area_visibility_for_all_tiles(isvisible: bool, areaname: String) -> void:
	# Loop over each tile in the current level
	for tile in get_children():
		tile.set_area_sprite_visibility(isvisible, areaname)


# Load the areas from mapdata into the brushcomposer
func load_area_data():
	brushcomposer.set_area_data(get_map_areas())
	set_area_visibility_for_all_tiles(false, brushcomposer.get_selected_area_name())
