@tool
extends Control

#region UI Components
var _main_split: HSplitContainer
var _tree_view: Tree
var _search_bar: LineEdit
var _inspector_container: VBoxContainer
var _inspector_content: VBoxContainer
var _mixer_container: HBoxContainer
var _preview_player: AudioStreamPlayer
var _drop_hint: Label
var _sync_label: Label
var _is_out_of_sync: bool = false
var _doc_viewer: RichTextLabel

var _creation_dialog: ConfirmationDialog
var _creation_name: LineEdit
var _creation_pending_files: Array
var _creation_target_path: String

var _context_menu: PopupMenu
var _context_target_path: String
var _rename_dialog: ConfirmationDialog
var _rename_input: LineEdit
#endregion

#region Data
const RESOURCE_ROOT = "res://resources/audio_data"
var _scanned_resources: Dictionary = {} # Path -> SoundData
var _current_selection: SoundData
var _current_bank: SoundBank
var _inspector_locked: bool = false
var _editors: Dictionary = {} # Prop -> Control
var _current_play_button: Button = null
var _current_lang: String = "Auto" # "Auto", "EN", "ES"
var plugin: EditorPlugin
var _bus_meters: Dictionary = {} # int -> ProgressBar
var _live_list_container: Tree
var _monitor_timer: float = 0.0
var _enable_live_monitor: bool = true
var _preview_history: Dictionary = {} # Map<SoundData, Dictionary>
var _last_bus_count: int = -1
var _last_bus_names: String = ""
var __undo_redo: UndoRedo
var _undo_redo: UndoRedo:
	get:
		if not __undo_redo:
			__undo_redo = UndoRedo.new()
		return __undo_redo
#endregion

#region Localization
const L10N_DATA = preload("res://addons/AudioDashboard/translations.gd")

func _t(key: String) -> String:
	var lang = _current_lang
	if lang == "Auto":
		var editor_lang = EditorInterface.get_editor_settings().get_setting("interface/editor/editor_language")
		if editor_lang.begins_with("es"): lang = "ES"
		elif editor_lang.begins_with("fr"): lang = "FR"
		elif editor_lang.begins_with("de"): lang = "DE"
		else: lang = "EN"


	
	var data = L10N_DATA.DATA
	if not data.has(lang): lang = "EN"
	
	if data[lang].has(key):
		return data[lang][key]
		
	# Fallback to English if key missing in target lang
	if lang != "EN" and data["EN"].has(key):
		return data["EN"][key]
		
	return key
#endregion

const GROUP_ICON = "Folder"
const SOUND_ICON = "AudioStreamPlayer"

func _ready() -> void:

	_load_settings()
	_build_ui()
	# Initialize structure silently
	_initialize_structure()
	
	# Polling for VU Meters if visible
	set_process(true)
	
	# Register preview player with AudioManager if available
	var am = get_node_or_null("/root/AudioManager")
	if am:
		# If we have a way to register external players in AudioManager, we'd use it here.
		# For now, AudioManager.gd tracks _player_to_data which is internal.
		# Placeholder for monitor safety logic

		pass
	
	# Wait for the editor to be stable before the first refresh (no forced scan)
	var timer = get_tree().create_timer(3.0)
	timer.timeout.connect(func(): _refresh_library(false))
	
	# Connect to FS changes to auto-update the sync labels
	var fs = EditorInterface.get_resource_filesystem()
	if not fs.filesystem_changed.is_connected(_on_fs_changed):
		fs.filesystem_changed.connect(_on_fs_changed)
	if not fs.resources_reimported.is_connected(_on_resources_changed):
		fs.resources_reimported.connect(_on_resources_changed)

func _on_fs_changed():
	_refresh_library(false)

func _on_resources_changed(_resources: PackedStringArray):
	_refresh_library(false)

#region UI Construction
func _build_ui() -> void:
	# Clear previous
	for c in get_children():
		c.queue_free()

		
	# Main Layout
	var main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(main_vbox)

	
	# Toolbar
	_build_toolbar(main_vbox)


	# Split View
	_main_split = HSplitContainer.new()
	_main_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(_main_split)

	
	# Left: Library (Tree)
	var left_panel = VBoxContainer.new()
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.custom_minimum_size.x = 250
	left_panel.size_flags_stretch_ratio = 0.3
	_main_split.add_child(left_panel)
	
	_search_bar = LineEdit.new()
	_search_bar.placeholder_text = _t("SEARCH_PLACEHOLDER")
	_search_bar.right_icon = get_theme_icon("Search", "EditorIcons")
	_search_bar.clear_button_enabled = true
	_search_bar.text_changed.connect(_on_search_text_changed)
	left_panel.add_child(_search_bar)


	
	var tree_script = load("res://addons/AudioDashboard/DashboardTree.gd")
	if not tree_script:
		print("AudioDashboard: ERROR - Could not load DashboardTree.gd script!")
		_tree_view = Tree.new()
	else:
		_tree_view = tree_script.new()
		
	_tree_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree_view.hide_root = true
	_tree_view.select_mode = Tree.SELECT_MULTI
	
	_tree_view.item_selected.connect(_request_selection_update)
	_tree_view.multi_selected.connect(func(_item, _col, _sel): _request_selection_update())
	left_panel.add_child(_tree_view)

	
	# Right: Inspector & Mixer
	var right_panel = TabContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_stretch_ratio = 0.7
	_main_split.add_child(right_panel)
	
	# Tab 1: Inspector
	var inspector_scroll = ScrollContainer.new()
	right_panel.add_child(inspector_scroll)
	right_panel.set_tab_title(0, _t("TAB_INSPECTOR"))
	
	_inspector_container = VBoxContainer.new()
	_inspector_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector_scroll.add_child(_inspector_container)
	
	_inspector_content = VBoxContainer.new() # Holds dynamic content
	_inspector_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspector_container.add_child(_inspector_content)
	
	# Tab 2: Mixer
	var mixer_scroll = ScrollContainer.new()
	right_panel.add_child(mixer_scroll)
	right_panel.set_tab_title(1, _t("TAB_MIXER"))
	
	_mixer_container = HBoxContainer.new()
	_mixer_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mixer_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mixer_scroll.add_child(_mixer_container)
	
	# Tab 3: Live Monitor
	_live_list_container = Tree.new()
	right_panel.add_child(_live_list_container)
	right_panel.set_tab_title(2, _t("TAB_LIVE"))
	
	_live_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_live_list_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_live_list_container.columns = 5
	_live_list_container.set_column_title(0, _t("LIST_COL_STATE"))
	_live_list_container.set_column_title(1, _t("LIST_COL_NAME"))
	_live_list_container.set_column_title(2, _t("LIST_COL_BUS"))
	_live_list_container.set_column_title(3, _t("LIST_COL_TIME"))
	_live_list_container.set_column_title(4, _t("LIST_COL_VOL"))
	_live_list_container.set_column_titles_visible(true)
	_live_list_container.hide_root = true
	_live_list_container.set_column_expand(0, false)
	_live_list_container.set_column_custom_minimum_width(0, 50)
	
	# Tab 4: Settings
	var settings_scroll = ScrollContainer.new()
	right_panel.add_child(settings_scroll)
	right_panel.set_tab_title(3, _t("TAB_SETTINGS"))
	
	var settings_vbox = VBoxContainer.new()
	settings_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_scroll.add_child(settings_vbox)
	_build_settings_tab(settings_vbox)
	
	# Tab 5: Documentation
	var doc_scroll = ScrollContainer.new()
	right_panel.add_child(doc_scroll)
	right_panel.set_tab_title(4, _t("TAB_DOCS"))
	
	_doc_viewer = RichTextLabel.new()
	_doc_viewer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_doc_viewer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_doc_viewer.bbcode_enabled = true
	_doc_viewer.selection_enabled = true
	doc_scroll.add_child(_doc_viewer)
	_update_docs() # Initial load
	
	# Preview Player
	_preview_player = AudioStreamPlayer.new()
	add_child(_preview_player)
	
	# Initial states
	_update_mixer_ui()
	
	# Creation Dialog
	_creation_dialog = ConfirmationDialog.new()
	_creation_dialog.title = _t("DIALOG_CREATE_TITLE")
	_creation_dialog.min_size = Vector2(300, 100)
	add_child(_creation_dialog)
	
	var vbox = VBoxContainer.new()
	_creation_dialog.add_child(vbox)
	
	var lbl = Label.new()
	lbl.text = _t("LBL_RESOURCE_NAME")
	vbox.add_child(lbl)
	
	_creation_name = LineEdit.new()
	vbox.add_child(_creation_name)
	
	_creation_dialog.confirmed.connect(_on_create_confirmed)
	
	# Context Menu
	_context_menu = PopupMenu.new()
	_context_menu.add_item(_t("MENU_NEW_FOLDER"), 0)
	_context_menu.add_item(_t("MENU_RENAME"), 1)
	_context_menu.add_item(_t("MENU_DELETE"), 2)
	_context_menu.add_separator()
	_context_menu.add_item(_t("MENU_NEW_BANK"), 3)
	_context_menu.id_pressed.connect(_on_context_menu_item_selected)
	add_child(_context_menu)
	
	# Rename Dialog
	_rename_dialog = ConfirmationDialog.new()
	_rename_dialog.title = _t("MENU_RENAME")
	_rename_dialog.min_size = Vector2(300, 80)
	var rvbox = VBoxContainer.new()
	_rename_dialog.add_child(rvbox)
	_rename_input = LineEdit.new()
	rvbox.add_child(_rename_input)
	_rename_dialog.confirmed.connect(_on_rename_confirmed)
	add_child(_rename_dialog)
	
	# Enable Right Click on Tree
	_tree_view.set_allow_rmb_select(true)
	_tree_view.item_mouse_selected.connect(_on_tree_item_mouse_selected)
	
	# Restore inspection state
	if _current_bank:
		_inspect_bank(_current_bank, true)
	elif _current_selection:
		_inspect_resource(_current_selection, true)
	
	# Refresh docs if language changed
	_update_docs()

func _update_docs() -> void:
	if not _doc_viewer: return
	
	var readme_path = "res://addons/AudioDashboard/README.md"
	if not FileAccess.file_exists(readme_path):
		_doc_viewer.text = "README.md not found."
		return
		
	var content = FileAccess.get_file_as_string(readme_path)
	var lang = _current_lang
	if lang == "Auto":
		var editor_lang = EditorInterface.get_editor_settings().get_setting("interface/editor/editor_language")
		if editor_lang.begins_with("es"): lang = "ES"
		elif editor_lang.begins_with("fr"): lang = "FR"
		elif editor_lang.begins_with("de"): lang = "DE"
		else: lang = "EN"
	
	# Extract relevant section
	var section_header = "# Documentation in English" # Default
	if lang == "ES": section_header = "# Documentación en Español"
	elif lang == "FR": section_header = "# Documentation en Français"
	elif lang == "DE": section_header = "# Dokumentation auf Deutsch"
	
	var start_idx = content.find(section_header)
	if start_idx == -1: start_idx = 0
	
	var next_section_idx = content.find("\n# ", start_idx + 10)
	var section_text = ""
	if next_section_idx == -1:
		section_text = content.substr(start_idx)
	else:
		section_text = content.substr(start_idx, next_section_idx - start_idx)
		
	# Simple MD -> BBCode conversion
	var bbcode = section_text
	
	# Headers
	bbcode = bbcode.replace("### ", "[b][color=cyan][i]")
	bbcode = bbcode.replace("## ", "[b][size=18][color=yellow]")
	bbcode = bbcode.replace("# ", "[b][size=22][color=white]")
	
	# Close tags for headers (assuming they end on newline)
	var lines = bbcode.split("\n")
	for i in range(lines.size()):
		if lines[i].contains("[size=") or lines[i].contains("[i]"):
			lines[i] += "[/color][/size][/b]" if lines[i].contains("[size=") else "[/i][/color][/b]"
	bbcode = "\n".join(lines)
	
	# Bold
	bbcode = bbcode.replace("**", "[b]").replace("**", "[/b]") # Rough
	# Code
	bbcode = bbcode.replace("`", "[code]").replace("`", "[/code]")
	
	_doc_viewer.text = bbcode



func _build_toolbar(parent: Control):
	var toolbar = HBoxContainer.new()
	parent.add_child(toolbar)
	
	var title = Label.new()
	title.text = " " + _t("LBL_TITLE")
	title.add_theme_font_size_override("font_size", 16)
	toolbar.add_child(title)
	
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)
	
	var refresh_btn = Button.new()
	refresh_btn.text = _t("BTN_REFRESH")
	refresh_btn.icon = get_theme_icon("Reload", "EditorIcons")
	refresh_btn.pressed.connect(func(): _refresh_library(true))
	toolbar.add_child(refresh_btn)
	
	var compile_btn = Button.new()
	compile_btn.text = _t("BTN_COMPILE")
	compile_btn.icon = get_theme_icon("Save", "EditorIcons")
	compile_btn.pressed.connect(_compile_sounds)
	toolbar.add_child(compile_btn)
	
	_sync_label = Label.new()
	_sync_label.text = _t("LBL_SYNC_PENDING")
	_sync_label.add_theme_color_override("font_color", Color.YELLOW)
	_sync_label.visible = false
	toolbar.add_child(_sync_label)
	
	var init_btn = Button.new()
	init_btn.text = _t("BTN_INIT")
	init_btn.pressed.connect(_initialize_structure)
	toolbar.add_child(init_btn)
	
	var diag_btn = Button.new()
	diag_btn.text = _t("BTN_DIAG")
	diag_btn.pressed.connect(_run_diagnostics)
	toolbar.add_child(diag_btn)
	
	var stop_btn = Button.new()
	stop_btn.text = _t("BTN_STOP")
	stop_btn.icon = get_theme_icon("Stop", "EditorIcons")
	stop_btn.pressed.connect(_stop_preview)
	toolbar.add_child(stop_btn)
