class_name DMobfaction
extends RefCounted


# There's a D in front of the class name to indicate this class only handles mob data, nothing more
# This script is intended to be used inside the GameData autoload singleton
# This script handles the data for one mobfaction. You can access it through Gamedata.mods.by_id("Core")


# Represents a mob faction and its properties.
# This script is used for handling mob faction data within the GameData autoload singleton.
# Example mob faction JSON:
# {
# 	"id": "undead",
# 	"name": "The Undead",
# 	"description": "The unholy remainders of our past sins.",
#	"relations": [
#			{
#				"relation_type": "core"
#				"mobgroup": ["basic_zombies", "basic_vampires"],
#				"mobs": ["small slime", "big slime"],
#				"factions": ["human_faction", "animal_faction"]
#			},
#			{
#				"relation_type": "hostile"
#				"mobgroup": ["security_robots", "national_guard"],
#				"mobs": ["jabberwock", "cerberus"],
#				"factions": ["human_faction", "animal_faction"]
#			}
#		]
#	}

# Inner class to handle relations in a mob faction
class Relation:
	var relation_type: String  # Can be "hostile", "neutral", or "friendly"
	var mobgroups: Array = []  # Array of mobgroup IDs
	var mobs: Array = []       # Array of mob IDs
	var factions: Array = []   # Array of faction IDs

	# Constructor to initialize the relation with data from a dictionary
	func _init(relation_data: Dictionary):
		relation_type = relation_data.get("relation_type", "neutral")  # Default to "neutral" if not specified
		mobgroups = relation_data.get("mobgroups", [])
		mobs = relation_data.get("mobs", [])
		factions = relation_data.get("factions", [])

	# Returns all relation properties as a dictionary
	func get_data() -> Dictionary:
		var data: Dictionary = {
			"relation_type": relation_type
		}
		if not mobgroups.is_empty():
			data["mobgroups"] = mobgroups
		if not mobs.is_empty():
			data["mobs"] = mobs
		if not factions.is_empty():
			data["factions"] = factions
		return data

# Properties defined in the JSON structure
var id: String
var name: String
var description: String
var relations: Array = []
var parent: DMobfactions

# Constructor to initialize itemgroup properties from a dictionary
# myparent: The list containing all itemgroups for this mod
func _init(data: Dictionary, myparent: DMobfactions):
	parent = myparent
	id = data.get("id", "")
	name = data.get("name", "")
	description = data.get("description", "")
	relations = []
	for relation_data in data.get("relations", []):
		relations.append(Relation.new(relation_data))


# Returns all properties of the mob faction as a dictionary
func get_data() -> Dictionary:
	var data: Dictionary = {
		"id": id,
		"name": name,
		"description": description,
		"relations": []
	}
	for relation in relations:
		data["relations"].append(relation.get_data())
	return data


# Method to save any changes to the stat back to disk
func save_to_disk():
	parent.save_mobfactions_to_disk()
# Handles faction deletion
func delete():
	var relationmobs: Array =  relations.filter(func(relation): return relation.has("mob"))
	for killrelation in relationmobs:
		Gamedata.mods.remove_reference(DMod.ContentType.MOBS, killrelation.mob, DMod.ContentType.MOBFACTIONS, id)
	var relationmobgroups: Array = relations.filter(func(relation): return relation.has("mobgroup"))
	for killrelation in relationmobgroups:
		Gamedata.mods.remove_reference(DMod.ContentType.MOBGROUPS, killrelation.mobgroup, DMod.ContentType.MOBFACTIONS, id)


# Handles quest changes
func changed(olddata: DMobfaction):
	# Get mobs and mobgroups from the old relations
	var old_quest_mobs: Array = olddata.relations.filter(func(relation): return relation.has("mob"))
	var old_quest_mobgroups: Array = olddata.relations.filter(func(relation): return relation.has("mobgroup"))
	# Get mobs and mobgroups from the new relations
	var new_quest_mobs: Array = relations.filter(func(relation): return relation.has("mob"))
	var new_quest_mobgroups: Array = relations.filter(func(relation): return relation.has("mobgroup"))

	# Remove references for old mobs that are not in the new data
	for old_mob in old_quest_mobs:
		if old_mob not in new_quest_mobs:
			Gamedata.mods.remove_reference(DMod.ContentType.MOBS, old_mob.mob, DMod.ContentType.MOBFACTIONS, id)
	# Remove references for old mobgroups that are not in the new data
	for old_mobgroup in old_quest_mobgroups:
		if old_mobgroup not in new_quest_mobgroups:
			Gamedata.mods.remove_reference(DMod.ContentType.MOBGROUPS, old_mobgroup.mobgroup, DMod.ContentType.MOBFACTIONS, id)

	# Add references for new mobs
	for new_mob in new_quest_mobs:
		Gamedata.mods.add_reference(DMod.ContentType.MOBS, new_mob.mob, DMod.ContentType.MOBFACTIONS, id)
	# Add references for new mobgroups
	for new_mobgroup in new_quest_mobgroups:
		Gamedata.mods.add_reference(DMod.ContentType.MOBGROUPS, new_mobgroup.mobgroup, DMod.ContentType.MOBFACTIONS, id)
	save_to_disk()

# Removes all relations where the mob property matches the given mob_id
func remove_relations_by_mob(mob_id: String) -> void:
	relations = relations.filter(func(relation): 
		return not (relation.has("mob") and relation.mob == mob_id)
	)
	save_to_disk()


# Removes all relations where the mobgroup property matches the given mobgroup_id
func remove_relations_by_mobgroup(mobgroup_id: String) -> void:
	relations = relations.filter(func(relation): 
		return not (relation.has("mobgroup") and relation.mobgroup == mobgroup_id)
	)
	save_to_disk()
