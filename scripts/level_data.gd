class_name LevelData
extends RefCounted
## The authored campaign, in story order. Custom editor levels are opened
## explicitly and do not silently become part of the campaign.

const LevelDefinition = preload("res://levels/level_definition.gd")
const CAMPAIGN_PATHS: Array[String] = [
	"res://levels/01_a_direction_unseen.tres",
	"res://levels/02_the_missing_span.tres",
	"res://levels/03_two_turns_from_home.tres",
]


static func definitions() -> Array[FoldLevel]:
	var levels: Array[FoldLevel] = []
	for path in CAMPAIGN_PATHS:
		var level: FoldLevel = LevelDefinition.load_level(path)
		if level == null:
			push_error("Campaign level is missing or invalid: %s" % path)
			continue
		levels.append(level)
	return levels


static func all_levels() -> Array[Dictionary]:
	var levels: Array[Dictionary] = []
	for definition in definitions():
		levels.append(definition.to_dictionary())
	return levels


static func solutions() -> Array[Array]:
	var routes: Array[Array] = []
	for level in all_levels():
		routes.append(level["solution"])
	return routes