#endregion

#region Library Logic (Tree)
var _tree_collapsed_states: Dictionary = {} # Map<String (path), bool (collapsed)>

func _refresh_library(force_scan: bool = true) -> void:
	_scanned_resources.clear()
	
	# Guard: Only scan if requested and not already scanning to avoid "Task already exists" error
	if force_scan and not EditorInterface.get_resource_filesystem().is_scanning():
		EditorInterface.get_resource_filesystem().scan()
	
	# Recursive scan (Data only first)
	_scan_data_only(RESOURCE_ROOT)
	
	# Detect if we need an update
	_check_sync_status()
	
	# Build UI Tree (Depends on UI)
	if not _tree_view: return # UI not ready yet
	
	# Save collapsed states before clearing
	var tree_root = _tree_view.get_root()
	if tree_root:
		_save_tree_collapsed_states(tree_root)
	
	_tree_view.clear()
	var root = _tree_view.create_item()
	_rebuild_tree_ui(RESOURCE_ROOT, root)

func _save_tree_collapsed_states(item: TreeItem):
	var meta = item.get_metadata(0)
	if meta and typeof(meta) == TYPE_DICTIONARY and meta.has("path"):
		_tree_collapsed_states[meta["path"]] = item.collapsed
	var child = item.get_first_child()
	while child:
		_save_tree_collapsed_states(child)
		child = child.get_next()

func _check_sync_status():
	_is_out_of_sync = false
	var script_path = "res://addons/AudioDashboard/audio/Sounds.gd"
	if not FileAccess.file_exists(script_path):
		_is_out_of_sync = true
	else:
		var content = FileAccess.get_file_as_string(script_path)
		
		var sound_data_paths = []
		for path in _scanned_resources:
			if _scanned_resources[path] is SoundData:
				sound_data_paths.append(path)
		
		# Check for missing slugs in script
		for path in sound_data_paths:
			var res: SoundData = _scanned_resources[path]
			var slug_to_find = res.slug
			if slug_to_find.is_empty():
				_is_out_of_sync = true
				break
			if not ("\"" + slug_to_find + "\"") in content:
				_is_out_of_sync = true
				break
		
		# Check for extra paths / deleted files in script
		if not _is_out_of_sync:
			var lines = content.split("\n")
			var list_in_script = []
			for line in lines:
				if "const " in line and " = \"" in line:
					var path = line.split(" = \"")[1].split("\"")[0]
					list_in_script.append(path)
			
			if list_in_script.size() != sound_data_paths.size():
				_is_out_of_sync = true
			else:
				var all_slugs = []
				for path in sound_data_paths:
					all_slugs.append(_scanned_resources[path].slug)
				
				for s in list_in_script:
					if not s in all_slugs:
						_is_out_of_sync = true
						break
				
	if _sync_label:
		_sync_label.visible = _is_out_of_sync

func _gather_all_tres(path: String, out_list: Array):
	var dir = DirAccess.open(path)
	if not dir: return
	dir.list_dir_begin()
	var fn = dir.get_next()
	while fn != "":
		if dir.current_is_dir():
			if not fn.begins_with("."):
				_gather_all_tres(path.path_join(fn), out_list)
		else:
			if fn.ends_with(".tres") or fn.ends_with(".res"):
				out_list.append(path.path_join(fn))
		fn = dir.get_next()
				
	if _sync_label:
		_sync_label.visible = _is_out_of_sync

func _compile_sounds():
	_generate_sounds_helper()
	_is_out_of_sync = false
	if _sync_label: _sync_label.visible = false

func _scan_data_only(path: String):
	var dir = DirAccess.open(path)
	if not dir: return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if dir.current_is_dir():
			if file_name != "." and file_name != ".." and file_name != "addons" and file_name != ".godot":
				_scan_data_only(path.path_join(file_name))
		else:
			if file_name.ends_with(".tres") or file_name.ends_with(".res"):
				var full_path = path.path_join(file_name)
				var res = load(full_path)
				if res is SoundData:
					_scanned_resources[full_path] = res
					# Auto-generate slug if empty
					if res.slug.is_empty():
						var base_slug = file_name.get_basename().to_snake_case()
						var final_slug = base_slug
						
						# Check for collisions in what we've already scanned
						var used_slugs = []
						for p in _scanned_resources: used_slugs.append(_scanned_resources[p].slug)
						
						if final_slug in used_slugs:
							var parent = path.get_file().to_snake_case()
							final_slug = parent + "_" + base_slug
							
						res.slug = final_slug
						ResourceSaver.save(res, full_path)
		file_name = dir.get_next()

func _rebuild_tree_ui(path: String, parent_item: TreeItem):
	# Simplified recurse for UI
	_scan_dir_recursive(path, parent_item)

func _scan_dir_recursive(path: String, parent_item: TreeItem):
	var dir = DirAccess.open(path)
	if not dir:
		# Attempt to create if missing
		DirAccess.make_dir_recursive_absolute(path)
		dir = DirAccess.open(path)
		if not dir: return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	var dirs = []
	var files = []
	
	while file_name != "":
		if dir.current_is_dir():
			if file_name != "." and file_name != ".." and file_name != "addons" and file_name != ".godot":
				dirs.append(file_name)
		else:
			if file_name.ends_with(".tres") or file_name.ends_with(".res"):
				files.append(file_name)
		file_name = dir.get_next()
		
	dirs.sort()
	files.sort()
	
	# Process Dirs
	for d in dirs:
		# Pruning: Only show folders that assume they contain audio stuff? 
		# Or show all? Let's show all but maybe filter empty ones later.
		# For now, just show structure.
		var full_path = path.path_join(d)
		var item = _tree_view.create_item(parent_item)
		item.set_text(0, d)
		item.set_icon(0, get_theme_icon("Folder", "EditorIcons"))
		item.set_metadata(0, {"type": "dir", "path": full_path})
		# Restore collapsed state from memory, default to false (expanded)
		item.collapsed = _tree_collapsed_states.get(full_path, false)
		
		# Recursion
		_scan_dir_recursive(full_path, item)
		
		# Optimization: Remove empty folder items if they have no SoundData in children
		# (Simplified: if no children, remove. But needs deep check. Let's keep it simple for now)

	# Process Files (SoundData & SoundBanks)
	for f in files:
		var full_path = path.path_join(f)
		var res = load(full_path)
		if res is SoundData:
			_scanned_resources[full_path] = res
			var item = _tree_view.create_item(parent_item)
			item.set_text(0, f.trim_suffix(".tres"))
			item.set_icon(0, load("res://addons/AudioDashboard/icons/audio_icon.png"))


			item.set_metadata(0, {"type": "file", "path": full_path, "res": res})
		elif res is SoundBank:
			_scanned_resources[full_path] = res
			var item = _tree_view.create_item(parent_item)
			item.set_text(0, f.trim_suffix(".tres"))
			item.set_icon(0, load("res://addons/AudioDashboard/icons/bank_icon.png"))


			item.set_metadata(0, {"type": "file", "path": full_path, "res": res})

func _on_search_text_changed(new_text: String) -> void:
	_filter_tree(new_text)

func _filter_tree(query: String) -> void:
	var root = _tree_view.get_root()
	if not root: return
	
	var clean_query = query.strip_edges()
	if clean_query.is_empty():
		_reset_tree_visibility(root)
		return
		
	var is_tag_search = query.begins_with("#")
	var is_bus_search = query.begins_with("@")
	var tag_query = query.substr(1).to_lower().strip_edges()
	var normal_query = query.to_lower()
	
	_recursive_filter(root, normal_query, is_tag_search, tag_query, is_bus_search)



func _recursive_filter(item: TreeItem, query: String, is_tag: bool, tag_q: String, is_bus: bool = false) -> bool:
	var visible = false
	var metadata = item.get_metadata(0)
	
	if metadata and metadata.has("res") and metadata["res"] is SoundData:
		var sound_data_res: SoundData = metadata["res"]
		var match_found = false
		if is_tag:
			match_found = sound_data_res.group_tag.to_lower().contains(tag_q)
		elif is_bus:
			match_found = sound_data_res.bus.to_lower().contains(tag_q) # tag_q is just substr(1)
		else:
			match_found = sound_data_res.resource_path.get_file().to_lower().contains(query)
		
		item.visible = match_found
		visible = match_found
	else:
		# Folder or non-SoundData file
		var has_visible_child = false
		var child = item.get_first_child()
		while child:
			if _recursive_filter(child, query, is_tag, tag_q, is_bus):
				has_visible_child = true
			child = child.get_next()
		
		# Folders are visible if they have visible children or match the normal query
		item.visible = has_visible_child or (not is_tag and item.get_text(0).to_lower().contains(query))
		visible = item.visible
		
	return visible

func _reset_tree_visibility(item: TreeItem):
	item.visible = true
	# Restore collapsed state if we have it, otherwise default to expanded in search reset?
	# Usually we want to keep what was there.
	var metadata = item.get_metadata(0)
	if metadata and metadata.has("path"):
		if _tree_collapsed_states.has(metadata["path"]):
			item.collapsed = _tree_collapsed_states[metadata["path"]]
			
	var child = item.get_first_child()
	while child:
		_reset_tree_visibility(child)
		child = child.get_next()


var _selection_update_pending: bool = false
func _request_selection_update():
	if _selection_update_pending: return
	_selection_update_pending = true
	_do_selection_update.call_deferred()

func _do_selection_update():
	_selection_update_pending = false
	_on_tree_item_selected()

func _on_tree_item_selected():
	if not is_instance_valid(_tree_view) or _inspector_locked: 
		return
		
	var selected_items = []
	var bank_handled = false
	var item = _tree_view.get_next_selected(null)
	
	while item:
		var meta = item.get_metadata(0)
		if meta and meta.has("res"):
			var res = meta["res"]
			if res is SoundData:
				selected_items.append(res)
			elif res is SoundBank:
				_inspect_bank(res)
				bank_handled = true
		item = _tree_view.get_next_selected(item)
	
	if bank_handled:
		return
	
	if selected_items.size() == 1:
		_inspect_resource(selected_items[0])
	elif selected_items.size() > 1:
		_inspect_multi_selection(selected_items)
	else:
		_clear_inspector()

func _on_tree_item_mouse_selected(pos, mouse_button_index):
	if mouse_button_index == MOUSE_BUTTON_RIGHT:
		var item = _tree_view.get_item_at_position(pos)
		if item:
			item.select(0)
			var meta = item.get_metadata(0)
			if meta:
				_context_target_path = meta["path"]
				
				# Dynamic Context Menu
				_context_menu.clear()
				_context_menu.add_item(_t("MENU_NEW_FOLDER"), 0)
				_context_menu.add_item(_t("MENU_RENAME"), 1)
				_context_menu.add_item(_t("MENU_DELETE"), 2)
				_context_menu.add_separator()
				_context_menu.add_item(_t("MENU_NEW_BANK"), 3)
				
				if _current_bank and meta.get("res") is SoundData:
					_context_menu.add_separator()
					_context_menu.add_item(_t("MENU_ADD_TO_BANK"), 4)
				
				_context_menu.position = get_screen_position() + get_local_mouse_position()
				_context_menu.popup()

