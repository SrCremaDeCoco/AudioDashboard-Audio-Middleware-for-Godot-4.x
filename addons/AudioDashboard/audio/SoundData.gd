## A resource representing an "Atomized Sound" in the AudioDashboard system.
##
## [SoundData] is the core configuration unit for audio. It decouples the game logic 
## from specific audio files by using a [member slug] and allows for complex playback 
## behaviors like randomization, sequential playback, and distance-based 3D audio.
## [br][br]
## [b]Note:[/b] [SoundData] resources are typically managed via the AudioDashboard editor tab.
@icon("res://addons/AudioDashboard/icons/audio_icon.png")
@tool
class_name SoundData
extends Resource

#region Configuration
@export_group("Management")
## Unique identifier used to trigger this sound from code.
## [br][br]
## [b]Example:[/b] [code]AudioManager.play_global("ui_click")[/code]
@export var slug: String = ""

@export_group("Audio Config")
## The list of audio clips to play. Can contain [AudioStream] (basic) or [AudioClip] (advanced).
@export var clips: Array[Resource] = []
## Overall volume offset in decibels. This value is added to the individual clip's volume.
@export_range(-80, 24) var volume_db: float = 0.0
## Base playback speed/pitch. 1.0 is normal.
@export_range(0.1, 4.0) var pitch_scale: float = 1.0
## Maximum random variation applied to the pitch on each play (e.g. 0.1 means +/- 0.1).
@export_range(0.0, 1.0) var pitch_randomness: float = 0.0

@export_group("3D Settings")
## Maximum distance (in meters) at which the sound is audible. Set to 0 for infinite distance.
@export var max_distance: float = 0.0 
## The mathematical model used to calculate volume drop over distance in 3D space.
@export var attenuation_model: AudioStreamPlayer3D.AttenuationModel = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
## Controls how much the sound pans across the stereo field based on its 3D position.
@export_range(0.0, 3.0) var panning_strength: float = 1.0

@export_group("Playback Behavior")
## Determines how a clip is selected from the [member clips] array.
enum ShuffleMode {
	RANDOM, ## Picks a clip at random on every play.
	SEQUENTIAL, ## Plays clips in the order they appear in the array.
	RANDOM_NO_REPEAT ## Random selection that avoids repeating the last X clips.
}
@export var shuffle_mode: ShuffleMode = ShuffleMode.RANDOM
## Number of previous clips to keep in memory to avoid immediate repetition (only used by [constant RANDOM_NO_REPEAT]).
@export var repeat_prevention: int = 1
## If enabled, the playlist or the single clip will restart automatically once it finishes.
@export var loop: bool = false

## Defines the automatic cleanup behavior of the sound instance.
enum Lifetime { 
	GLOBAL, ## Sound persists until it finishes normally or is manually stopped.
	SCENE, ## Sound is automatically stopped when the current scene changes.
	BANK ## Sound is automatically stopped when its source [SoundBank] is unloaded.
}
@export_group("Lifetime & Cleanup")
## Determines when the sound should be forcefully stopped by the [AudioManager].
@export var lifetime: Lifetime = Lifetime.SCENE
## If enabled, only one instance of this [SoundData] can play at any given time.
@export var is_unique: bool = false
## If [member is_unique] is enabled, determines if calling play again restarts the sound or lets it continue.
@export var restart_if_playing: bool = true

## The name of the [AudioBus] where this sound will be routed.
@export var bus: String = "Master"

@export_group("Management")
## Optional tag used to group and filter sounds within the AudioDashboard UI.
@export var group_tag: String = "Default"
## Limits how many instances of this specific sound can play simultaneously to prevent audio saturation.
@export var max_polyphony: int = 5
#endregion

#region Runtime Logic
## returning a random clip from the array.
func get_clip() -> Resource:

	if clips.is_empty(): return null
	return clips.pick_random()

## returning the pitch with applied randomness.
func get_pitch() -> float:
	if pitch_randomness <= 0: return pitch_scale
	return pitch_scale + randf_range(-pitch_randomness, pitch_randomness)
#endregion
