## A container for a specific audio stream with custom playback parameters.
##
## [AudioClip] allows for fine-tuning individual variations of a [SoundData]. 
## It supports non-destructive trimming, volume offsets per-clip, and 
## procedurally-controlled fades.
@tool
class_name AudioClip
extends Resource

## The raw [AudioStream] (WAV, MP3, OGG) to be played.
@export var stream: AudioStream

@export_group("Playback")
## Volume adjustment (dB) specific to this clip. Added to the parent [member SoundData.volume_db].
@export_range(-80, 24) var volume_offset: float = 0.0
## Duration of the initial fade-in (in seconds).
@export_range(0, 10) var fade_in: float = 0.0
## The exponent of the fade-in easing curve (1.0 = Linear).
@export_range(0.1, 5.0) var fade_in_curve: float = 1.0

## Duration of the final fade-out (in seconds). Triggers before the clip ends or at [member end_time].
@export_range(0, 10) var fade_out: float = 0.0
## The exponent of the fade-out easing curve (1.0 = Linear).
@export_range(0.1, 5.0) var fade_out_curve: float = 1.0

@export_group("Trim")
## The timestamp (in seconds) where playback begins.
@export var start_time: float = 0.0
## The timestamp (in seconds) where playback stops. Set to 0 to play until the end of the file.
@export var end_time: float = 0.0

@export_group("Advanced")
## If enabled, this individual clip will loop indefinitely.
@export var loop: bool = false
## Probability factor for random selection. Clips with higher weight are picked more often.
@export_range(0.0, 100.0) var random_weight: float = 1.0

func get_length() -> float:
	if stream:
		return stream.get_length()
	return 0.0
