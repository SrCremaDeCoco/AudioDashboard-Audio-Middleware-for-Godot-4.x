@tool
extends EditorPlugin

const DASHBOARD_SCENE = preload("res://addons/AudioDashboard/AudioDashboard.tscn")
var dashboard_instance
var _export_plugin
var _debugger_plugin

class AudioDashboardDebugger extends EditorDebuggerPlugin:
	var dashboard: Control
	func _has_capture(prefix: String) -> bool:
		return prefix == "audio_dashboard"
	func _capture(message: String, data: Array, session_id: int) -> bool:
		if message == "audio_dashboard:monitor" and is_instance_valid(dashboard):
			dashboard._receive_monitor_data(data)
			return true
		return false

func _enter_tree():
	# Register the AudioManager as a singleton only if it's missing or points elsewhere
	# This prevents the editor from marking the project as modified on every startup
	var am_path = "res://addons/AudioDashboard/audio/AudioManager.gd"
	var current_autoloads = _get_autoload_dict()
	
	if not current_autoloads.has("AudioManager") or current_autoloads["AudioManager"] != am_path:
		add_autoload_singleton("AudioManager", am_path)
	
	dashboard_instance = DASHBOARD_SCENE.instantiate()
	dashboard_instance.plugin = self
	
	# Add the main panel to the editor's main viewport.
	get_editor_interface().get_editor_main_screen().add_child(dashboard_instance)
	# Hide it by default until the tab is clicked.
	_make_visible(false)
	
	# Register Export Plugin
	_export_plugin = preload("res://addons/AudioDashboard/dashboard_export_plugin.gd").new()
	add_export_plugin(_export_plugin)
	
	# Register Debugger Plugin
	_debugger_plugin = AudioDashboardDebugger.new()
	_debugger_plugin.dashboard = dashboard_instance
	add_debugger_plugin(_debugger_plugin)

func _exit_tree():
	# Remove the singleton when the plugin is disabled
	remove_autoload_singleton("AudioManager")
	
	if _export_plugin:
		remove_export_plugin(_export_plugin)
		_export_plugin = null
		
	if _debugger_plugin:
		remove_debugger_plugin(_debugger_plugin)
		_debugger_plugin = null
	
	if dashboard_instance:
		dashboard_instance.queue_free()

func _has_main_screen():
	return true

func _make_visible(visible):
	if dashboard_instance:
		dashboard_instance.visible = visible

func _get_plugin_name():
	var editor_lang = EditorInterface.get_editor_settings().get_setting("interface/editor/editor_language")
	var lang = "EN"
	if editor_lang.begins_with("es"): lang = "ES"
	elif editor_lang.begins_with("fr"): lang = "FR"
	elif editor_lang.begins_with("de"): lang = "DE"
	
	var translations = load("res://addons/AudioDashboard/translations.gd")
	if translations and translations.DATA.has(lang):
		return translations.DATA[lang].get("PLUGIN_NAME", "Audio Dashboard")
		
	return "Audio Dashboard"


func _get_plugin_icon():
	# Use the SVG icon for the main tab
	return preload("res://addons/AudioDashboard/icons/AudioIcon.svg")


# --- Smart Drop Logic ---
func _forward_3d_can_drop_data(viewport_control: Control, data: Variant) -> bool:
	return _is_audio_dashboard_data(data)

func _forward_3d_drop_data(viewport_control: Control, data: Variant, position: Vector2) -> void:
	_handle_audio_dashboard_drop(data, true)

func _forward_2d_can_drop_data(viewport_control: Control, data: Variant) -> bool:
	return _is_audio_dashboard_data(data)

func _forward_2d_drop_data(viewport_control: Control, data: Variant, position: Vector2) -> void:
	_handle_audio_dashboard_drop(data, false)

func _is_audio_dashboard_data(data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.get("type") == "audio_dashboard_resource"

func _handle_audio_dashboard_drop(data: Variant, is_3d: bool):
	var resources = data.get("resources", [])
	var root = get_editor_interface().get_edited_scene_root()
	if not root: return
	
	var undo_redo = get_undo_redo()
	undo_redo.create_action("Add SceneAudioSource(s)")
	
	for res in resources:
		# Create appropriate SceneAudioSource for the context
		var script_path = "res://addons/AudioDashboard/audio/SceneAudioSource.gd" if is_3d else "res://addons/AudioDashboard/audio/SceneAudioSource2D.gd"
		var sas_script = load(script_path)
		var node = Node3D.new() if is_3d else Node2D.new()
		node.set_script(sas_script)
		node.sound_data = res
		node.name = res.resource_path.get_file().get_basename()
		
		undo_redo.add_do_method(root, "add_child", node)
		undo_redo.add_do_reference(node)
		undo_redo.add_undo_method(root, "remove_child", node)
		
		# Set owner for persistence
		undo_redo.add_do_property(node, "owner", root)
		
	
func _get_autoload_dict() -> Dictionary:
	var dict = {}
	for prop in ProjectSettings.get_property_list():
		var name = prop["name"]
		if name.begins_with("autoload/"):
			var autoload_name = name.trim_prefix("autoload/")
			dict[autoload_name] = ProjectSettings.get_setting(name)
	return dict
