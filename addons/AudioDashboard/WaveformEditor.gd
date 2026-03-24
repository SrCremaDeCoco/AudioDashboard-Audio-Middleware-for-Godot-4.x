@tool
extends ColorRect

# Signal to notify changes
signal resource_updated

var _clip: AudioClip
var _stream_data: PackedFloat32Array
var _hovered_handle: String = ""
var _dragging_handle: String = ""
var no_clip_text: String = "No Clip"

func set_clip(clip: AudioClip):
	_clip = clip
	if _clip and _clip.stream:
		$ClipInfo.text = _clip.stream.resource_path.get_file()
		_load_waveform_data()
	else:
		$ClipInfo.text = no_clip_text
		_stream_data.clear()
	queue_redraw()

func _load_waveform_data():
	_stream_data.clear()
	if not _clip or not _clip.stream: return
	
	var stream = _clip.stream
	var bins = 300 # Resolution of waveform
	
	if stream is AudioStreamWAV:
		_stream_data = _generate_wav_peaks(stream, bins)
	else:
		# MP3/OGG placeholder
		_stream_data = _generate_placeholder_peaks(bins, stream.resource_path.hash())
	
	queue_redraw()

func _generate_wav_peaks(wav: AudioStreamWAV, bins: int) -> PackedFloat32Array:
	var peaks = PackedFloat32Array()
	var data = wav.data
	if data.is_empty(): return peaks
	
	var format = wav.format
	var b_per_sample = 1
	if format == AudioStreamWAV.FORMAT_16_BITS: b_per_sample = 2
	
	var total_samples = data.size() / b_per_sample
	if wav.stereo: total_samples /= 2
	
	var samples_per_bin = total_samples / bins
	if samples_per_bin < 1: samples_per_bin = 1
	
	for i in range(bins):
		var max_v = 0.0
		var start_sample = i * samples_per_bin
		var byte_idx = start_sample * b_per_sample * (2 if wav.stereo else 1)
		
		# Sample up to 10 points in each bin to find a peak (performance balance)
		for j in range(10):
			var cur_byte = byte_idx + (j * (samples_per_bin / 10) * b_per_sample)
			if cur_byte + 1 >= data.size(): break
			
			var val = 0.0
			if format == AudioStreamWAV.FORMAT_8_BITS:
				val = abs(float(data[cur_byte]) - 128.0) / 128.0
			else:
				var low = data[cur_byte]
				var high = data[cur_byte+1]
				var combined = low | (high << 8)
				if combined > 32767: combined -= 65536
				val = abs(float(combined)) / 32768.0
			if val > max_v: max_v = val
		peaks.append(max_v)
	return peaks

func _generate_placeholder_peaks(bins: int, seed_val: int) -> PackedFloat32Array:
	var peaks = PackedFloat32Array()
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_val
	for i in range(bins):
		peaks.append(rng.randf_range(0.1, 0.7))
	return peaks
	