func _on_context_menu_item_selected(id: int):
	match id:
		0: # New Folder
			var dir_base = _context_target_path
			if FileAccess.file_exists(_context_target_path):
				dir_base = _context_target_path.get_base_dir()
				
			var new_dir_name = "New Folder"
			var new_path = dir_base.path_join(new_dir_name)
			var counter = 1
			while DirAccess.dir_exists_absolute(new_path):
				new_path = dir_base.path_join("New Folder %d" % counter)
				counter += 1
			
			var ur = _undo_redo
			ur.create_action("Create Folder")
			ur.add_do_method(DirAccess.make_dir_recursive_absolute.bind(new_path))
			var trash_path = _get_trash_path(new_path) # We'll "delete" it by moving to trash on undo
			ur.add_undo_method(_move_to_trash.bind(new_path, trash_path))
			ur.add_do_method(_refresh_library)
			ur.add_undo_method(_refresh_library)
			ur.commit_action()
		1: # Rename
			_rename_input.text = _context_target_path.get_file()
			_rename_dialog.popup_centered()
		2: # Delete
			var target = _context_target_path
			
			# Collect all resources to be deleted for cleanup
			var resources_to_cleanup = []
			if DirAccess.dir_exists_absolute(target):
				var files = []
				_gather_files_by_extension(target, ["tres", "res"], files)
				for f in files:
					var r = load(f)
					if r is SoundData:
						resources_to_cleanup.append(f)
			else:
				var r = load(target)
				if r is SoundData:
					resources_to_cleanup.append(target)

			# --- UNDO REDO ACTION ---
			var ur = _undo_redo
			ur.create_action("Delete Sound(s) and Cleanup References", UndoRedo.MERGE_DISABLE)
			
			# 1. Cleanup references in SoundBanks (using UndoRedo)
			for res_path in resources_to_cleanup:
				_cleanup_global_references(res_path, ur)
				
			# 2. Physical Deletion via Trash
			# If it's a directory, we move the whole directory. 
			# If it's a file, we move the file and its .uid.
			if DirAccess.dir_exists_absolute(target):
				var trash_dir = _get_trash_path(target)
				ur.add_do_method(_move_to_trash.bind(target, trash_dir))
				ur.add_undo_method(_restore_from_trash.bind(trash_dir, target))
			else:
				var trash_file = _get_trash_path(target)
				ur.add_do_method(_move_to_trash.bind(target, trash_file))
				ur.add_undo_method(_restore_from_trash.bind(trash_file, target))
				
				var uid_file = target + ".uid"
				if FileAccess.file_exists(uid_file):
					var uid_trash = trash_file + ".uid"
					ur.add_do_method(_move_to_trash.bind(uid_file, uid_trash))
					ur.add_undo_method(_restore_from_trash.bind(uid_trash, uid_file))
			
			# Notification and refresh
			ur.add_do_method(EditorInterface.get_resource_filesystem().scan)
			ur.add_do_method(_refresh_library)
			ur.add_do_method(_inspect_resource.bind(null))
			ur.add_do_method(_generate_sounds_helper)
			
			# Undo should also refresh UI
			ur.add_undo_method(EditorInterface.get_resource_filesystem().scan)
			ur.add_undo_method(_refresh_library)
			ur.add_undo_method(_generate_sounds_helper)
			
			ur.commit_action()
		3: # New SoundBank
			var dir_base = _context_target_path
			if FileAccess.file_exists(_context_target_path):
				dir_base = _context_target_path.get_base_dir()
				
			var new_path = dir_base.path_join("NewBank.tres")
			var counter = 1
			while FileAccess.file_exists(new_path):
				new_path = dir_base.path_join("NewBank_%d.tres" % counter)
				counter += 1
			
			var ur = _undo_redo
			ur.create_action("Create SoundBank")
			ur.add_do_method(_create_bank_at_path.bind(new_path))
			var trash_path = _get_trash_path(new_path)
			ur.add_undo_method(_move_to_trash.bind(new_path, trash_path))
			ur.add_do_method(_refresh_library)
			ur.add_undo_method(_refresh_library)
			ur.commit_action()
		4: # Add to Bank
			if _current_bank and FileAccess.file_exists(_context_target_path):
				var res = load(_context_target_path)
				if res is SoundData:
					if not res in _current_bank.sounds:
						var ur = _undo_redo
						ur.create_action("Add to Bank")
						
						var old_sounds = _current_bank.sounds.duplicate()
						var new_sounds = _current_bank.sounds.duplicate()
						new_sounds.append(res)
						
						ur.add_do_property(_current_bank, "sounds", new_sounds)
						ur.add_undo_property(_current_bank, "sounds", old_sounds)
						ur.add_do_method(_save_resource.bind(_current_bank))
						ur.add_undo_method(_save_resource.bind(_current_bank))
						ur.add_do_method(_inspect_bank.bind(_current_bank, true))
						ur.add_undo_method(_inspect_bank.bind(_current_bank, true))
						ur.commit_action()

func _on_rename_confirmed():
	var new_name = _rename_input.text.strip_edges()
	if new_name.is_empty(): return
	
	var old_path = _context_target_path
	var old_ext = old_path.get_extension()
	if old_ext != "" and not new_name.ends_with("." + old_ext):
		new_name += "." + old_ext
		
	var new_path = old_path.get_base_dir().path_join(new_name)
	if old_path == new_path: return
	
	# Capture UIDs
	var old_uid = ""
	var old_uid_int = ResourceLoader.get_resource_uid(old_path)
	if old_uid_int != -1: old_uid = ResourceUID.id_to_text(old_uid_int)
	
	var ur = _undo_redo
	ur.create_action("Rename " + old_path.get_file())
	ur.add_do_method(_perform_rename_full.bind(old_path, new_path, old_uid, old_uid))
	ur.add_undo_method(_perform_rename_full.bind(new_path, old_path, old_uid, old_uid))
	ur.add_do_method(_refresh_library)
	ur.add_undo_method(_refresh_library)
	ur.add_do_method(_refresh_current_inspection)
	ur.add_undo_method(_refresh_current_inspection)
	ur.commit_action()

func _perform_rename_full(from_path: String, to_path: String, old_uid: String, new_uid: String):
	var err = DirAccess.rename_absolute(from_path, to_path)
	if err == OK:
		# Rename .uid file
		if FileAccess.file_exists(from_path + ".uid"):
			DirAccess.rename_absolute(from_path + ".uid", to_path + ".uid")
		
		# Update references in project files
		_update_project_references_text(from_path, to_path, old_uid, new_uid)
		
		# Notify filesystem
		EditorInterface.get_resource_filesystem().update_file(from_path)
		EditorInterface.get_resource_filesystem().update_file(to_path)
		
		# Update memory instance if loaded
		var res = ResourceLoader.load(to_path)
		if res:
			res.take_over_path(to_path)
			
		_generate_sounds_helper()
	else:
		printerr("AudioDashboard: Failed to rename from ", from_path, " to ", to_path, " Error: ", err)

#endregion

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree(): return
	if not event is InputEventKey or not event.pressed: return
	
	var k_event = event as InputEventKey
	var command_or_control = k_event.ctrl_pressed or k_event.meta_pressed
	
	if command_or_control and k_event.keycode == KEY_Z:
		if k_event.shift_pressed:
			if _undo_redo.has_redo():
				print("AudioDashboard: Redoing...")
				_undo_redo.redo()
				get_viewport().set_input_as_handled()
		else:
			if _undo_redo.has_undo():
				print("AudioDashboard: Undoing...")
				_undo_redo.undo()
				get_viewport().set_input_as_handled()
			else:
				print("AudioDashboard: No undo actions in stack.")
	elif command_or_control and k_event.keycode == KEY_Y:
		if _undo_redo.has_redo():
			_undo_redo.redo()
			get_viewport().set_input_as_handled()

func _process(delta):
	# Update Meters
	if is_instance_valid(_mixer_container) and _mixer_container.is_visible_in_tree():
		for bus_idx in _bus_meters:
			var bar = _bus_meters[bus_idx]
			if is_instance_valid(bar):
				var peak = db_to_linear(AudioServer.get_bus_peak_volume_left_db(bus_idx, 0))
				var current = bar.value / 100.0
				var target = peak
				var val = lerp(current, target, 0.5) if target > current else lerp(current, target, 0.1)
				bar.value = val * 100.0
				
				
		# Update Mixer if AudioServer changed externally
		var current_count = AudioServer.bus_count
		var current_names = ""
		for i in current_count:
			current_names += AudioServer.get_bus_name(i) + "|"
		
		if current_count != _last_bus_count or current_names != _last_bus_names:
			_last_bus_count = current_count
			_last_bus_names = current_names
			_update_mixer_ui()

	# Update Live Monitor Timeout
	if is_instance_valid(_live_list_container) and _live_list_container.is_visible_in_tree():
		_monitor_timer += delta
		if _monitor_timer >= 1.5: # Timeout if game stopped
			_monitor_timer = 0.0
			_clear_live_monitor()

var _monitor_expanded_states: Dictionary = {}

func _clear_live_monitor():
	_live_list_container.clear()
	var root = _live_list_container.create_item()
	var empty = _live_list_container.create_item(root)
	empty.set_text(1, _t("MSG_LIVE_WAITING"))

func _format_time(sec: float) -> String:
	return "%.2fs" % sec

func _save_tree_state(item: TreeItem):
	var meta = item.get_metadata(0)
	if meta != null and typeof(meta) == TYPE_STRING:
		_monitor_expanded_states[meta] = item.collapsed
	var child = item.get_first_child()
	while child:
		_save_tree_state(child)
		child = child.get_next()

func _receive_monitor_data(data: Array):
	if typeof(data) == TYPE_ARRAY and data.size() > 0:
		var payload = data[0]
		if typeof(payload) != TYPE_DICTIONARY: return
		
		_monitor_timer = 0.0 # Keep alive
		
		# Save state before clearing
		var root_prev = _live_list_container.get_root()
		if root_prev:
			_save_tree_state(root_prev)
		
		_live_list_container.clear()
		var root = _live_list_container.create_item()
		
		if payload.banks.is_empty() and payload.sounds.is_empty():
			var empty = _live_list_container.create_item(root)
			empty.set_text(1, _t("MSG_LIVE_EMPTY"))
			return
			
		# Render Banks
		var bank_nodes = {}
		for b in payload.banks:
			var bank_item = _live_list_container.create_item(root)
			var node_id = "bnk_" + b
			bank_item.set_metadata(0, node_id)
			bank_item.set_icon(0, load("res://addons/AudioDashboard/icons/bank_icon.png"))


			bank_item.set_text(1, b)
			if _monitor_expanded_states.has(node_id):
				bank_item.collapsed = _monitor_expanded_states[node_id]
			bank_nodes[b] = bank_item
			
		# Render Sounds and Instances
		for s_name in payload.sounds:
			var s_data = payload.sounds[s_name]
			var b_name = s_data.get("bank", "Orphan/Forced")
			
			var parent_node = bank_nodes.get(b_name, root)
			var sound_node = _live_list_container.create_item(parent_node)
			var snd_node_id = "snd_" + b_name + "_" + s_name
			sound_node.set_metadata(0, snd_node_id)
			
			var inst_count = s_data.instances.size()
			sound_node.set_icon(0, load("res://addons/AudioDashboard/icons/audio_icon.png"))


			sound_node.set_text(1, s_name + (" (x%d)" % inst_count))
			
			if _monitor_expanded_states.has(snd_node_id):
				sound_node.collapsed = _monitor_expanded_states[snd_node_id]
			else:
				sound_node.collapsed = (inst_count == 0) # Auto-collapse if no activity
			
			# Render instance details
			for i in range(inst_count):
				var inst = s_data.instances[i]
				var inst_node = _live_list_container.create_item(sound_node)
				var inst_node_id = snd_node_id + "_inst_" + str(i)
				inst_node.set_metadata(0, inst_node_id)
				inst_node.set_icon(0, get_theme_icon("Play", "EditorIcons")) # Using Play or Sub icon
				inst_node.set_text(1, ">>") # Indent to signify instance
				inst_node.set_text(2, inst.get("bus", "Master"))
				
				var p = inst.get("progress", 0.0)
				var l = inst.get("length", 0.0)
				if l <= 0.0:
					inst_node.set_text(3, _format_time(p) + " / --:--")
				else:
					inst_node.set_text(3, _format_time(p) + " / " + _format_time(l))
					
				var db = inst.get("db", 0.0)
				inst_node.set_text(4, "%.1f dB" % db)

#region Inspector Logic
func _change_resource_property(resource: Resource, property_name: String, new_value, action_name: String = ""):
	if not plugin:
		resource.set(property_name, new_value)
		_save_resource(resource)
		return
		
	var undo_redo = _undo_redo
	undo_redo.create_action("Change %s: %s" % [resource.resource_path.get_file(), action_name])
	undo_redo.add_do_property(resource, property_name, new_value)
	undo_redo.add_undo_property(resource, property_name, resource.get(property_name))
	undo_redo.add_do_method(_save_resource.bind(resource))
	undo_redo.add_undo_method(_save_resource.bind(resource))
	
	# Visual Refresh
	if _current_selection == resource:
		undo_redo.add_do_method(_inspect_resource.bind(resource, true))
		undo_redo.add_undo_method(_inspect_resource.bind(resource, true))
	elif _current_bank == resource:
		undo_redo.add_do_method(_inspect_bank.bind(resource, true))
		undo_redo.add_undo_method(_inspect_bank.bind(resource, true))
		
	undo_redo.commit_action()

func _add_property_slider(parent: Control, label_text: String, res: Resource, property_name: String, min_v, max_v, step, tooltip: String = ""):
	var lbl = Label.new()
	lbl.text = label_text
	lbl.tooltip_text = tooltip
	parent.add_child(lbl)
	
	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var s = HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = res.get(property_name)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var spin = SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = step
	spin.value = res.get(property_name)
	spin.custom_minimum_size.x = 70
	
	# Sync Logic
	s.value_changed.connect(func(v):
		spin.value = v
		_change_resource_property(res, property_name, v, label_text)
	)
	
	spin.value_changed.connect(func(v):
		s.value = v
		_change_resource_property(res, property_name, v, label_text)
	)
	
	hbox.add_child(s)
	hbox.add_child(spin)
	parent.add_child(hbox)

