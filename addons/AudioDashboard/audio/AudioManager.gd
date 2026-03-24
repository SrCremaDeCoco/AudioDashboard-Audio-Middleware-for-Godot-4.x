## Centralized manager for the AudioDashboard sound system.
##
## The [AudioManager] provides a high-level API for playing sounds, managing polyphony, 
## and handling sound bank memory. It works as a singleton (Autoload) and uses a 
## performance-optimized pooling system for [AudioStreamPlayer] and [AudioStreamPlayer3D].
## [br][br]
## [b]Key Features:[/b]
## - Automatic pooling of audio players.
## - Distance-based culling for 3D sounds.
## - Unique instance management (e.g. for background music).
## - Scoped lifetime (Global, Scene, or Bank-linked).
extends Node

#region Internal Variables
## Pool of 2D players to reuse.
var _players_pool: Array[AudioStreamPlayer] = []
## Pool of 3D players to reuse.
var _players_3d_pool: Array[AudioStreamPlayer3D] = []
## Pool of 2D players to reuse.
var _players_2d_pool: Array[AudioStreamPlayer2D] = []
## Dictionary to track active instances for polyphony limits.
var _active_instances: Dictionary = {} # Map<SoundData, int>
## Dictionary to track playback history for NO_REPEAT mode.
var _playback_history: Dictionary = {} # Map<ResourceUID, Array[int]>
## Tracks which SoundData each player is currently handling to prevent polyphony leaks.
var _player_to_data: Dictionary = {} # Map<AudioStreamPlayer, SoundData>
## Tracks the internal hook node used for SCENE lifetime cleanup.
var _player_to_hook: Dictionary = {} # Map<AudioStreamPlayer, Node>
var _last_play_times: Dictionary = {} # SoundData -> msec
const MIN_SOUND_INTERVAL_MS = 15 # Debounce para sonidos muy frecuentes

# SoundBank RAM Management
var _loaded_banks: Dictionary = {} # Map<SoundBank, int (reference count)>
var _available_sounds: Dictionary = {} # Map<String (SoundData path), bool>

# FIX WEB
var _audio_unlocked: bool = false
var _pending_sounds: Array = []
#endregion

#region Initialization
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_pool(64, false) # Pool inicial ampliado para evitar add_child en gameplay
	_create_pool(32, true) # Pool inicial 3D
	_create_pool(32, false, true) # Pool inicial 2D

var _monitor_timer: float = 0.0
func _process(delta: float) -> void:
	if not OS.is_debug_build() or not EngineDebugger.is_active(): return
	
	_monitor_timer += delta
	if _monitor_timer >= 0.2:
		_monitor_timer = 0.0
		if not ProjectSettings.get_setting("audio_dashboard/enable_live_monitor", true):
			return
			
		var payload = {
			"banks": [],
			"sounds": {}
		}
		
		# Register Banks
		for b in _loaded_banks:
			var bank_name = b.resource_path.get_file().get_basename() if b.resource_path else "Unsaved Bank"
			payload.banks.append(bank_name)
			for s in b.sounds:
				if s:
					var s_name = s.resource_path.get_file().get_basename()
					if not payload.sounds.has(s_name):
						payload.sounds[s_name] = {"bank": bank_name, "instances": []}
		
		# Register Instances
		for player in _player_to_data:
			if is_instance_valid(player) and player.playing:
				var res = _player_to_data[player]
				var stream = player.stream
				var s_name = res.resource_path.get_file().get_basename() if res else "Unknown"
				
				if not payload.sounds.has(s_name):
					payload.sounds[s_name] = {"bank": "Orphan/Forced", "instances": []}
					if not "Orphan/Forced" in payload.banks:
						payload.banks.append("Orphan/Forced")
						
				payload.sounds[s_name].instances.append({
					"progress": player.get_playback_position(),
					"length": stream.get_length() if stream else 0.0,
					"bus": player.bus,
					"db": player.volume_db,
					"type": "2D" if player is AudioStreamPlayer2D else ("3D" if player is AudioStreamPlayer3D else "Global")
				})
				
		EngineDebugger.send_message("audio_dashboard:monitor", [payload])

