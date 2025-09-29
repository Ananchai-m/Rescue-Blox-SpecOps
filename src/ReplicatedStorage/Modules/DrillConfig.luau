-- Drilling system configuration
-- Shared constants between client and server

local DrillConfig = {}

-- Drilling constants
DrillConfig.CLICKS_REQUIRED = 10 -- จำนวนครั้งที่ต้องคลิกเพื่อทำลาย Motor6D
DrillConfig.DETECTION_RANGE = 10 -- ระยะการตรวจสอบ BasePart รอบๆ ตำแหน่งที่คลิก (Client)
DrillConfig.TARGET_RADIUS = 6 -- ระยะการตรวจสอบใน Server
DrillConfig.HIDE_DELAY = 1.25 -- เวลารอก่อนซ่อน UI (วินาที)

return DrillConfig