func _add_inspector_header(title: String, subtitle: String = ""):
	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var header = Label.new()
	header.text = title
	header.add_theme_font_size_override("font_size", 20)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.clip_text = true
	hbox.add_child(header)
	
	var pin_btn = Button.new()
	pin_btn.toggle_mode = true
	pin_btn.button_pressed = _inspector_locked
	pin_btn.icon = get_theme_icon("Pin", "EditorIcons")
	pin_btn.tooltip_text = _t("TOOLTIP_PIN")
	pin_btn.flat = true
	
	pin_btn.toggled.connect(func(pressed):
		_inspector_locked = pressed
	)
	hbox.add_child(pin_btn)
	
	_inspector_content.add_child(hbox)
	
	if not subtitle.is_empty():
		var type_lbl = Label.new()
		type_lbl.text = subtitle
		type_lbl.modulate = Color(1, 1, 1, 0.5)
		_inspector_content.add_child(type_lbl)
	
	_add_separator()

func _clear_inspector(force: bool = false):
	if _inspector_locked and not force: return
	
	for c in _inspector_content.get_children():
		c.queue_free()
	_current_selection = null
	_current_bank = null
	if force:
		_inspector_locked = false



func _inspect_resource(res: SoundData, force: bool = false):
	if _inspector_locked and not force: return
	
	_clear_inspector(true)

	_current_selection = res
	_current_bank = null
	if not res: return
	
	# Auto-repair legacy / broken resources
	if res.clips == null:
		res.clips = []
	
	# Header
	_add_inspector_header(res.resource_path.get_file().get_basename(), _t("SEC_SOUND_DATA"))


	
	# --- Properties ---
	var grid = GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspector_content.add_child(grid)

	# Volume
	_add_property_slider(grid, _t("PROP_VOLUME"), res, "volume_db", -40, 20, 0.1, _t("TOOLTIP_VOL"))
	# Pitch
	_add_property_slider(grid, _t("PROP_PITCH"), res, "pitch_scale", 0.01, 4.0, 0.01, _t("TOOLTIP_PITCH"))
	# Pitch Random
	_add_property_slider(grid, _t("PROP_PITCH_RAND"), res, "pitch_randomness", 0.0, 1.0, 0.01, _t("TOOLTIP_PITCH_RAND"))
	
	# Bus Selector
	var bus_lbl = Label.new()
	bus_lbl.text = _t("PROP_BUS")
	bus_lbl.tooltip_text = _t("TOOLTIP_BUS")
	grid.add_child(bus_lbl)
	
	var bus_opt = OptionButton.new()
	var bus_found = false
	for i in AudioServer.bus_count:
		var b_name = AudioServer.get_bus_name(i)
		bus_opt.add_item(b_name)
		if b_name == res.bus: 
			bus_opt.selected = i
			bus_found = true
			
	if not bus_found and not res.bus.is_empty():
		bus_opt.add_item(res.bus + " " + _t("LBL_MISSING_SUFFIX"))
		bus_opt.selected = bus_opt.item_count - 1
		bus_opt.set_item_custom_fg_color(bus_opt.selected, Color.RED)
		
		var warn = Label.new()
		warn.text = _t("LBL_BUS_MISSING_WARN")
		warn.add_theme_color_override("font_color", Color.YELLOW)
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_inspector_content.add_child(warn) # Add below the grid? Or inside?
		# Better add to content directly after grid
		
	bus_opt.item_selected.connect(func(idx):
		var new_bus = bus_opt.get_item_text(idx)
		if _t("LBL_MISSING_SUFFIX") in new_bus:
			new_bus = new_bus.replace(" " + _t("LBL_MISSING_SUFFIX"), "")
		_change_resource_property(res, "bus", new_bus, _t("PROP_BUS"))
		_inspect_resource(res, true) # Refresh to update warnings
	)
	grid.add_child(bus_opt)
	
	_add_separator()
	
	# --- 3D Settings ---
	var threed_lbl = Label.new()
	threed_lbl.text = _t("SEC_3D")
	_inspector_content.add_child(threed_lbl)

	var grid_3d = GridContainer.new()
	grid_3d.columns = 2
	grid_3d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspector_content.add_child(grid_3d)

	# 3D Settings
	_add_property_slider(grid_3d, _t("PROP_DISTANCE"), res, "max_distance", 0, 2000, 1, _t("TOOLTIP_DISTANCE"))
	_add_property_slider(grid_3d, _t("PROP_PANNING"), res, "panning_strength", 0, 3, 0.1, _t("TOOLTIP_PANNING"))
	
	var atten_lbl = Label.new()
	atten_lbl.text = _t("PROP_ATTENUATION")
	atten_lbl.tooltip_text = _t("TOOLTIP_ATTENUATION")
	grid_3d.add_child(atten_lbl)
	
	var atten_opt = OptionButton.new()
	atten_opt.add_item(_t("ENUM_ATT_INVERSE"), 0)
	atten_opt.add_item(_t("ENUM_ATT_INVERSE_SQUARE"), 1)
	atten_opt.add_item(_t("ENUM_ATT_LOG"), 2)
	atten_opt.add_item(_t("ENUM_ATT_DISABLED"), 3)
	atten_opt.selected = res.attenuation_model
	atten_opt.item_selected.connect(func(idx):
		_change_resource_property(res, "attenuation_model", idx, _t("PROP_ATTENUATION"))
	)
	grid_3d.add_child(atten_opt)
	
	_add_separator()
	
	# --- Shuffle & Playback ---
	var shuffle_lbl = Label.new()
	shuffle_lbl.text = _t("SEC_PLAYBACK")
	_inspector_content.add_child(shuffle_lbl)

	var grid_mode = GridContainer.new()
	grid_mode.columns = 2
	grid_mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspector_content.add_child(grid_mode)
	
	var mode_lbl = Label.new()
	mode_lbl.text = _t("PROP_MODE") + ":"
	mode_lbl.tooltip_text = _t("TOOLTIP_MODE")
	grid_mode.add_child(mode_lbl)

	var mode_opt = OptionButton.new()
	mode_opt.add_item(_t("ENUM_RANDOM"), 0)
	mode_opt.add_item(_t("ENUM_SEQUENTIAL"), 1)
	mode_opt.add_item(_t("ENUM_NO_REPEAT"), 2)
	mode_opt.selected = res.shuffle_mode 
	mode_opt.item_selected.connect(func(idx):
		_change_resource_property(res, "shuffle_mode", idx, _t("PROP_MODE")) 
	)
	grid_mode.add_child(mode_opt)
	
	var chk_loop = CheckBox.new()
	chk_loop.text = _t("PROP_LOOP")
	chk_loop.tooltip_text = _t("TOOLTIP_LOOP")
	chk_loop.button_pressed = res.loop
	chk_loop.toggled.connect(func(v):
		_change_resource_property(res, "loop", v, _t("PROP_LOOP"))
	)
	grid_mode.add_child(chk_loop)
	
	_add_property_slider(grid_mode, _t("PROP_REPEAT"), res, "repeat_prevention", 1, 10, 1, _t("TOOLTIP_REPEAT"))

	# Management
	_add_separator()
	var mgmt_lbl = Label.new()
	mgmt_lbl.text = _t("SEC_MGMT")
	_inspector_content.add_child(mgmt_lbl)
	
	var grid_mgmt = GridContainer.new()
	grid_mgmt.columns = 2
	grid_mgmt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspector_content.add_child(grid_mgmt)
	
	_add_property_slider(grid_mgmt, _t("PROP_POLYPHONY"), res, "max_polyphony", 1, 64, 1, _t("TOOLTIP_POLYPHONY"))
	
	var tag_lbl = Label.new()
	tag_lbl.text = _t("PROP_TAG")
	tag_lbl.tooltip_text = _t("TOOLTIP_TAG")
	grid_mgmt.add_child(tag_lbl)
	
	var tag_input = LineEdit.new()
	tag_input.text = res.group_tag
	tag_input.clear_button_enabled = true
	var apply_tag = func(new_text: String):
		if new_text != res.group_tag:
			_change_resource_property(res, "group_tag", new_text, _t("PROP_TAG"))
			
	tag_input.text_submitted.connect(apply_tag)
	tag_input.focus_exited.connect(func(): apply_tag.call(tag_input.text))
	grid_mgmt.add_child(tag_input)

	# --- Lifetime ---
	var life_lbl = Label.new()
	life_lbl.text = _t("PROP_LIFETIME")
	life_lbl.tooltip_text = _t("TOOLTIP_LIFETIME")
	grid_mgmt.add_child(life_lbl)
	
	var life_opt = OptionButton.new()
	life_opt.add_item(_t("ENUM_L_GLOBAL"), 0)
	life_opt.add_item(_t("ENUM_L_SCENE"), 1)
	life_opt.add_item(_t("ENUM_L_BANK"), 2)
	life_opt.selected = res.lifetime
	life_opt.item_selected.connect(func(idx):
		_change_resource_property(res, "lifetime", idx, _t("PROP_LIFETIME"))
	)
	grid_mgmt.add_child(life_opt)
	
	var unique_chk = CheckBox.new()
	unique_chk.text = _t("PROP_UNIQUE")
	unique_chk.tooltip_text = _t("TOOLTIP_UNIQUE")
	unique_chk.button_pressed = res.is_unique
	unique_chk.toggled.connect(func(v):
		_change_resource_property(res, "is_unique", v, _t("PROP_UNIQUE"))
		_inspect_resource(res, true) # Refresh to show/hide restart toggle
	)
	grid_mgmt.add_child(unique_chk)
	
	if res.is_unique:
		var restart_chk = CheckBox.new()
		restart_chk.text = _t("PROP_RESTART")
		restart_chk.tooltip_text = _t("TOOLTIP_RESTART")
		restart_chk.button_pressed = res.restart_if_playing
		restart_chk.toggled.connect(func(v):
			_change_resource_property(res, "restart_if_playing", v, _t("PROP_RESTART"))
		)
		grid_mgmt.add_child(restart_chk)
	else:
		grid_mgmt.add_child(Control.new()) # Spacer

	
	# --- Clips Manager ---
	var clips_header = HBoxContainer.new()
	_inspector_content.add_child(clips_header)
	
	var clips_lbl = Label.new()
	clips_lbl.text = _t("SEC_CLIPS") % res.clips.size()
	clips_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clips_header.add_child(clips_lbl)
	
	var clip_search = LineEdit.new()
	clip_search.placeholder_text = _t("FILTER_CLIPS")
	clip_search.custom_minimum_size.x = 150
	clip_search.right_icon = get_theme_icon("Search", "EditorIcons")
	clips_header.add_child(clip_search)
	
	# Drop Zone for Clips
	var drop_zone = PanelContainer.new()
	drop_zone.custom_minimum_size.y = 60
	var drop_lbl = Label.new()
	drop_lbl.text = _t("LBL_DROP_ZONE")
	drop_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	drop_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	drop_lbl.modulate = Color(1, 1, 1, 0.5)
	drop_zone.add_child(drop_lbl)
	_inspector_content.add_child(drop_zone)
	
	var clip_list_vbox = VBoxContainer.new()
	_inspector_content.add_child(clip_list_vbox)
	
	clip_search.text_changed.connect(func(txt):
		var query = txt.to_lower()
		for row in clip_list_vbox.get_children():
			if row is HBoxContainer and row.get_child_count() > 1:
				var lbl = row.get_child(1)
				if lbl is Label:
					row.visible = query.is_empty() or (query in lbl.text.to_lower())
	)

	# Clip List
	for i in range(res.clips.size()):
		var item = res.clips[i]
		var row = HBoxContainer.new()
		
		var name_lbl = Label.new()
		var clip_res: AudioClip = null
		
		# Polymorphic handling
		if item is AudioClip:
			clip_res = item
			if item.stream:
				name_lbl.text = item.stream.resource_path.get_file()
			else:
				name_lbl.text = _t("LBL_NULL_STREAM")
		elif item is AudioStream:
			name_lbl.text = item.resource_path.get_file()
		else:
			name_lbl.text = _t("LBL_EMPTY_UNKNOWN")
			
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.clip_text = true
		
		# Migration / Edit Button
		var edit_btn = Button.new()
		if clip_res:
			edit_btn.text = _t("BTN_EDIT")
			edit_btn.pressed.connect(func(): _open_clip_editor(res, i))
		else:
			edit_btn.text = _t("BTN_CONVERT")
			edit_btn.pressed.connect(func(): _convert_to_audioclip(res, i))
		
		var del_btn = Button.new()
		del_btn.text = "X"
		del_btn.modulate = Color.RED
		del_btn.pressed.connect(func(): _request_delete_clip(res, i))
		
		var play_clip_btn = Button.new()
		play_clip_btn.text = "▶"
		if clip_res:
			play_clip_btn.pressed.connect(func(): _play_stream_only(clip_res.stream, res, clip_res, play_clip_btn))
		elif item is AudioStream:
			play_clip_btn.pressed.connect(func(): _play_stream_only(item, res, null, play_clip_btn))
		
		row.add_child(play_clip_btn)
		row.add_child(name_lbl)
		row.add_child(edit_btn)
		row.add_child(del_btn)
		clip_list_vbox.add_child(row)
		
	_add_separator()
	
	var test_btn = Button.new()
	test_btn.text = _t("BTN_TEST_PLAY")
	test_btn.custom_minimum_size.y = 40
	test_btn.pressed.connect(func(): _play_preview(res, test_btn))
	_inspector_content.add_child(test_btn)

