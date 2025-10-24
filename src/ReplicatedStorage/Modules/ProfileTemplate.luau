--!strict
-- ProfileTemplate.luau
-- กำหนดโครงสร้างข้อมูล PlayerProfile เริ่มต้น

export type MissionState = "locked" | "active" | "cleared"

export type Mission = {
	state: MissionState,
	bestTime: number?
}

export type InventoryItem = {
	id: string,
	slotCost: number,
	tier: number,
	uses: number?
}

export type EquippedItem = {
	id: string,
	row: number,
	column: number,
	color: { r: number, g: number, b: number }?
}

export type PlayerProfile = {
	meta: {
		version: number,
		createdAt: number,
		lastSeenAt: number,
		hasWatchedIntro: boolean?
	},
	identity: {
		userId: number,
		name: string,
		displayName: string?
	},
	progression: {
		level: number,
		xp: number,
		missions: { [string]: Mission }
	},
	stats: {
		totalRescued: number,
		deaths: number,
		revivesByFriend: number,
		revivesPurchased: number,
		bestTimePerBuilding: { [string]: number },
		bestBuilding: string?,
		coins: number
	},
	bot: {
		colors: { [string]: { r: number, g: number, b: number } },
		slotsUnlocked: number,
		inventory: {
			owned: { [string]: InventoryItem },
			equipped: { EquippedItem }
		}
	},
	monetization: {
		gamepasses: { [number]: boolean },
		devProducts: {
			receipts: { string },
			quickRespawnCount: number
		}
	}
}

local ProfileTemplate = {}

function ProfileTemplate.new(player: Player): PlayerProfile
	local now = os.time()

	return {
		meta = {
			version = 1,
			createdAt = now,
			lastSeenAt = now,
			hasWatchedIntro = false
		},
		identity = {
			userId = player.UserId,
			name = player.Name,
			displayName = player.DisplayName
		},
		progression = {
			level = 1,
			xp = 0,
			missions = {}
		},
		stats = {
			totalRescued = 0,
			deaths = 0,
			revivesByFriend = 0,
			revivesPurchased = 0,
			bestTimePerBuilding = {},
			bestBuilding = nil,
			coins = 0
		},
		bot = {
			colors = {},
			slotsUnlocked = 8,
			inventory = {
				owned = {
					-- Starter items
					SolarCell = {
						id = "SolarCell",
						slotCost = 2,
						tier = 1,
						uses = nil
					},
					ThermometerCamera = {
						id = "ThermometerCamera",
						slotCost = 1,
						tier = 1,
						uses = nil
					},
					Zoom3x5xCamera = {
						id = "Zoom3x5xCamera",
						slotCost = 1,
						tier = 1,
						uses = nil
					}
				},
				equipped = {}
			}
		},
		monetization = {
			gamepasses = {},
			devProducts = {
				receipts = {},
				quickRespawnCount = 0
			}
		}
	}
end

return ProfileTemplate
