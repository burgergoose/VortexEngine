achievements

easiest way is the achievement editor: main menu, press 7, Achievement Editor (pick your mod with left/right first)

each achievement is named after its id (lowercase letters, numbers, - and _):
<id>.json - name, description and how you unlock it (the editor makes this one)
<id>.png - the icon, 150x150 looks best (optional)
<id>.lua or <id>.hx - runs in every song while its still locked (optional)

unlock types:
manual - only a script can unlock it, with unlockAchievement(achievementId)
song_complete - beat "song" (leave it empty for any song)
week_complete - beat the last song of "week" in story mode

you can also set maxMisses (-1 for any), minAccuracy (0-100), minScore and allowPractice.
"maxScore": 3 makes it a progress one, every finish counts as 1.
botplay and the chart editor dont unlock anything.

the psych way (data/achievements.json) still works too.