func _inspect_multi_selection(resources: Array, force: bool = false):
	if _inspector_locked and not force: return
	_clear_inspector(true)
	
	var header = Label.new()
	var raw_label = _t("LBL_MULTI_SELECT")
	if "%d" in raw_label:
		header.text = raw_label % resources.size()
	else:
		header.text = raw_label + " (" + str(resources.size()) + ")"
	
	header.add_theme_font_size_override("font_size", 20)
	_inspector_content.add_child(header)
	
	_add_separator()
	
	var grid = GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspector_content.add_child(grid)
	
	# Only show properties that make sense for bulk editing
	_add_multi_property_slider(grid, _t("PROP_VOLUME"), resources, "volume_db", -40, 20, 0.1)
	_add_multi_property_slider(grid, _t("PROP_PITCH"), resources, "pitch_scale", 0.01, 4.0, 0.01)
	
	# Bus Selector
	var bus_lbl = Label.new()
	bus_lbl.text = _t("PROP_BUS")
	grid.add_child(bus_lbl)
	
	var bus_opt = OptionButton.new()
	var all_buses_names = []
	for i in AudioServer.bus_count:
		var b_name = AudioServer.get_bus_name(i)
		bus_opt.add_item(b_name)
		all_buses_names.append(b_name)
	
	# If current selection varies or uses a missing bus, handle it
	var first_bus = resources[0].bus
	if not first_bus in all_buses_names and not first_bus.is_empty():
		bus_opt.add_item(first_bus + " " + _t("LBL_MISSING_SUFFIX"))
		bus_opt.set_item_custom_fg_color(bus_opt.item_count - 1, Color.RED)
	
	bus_opt.item_selected.connect(func(idx):
		var new_bus = bus_opt.get_item_text(idx)
		if _t("LBL_MISSING_SUFFIX") in new_bus:
			new_bus = new_bus.replace(" " + _t("LBL_MISSING_SUFFIX"), "")
			
		var ur = _undo_redo
		ur.create_action("Change Bus (Multi)")
		for r in resources:
			ur.add_do_property(r, "bus", new_bus)
			ur.add_undo_property(r, "bus", r.bus)
			ur.add_do_method(_save_resource.bind(r))
			ur.add_undo_method(_save_resource.bind(r))
		
		ur.add_do_method(_inspect_multi_selection.bind(resources, true))
		ur.add_undo_method(_inspect_multi_selection.bind(resources, true))
		ur.commit_action()
	)
	grid.add_child(bus_opt)
	
	# Tag Edit
	var tag_lbl = Label.new()
	tag_lbl.text = _t("PROP_TAG")
	grid.add_child(tag_lbl)
	
	var tag_input = LineEdit.new()
	tag_input.placeholder_text = _t("PLACEHOLDER_BATCH_TAG")
	tag_input.clear_button_enabled = true
	
	var apply_tags = func(new_text: String):
		var modified = false
		for r in resources: if r.group_tag != new_text: modified = true
		if not modified: return
		
		var ur = _undo_redo
		ur.create_action("Change Tag (Multi)")
		for r in resources:
			ur.add_do_property(r, "group_tag", new_text)
			ur.add_undo_property(r, "group_tag", r.group_tag)
			ur.add_do_method(_save_resource.bind(r))
			ur.add_undo_method(_save_resource.bind(r))
		
		ur.add_do_method(_inspect_multi_selection.bind(resources, true))
		ur.add_undo_method(_inspect_multi_selection.bind(resources, true))
		ur.commit_action()
	
	tag_input.text_submitted.connect(apply_tags)
	tag_input.focus_exited.connect(func(): apply_tags.call(tag_input.text))

	grid.add_child(tag_input)

func _inspect_bank(bank: SoundBank, force: bool = false):
	if _inspector_locked and not force: return
	
	_clear_inspector(true)
	_current_bank = bank

	
	# Header
	_add_inspector_header(bank.resource_path.get_file().get_basename(), _t("SEC_BANK"))


	
	# Open in native Inspector button
	var open_btn = Button.new()
	open_btn.text = _t("BTN_BANK_OPEN_RES")
	open_btn.pressed.connect(func(): EditorInterface.edit_resource(bank))
	_inspector_content.add_child(open_btn)
	
	_add_separator()
	
	# Sounds list header
	var sounds_lbl = Label.new()
	var raw_label = _t("LBL_BANK_SOUNDS")
	if "%d" in raw_label:
		sounds_lbl.text = raw_label % bank.sounds.size()
	else:
		sounds_lbl.text = raw_label + " (" + str(bank.sounds.size()) + ")"
	sounds_lbl.add_theme_font_size_override("font_size", 14)
	_inspector_content.add_child(sounds_lbl)
	
	# Drop zone for adding sounds
	var drop_zone = PanelContainer.new()
	drop_zone.custom_minimum_size.y = 50
	var drop_lbl = Label.new()
	drop_lbl.text = _t("LBL_BANK_DROP")
	drop_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	drop_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	drop_lbl.modulate = Color(1, 1, 1, 0.5)
	drop_zone.add_child(drop_lbl)
	_inspector_content.add_child(drop_zone)
	
	if bank.sounds.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = _t("LBL_BANK_EMPTY")
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_lbl.modulate = Color(1, 1, 1, 0.4)
		_inspector_content.add_child(empty_lbl)
	else:
		var sound_list = VBoxContainer.new()
		_inspector_content.add_child(sound_list)
		
		for i in range(bank.sounds.size()):
			var s = bank.sounds[i]
			var row = HBoxContainer.new()
			
			var icon_tex = load("res://addons/AudioDashboard/icons/audio_icon.png")


			var icon_rect = TextureRect.new()
			icon_rect.texture = icon_tex
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon_rect.custom_minimum_size = Vector2(16, 16)
			row.add_child(icon_rect)
			
			var name_lbl = Label.new()
			if s:
				name_lbl.text = s.resource_path.get_file().get_basename()
				name_lbl.tooltip_text = s.resource_path
			else:
				name_lbl.text = _t("LBL_EMPTY_UNKNOWN")
			name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name_lbl.clip_text = true
			row.add_child(name_lbl)
			
			# Select sound button
			if s:
				var sel_btn = Button.new()
				sel_btn.text = "→"
				sel_btn.tooltip_text = _t("TOOLTIP_INSPECT_DATA")
				sel_btn.pressed.connect(func(): 
					_inspect_resource(s)
					_select_in_tree(s.resource_path)
				)
				row.add_child(sel_btn)
			
			# Remove from bank button
			var del_btn = Button.new()
			del_btn.text = "X"
			del_btn.modulate = Color.RED
			var idx = i
			del_btn.pressed.connect(func():
				var ur = _undo_redo
				ur.create_action("Remove Sound from Bank")
				
				var old_sounds = bank.sounds.duplicate()
				var new_sounds = bank.sounds.duplicate()
				new_sounds.remove_at(idx)
				
				ur.add_do_property(bank, "sounds", new_sounds)
				ur.add_undo_property(bank, "sounds", old_sounds)
				ur.add_do_method(_save_resource.bind(bank))
				ur.add_undo_method(_save_resource.bind(bank))
				ur.add_do_method(_inspect_bank.bind(bank, true))
				ur.add_undo_method(_inspect_bank.bind(bank, true))
				
				ur.commit_action()
			)
			row.add_child(del_btn)
			
			sound_list.add_child(row)

func _add_multi_property_slider(parent: Control, label_text: String, resources: Array, property_name: String, min_v, max_v, step):
	var lbl = Label.new()
	lbl.text = label_text
	parent.add_child(lbl)
	
	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var s = HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = resources[0].get(property_name)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	s.value_changed.connect(func(v):
		var ur = _undo_redo
		ur.create_action("Change %s (Multi)" % label_text)
		for res in resources:
			ur.add_do_property(res, property_name, v)
			ur.add_undo_property(res, property_name, res.get(property_name))
			ur.add_do_method(_save_resource.bind(res))
			ur.add_undo_method(_save_resource.bind(res))
			
		ur.add_do_method(_inspect_multi_selection.bind(resources, true))
		ur.add_undo_method(_inspect_multi_selection.bind(resources, true))
		ur.commit_action()
	)
	
	hbox.add_child(s)
	parent.add_child(hbox)

func _add_bus_selector(res: SoundData, parent: Control = null):
	var target = parent if parent else _inspector_content
	var hbox = HBoxContainer.new()
	hbox.tooltip_text = _t("TOOLTIP_BUS")
	var lbl = Label.new()
	lbl.text = _t("PROP_BUS")
	var opt = OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var buses = []
	var bus_found = false
	for i in range(AudioServer.bus_count):
		var b_name = AudioServer.get_bus_name(i)
		buses.append(b_name)
		opt.add_item(b_name)
		if res.bus == b_name:
			opt.selected = opt.item_count - 1
			bus_found = true
			
	if not bus_found and not res.bus.is_empty():
		opt.add_item(res.bus + " " + _t("LBL_MISSING_SUFFIX"))
		opt.selected = opt.item_count - 1
		opt.set_item_custom_fg_color(opt.selected, Color.RED)
		
		var warn = Label.new()
		warn.text = _t("LBL_BUS_MISSING_WARN")
		warn.add_theme_color_override("font_color", Color.YELLOW)
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		target.add_child(warn)
			
	opt.item_selected.connect(func(idx):
		var text = opt.get_item_text(idx)
		if _t("LBL_MISSING_SUFFIX") in text:
			text = text.replace(" " + _t("LBL_MISSING_SUFFIX"), "")
		res.bus = text
		_save_resource(res)
		_inspect_resource(res, true) # Refresh to update warning
	)
	
	hbox.add_child(lbl)
	hbox.add_child(opt)
	target.add_child(hbox)

func _add_separator():
	var sep = HSeparator.new()
	sep.custom_minimum_size.y = 20
	_inspector_content.add_child(sep)

func _save_resource(res: Resource):
	if not res: return
	
	# Persistent Safety: Avoid saving SoundBanks that have null/broken entries to prevent emptying them
	# Seguridad de persistencia: Evita guardar SoundBanks que tengan entradas nulas/rotas para evitar que se vacíen
	if res is SoundBank:
		for s in res.sounds:
			if s == null:
				printerr("AudioDashboard: [ERROR] Attempted to save a SoundBank with null references. Save cancelled to prevent data loss. Please fix the references first.")
				return
				
	ResourceSaver.save(res, res.resource_path)
	EditorInterface.get_resource_filesystem().update_file(res.resource_path)

func _add_line_edit(label: String, val: String, callback: Callable, tooltip: String = ""):
	var hbox = HBoxContainer.new()
	if tooltip != "": hbox.tooltip_text = tooltip
	
	var lbl = Label.new()
	lbl.text = label
	lbl.custom_minimum_size.x = 100
	
	var edit = LineEdit.new()
	edit.text = val
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_submitted.connect(func(new_text):
		callback.call(new_text)
		_save_resource(_current_selection)
	)
	
	hbox.add_child(lbl)
	hbox.add_child(edit)
	_inspector_content.add_child(hbox)
#endregion

#region Preview & Mixer
func _update_mixer_ui():
	for c in _mixer_container.get_children(): c.queue_free()
	
	# --- Header / Toolbar ---
	var header = HBoxContainer.new()
	var title = Label.new()
	title.text = _t("MIXER_TITLE")
	title.add_theme_font_size_override("font_size", 14)
	
	var add_btn = Button.new()
	add_btn.text = _t("BTN_ADD_BUS")
	add_btn.pressed.connect(_add_new_bus)
	
	header.add_child(title)
	header.add_child(VSeparator.new())
	header.add_child(add_btn)
	
	# Mixer layout configuration
	pass


	# Alternative: The "Add Bus" button is a special strip at the end.
	
	# --- Strips ---
	for i in range(AudioServer.bus_count):
		var bus_name = AudioServer.get_bus_name(i)
		
		var strip = VBoxContainer.new()
		strip.custom_minimum_size.x = 80
		
		# Name (Editable via double click or menu? Let's use Button)
		var name_btn = Button.new()
		name_btn.text = bus_name
		name_btn.clip_text = true
		name_btn.tooltip_text = bus_name
		name_btn.pressed.connect(func(): _initiate_bus_rename(i))
		strip.add_child(name_btn)
		
		# Meter & Slider Container
		var slider_hbox = HBoxContainer.new()
		slider_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		
		# VU Meter
		var vu_bar = ProgressBar.new()
		vu_bar.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
		vu_bar.show_percentage = false
		vu_bar.custom_minimum_size.x = 8
		vu_bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vu_bar.value = 0
		_bus_meters[i] = vu_bar
		slider_hbox.add_child(vu_bar)
		
		# Volume Slider
		var vol_slider = VSlider.new()
		vol_slider.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vol_slider.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vol_slider.min_value = -80
		vol_slider.max_value = 6
		vol_slider.step = 0.1
		vol_slider.value = AudioServer.get_bus_volume_db(i)
		slider_hbox.add_child(vol_slider)
		
		strip.add_child(slider_hbox)
		
		# SpinBox for precise entry
		var vol_spin = SpinBox.new()
		vol_spin.min_value = -80
		vol_spin.max_value = 6
		vol_spin.step = 0.1
		vol_spin.value = AudioServer.get_bus_volume_db(i)
		vol_spin.custom_minimum_size.x = 70
		vol_spin.alignment = HORIZONTAL_ALIGNMENT_CENTER
		
		# Sync logic
		vol_slider.value_changed.connect(func(v):
			AudioServer.set_bus_volume_db(i, v)
			vol_spin.value = v
		)
		vol_spin.value_changed.connect(func(v):
			AudioServer.set_bus_volume_db(i, v)
			vol_slider.value = v
		)
		
		strip.add_child(vol_spin)
		
		# Mute/Solo (Optional, keep simple for now)
		
		# Delete (If not Master)
		if i > 0:
			var del_btn = Button.new()
			del_btn.text = "x"
			del_btn.modulate = Color(1, 0.4, 0.4)
			del_btn.pressed.connect(func(): _delete_bus(i))
			strip.add_child(del_btn)
		else:
			# Spacer for alignment
			var s = Control.new()
			s.custom_minimum_size.y = 31 # Approx button height
			strip.add_child(s)
			
		_mixer_container.add_child(strip)
		_mixer_container.add_child(VSeparator.new())

	# "Add Bus" Strip
	var add_strip = VBoxContainer.new()
	add_strip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_strip.alignment = BoxContainer.ALIGNMENT_CENTER
	var big_add_btn = Button.new()
	big_add_btn.text = "+"
	big_add_btn.custom_minimum_size = Vector2(40, 100)
	big_add_btn.pressed.connect(_add_new_bus)
	add_strip.add_child(big_add_btn)
	_mixer_container.add_child(add_strip)

