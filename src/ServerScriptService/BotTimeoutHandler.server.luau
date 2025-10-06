--!strict
-- BotTimeoutHandler.server.luau
-- รับ event เมื่อ RescueBot timeout (HP = 0 เกิน 30 วินาที) และแสดงสรุปคะแนน

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameSummary = require(ReplicatedStorage.Modules.GameSummary)

-- รอ RemoteEvent
local remoteEvents = ReplicatedStorage:WaitForChild("RescueBotRemotes")
local botTimeoutEvent = remoteEvents:WaitForChild("BotTimeout")

botTimeoutEvent.OnServerEvent:Connect(function(player)
	print(`[BotTimeoutHandler] Player {player.Name} timeout - showing summary`)

	-- Setup callback เพื่อพาผู้เล่นกลับ lobby เมื่อปิด summary
	local originalCallback = GameSummary.onSummaryClosed

	GameSummary.onSummaryClosed = function(closedPlayer)
		if closedPlayer == player then
			-- พาผู้เล่นกลับ lobby
			GameSummary.resetToLobby(player)
			print(`[BotTimeoutHandler] Player {player.Name} returned to lobby`)

			-- คืนค่า callback เดิม
			GameSummary.onSummaryClosed = originalCallback
		elseif originalCallback then
			-- เรียก callback เดิมสำหรับผู้เล่นคนอื่น
			originalCallback(closedPlayer)
		end
	end

	-- แสดงสรุปคะแนน
	GameSummary.showSummary(player)
end)

print("[BotTimeoutHandler] Initialized")
