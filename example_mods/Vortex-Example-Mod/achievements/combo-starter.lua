function goodNoteHit(id, direction, noteType, isSustain)
	if botPlay then return end
	if getProperty('combo') >= 20 then
		unlockAchievement(achievementId)
	end
end