## creates a pool of AudioStreamPlayers.
func _create_pool(count: int, is_3d: bool, is_2d: bool = false) -> void:
	for i in range(count):
		_add_player_to_pool(is_3d, is_2d)

func _input(event):
	if OS.get_name() == "Web" and not _audio_unlocked:
		if event is InputEventMouseButton or event is InputEventKey or event is InputEventScreenTouch:
			_audio_unlocked = true
			
			# Unlock AudioContext
			var was_muted = AudioServer.is_bus_mute(0)
			AudioServer.set_bus_mute(0, true)
			await get_tree().create_timer(0.01).timeout
			AudioServer.set_bus_mute(0, was_muted)
			
			print("AudioManager: Web AudioContext unlocked")

			_flush_pending_sounds()

func _flush_pending_sounds():
	if OS.get_name() == "Web":
		_cleanup_all_players()

	# Play pending sounds
	for pending in _pending_sounds:
		var data = pending.data
		var volume_offset = pending.volume_offset
		var owner = pending.owner
		var is_3d = pending.is_3d
		var pos = pending.pos
		
		print("AudioManager: Playing pending sound: ", data.slug if data else "unknown")
		
		if is_3d:
			play_at_position(data, pos, volume_offset, owner)
		else:
			play_global(data, volume_offset, owner)
	
	_pending_sounds.clear()

func _cleanup_all_players():
	# Limpiar todos los players del pool
	for player in _players_pool:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	for player in _players_3d_pool:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	for player in _players_2d_pool:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	
	_player_to_data.clear()
	_player_to_hook.clear()
	_active_instances.clear()
#endregion

#region Public API
## Plays a sound globally (UI, 2D music, etc.).
## [br][br]
## [param data] can be a [SoundData] resource, a String "slug" (e.g. from [AudioRegistry]), or a String path.
## [param volume_offset] is an additional dB adjustment applied only to this specific playback.
## [param owner] [b](Optional)[/b]. The node that controls the sound's lifecycle if [constant SoundData.SCENE] is used. 
## Defaults to the current scene root.
## [br][br]
## [b]Example Usage:[/b]
## [codeblock]
## # Using a constant from Sounds.gd
## AudioManager.play_global(Sounds.UI_CLICK)
##
## # Playing with a volume adjustment and an explicit owner
## AudioManager.play_global(Sounds.MUSIC_LEVEL_1, -10.0, self)
## [/codeblock]
func play_global(data: Variant, volume_offset: float = 0.0, owner: Node = null) -> AudioStreamPlayer:
	var sound_data: SoundData = _resolve_data(data)
	if not _can_play(sound_data): return null

	# if in Web, queue the sound
	if OS.get_name() == "Web" and not _audio_unlocked:
		push_warning("AudioManager: Attempting to play before user interaction. Sound will be queued but may not play until first click.")
		_pending_sounds.append({
			"data": sound_data,
			"volume_offset": volume_offset,
			"owner": owner,
			"is_3d": false,
			"pos": Vector3.ZERO
		})
		return null
	
	# --- Debounce Check ---
	var now = Time.get_ticks_msec()
	if _last_play_times.has(sound_data):
		if now - _last_play_times[sound_data] < MIN_SOUND_INTERVAL_MS:
			return null
	_last_play_times[sound_data] = now
	
	# Uniqueness check
	if sound_data.is_unique:
		var existing = _get_active_player_of(sound_data)
		if existing:
			if not sound_data.restart_if_playing:
				return existing
			_stop_all_instances_of(sound_data)
	
	var player = _get_idle_player(false)
	var final_owner = owner if owner else get_tree().current_scene
	_setup_player(player, sound_data, volume_offset, final_owner)
	player.play()
	
	return player