func _draw():
	if not _clip: return
	
	var w = size.x
	var h = size.y
	
	# Draw Background Grid
	draw_line(Vector2(0, h / 2), Vector2(w, h / 2), Color(1, 1, 1, 0.2), 1.0)
	
	# Draw Waveform from peak data
	if _stream_data.is_empty():
		draw_line(Vector2(0, h / 2), Vector2(w, h / 2), Color(0.2, 0.8, 1, 0.5), 2.0)
	else:
		var bin_w = w / _stream_data.size()
		for i in range(_stream_data.size()):
			var peak = _stream_data[i]
			var x = i * bin_w
			var bar_h = peak * (h / 1.5) # Scale to fit nicely
			draw_line(Vector2(x, h/2 - bar_h), Vector2(x, h/2 + bar_h), Color(0.2, 0.8, 1, 0.8 if peak > 0.1 else 0.4))
	
	# Draw Trim Regions (Darkened areas outside trim)
	var duration = _clip.get_length()
	if duration <= 0: return
	
	var px_per_sec = w / duration
	var start_x = _clip.start_time * px_per_sec
	var end_x = (_clip.end_time if _clip.end_time > 0 else duration) * px_per_sec
	
	# Region Before Start
	draw_rect(Rect2(0, 0, start_x, h), Color(0, 0, 0, 0.6))
	# Region After End
	draw_rect(Rect2(end_x, 0, w - end_x, h), Color(0, 0, 0, 0.6))
	
	# Draw Handles (Triangles)
	_draw_handle(start_x, h, Color.GREEN, "Start")
	_draw_handle(end_x, h, Color.RED, "End")
	
	# Draw Fades (Curves)
	var fade_color_in = Color(0.2, 1, 0.2, 0.8)
	var fade_color_out = Color(1, 0.2, 0.2, 0.8)
	
	if _clip.fade_in > 0:
		var fade_in_px = _clip.fade_in * px_per_sec
		var points_in = PackedVector2Array()
		for i in range(20):
			var t = float(i) / 19.0
			var x = start_x + (t * fade_in_px)
			
			# Evaluate Curve (Expo approx)
			var y_t = t
			if _clip.fade_in_curve > 1.0: y_t = pow(t, 2.5) # Ease In
			elif _clip.fade_in_curve < 1.0: y_t = 1.0 - pow(1.0 - t, 2.5) # Ease Out
			
			var y = h - (y_t * h) # 0 to 1 -> h to 0 (Bottom up)
			points_in.append(Vector2(x, y))
			
		draw_polyline(points_in, fade_color_in, 2.0)
		
	if _clip.fade_out > 0:
		var fade_out_px = _clip.fade_out * px_per_sec
		var points_out = PackedVector2Array()
		for i in range(20):
			var t = float(i) / 19.0
			var x = end_x - fade_out_px + (t * fade_out_px)
			
			# Evaluate Curve
			var y_t = t
			# For fade out, 0 is full vol, 1 is silent
			# We want t=0 (start of fade) -> y=0 (top)
			# t=1 (end of fade) -> y=h (bottom)
			
			var curve_val = t
			if _clip.fade_out_curve > 1.0: curve_val = pow(t, 2.5)
			elif _clip.fade_out_curve < 1.0: curve_val = 1.0 - pow(1.0 - t, 2.5)
			
			var y = curve_val * h

			points_out.append(Vector2(x, y))
			
		draw_polyline(points_out, fade_color_out, 2.0)

func _draw_handle(x, h, color, type):
	var points = PackedVector2Array([
		Vector2(x, 0),
		Vector2(x, h),
	])
	draw_line(points[0], points[1], color, 2.0)
	# Handle Grip
	draw_circle(Vector2(x, 10), 6, color)

func _gui_input(event):
	if not _clip: return
	var duration = _clip.get_length()
	if duration <= 0: return
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# Check hit test
				_dragging_handle = _get_handle_at(event.position)
			else:
				_dragging_handle = ""
				if _clip.resource_path != "": ResourceSaver.save(_clip) # Auto-save?
				resource_updated.emit()
				
	if event is InputEventMouseMotion and _dragging_handle != "":
		var time = (event.position.x / size.x) * duration
		time = clamp(time, 0, duration)
		
		if _dragging_handle == "Start":
			_clip.start_time = time
		elif _dragging_handle == "End":
			_clip.end_time = time
			
		queue_redraw()

func _get_handle_at(pos):
	var duration = _clip.get_length()
	var px_per_sec = size.x / duration
	var start_x = _clip.start_time * px_per_sec
	var end_x = (_clip.end_time if _clip.end_time > 0 else duration) * px_per_sec
	
	if pos.distance_to(Vector2(start_x, 10)) < 15: return "Start"
	if pos.distance_to(Vector2(end_x, 10)) < 15: return "End"
	return ""