func _add_new_bus():
	var ur = _undo_redo
	ur.create_action("Add Audio Bus")
	ur.add_do_method(_perform_add_bus.bind(_t("LBL_NEW_BUS")))
	ur.add_undo_method(_perform_delete_bus.bind(AudioServer.bus_count)) # The new one will be at the end
	ur.add_do_method(_update_mixer_ui)
	ur.add_undo_method(_update_mixer_ui)
	ur.commit_action()

func _perform_add_bus(bus_name: String):
	var idx = AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	_save_bus_layout()

func _perform_delete_bus(idx: int):
	if idx <= 0: return
	AudioServer.remove_bus(idx)
	_save_bus_layout()

func _delete_bus(idx: int):
	if idx <= 0: return # Safety (Master cannot be deleted)
	
	var ur = _undo_redo
	ur.create_action("Delete Audio Bus")
	# We need to save the bus state (volume, effects, etc.) if we want precise undo.
	# For now, let's at least undo the name and existence.
	# More robust: use a temporary bus layout? 
	# Simplified for now:
	var old_name = AudioServer.get_bus_name(idx)
	ur.add_do_method(_perform_delete_bus.bind(idx))
	ur.add_undo_method(_perform_add_bus_at.bind(idx, old_name))
	ur.add_do_method(_update_mixer_ui)
	ur.add_undo_method(_update_mixer_ui)
	ur.commit_action()

func _perform_add_bus_at(idx: int, bus_name: String):
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	_save_bus_layout()

func _perform_rename_bus(idx: int, new_name: String):
	AudioServer.set_bus_name(idx, new_name)
	_save_bus_layout()

func _save_bus_layout():
	var layout = AudioServer.generate_bus_layout()
	var path = ProjectSettings.get_setting("audio/bus_layout")
	if path == "":
		path = "res://default_bus_layout.tres"
	
	var err = ResourceSaver.save(layout, path)
	if err == OK:
		print("AudioDashboard: Saved audio bus layout to ", path)
		# Notify editor of file change
		EditorInterface.get_resource_filesystem().update_file(path)
	else:
		printerr("AudioDashboard: Failed to save audio bus layout. Error: ", err)

func _initiate_bus_rename(idx: int):
	# Create a dedicated rename dialog for the bus

	var dialog = AcceptDialog.new()
	dialog.title = _t("LBL_RENAME_BUS") + ": " + AudioServer.get_bus_name(idx)
	var vbox = VBoxContainer.new()
	var input = LineEdit.new()
	input.text = AudioServer.get_bus_name(idx)
	vbox.add_child(input)
	dialog.add_child(vbox)
	dialog.confirmed.connect(func():
		var new_name = input.text.strip_edges()
		if not new_name.is_empty() and new_name != AudioServer.get_bus_name(idx):
			var ur = _undo_redo
			ur.create_action("Rename Audio Bus")
			ur.add_do_method(_perform_rename_bus.bind(idx, new_name))
			ur.add_undo_method(_perform_rename_bus.bind(idx, AudioServer.get_bus_name(idx)))
			ur.add_do_method(_update_mixer_ui)
			ur.add_undo_method(_update_mixer_ui)
			ur.commit_action()
		dialog.queue_free()
	)
	add_child(dialog)
	dialog.popup_centered()

func _play_preview(res: SoundData, btn: Button = null):
	# Check if we are already playing this resource (or just if the button is in "Stop" mode)
	if btn and btn == _current_play_button and _preview_player.playing:
		_stop_preview()
		return
	
	# Stop any previous
	_stop_preview()
	
	if res.clips.is_empty(): return
	
	var index = 0
	if res.clips.size() > 1:
		# Initialize history for this resource if missing
		if not _preview_history.has(res):
			_preview_history[res] = {"last_indices": [], "seq_index": 0}
			
		var history = _preview_history[res]
		
		match res.shuffle_mode:
			SoundData.ShuffleMode.SEQUENTIAL:
				index = history.seq_index % res.clips.size()
				history.seq_index += 1
				
			SoundData.ShuffleMode.RANDOM_NO_REPEAT:
				var available_indices = []
				var prevent_count = clampi(res.repeat_prevention, 1, res.clips.size() - 1)
				
				for i in range(res.clips.size()):
					if not i in history.last_indices:
						available_indices.append(i)
				
				if available_indices.is_empty():
					var last = history.last_indices.back() if not history.last_indices.is_empty() else -1
					for i in range(res.clips.size()):
						if i != last or res.clips.size() == 1:
							available_indices.append(i)
				
				index = available_indices.pick_random()
				
				# Update history
				history.last_indices.append(index)
				while history.last_indices.size() > prevent_count:
					history.last_indices.pop_front()
					
			SoundData.ShuffleMode.RANDOM:
				index = randi() % res.clips.size()
	
	var clip = res.clips[index]
	_play_stream_only(clip, res, null, btn)

func _stop_preview():
	_preview_player.stop()
	_preview_player.stream = null # Optimize memory
	
	if _current_play_button:
		# Restore button state
		if _current_play_button.has_meta("original_text"):
			_current_play_button.text = _current_play_button.get_meta("original_text")
		if _current_play_button.has_meta("original_icon"):
			_current_play_button.icon = _current_play_button.get_meta("original_icon")
		_current_play_button = null

func _on_preview_finished():
	_stop_preview()

func _play_stream_only(any_clip: Resource, res: SoundData, clips_model: AudioClip = null, btn: Button = null):
	if not any_clip: return
	
	var stream: AudioStream = any_clip as AudioStream
	var model: AudioClip = clips_model
	
	if any_clip is AudioClip:
		stream = any_clip.stream
		model = any_clip
		
	if not stream: return
	
	# If same button is clicked while playing, stop it.
	if btn and btn == _current_play_button and _preview_player.playing:
		_stop_preview()
		return
		
	# Stop previous
	_stop_preview()
	
	if not _preview_player.finished.is_connected(_on_preview_finished):
		_preview_player.finished.connect(_on_preview_finished)
	
	_preview_player.stream = stream
	_preview_player.volume_db = res.volume_db
	_preview_player.pitch_scale = res.get_pitch()
	_preview_player.bus = res.bus
	
	if model:
		_preview_player.volume_db += model.volume_offset
		
	_preview_player.play()

	
	# Update Button State
	if btn:
		_current_play_button = btn
		btn.set_meta("original_text", btn.text)
		btn.set_meta("original_icon", btn.icon)
		
		# If it's the main Test Play button (text based)
		if btn.text.begins_with("TEST") or btn.text == _t("BTN_TEST_PLAY"):
			btn.text = _t("BTN_STOP_PREVIEW")
		else:
			# Likely a clip button (icon/small text)
			btn.text = "■"
#endregion

#region Drag & Drop
func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if typeof(data) == TYPE_DICTIONARY and data.has("files"):
		return true
	return false

func _drop_data(at_position: Vector2, data: Variant) -> void:
	if typeof(data) == TYPE_DICTIONARY and data.has("files"):
		var files = data["files"]
		
		# Check where we dropped
		# If over Inspector (and selection active) -> Add to selection
		# We can check if `at_position` is within inspector bounds, or if `_current_selection` is valid and we are NOT over the tree.
		
		# Better: Check if over Tree
		var tree_rect = _tree_view.get_global_rect()
		# Convert global to local for rect check? No, get_global_rect returns global. 
		# `at_position` is local to Dashboard.
		var global_pos = get_global_position() + at_position
		
		if _tree_view.get_global_rect().has_point(global_pos):
			# Dropped on Tree
			# Find item
			# Tree's local pos calculation:
			var tree_local = global_pos - _tree_view.get_global_position()
			var item = _tree_view.get_item_at_position(tree_local)
			
			if item:
				var meta = item.get_metadata(0)
				if meta and meta["type"] == "dir":
					_initiate_smart_creation(meta["path"], files)
					return
		
		# Fallback: Inspector / General
		if _current_bank:
			# Adding .tres files (SoundData) to the currently inspected bank
			var to_add = []
			for f in files:
				if f.ends_with(".tres") or f.ends_with(".res"):
					var res = load(f)
					if res is SoundData:
						if not res in _current_bank.sounds:
							to_add.append(res)
			if not to_add.is_empty():
				var ur = _undo_redo
				ur.create_action("Add to Bank (Drop)")
				var old_sounds = _current_bank.sounds.duplicate()
				var new_sounds = _current_bank.sounds.duplicate()
				new_sounds.append_array(to_add)
				
				ur.add_do_property(_current_bank, "sounds", new_sounds)
				ur.add_undo_property(_current_bank, "sounds", old_sounds)
				ur.add_do_method(_save_resource.bind(_current_bank))
				ur.add_undo_method(_save_resource.bind(_current_bank))
				ur.add_do_method(_inspect_bank.bind(_current_bank, true))
				ur.add_undo_method(_inspect_bank.bind(_current_bank, true))
				ur.commit_action()
		elif _current_selection:
			_add_clips_to_resource(_current_selection, files)

func _initiate_smart_creation(target_folder: String, files: Array):
	var valid_files = []
	for f in files:
		if f.get_extension() in ["wav", "mp3", "ogg"]:
			valid_files.append(f)
			
	if valid_files.is_empty(): return
	
	_creation_pending_files = valid_files
	_creation_target_path = target_folder
	
	# Suggest name from first file
	var suggestion = valid_files[0].get_file().get_basename()
	# Strip numbers if possible (simple regex or heuristic)
	# E.g. "footstep_01" -> "footstep"
	# Keep it simple for now
	
	_creation_name.text = suggestion
	_creation_dialog.popup_centered()
	
func _convert_to_audioclip(res: SoundData, idx: int):
	var stream = res.clips[idx]
	if stream is AudioStream:
		var new_clip = AudioClip.new()
		new_clip.stream = stream
		# Rename sub-resource if we want embedded? 
		# For now, just embedded in the array.
		res.clips[idx] = new_clip
		_save_resource(res)
		_inspect_resource(res)

func _request_delete_clip(res: SoundData, idx: int):
	var item = res.clips[idx]
	var name = "Unknown"
	if item is AudioStream: name = item.resource_path.get_file()
	if item is AudioClip and item.stream: name = item.stream.resource_path.get_file()
	
	var confirm = ConfirmationDialog.new()
	confirm.title = _t("DIALOG_DELETE_CONFIRM")
	confirm.dialog_text = _t("DIALOG_DELETE_MSG_CLIP") % name
	confirm.confirmed.connect(func():
		var ur = _undo_redo
		ur.create_action("Delete Clip")
		var old_clips = res.clips.duplicate()
		var new_clips = res.clips.duplicate()
		new_clips.remove_at(idx)
		
		ur.add_do_property(res, "clips", new_clips)
		ur.add_undo_property(res, "clips", old_clips)
		ur.add_do_method(_save_resource.bind(res))
		ur.add_undo_method(_save_resource.bind(res))
		ur.add_do_method(_inspect_resource.bind(res, true))
		ur.add_undo_method(_inspect_resource.bind(res, true))
		ur.commit_action()
		confirm.queue_free()
	)
	add_child(confirm)
	confirm.popup_centered()

