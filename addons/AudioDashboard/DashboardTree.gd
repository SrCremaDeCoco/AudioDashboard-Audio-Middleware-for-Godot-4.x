@tool
extends Tree

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	var dashboard = _find_dashboard()
	if dashboard:
		# Convert to Dashboard local space
		var global = get_global_position() + at_position
		var local_to_dashboard = global - dashboard.get_global_position()
		return dashboard.has_method("_can_drop_data") and dashboard._can_drop_data(local_to_dashboard, data)
	return false

func _drop_data(at_position: Vector2, data: Variant) -> void:
	var dashboard = _find_dashboard()
	if dashboard:
		var global = get_global_position() + at_position
		var local_to_dashboard = global - dashboard.get_global_position()
		if dashboard.has_method("_drop_data"):
			dashboard._drop_data(local_to_dashboard, data)

func _get_drag_data(at_position: Vector2) -> Variant:
	var selected = []
	var item = get_next_selected(null)
	while item:
		var meta = item.get_metadata(0)
		if meta and meta.has("res") and meta["res"] is SoundData:
			selected.append(meta["res"])
		elif meta and meta.has("type") and meta["type"] == "file":
			# Handle direct file dragging if needed
			pass
		item = get_next_selected(item)
	
	if selected.is_empty(): return null
	
	var preview = Label.new()
	preview.text = selected[0].resource_path.get_file()
	if selected.size() > 1:
		preview.text += " (x%d)" % selected.size()
	set_drag_preview(preview)
	
	return {
		"type": "audio_dashboard_resource",
		"resources": selected,
		"files": selected.map(func(r): return r.resource_path)
	}

func _find_dashboard() -> Control:
	var node = get_parent()
	while node:
		if node.get_script() and node.get_script().resource_path.ends_with("AudioDashboard.gd"):
			return node
		node = node.get_parent()
	return null
