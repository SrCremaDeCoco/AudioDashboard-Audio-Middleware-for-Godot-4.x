## A collection of [SoundData] resources grouped for memory management.
##
## SoundBanks are the primary way to manage RAM usage in the AudioDashboard system. 
## By grouping sounds into banks (e.g. "Level1_Bank", "Generic_UI_Bank"), you can 
## ensure that only the necessary audio data is loaded into memory at any given time.
## [br][br]
## [b]Recommended Workflow:[/b]
## [codeblock]
## # In a level's _ready() function:
## func _ready():
##     AudioManager.load_bank(level_bank)
##
## # In the level's _exit_tree() or before changing scenes:
## func _exit_tree():
##     AudioManager.unload_bank(level_bank)
## [/codeblock]
@icon("res://addons/AudioDashboard/icons/bank_icon.png")
@tool
class_name SoundBank
extends Resource

## The list of [SoundData] resources contained in this bank.
@export var sounds: Array[SoundData] = []