func _open_clip_editor(res: SoundData, idx: int):
	var clip: AudioClip = res.clips[idx]
	
	# Create a larger dialog for the Visual Editor
	var dialog = AcceptDialog.new()
	dialog.title = _t("CLIP_EDITOR_TITLE") % (clip.stream.resource_path.get_file() if clip.stream else _t("LBL_NULL_STREAM"))
	dialog.min_size = Vector2(800, 500)
	
	var split = HSplitContainer.new() # Split container for Controls vs Waveform? Or just VBox
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	# Top: Waveform Editor
	var waveform_ed = preload("res://addons/AudioDashboard/WaveformEditor.tscn").instantiate()
	waveform_ed.no_clip_text = _t("LBL_EMPTY_UNKNOWN")
	waveform_ed.custom_minimum_size.y = 250
	waveform_ed.size_flags_vertical = Control.SIZE_EXPAND_FILL
	waveform_ed.set_clip(clip)
	vbox.add_child(waveform_ed)
	
	# Bottom: Sliders & Properties (Fine tuning)
	var props_grid = GridContainer.new()
	props_grid.columns = 2
	
	# Loop & Weight
	var chk_loop = CheckBox.new()
	chk_loop.text = _t("CLIP_LOOP")
	chk_loop.button_pressed = clip.loop
	chk_loop.toggled.connect(func(v): clip.loop = v)
	props_grid.add_child(chk_loop)
	
	var lbl_weight = Label.new()
	var slider_weight = HSlider.new()
	slider_weight.min_value = 0; slider_weight.max_value = 100;
	slider_weight.custom_minimum_size.x = 200
	slider_weight.value = clip.random_weight
	lbl_weight.text = _t("CLIP_WEIGHT") % clip.random_weight
	slider_weight.value_changed.connect(func(v):
		clip.random_weight = v
		lbl_weight.text = _t("CLIP_WEIGHT") % v
	)
	var w_box = HBoxContainer.new()
	w_box.add_child(lbl_weight)
	w_box.add_child(slider_weight)
	props_grid.add_child(w_box)
	
	vbox.add_child(props_grid)
	vbox.add_child(HSeparator.new())
	
	# Fine Tune Sliders
	_add_editor_slider(vbox, _t("CLIP_FADE_IN"), clip.fade_in, 0, 5, 0.1, func(v):
		clip.fade_in = v
		waveform_ed.queue_redraw()
	)
	_add_editor_slider(vbox, _t("CLIP_FADE_IN_CURVE"), clip.fade_in_curve, 0.1, 5.0, 0.1, func(v):
		clip.fade_in_curve = v
		waveform_ed.queue_redraw()
	)
	
	vbox.add_child(HSeparator.new())
	
	_add_editor_slider(vbox, _t("CLIP_FADE_OUT"), clip.fade_out, 0, 5, 0.1, func(v):
		clip.fade_out = v
		waveform_ed.queue_redraw()
	)
	_add_editor_slider(vbox, _t("CLIP_FADE_OUT_CURVE"), clip.fade_out_curve, 0.1, 5.0, 0.1, func(v):
		clip.fade_out_curve = v
		waveform_ed.queue_redraw()
	)
	
	vbox.add_child(HSeparator.new())
	
	_add_editor_slider(vbox, _t("CLIP_VOL_OFFSET"), clip.volume_offset, -20, 20, 1, func(v): clip.volume_offset = v)
	
	dialog.add_child(vbox)
	dialog.confirmed.connect(func(): _save_resource(res)) # Save on close
	add_child(dialog)
	dialog.popup_centered()

func _add_editor_slider(parent, label, val, min_v, max_v, step, setter_func):
	var hbox = HBoxContainer.new()
	var l = Label.new()
	l.text = label
	l.custom_minimum_size.x = 120
	
	var s = HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = val
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var spin = SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = step
	spin.value = val
	spin.custom_minimum_size.x = 70
	
	s.value_changed.connect(func(v):
		spin.value = v
		setter_func.call(v)
		# Trigger redraw in editor if available? handled by setter usually invoking logic, 
		# but for this specific editor, logic is in the caller via setters updating vars. 
		# If we need to force redraw, we might need a signal. 
		# But wait, the _open_clip_editor caller logic doesn't redraw waveform.
		# The WaveformEditor logic is separate. 
	)
	
	spin.value_changed.connect(func(v):
		s.value = v
		setter_func.call(v)
	)
	
	hbox.add_child(l)
	hbox.add_child(s)
	hbox.add_child(spin)
	parent.add_child(hbox)
	return s # Return slider so we can drive it externally if needed

func _on_create_confirmed():
	var name = _creation_name.text
	if name.is_empty(): return
	
	var save_path = _creation_target_path.path_join(name + ".tres")
	if FileAccess.file_exists(save_path):
		# Append timestamp or counter if exists
		save_path = _creation_target_path.path_join(name + "_" + str(Time.get_ticks_msec()) + ".tres")
	
	# Create Resource
	var res = SoundData.new()
	res.shuffle_mode = SoundData.ShuffleMode.RANDOM_NO_REPEAT
	
	# Add Clips
	for f in _creation_pending_files:
		var stream = load(f)
		if stream:
			res.clips.append(stream)
	
	var ur = _undo_redo
	ur.create_action("Create SoundData")
	ur.add_do_method(_save_resource_and_refresh.bind(res, save_path))
	var trash_path = _get_trash_path(save_path)
	ur.add_undo_method(_move_to_trash.bind(save_path, trash_path))
	ur.add_do_method(_refresh_library)
	ur.add_undo_method(_refresh_library)
	ur.commit_action()

func _create_bank_at_path(path: String):
	var bank = SoundBank.new()
	ResourceSaver.save(bank, path)
	EditorInterface.get_resource_filesystem().update_file(path)

func _save_resource_and_refresh(res: Resource, path: String):
	ResourceSaver.save(res, path)
	EditorInterface.get_resource_filesystem().update_file(path)
	_generate_sounds_helper()
	
	# Auto-select the new item?
	# Need to find it in tree. _refresh_library rebuilds tree.
	# Leaving selection logic for later.

func _add_clips_to_resource(res: SoundData, files: Array):
	var to_add = []
	for f in files:
		if f.get_extension() in ["wav", "mp3", "ogg"]:
			var stream = load(f)
			if stream:
				to_add.append(stream)
				
	if not to_add.is_empty():
		var ur = _undo_redo
		ur.create_action("Add Clips")
		var old_clips = res.clips.duplicate()
		var new_clips = res.clips.duplicate()
		new_clips.append_array(to_add)
		
		ur.add_do_property(res, "clips", new_clips)
		ur.add_undo_property(res, "clips", old_clips)
		ur.add_do_method(_save_resource.bind(res))
		ur.add_undo_method(_save_resource.bind(res))
		ur.add_do_method(_inspect_resource.bind(res, true))
		ur.add_undo_method(_inspect_resource.bind(res, true))
		ur.commit_action()

func _create_resources(files: Array):
	# ... (Existing creation logic)
	for f in files:
		if f.get_extension() in ["wav", "mp3", "ogg"]:
			_create_sound_data_from_audio(f)
	_refresh_library()

func _create_sound_data_from_audio(audio_path: String):
	var new_res = SoundData.new()
	var stream = load(audio_path)
	if stream:
		new_res.clips = [stream]
		new_res.resource_name = audio_path.get_file().get_basename()
		var save_path = audio_path.get_base_dir() + "/" + new_res.resource_name + "_data.tres"
		ResourceSaver.save(new_res, save_path)

func _initialize_structure():
	var dir = DirAccess.open("res://")
	if not dir.dir_exists(RESOURCE_ROOT):
		dir.make_dir_recursive(RESOURCE_ROOT)
		
	# Create default categories in the Resource Root
	var folders = ["SFX", "Music", "UI", "Ambience", "Voice", "AudioBanks"]
	for folder in folders:
		var full_path = RESOURCE_ROOT + "/" + folder
		if not dir.dir_exists(full_path):
			dir.make_dir_recursive(full_path)
			
	print(_t("MSG_STRUCTURE_INIT") % RESOURCE_ROOT)
func _run_diagnostics():
	var report = "[b][size=18]" + _t("DIAG_TITLE") + "[/size][/b]\n\n"
	var issues = 0
	var warnings = 0
	
	# 1. Check for Missing Audio Files & Duplicates
	var slugs_seen = {} # Slug -> Path
	for path in _scanned_resources:
		var res = _scanned_resources[path]
		if res is SoundData:
			# Slug Collision
			if slugs_seen.has(res.slug):
				report += "[color=red][ERR][/color] " + _t("DIAG_DUP_SLUG") % [res.slug, path, slugs_seen[res.slug]] + "\n"
				issues += 1
			slugs_seen[res.slug] = path
			
			# Missing Clips
			if res.clips.is_empty():
				report += "[color=yellow][WARN][/color] " + _t("DIAG_EMPTY_SOUND") % path + "\n"
				warnings += 1
			else:
				for i in range(res.clips.size()):
					var c = res.clips[i]
					var stream = c.stream if c is AudioClip else c
					if not stream:
						report += "[color=red][ERR][/color] " + _t("DIAG_NULL_CLIP") % [i, path] + "\n"
						issues += 1
					elif not FileAccess.file_exists(stream.resource_path):
						report += "[color=red][ERR][/color] " + _t("DIAG_MISSING_FILE") % [stream.resource_path, path] + "\n"
						issues += 1
			
			# Invalid Bus
			var bus_exists = false
			for j in AudioServer.bus_count:
				if AudioServer.get_bus_name(j) == res.bus:
					bus_exists = true
					break
			if not bus_exists:
				report += "[color=yellow][WARN][/color] " + _t("DIAG_INVALID_BUS") % [res.bus, path] + "\n"
				warnings += 1
				
		elif res is SoundBank:
			# Missing or Null entries in banks
			if res.sounds.is_empty():
				report += "[color=yellow][WARN][/color] " + _t("DIAG_EMPTY_BANK") % path + "\n"
				warnings += 1
			else:
				for i in range(res.sounds.size()):
					if res.sounds[i] == null:
						report += "[color=red][ERR][/color] " + _t("DIAG_NULL_BANK_ENTRY") % [i, path] + "\n"
						issues += 1
	
	if issues == 0 and warnings == 0:
		report += "[color=green]" + _t("DIAG_NO_ISSUES") + "[/color]\n"
	else:
		report += "\n" + _t("DIAG_SUMMARY") % [issues, warnings]
	
	# Show Dialog
	var dialog = AcceptDialog.new()
	dialog.title = _t("BTN_DIAG")
	dialog.min_size = Vector2(600, 400)
	var scroll = ScrollContainer.new()
	var rich = RichTextLabel.new()
	rich.bbcode_enabled = true
	rich.text = report
	rich.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rich.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(rich)
	dialog.add_child(scroll)
	add_child(dialog)
	dialog.popup_centered()
	dialog.finished.connect(func(): dialog.queue_free())

func _update_project_references_text(old_path: String, new_path: String, old_uid: String, new_uid: String):
	var extensions = ["tres", "res", "tscn"]
	var files_to_scan = []
	_gather_files_by_extension("res://", extensions, files_to_scan)
	
	for f_path in files_to_scan:
		# Skip the dashboard itself and system files
		if f_path.contains("addons/AudioDashboard"): continue
		
		var content = FileAccess.get_file_as_string(f_path)
		if content.is_empty(): continue
		
		var changed = false
		
		# Path replacement
		if old_path in content:
			content = content.replace(old_path, new_path)
			changed = true
			
		# UID replacement
		if not old_uid.is_empty() and old_uid in content:
			content = content.replace(old_uid, new_uid)
			changed = true
			
		if changed:
			var f = FileAccess.open(f_path, FileAccess.WRITE)
			if f:
				f.store_string(content)
				f.close()
				print("AudioDashboard: Updated references in ", f_path)
				
				# If it's a resource file, reload it from memory to reflect changes immediately
				if f_path.get_extension() in ["tres", "res"]:
					var res = load(f_path)
					if res and res is Resource:
						res.reload_from_file()

func _gather_files_by_extension(path: String, extensions: Array, out_list: Array):
	var dir = DirAccess.open(path)
	if not dir: return
	dir.list_dir_begin()
	var fn = dir.get_next()
	while fn != "":
		if dir.current_is_dir():
			if not fn.begins_with("."):
				_gather_files_by_extension(path.path_join(fn), extensions, out_list)
		else:
			if fn.get_extension().to_lower() in extensions:
				out_list.append(path.path_join(fn))
		fn = dir.get_next()

func _update_all_bank_references(_o, _n):
	pass # Deprecated in favor of _update_project_references_text

func _gather_banks_recursive(_p, _l):
	pass # Deprecated

