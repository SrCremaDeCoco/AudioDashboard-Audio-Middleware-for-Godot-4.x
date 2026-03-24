@tool
extends EditorExportPlugin

const EXCLUDED_PATH = "res://addons/AudioDashboard/"

func _get_name():
	return "AudioDashboardExcluder"

func _export_file(path: String, type: String, features: PackedStringArray) -> void:
	# Keep runtime scripts that the game needs
	# These are all the scripts and resources in the /audio/ folder.
	if path.begins_with("res://addons/AudioDashboard/audio/"):
		return
		
	# Skip everything else in the plugin folder (editor scripts, UI, etc.)
	# This avoids including the dashboard panel, icons, and translation logic in the final build.
	elif path.begins_with(EXCLUDED_PATH):
		skip()
