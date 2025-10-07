-- SharedProfileService
-- Shared ProfileService instance สำหรับทุก server scripts

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProfileService = require(ReplicatedStorage.Modules.ProfileService)

-- สร้าง ProfileService instance เพียงครั้งเดียว
local sharedProfileService = ProfileService.new()

return sharedProfileService