## Plays a sound at a specific 3D position with distance culling.
## [br][br]
## [param data] the sound to play (slug, path, or resource).
## [param global_pos] the Vector3 position in global space.
## [param volume_offset] additional dB offset for this instance.
## [param owner] [b](Optional)[/b]. The node that controls the sound's lifecycle if [constant SoundData.SCENE] is used.
## [br][br]
## [b]Example Usage:[/b]
## [codeblock]
## # Play an explosion at the current node's position
## AudioManager.play_at_position(Sounds.EXPLOSION, global_position)
## [/codeblock]
func play_at_position(data: Variant, global_pos: Vector3, volume_offset: float = 0.0, owner: Node = null) -> AudioStreamPlayer3D:
	var sound_data: SoundData = _resolve_data(data)
	if not _can_play(sound_data): return null

	# if in Web, queue the sound
	if OS.get_name() == "Web" and not _audio_unlocked:
		push_warning("AudioManager: Queuing 3D sound until user interaction: " + (sound_data.slug if sound_data else "unknown"))
		_pending_sounds.append({
			"data": sound_data,
			"volume_offset": volume_offset,
			"owner": owner,
			"is_3d": true,
			"pos": global_pos
		})
		return null
		
	# --- Debounce Check ---
	var now = Time.get_ticks_msec()
	if _last_play_times.has(sound_data):
		if now - _last_play_times[sound_data] < MIN_SOUND_INTERVAL_MS:
			return null
	_last_play_times[sound_data] = now
	
	# Uniqueness check
	if sound_data.is_unique:
		var existing = _get_active_player_of(sound_data)
		if existing:
			if not sound_data.restart_if_playing:
				return existing
			_stop_all_instances_of(sound_data)
	
	# Optimization: Distance Culling
	if sound_data.max_distance > 0:
		var listener = get_viewport().get_camera_3d() # Simplified listener check
		if listener:
			var dist = listener.global_position.distance_to(global_pos)
			if dist > sound_data.max_distance:
				return null # Too far, don't play
	
	var player = _get_idle_player(true)
	player.global_position = global_pos
	var final_owner = owner if owner else get_tree().current_scene
	_setup_player(player, sound_data, volume_offset, final_owner)
	player.play()
	
	return player

## Plays a sound at a specific 2D position with distance culling.
## [br][br]
## [param data] the sound to play (slug, path, or resource).
## [param global_pos] the Vector2 position in global space.
## [param volume_offset] additional dB offset for this instance.
## [param owner] [b](Optional)[/b]. The node that controls the sound's lifecycle if [constant SoundData.SCENE] is used.
func play_at_position_2d(data: Variant, global_pos: Vector2, volume_offset: float = 0.0, owner: Node = null) -> AudioStreamPlayer2D:
	var sound_data: SoundData = _resolve_data(data)
	if not _can_play(sound_data): return null
	
	# --- Debounce Check ---
	var now = Time.get_ticks_msec()
	if _last_play_times.has(sound_data):
		if now - _last_play_times[sound_data] < MIN_SOUND_INTERVAL_MS:
			return null
	_last_play_times[sound_data] = now
	
	# Uniqueness check
	if sound_data.is_unique:
		var existing = _get_active_player_of(sound_data)
		if existing:
			if not sound_data.restart_if_playing:
				return existing
			_stop_all_instances_of(sound_data)
	
	# Optimization: Distance Culling
	if sound_data.max_distance > 0:
		var cam = get_viewport().get_camera_2d()
		if cam:
			var dist = cam.get_screen_center_position().distance_to(global_pos)
			if dist > sound_data.max_distance:
				return null
	
	var player = _get_idle_player(false, true)
	player.global_position = global_pos
	var final_owner = owner if owner else get_tree().current_scene
	_setup_player(player, sound_data, volume_offset, final_owner)
	player.play()
	
	return player

