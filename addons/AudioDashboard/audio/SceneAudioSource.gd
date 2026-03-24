@icon("res://addons/AudioDashboard/icons/audio_icon.png")
class_name SceneAudioSource

extends Node3D

## The sound data to play.
@export var sound_data: SoundData
## Whether to play automatically on ready.
@export var autoplay: bool = true
## If true, ignores 3D position (good for Music/UI).
@export var is_global: bool = false
## Fade in time (override). -1 uses data settings.
@export var fade_in_time: float = -1.0

var _player: Node = null

func _ready() -> void:
	if autoplay and sound_data:
		play()

func play() -> void:
	if not sound_data: return
	
	if is_global:
		_player = AudioManager.play_global(sound_data)
	else:
		_player = AudioManager.play_at_position(sound_data, global_position)
		
	# Apply override if needed (though AudioManager usually handles fades from AudioClip)
	# If we wanted to force a fade in from scene settings, we'd need to tween volume here
	# but AudioManager returns the player already playing.
	# Trust SoundData processing in AudioManager


func stop() -> void:
	if is_instance_valid(_player):
		AudioManager.stop_playing(_player)
		_player = null