func _generate_sounds_helper():
	var script_path = "res://addons/AudioDashboard/audio/Sounds.gd"
	var content = "@tool\nextends Object\nclass_name Sounds\n\n# --- GENERATED BY AUDIODASHBOARD (DO NOT EDIT MANUALLY) ---\n\n"
	
	# Force a fresh local scan to ensure we have the latest files, 
	# avoiding reliance on potentially stale global _scanned_resources
	var local_scan = {}
	_recursive_scan_to_dict(RESOURCE_ROOT, local_scan)
	
	var keys = local_scan.keys()
	# SAFETY: If scan returned 0, double check the filesystem
	if local_scan.is_empty():
		var dir = DirAccess.open(RESOURCE_ROOT)
		if dir:
			dir.list_dir_begin()
			var filename = dir.get_next()
			var has_any_files = false
			while filename != "":
				if not dir.current_is_dir() and (filename.ends_with(".tres") or filename.ends_with(".res")):
					has_any_files = true
					break
				filename = dir.get_next()
			
			if has_any_files:
				# Directory is NOT empty, but scan returned 0. 
				# This means Godot hasn't "loaded" the resources yet.
				# Let's try to wait a bit or just return with a message.
				printerr("AudioDashboard: Files detected but not yet loaded by engine. Please wait a moment and try again.")
				return
	
	# Update the global cache so the sync label reflects the new reality too
	for k in local_scan:
		_scanned_resources[k] = local_scan[k]
		
	keys.sort()
	
	var registry_content = "@tool\nextends Object\nclass_name AudioRegistry\n\n# --- GENERATED BY AUDIODASHBOARD (DO NOT EDIT MANUALLY) ---\n\nconst SLUGS = {\n"
	
	var used_const_names = {} # Map<String, int> to handle collisions
	
	for path in keys:
		if not local_scan[path] is SoundData:
			continue
			
		var res = local_scan[path]
		var file_name = path.get_file().get_basename()
		# Format name for Constants (SCREAMING_SNAKE_CASE)
		var const_name = file_name.to_upper().replace(" ", "_").replace("-", "_")
		if const_name[0] in "0123456789": const_name = "_" + const_name
		
		# Collision Prevention: if name already used, append parent folder
		if used_const_names.has(const_name):
			var parent = path.get_base_dir().get_file().to_upper().replace(" ", "_").replace("-", "_")
			const_name = parent + "_" + const_name
			
		used_const_names[const_name] = true
		
		# Ensure Slug is updated
		if res.slug.is_empty():
			res.slug = file_name.to_snake_case()
			ResourceSaver.save(res, path)
			
		# UID for the registry (internal)
		var uid = ResourceLoader.get_resource_uid(path)
		var final_path = ResourceUID.id_to_text(uid) if uid != -1 else path
		
		content += "const %s = \"%s\"\n" % [const_name, res.slug]
		registry_content += "\t\"%s\": \"%s\",\n" % [res.slug, final_path]
		
		# Store the finally used const_name back into local_scan metadata for the match statement
		# (We'll use a temporary metadata key for this session)
		res.set_meta("tmp_const_name", const_name)
	
	registry_content += "}\n"
	
	# Add static helper for dynamic lookup
	content += "\n## Returns the slug of a sound by its name (case-insensitive).\n"
	content += "static func get_sound_path(name: String) -> String:\n"
	content += "\tmatch name.to_upper().strip_edges():\n"
	for path in keys:
		if not local_scan[path] is SoundData:
			continue
		var res = local_scan[path]
		var const_name = res.get_meta("tmp_const_name", "")
		if not const_name.is_empty():
			content += "\t\t\"%s\": return %s\n" % [const_name, const_name]
			res.remove_meta("tmp_const_name")
	content += "\t\t_: return \"\"\n"
	
	# Save AudioRegistry.gd
	var reg_path = "res://addons/AudioDashboard/audio/AudioRegistry.gd"
	var reg_file = FileAccess.open(reg_path, FileAccess.WRITE)
	if reg_file:
		reg_file.store_string(registry_content)
		reg_file.close()
		EditorInterface.get_resource_filesystem().update_file(reg_path)
	
	# Load the script resource to update its source_code in-memory
	var script = load(script_path)
	if not script:
		# If it's the very first time, we create the file first
		var file = FileAccess.open(script_path, FileAccess.WRITE)
		if file:
			file.store_string(content)
			file.close()
		script = load(script_path)
	
	if script:
		script.source_code = content
		var err = ResourceSaver.save(script, script_path)
		if err == OK:
			script.reload()
			# Notify the editor's filesystem of the change
			EditorInterface.get_resource_filesystem().update_file(script_path)
			
			# Refresh the "Pending Changes" status in UI
			_check_sync_status()
			# Print to console for feedback
			print("AudioDashboard: Sounds.gd updated and reloaded.")
		else:
			printerr("AudioDashboard: ResourceSaver failed. Falling back to FileAccess. Error: ", err)
			var file = FileAccess.open(script_path, FileAccess.WRITE)
			if file:
				file.store_string(content)
				file.close()
				print(_t("MSG_GENERATED") % keys.size())
	else:
		printerr("AudioDashboard: Could not load Sounds.gd for internal saving at ", script_path)

func _build_settings_tab(parent: Control):
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	parent.add_child(margin)
	
	var vbox = VBoxContainer.new()
	margin.add_child(vbox)
	
	var section_lang = Label.new()
	section_lang.text = _t("SEC_SETTINGS_LANG")
	section_lang.add_theme_font_size_override("font_size", 16)
	vbox.add_child(section_lang)
	
	var lang_opt = OptionButton.new()
	lang_opt.add_item(_t("LANG_AUTO"), 0)
	lang_opt.add_item(_t("LANG_EN"), 1)
	lang_opt.add_item(_t("LANG_ES"), 2)
	lang_opt.add_item(_t("LANG_FR"), 3)
	lang_opt.add_item(_t("LANG_DE"), 4)


	
	match _current_lang:
		"Auto": lang_opt.selected = 0
		"EN": lang_opt.selected = 1
		"ES": lang_opt.selected = 2
		"FR": lang_opt.selected = 3
		"DE": lang_opt.selected = 4


		
	lang_opt.item_selected.connect(func(idx):
		match idx:
			0: _current_lang = "Auto"
			1: _current_lang = "EN"
			2: _current_lang = "ES"
			3: _current_lang = "FR"
			4: _current_lang = "DE"


		_save_settings()
		_build_ui() # Re-build everything to apply language
		_refresh_library(true) # Re-scan to ensure everything is in sync
	)
	vbox.add_child(lang_opt)
	
	vbox.add_child(HSeparator.new())
	
	var monitor_lbl = Label.new()
	monitor_lbl.text = _t("SEC_SETTINGS_MONITOR")
	monitor_lbl.add_theme_font_size_override("font_size", 16)
	vbox.add_child(monitor_lbl)
	
	var monitor_chk = CheckBox.new()
	monitor_chk.text = _t("LBL_ENABLE_MONITOR")
	monitor_chk.tooltip_text = _t("TOOLTIP_MONITOR")
	monitor_chk.button_pressed = _enable_live_monitor
	monitor_chk.toggled.connect(func(v):
		_enable_live_monitor = v
		_save_settings()
	)
	vbox.add_child(monitor_chk)
	
	vbox.add_child(HSeparator.new())
	
	var info_lbl = Label.new()
	info_lbl.text = _t("LBL_TITLE")
	info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_lbl.modulate = Color(1, 1, 1, 0.4)
	vbox.add_child(info_lbl)

func _save_settings():
	if not Engine.is_editor_hint(): return
	var config = ConfigFile.new()
	var path = "res://addons/AudioDashboard/settings.cfg"
	config.set_value("general", "language", _current_lang)
	config.set_value("general", "enable_live_monitor", _enable_live_monitor)
	config.save(path)
	
	ProjectSettings.set_setting("audio_dashboard/enable_live_monitor", _enable_live_monitor)
	ProjectSettings.save()

func _load_settings():
	if not Engine.is_editor_hint(): return
	var config = ConfigFile.new()
	var path = "res://addons/AudioDashboard/settings.cfg"
	if config.load(path) == OK:
		_current_lang = config.get_value("general", "language", "Auto")
		_enable_live_monitor = config.get_value("general", "enable_live_monitor", true)
		
	if not ProjectSettings.has_setting("audio_dashboard/enable_live_monitor"):
		ProjectSettings.set_setting("audio_dashboard/enable_live_monitor", _enable_live_monitor)
		ProjectSettings.save()

#endregion

func _select_in_tree(target_path: String) -> void:
	if not _tree_view: return
	var root = _tree_view.get_root()
	if not root: return
	
	var found = _find_item_by_path(root, target_path)
	if found:
		# Expand parents
		var p = found.get_parent()
		while p:
			p.collapsed = false
			p = p.get_parent()
		
		found.select(0)
		_tree_view.scroll_to_item(found)

func _find_item_by_path(item: TreeItem, target_path: String) -> TreeItem:
	if not item: return null
	
	var metadata = item.get_metadata(0)
	if metadata and metadata is Dictionary and metadata.get("type") == "file":
		var res = metadata.get("res")
		if res and res.resource_path == target_path:
			return item
	
	var child = item.get_first_child()
	while child:
		var result = _find_item_by_path(child, target_path)
		if result: return result
		child = child.get_next()
	return null

func _recursive_scan_to_dict(path: String, out_dict: Dictionary):
	var dir = DirAccess.open(path)
	if not dir: return
	dir.list_dir_begin()
	var fn = dir.get_next()
	while fn != "":
		if dir.current_is_dir():
			if not fn.begins_with("."):
				_recursive_scan_to_dict(path.path_join(fn), out_dict)
		else:
			if fn.ends_with(".tres") or fn.ends_with(".res"):
				var full_path = path.path_join(fn)
				# CRITICAL: Verify file exists on DISK to avoid Godot's stale resource cache
				if FileAccess.file_exists(full_path):
					var res = ResourceLoader.load(full_path)
					if res:
						out_dict[full_path] = res
		fn = dir.get_next()

func _cleanup_global_references(res_path: String, ur = null):
	# Find all SoundBanks in the project
	var banks = []
	_gather_files_by_extension(RESOURCE_ROOT, ["tres", "res"], banks)
	
	var res_uid_text = ""
	var res_uid = ResourceLoader.get_resource_uid(res_path)
	if res_uid != -1:
		res_uid_text = ResourceUID.id_to_text(res_uid)

	for b_path in banks:
		var b = load(b_path)
		if b is SoundBank:
			var modified = false
			var old_sounds = b.sounds.duplicate()
			var new_sounds = []
			
			for s in b.sounds:
				if s == null: 
					modified = true
					continue
				
				var matches = false
				if s.resource_path == res_path:
					matches = true
				elif not res_uid_text.is_empty():
					var s_uid = ResourceLoader.get_resource_uid(s.resource_path)
					if s_uid != -1 and ResourceUID.id_to_text(s_uid) == res_uid_text:
						matches = true
				
				if matches:
					modified = true
				else:
					new_sounds.append(s)
			
			if modified:
				if ur:
					ur.add_do_property(b, "sounds", new_sounds)
					ur.add_undo_property(b, "sounds", old_sounds)
					ur.add_do_method(_save_resource.bind(b))
					ur.add_undo_method(_save_resource.bind(b))
					ur.add_do_method(_refresh_bank_ui_if_active.bind(b))
					ur.add_undo_method(_refresh_bank_ui_if_active.bind(b))
				else:
					b.sounds = new_sounds
					_save_resource(b)
					_refresh_bank_ui_if_active(b)

func _refresh_bank_ui_if_active(bank: SoundBank):
	if _current_bank == bank:
		_inspect_bank(bank, true)

func _refresh_current_inspection():
	if _current_bank:
		_inspect_bank(_current_bank, true)
	elif _current_selection:
		_inspect_resource(_current_selection, true)

func _perform_physical_deletion(target: String, resources: Array):
	# DEPRECATED: Handled by _move_to_trash in the UndoRedo action
	pass

func _get_trash_path(original_path: String) -> String:
	var trash_base = "user://audio_dashboard_trash"
	if not DirAccess.dir_exists_absolute(trash_base):
		DirAccess.make_dir_recursive_absolute(trash_base)
	
	var timestamp = str(Time.get_ticks_msec())
	var filename = original_path.get_file()
	return trash_base.path_join(timestamp + "_" + filename)

func _move_to_trash(from_path: String, to_path: String):
	if not (FileAccess.file_exists(from_path) or DirAccess.dir_exists_absolute(from_path)):
		return
	
	var dir = DirAccess.open("user://")
	# Ensure parent directory of to_path exists
	DirAccess.make_dir_recursive_absolute(to_path.get_base_dir())
	
	var err = DirAccess.rename_absolute(from_path, to_path)
	if err != OK:
		printerr("AudioDashboard: Failed to move to trash: ", from_path, " -> ", to_path, " Error: ", err)

func _restore_from_trash(trash_path: String, original_path: String):
	if not (FileAccess.file_exists(trash_path) or DirAccess.dir_exists_absolute(trash_path)):
		# Try to find it if it was renamed/moved? 
		# No, just return error if missing.
		printerr("AudioDashboard: Cannot restore, trash file missing: ", trash_path)
		return
		
	# Ensure parent directory of original_path exists (it might have been deleted too)
	DirAccess.make_dir_recursive_absolute(original_path.get_base_dir())
	
	var err = DirAccess.rename_absolute(trash_path, original_path)
	if err != OK:
		printerr("AudioDashboard: Failed to restore from trash: ", trash_path, " -> ", original_path, " Error: ", err)

func _remove_recursive_absolute(path: String):
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var fn = dir.get_next()
		while fn != "":
			if dir.current_is_dir() and fn != "." and fn != "..":
				_remove_recursive_absolute(path.path_join(fn))
			else:
				DirAccess.remove_absolute(path.path_join(fn))
			fn = dir.get_next()
		DirAccess.remove_absolute(path)