# Helper to resolve SoundData from various inputs (Resource, Slug, or UID)
func _resolve_data(data: Variant) -> SoundData:
	if data is SoundData:
		return data
		
	var path_to_load = ""
	
	if data is String:
		# 1. Check if it's a known Slug
		if AudioRegistry.SLUGS.has(data):
			path_to_load = AudioRegistry.SLUGS[data]
		# 2. Check if it's already a UID
		elif data.begins_with("uid://"):
			path_to_load = data
		# 3. Fallback to direct path (deprecated but kept for compatibility)
		else:
			path_to_load = data
			
	if path_to_load.is_empty():
		return null
		
	# In Godot 4 builds, FileAccess.file_exists doesn't work well with UIDs
	# We rely on ResourceLoader.exists() or just attempting the load.
	if ResourceLoader.exists(path_to_load):
		return load(path_to_load) as SoundData
	else:
		push_error("AudioManager: Sound not found: " + str(data))
		
	return null

## Returns a list of all currently playing sound instances.
## [br][br]
## Each element is a [Dictionary] with:
## [br]- [code]player[/code]: The AudioStreamPlayer node.
## [br]- [code]data[/code]: The [SoundData] resource.
## [br]- [code]progress[/code]: Playback position in seconds.
func get_active_instances() -> Array:
	var list = []
	for player in _player_to_data:
		if is_instance_valid(player) and player.playing:
			list.append({
				"player": player,
				"data": _player_to_data[player],
				"progress": player.get_playback_position()
			})
	return list
#endregion

#region Internal Logic
## Checks if the sound can play based on polyphony limits.
func _can_play(data: SoundData) -> bool:
	if not data:
		push_warning("AudioManager: Attempted to play null SoundData.")
		return false
	if data.clips.is_empty():
		push_warning("AudioManager: SoundData '%s' has no audio clips." % data.resource_path)
		return false
	
	# FIX WEB: En HTML5, los recursos cargan asíncronamente. Permitimos fallback.
	if OS.get_name() == "Web":
		if not _available_sounds.has(data.slug):
			push_warning("AudioManager Web: Sound '%s' not registered in banks yet, allowing attempt." % data.slug)
		return true

	# RAM Safety Check (Strict Mode)
	# Decoupled from paths: uses the unique slug
	if not _available_sounds.has(data.slug):
		push_error("AudioManager: STRICT MODE - Sound '%s' is NOT loaded in any active SoundBank! Playback ignored." % data.slug)
		return false
		
	if not _active_instances.has(data.slug): return true
	return _active_instances[data.slug] < data.max_polyphony

## Configures the player with the data's properties.
func _setup_player(player: Node, data: SoundData, volume_offset: float = 0.0, owner: Node = null) -> void:
	_play_stream_on_player(player, data, null, volume_offset, owner)

	# FIX WEB:
	if data.lifetime == SoundData.Lifetime.SCENE and is_instance_valid(owner):
		var hook = _AudioLifetimeHook.new()
		hook.player = player
		
		if OS.get_name() == "Web":
			await get_tree().process_frame
			if is_instance_valid(owner):
				owner.add_child(hook)
				_player_to_hook[player] = hook
		else:
			owner.add_child.call_deferred(hook)
			_player_to_hook[player] = hook

