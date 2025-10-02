--!strict
-- Sound Manager Module
-- Manages all game sounds with easy-to-use functions

local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local SoundManager = {}

-- Sound Library - เพิ่ม Sound IDs ที่ต้องการใช้ที่นี่
local SOUNDS = {
	-- Coin & Rewards
	CoinCollect = "rbxassetid://4612377122",
	CoinBurst = "rbxassetid://4612377122",

	-- UI Sounds
	ButtonClick = "rbxassetid://3398620867",
	ButtonHover = "rbxassetid://3398620867",
	MenuOpen = "rbxassetid://3398620867",
	MenuClose = "rbxassetid://3398620867",

	-- Game Sounds
	VictimRescued = "rbxassetid://3398620867",
	DrillHit = "rbxassetid://3398620867",
	DrillComplete = "rbxassetid://3398620867",
	Explosion = "rbxassetid://3398620867",

	-- Feedback
	Success = "rbxassetid://3398620867",
	Error = "rbxassetid://3398620867",
	Warning = "rbxassetid://3398620867",
}

-- Default sound properties
local DEFAULT_VOLUME = 0.5
local DEFAULT_PLAYBACK_SPEED = 1
local DEFAULT_ROLLOFF = 10

-- Play sound at a specific position in the world (3D sound)
function SoundManager.PlaySoundAt(soundName: string, position: Vector3, volume: number?, playbackSpeed: number?): Sound?
	local soundId = SOUNDS[soundName]
	if not soundId then
		warn("Sound not found:", soundName)
		return nil
	end

	-- Create invisible part at position for 3D sound
	local soundPart = Instance.new("Part")
	soundPart.Size = Vector3.new(0.1, 0.1, 0.1)
	soundPart.Position = position
	soundPart.Transparency = 1
	soundPart.CanCollide = false
	soundPart.Anchored = true
	soundPart.Parent = workspace

	-- Create sound
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or DEFAULT_VOLUME
	sound.PlaybackSpeed = playbackSpeed or DEFAULT_PLAYBACK_SPEED
	sound.RollOffMaxDistance = DEFAULT_ROLLOFF
	sound.Parent = soundPart

	-- Play and cleanup
	sound:Play()

	-- Wait for sound to finish then destroy
	task.delay(sound.TimeLength / sound.PlaybackSpeed + 0.1, function()
		soundPart:Destroy()
	end)

	return sound
end

-- Play sound at a part's position
function SoundManager.PlaySoundAtPart(soundName: string, part: BasePart, volume: number?, playbackSpeed: number?): Sound?
	if not part then
		warn("Part is nil for sound:", soundName)
		return nil
	end

	return SoundManager.PlaySoundAt(soundName, part.Position, volume, playbackSpeed)
end

-- Play global sound (2D, no 3D position)
function SoundManager.PlaySound(soundName: string, volume: number?, playbackSpeed: number?, parent: Instance?): Sound?
	local soundId = SOUNDS[soundName]
	if not soundId then
		warn("Sound not found:", soundName)
		return nil
	end

	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or DEFAULT_VOLUME
	sound.PlaybackSpeed = playbackSpeed or DEFAULT_PLAYBACK_SPEED
	sound.Parent = parent or SoundService

	sound:Play()
	Debris:AddItem(sound, sound.TimeLength / sound.PlaybackSpeed + 0.1)

	return sound
end

-- Play sound by direct asset ID (สำหรับเสียงพิเศษที่ไม่อยู่ใน library)
function SoundManager.PlaySoundById(soundId: string, position: Vector3?, volume: number?, playbackSpeed: number?): Sound?
	if not soundId or soundId == "" then
		warn("Invalid sound ID")
		return nil
	end

	-- Add rbxassetid:// prefix if not present
	if not string.match(soundId, "rbxassetid://") then
		soundId = "rbxassetid://" .. soundId
	end

	if position then
		-- 3D Sound
		local soundPart = Instance.new("Part")
		soundPart.Size = Vector3.new(0.1, 0.1, 0.1)
		soundPart.Position = position
		soundPart.Transparency = 1
		soundPart.CanCollide = false
		soundPart.Anchored = true
		soundPart.Parent = workspace

		local sound = Instance.new("Sound")
		sound.SoundId = soundId
		sound.Volume = volume or DEFAULT_VOLUME
		sound.PlaybackSpeed = playbackSpeed or DEFAULT_PLAYBACK_SPEED
		sound.RollOffMaxDistance = DEFAULT_ROLLOFF
		sound.Parent = soundPart

		sound:Play()

		task.delay(5, function() -- Max 5 seconds cleanup
			soundPart:Destroy()
		end)

		return sound
	else
		-- 2D Sound
		local sound = Instance.new("Sound")
		sound.SoundId = soundId
		sound.Volume = volume or DEFAULT_VOLUME
		sound.PlaybackSpeed = playbackSpeed or DEFAULT_PLAYBACK_SPEED
		sound.Parent = SoundService

		sound:Play()
		Debris:AddItem(sound, 5) -- Max 5 seconds cleanup

		return sound
	end
end

-- Play looping background music
function SoundManager.PlayMusic(soundName: string, volume: number?, fadeIn: boolean?): Sound?
	local soundId = SOUNDS[soundName]
	if not soundId then
		warn("Music not found:", soundName)
		return nil
	end

	local music = Instance.new("Sound")
	music.Name = "BackgroundMusic_" .. soundName
	music.SoundId = soundId
	music.Volume = fadeIn and 0 or (volume or 0.3)
	music.Looped = true
	music.Parent = SoundService

	music:Play()

	-- Fade in effect
	if fadeIn then
		local targetVolume = volume or 0.3
		local fadeTime = 2
		local steps = 20
		local increment = targetVolume / steps

		for i = 1, steps do
			task.wait(fadeTime / steps)
			music.Volume = math.min(music.Volume + increment, targetVolume)
		end
	end

	return music
end

-- Stop music with optional fade out
function SoundManager.StopMusic(musicName: string?, fadeOut: boolean?)
	local musicToStop = {}

	if musicName then
		-- Stop specific music
		local music = SoundService:FindFirstChild("BackgroundMusic_" .. musicName)
		if music then
			table.insert(musicToStop, music)
		end
	else
		-- Stop all music
		for _, sound in ipairs(SoundService:GetChildren()) do
			if sound:IsA("Sound") and string.match(sound.Name, "BackgroundMusic_") then
				table.insert(musicToStop, sound)
			end
		end
	end

	for _, music in ipairs(musicToStop) do
		if fadeOut then
			-- Fade out
			local fadeTime = 1
			local steps = 20
			local startVolume = music.Volume
			local decrement = startVolume / steps

			task.spawn(function()
				for i = 1, steps do
					task.wait(fadeTime / steps)
					music.Volume = math.max(music.Volume - decrement, 0)
				end
				music:Stop()
				music:Destroy()
			end)
		else
			music:Stop()
			music:Destroy()
		end
	end
end

-- Get sound ID from library
function SoundManager.GetSoundId(soundName: string): string?
	return SOUNDS[soundName]
end

-- Add new sound to library dynamically
function SoundManager.AddSound(soundName: string, soundId: string)
	if not string.match(soundId, "rbxassetid://") then
		soundId = "rbxassetid://" .. soundId
	end
	SOUNDS[soundName] = soundId
	print("Added sound to library:", soundName, "=", soundId)
end

-- Check if sound exists in library
function SoundManager.HasSound(soundName: string): boolean
	return SOUNDS[soundName] ~= nil
end

-- Get all available sounds
function SoundManager.GetAllSounds(): {[string]: string}
	return SOUNDS
end

return SoundManager
