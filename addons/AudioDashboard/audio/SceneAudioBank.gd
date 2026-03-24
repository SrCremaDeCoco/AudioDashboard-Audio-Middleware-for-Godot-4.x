@icon("res://addons/AudioDashboard/icons/audio_icon.png")
class_name SceneAudioBank

extends Node

## Automatically loads and unloads a SoundBank into RAM using the AudioManager.
## Place this in scenes where specific sounds are required.

enum LoadTrigger {ON_ENTER_TREE, MANUAL}
enum UnloadTrigger {ON_EXIT_TREE, MANUAL}

@export var bank: SoundBank
@export var load_trigger: LoadTrigger = LoadTrigger.ON_ENTER_TREE
@export var unload_trigger: UnloadTrigger = UnloadTrigger.ON_EXIT_TREE

func _enter_tree() -> void:
	if load_trigger == LoadTrigger.ON_ENTER_TREE:
		if OS.get_name() == "Web":
			await get_tree().process_frame
		load_bank()

func _exit_tree() -> void:
	if unload_trigger == UnloadTrigger.ON_EXIT_TREE:
		unload_bank()

func load_bank() -> void:
	if bank and AudioManager.has_method("load_bank"):
		AudioManager.load_bank(bank)

func unload_bank() -> void:
	if bank and AudioManager.has_method("unload_bank"):
		AudioManager.unload_bank(bank)