func _play_stream_on_player(player: Node, res: SoundData, specific_clip = null, volume_offset: float = 0.0, owner: Node = null):
	# Disconnect existing signals and cleanup old state
	_cleanup_player(player)
	
	var clip_to_play = specific_clip
	if not clip_to_play:
		clip_to_play = _select_clip(res)
	
	# Track this instance before playing
	_player_to_data[player] = res
	
	# Handle Scoped Lifetime (Hook Strategy)
	# This is much more robust than connecting signals as it covers null owners,
	# scene changes, and hidden nodes exiting the tree.
	if res.lifetime == SoundData.Lifetime.SCENE and is_instance_valid(owner):
		var hook = _AudioLifetimeHook.new()
		hook.player = player
		owner.add_child.call_deferred(hook)
		_player_to_hook[player] = hook
		
	# --- Track instance here to cover loops too ---
	_track_instance(res)
	
	var stream: AudioStream = null
	var clip_data: AudioClip = null
	
	if clip_to_play is AudioClip:
		stream = clip_to_play.stream
		clip_data = clip_to_play
	elif clip_to_play is AudioStream:
		stream = clip_to_play
	
	if not stream: return
	
	player.stream = stream
	player.volume_db = res.volume_db + volume_offset
	player.pitch_scale = res.get_pitch()
	player.bus = res.bus
	
	if player is AudioStreamPlayer3D:
		player.max_distance = res.max_distance
		player.attenuation_model = res.attenuation_model
		player.panning_strength = res.panning_strength
	elif player is AudioStreamPlayer2D:
		player.max_distance = res.max_distance
		player.attenuation_filter_cutoff_hz = 20500
		# AudioStreamPlayer2D doesn't have attenuation_model like 3D, 
		# but it has attenuation (float exponent). 
		# Mapping: 1.0 is inverse distance (approx). 
		player.attenuation = 1.0
		player.panning_strength = res.panning_strength

	# Apply AudioClip settings
	var start_offset = 0.0
	var is_looping = false
	
	if clip_data:
		player.volume_db += clip_data.volume_offset
		start_offset = clip_data.start_time
		is_looping = clip_data.loop
		
		# Fades (Tweening)
		if clip_data.fade_in > 0:
			player.volume_db -= 80 # Start silent
			var target_vol = res.volume_db + clip_data.volume_offset
			var tween = create_tween()
			
			# Determine Easing
			var ease_type = Tween.EASE_IN_OUT # Default
			if clip_data.fade_in_curve > 1.0: ease_type = Tween.EASE_IN
			elif clip_data.fade_in_curve < 1.0: ease_type = Tween.EASE_OUT
			
			tween.set_trans(Tween.TRANS_EXPO) # Professional feeling fade
			tween.set_ease(ease_type)
			
			tween.tween_property(player, "volume_db", target_vol, clip_data.fade_in)
			
		# Trim End / Fade Out
		if clip_data.end_time > 0 or clip_data.fade_out > 0:
			# If looping, we currently don't support trimmed loops well with this simple implementation.
			# We'll prioritize the loop over the trim stop, or implement complex looping.
			# For now, if looping, disable schedule stop.
			if not is_looping:
				_schedule_stop(player, clip_data)
	
	# Connect Signals based on Loop
	if is_looping:
		player.finished.connect(_on_loop_finished.bind(player, start_offset))
	elif res.loop:
		var current_stream_name = player.stream.resource_path.get_file() if player.stream else "None"
		player.finished.connect(_on_playlist_loop.bind(player, res, volume_offset, owner))
	else:
		player.finished.connect(_on_stream_finished.bind(player))

	player.play(start_offset)
	# _playback_history.append(player) # Removed

func _on_loop_finished(player: Node, start_offset: float):
	if is_instance_valid(player):
		# call_deferred is safer when restarting from 'finished' signal
		player.call_deferred("play", start_offset)

func _on_playlist_loop(player: Node, res: SoundData, vol_offset: float = 0.0, owner: Node = null):
	if is_instance_valid(player):
		# Use call_deferred to ensure the audio engine has finished its current cycle
		_play_stream_on_player.call_deferred(player, res, null, vol_offset, owner)

## Manually stops a specific sound instance and cleans up its polyphony slot.
## [br][br]
## [b]Example Usage:[/b]
## [codeblock]
## var player = AudioManager.play_global(Sounds.AMBIENCE)
## # ... later ...
## AudioManager.stop_playing(player)
## [/codeblock]
func stop_playing(player: Node):
	if is_instance_valid(player):
		player.stop()
		_cleanup_player(player)

