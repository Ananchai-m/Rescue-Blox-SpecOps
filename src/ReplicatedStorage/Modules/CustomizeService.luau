-- CustomizeService Module
-- จัดการการสื่อสารระหว่าง Client และ Server สำหรับ Customize

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CustomizeService = {}

local IS_SERVER = RunService:IsServer()
local IS_CLIENT = RunService:IsClient()

-- RemoteEvent สำหรับ save equipped items
local SaveEquipmentEvent: RemoteEvent?
local GetEquipmentFunction: RemoteFunction?

-- Initialize remotes
local function initializeRemotes()
	if IS_SERVER then
		-- สร้าง RemoteEvent ถ้ายังไม่มี
		SaveEquipmentEvent = ReplicatedStorage:FindFirstChild("SaveEquipment") :: RemoteEvent
		if not SaveEquipmentEvent then
			SaveEquipmentEvent = Instance.new("RemoteEvent")
			SaveEquipmentEvent.Name = "SaveEquipment"
			SaveEquipmentEvent.Parent = ReplicatedStorage
		end

		GetEquipmentFunction = ReplicatedStorage:FindFirstChild("GetEquipment") :: RemoteFunction
		if not GetEquipmentFunction then
			GetEquipmentFunction = Instance.new("RemoteFunction")
			GetEquipmentFunction.Name = "GetEquipment"
			GetEquipmentFunction.Parent = ReplicatedStorage
		end
	else
		-- Client รอให้ RemoteEvent ถูกสร้าง
		SaveEquipmentEvent = ReplicatedStorage:WaitForChild("SaveEquipment", 10) :: RemoteEvent
		GetEquipmentFunction = ReplicatedStorage:WaitForChild("GetEquipment", 10) :: RemoteFunction
	end
end

initializeRemotes()

-- CLIENT: บันทึก equipped items ไปยัง server
function CustomizeService.saveEquippedItems(equippedItems: {{id: string, row: number, column: number}})
	if not IS_CLIENT then
		warn("[CustomizeService] saveEquippedItems can only be called from client")
		return
	end

	if not SaveEquipmentEvent then
		warn("[CustomizeService] SaveEquipment event not found")
		return
	end

	print("[CustomizeService] Saving equipped items:", equippedItems)
	SaveEquipmentEvent:FireServer(equippedItems)
end

-- CLIENT: ดึงรายการ equipped items จาก server
function CustomizeService.getEquippedItems(): {{id: string, row: number, column: number}}?
	if not IS_CLIENT then
		warn("[CustomizeService] getEquippedItems can only be called from client")
		return nil
	end

	if not GetEquipmentFunction then
		warn("[CustomizeService] GetEquipment function not found")
		return nil
	end

	local success, result = pcall(function()
		return GetEquipmentFunction:InvokeServer()
	end)

	if success then
		return result
	else
		warn("[CustomizeService] Failed to get equipped items:", result)
		return nil
	end
end

-- SERVER: ตั้งค่า callback สำหรับรับ equipped items
function CustomizeService.onSaveEquipment(callback: (player: Player, equippedItems: {{id: string, row: number, column: number}}) -> ())
	if not IS_SERVER then
		warn("[CustomizeService] onSaveEquipment can only be called from server")
		return
	end

	if not SaveEquipmentEvent then
		warn("[CustomizeService] SaveEquipment event not found")
		return
	end

	SaveEquipmentEvent.OnServerEvent:Connect(callback)
end

-- SERVER: ตั้งค่า callback สำหรับส่ง equipped items กลับ
function CustomizeService.onGetEquipment(callback: (player: Player) -> {{id: string, row: number, column: number}}?)
	if not IS_SERVER then
		warn("[CustomizeService] onGetEquipment can only be called from server")
		return
	end

	if not GetEquipmentFunction then
		warn("[CustomizeService] GetEquipment function not found")
		return
	end

	GetEquipmentFunction.OnServerInvoke = callback
end

return CustomizeService
