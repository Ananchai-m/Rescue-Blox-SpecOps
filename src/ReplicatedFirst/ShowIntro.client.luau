--[[
	ShowIntro Client Script
	เรียกใช้ VideoIntro Module เพื่อแสดงวิดีโอตอนเข้าเกม
]]

local ReplicatedFirst = game:GetService("ReplicatedFirst")

-- โหลด VideoIntro Module
local VideoIntro = require(ReplicatedFirst:WaitForChild("VideoIntro"))

-- แสดงวิดีโอ ID: 5670824523
print("[ShowIntro] Starting video intro")
VideoIntro.Show(121639450792688)