## Centralized cleanup to prevent polyphony leaks.
func _cleanup_player(player: Node):
	if _player_to_data.has(player):
		var data = _player_to_data[player]
		if data:
			_decrement_instance(data)
		_player_to_data.erase(player)
	
	if _player_to_hook.has(player):
		var hook = _player_to_hook[player]
		if is_instance_valid(hook):
			hook.player = null # Prevent hook from stopping the player on exit during cleanup
			hook.queue_free()
		_player_to_hook.erase(player)
	
	if player.finished.get_connections().size() > 0:
		for connection in player.finished.get_connections():
			player.finished.disconnect(connection.callable)
			
	# FIX WEB: Limpiar stream inmediatamente en Web, con timer en Desktop
	if OS.get_name() == "Web":
		if is_instance_valid(player):
			player.stream = null
	else:
		get_tree().create_timer(1.0).timeout.connect(func(): 
			if is_instance_valid(player) and not player.playing:
				player.stream = null
		)

func _on_stream_finished(player: Node) -> void:
	_cleanup_player(player)

# Removed _on_owner_exited in favor of _AudioLifetimeHook

func _stop_all_instances_of(data: SoundData):
	for player in _player_to_data:
		if _player_to_data[player] == data:
			stop_playing(player)

func _get_active_player_of(data: SoundData) -> Node:
	for p in _player_to_data:
		if _player_to_data[p] == data:
			return p
	return null

func _schedule_stop(player: Node, clip_data: AudioClip):
	var duration = clip_data.get_length()
	if clip_data.end_time > 0:
		duration = clip_data.end_time - clip_data.start_time
		
	# Subtract fade out time to start fading before end
	var fade_start_delay = duration - clip_data.fade_out
	if fade_start_delay < 0: fade_start_delay = 0
	
	if clip_data.fade_out > 0:
		var t = get_tree().create_timer(fade_start_delay)
		t.timeout.connect(func():
			if is_instance_valid(player) and player.playing:
				var tween = create_tween()
				
				# Determine Easing
				var ease_type = Tween.EASE_IN
				if clip_data.fade_out_curve > 1.0: ease_type = Tween.EASE_OUT # Inverted logic for Fade Out feeling?
				elif clip_data.fade_out_curve < 1.0: ease_type = Tween.EASE_IN
				
				tween.set_trans(Tween.TRANS_EXPO)
				tween.set_ease(ease_type)
				
				tween.tween_property(player, "volume_db", -80.0, clip_data.fade_out)
				tween.tween_callback(player.stop)
		)
	elif clip_data.end_time > 0:
		# Hard stop at trim end
		get_tree().create_timer(duration).timeout.connect(func():
			if is_instance_valid(player): player.stop()
		)

func _select_clip(data: SoundData):
	# Select Clip
	var _clip: AudioStream
	
	if data.clips.is_empty():
		return null
	elif data.clips.size() == 1:
		# Optimization: Skip logic for single clips
		return data.clips[0]
	else:
		return _get_next_clip(data)

func _get_next_clip(data: SoundData) -> Resource:
	# Initialize history if missing
	if not _playback_history.has(data):
		_playback_history[data] = {"last_indices": [], "seq_index": 0}
		
	var history = _playback_history[data]
	var index = 0
	
	match data.shuffle_mode:
		SoundData.ShuffleMode.SEQUENTIAL:
			index = history.seq_index % data.clips.size()
			history.seq_index += 1
			
		SoundData.ShuffleMode.RANDOM_NO_REPEAT:
			var available_indices = []
			# Ensure we don't prevent more sounds than we have (must leave at least 1)
			# Standard behavior: avoid 'repeat_prevention' last sounds.
			var prevent_count = clampi(data.repeat_prevention, 1, data.clips.size() - 1)
			
			for i in range(data.clips.size()):
				if not i in history.last_indices:
					available_indices.append(i)
			
			if available_indices.is_empty():
				# Fallback if history somehow blocked everything (should be handled by clamp above)
				var last = history.last_indices.back() if not history.last_indices.is_empty() else -1
				for i in range(data.clips.size()):
					if i != last or data.clips.size() == 1:
						available_indices.append(i)
			
			index = available_indices.pick_random()
			
			# Update history
			history.last_indices.append(index)
			while history.last_indices.size() > prevent_count:
				history.last_indices.pop_front()
				
		SoundData.ShuffleMode.RANDOM:
			index = randi() % data.clips.size()
			
	return data.clips[index]

