Psych's mods/ folder.

If you're a beginner, we recommend you extract modTemplate.zip to get started on developing your mod.
Read the Psych GitHub wiki here:
https://github.com/ShadowMario/FNF-PsychEngine/wiki
Read the Lua Script API here:
https://shadowmario.github.io/psychengine.lua/

You can also add or edit specific files without the mod template, you just have to re-create the path to said file.

ABOUT EDITING:
If you want to change something, for example, within assets/shared/images or assets/base_game/images,
said edited files *must* be put in mods/images, the engine will handle the rest.

vortex stuff:
each mod goes in its own folder like mods/My-Mod/ (Vortex-Example-Mod is one you can look at)
song audio goes in mods/My-Mod/songs/<song>/ - Inst.ogg plus Voices.ogg, or Voices-Player.ogg and Voices-Opponent.ogg. .wav works too, .mp3 doesnt
the chart goes in mods/My-Mod/data/<song>/<song>.json
you dont need a week file, songs without one still show up
the game writes vortex_mods_log.txt next to the exe every time it starts, check it if your mod isnt showing up