## Returns an available player from the pool or creates a new one.
func _get_idle_player(is_3d: bool, is_2d: bool = false) -> Node:
	var pool = _players_3d_pool if is_3d else (_players_2d_pool if is_2d else _players_pool)
	
	for player in pool:
		if not player.playing:
			return player
			
	# If no idle player, expand pool
	return _add_player_to_pool(is_3d, is_2d)

## adds a new player to the pool.
func _add_player_to_pool(is_3d: bool, is_2d: bool = false) -> Node:
	var player
	if is_3d:
		player = AudioStreamPlayer3D.new()
		player.attenuation_filter_cutoff_hz = 20500 # Disable LPF (set to max human hearing)
		player.attenuation_filter_db = 0 # No volume drop due to filter
		_players_3d_pool.append(player)
	elif is_2d:
		player = AudioStreamPlayer2D.new()
		_players_2d_pool.append(player)
	else:
		player = AudioStreamPlayer.new()
		_players_pool.append(player)
		
	add_child(player)
	return player

## Decrements the active instance count for the sound.
func _decrement_instance(data: SoundData) -> void:
	if not data or data.slug.is_empty(): return
	if _active_instances.has(data.slug):
		_active_instances[data.slug] = max(0, _active_instances[data.slug] - 1)
		
## Increments the active instance count for the sound.
func _track_instance(data: SoundData) -> void:
	if not data or data.slug.is_empty(): return
	if not _active_instances.has(data.slug):
		_active_instances[data.slug] = 0
	_active_instances[data.slug] += 1

## Loads a [SoundBank] into active memory, making its sounds available for playback.
## [br][br]
## Uses a reference counter, so multiple calls to load the same bank will require an 
## equal number of [method unload_bank] calls to truly remove it from RAM.
## [br][br]
## [b]Example Usage:[/b]
## [codeblock]
## # Load bank on scene start
## AudioManager.load_bank(level_1_sounds)
## [/codeblock]
func load_bank(bank: SoundBank) -> void:
	if not bank: return
	if _loaded_banks.has(bank):
		_loaded_banks[bank] += 1
	else:
		_loaded_banks[bank] = 1
		for s in bank.sounds:
			if s: _available_sounds[s.slug] = true

## Unloads a [SoundBank] from memory, decrementing its reference count.
## [br][br]
## If the reference count reaches zero, all sounds belonging exclusively to this 
## bank will be blocked from playing (STRICT MODE) and RAM will be freed.
## [br][br]
## [b]Example Usage:[/b]
## [codeblock]
## # Unload bank on scene exit
## AudioManager.unload_bank(level_1_sounds)
## [/codeblock]
func unload_bank(bank: SoundBank) -> void:
	if not bank: return
	if _loaded_banks.has(bank):
		_loaded_banks[bank] -= 1
		if _loaded_banks[bank] <= 0:
			_loaded_banks.erase(bank)
			
			# Stop all sounds from this bank that have BANK lifetime
			for player in _player_to_data.keys():
				var data = _player_to_data[player]
				if data in bank.sounds and data.lifetime == SoundData.Lifetime.BANK:
					stop_playing(player)
					
			recalc_available_sounds()

func recalc_available_sounds() -> void:
	_available_sounds.clear()
	for b in _loaded_banks:
		for s in b.sounds:
			if s: _available_sounds[s.slug] = true
#endregion

# Internal hook to track node lifetimes without signal pollution
class _AudioLifetimeHook extends Node:
	var player: Node
	func _exit_tree():
		var am = get_node_or_null("/root/AudioManager")
		if am and is_instance_valid(player):
			am.stop_playing(player)
