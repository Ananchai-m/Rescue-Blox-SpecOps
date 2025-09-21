---
description: |
  # Roblox Game Rules for Cursor (Luau/Roblox Studio)

  ## เป้าหมาย
  - ให้ Cursor สร้างโค้ด Luau ที่รันได้จริงใน Roblox Studio
  - หลีกเลี่ยง UnknownGlobal (เรียกใช้ก่อนประกาศ)
  - โค้ดทั้งหมดต้องประกาศ local ก่อนใช้งานเสมอ
  - แยก Client / Server / Shared ให้ชัดเจน
  - ใช้ ModuleScript สำหรับ logic ที่แชร์ซ้ำ
  - Debug print ห้ามใส่ emoji

  ## โครงสร้างโปรเจกต์
  - ReplicatedStorage
    - Modules/
    - SharedTypes/
    - RemoteEvents/
      - Events/ (RemoteEvent)
      - Functions/ (RemoteFunction)
    - Bindables/ (BindableEvent/BindableFunction ใช้ร่วมกัน Client+Server)
    - GameConfig.lua
  - ServerScriptService
    - GameInit.server.lua
    - Systems/
  - StarterPlayer
    - StarterPlayerScripts/
      - ClientMain.client.lua
      - UI/
  - StarterGui
    - Screens/
  - ServerStorage
    - PrivateAssets/

  ## มาตรฐานการเขียนโค้ด
  - ใช้ `local` เสมอ
  - ดึง Service ผ่าน `game:GetService` ด้านบนไฟล์
  - ประกาศฟังก์ชัน/โมดูลก่อนใช้งาน
  - ตั้งชื่อสื่อความหมาย เช่น `InventorySystem`, `DialogController`
  - ใช้ `task.wait()` แทน `wait()`
  - DataStore ต้องใช้ `pcall` เสมอ (หรือ ProfileService)
  - ห้ามทำงานหนักใน Heartbeat/RenderStepped โดยไม่จำเป็น

  ## UI & Responsive
  - ใช้ `UDim2.fromScale()` สำหรับ `Size` และ `Position` แทน Offset
  - ใช้ `UIPadding`, `UIListLayout.Padding` เป็น `UDim.new(scale, 0)`
  - ใช้ `UIAspectRatioConstraint` เพื่อคงอัตราส่วน
  - ใช้ `AutomaticSize` สำหรับเนื้อหาที่เปลี่ยนแปลง
  - ใช้ `TextScaled` + `UITextSizeConstraint` (Min/Max)
  - ScrollingFrame ควรตั้ง `AutomaticCanvasSize` แทนการคำนวณเอง
  - หลีกเลี่ยงการอ่าน `AbsoluteSize` ทุกเฟรม (debounce ถ้าจำเป็น)

  ## Networking
  - **RemoteEvent**: Client ↔ Server (async) → default
  - **RemoteFunction**: Client ↔ Server (sync) → ใช้เท่าที่จำเป็น พร้อม timeout
  - **BindableEvent**: ภายในฝั่งเดียวกัน (async)
  - **BindableFunction**: ภายในฝั่งเดียวกัน (sync, ห้าม yield)
  - วาง Remote ที่ `ReplicatedStorage/RemoteEvents`
  - วาง Bindable ที่ `ReplicatedStorage/Bindables`

  ### DO
  - อ้างอิง instance ก่อนใช้เสมอ
  - Validate input ฝั่ง Server ทุกครั้ง
  - ใส่ cooldown/anti-spam
  - ใช้ RemoteEvent + callback แทน RemoteFunction ถ้าไม่เร่งด่วน

  ### DON'T
  - ❌ ใช้ Bindable* ข้าม Client ↔ Server นอก `ReplicatedStorage`
  - ❌ ทำงานหนักใน RemoteFunction/BindableFunction
  - ❌ ใช้ emoji ใน print()

  ## Debug / Logging
  - ใช้ `print()`, `warn()`, `error()` แบบไม่มี emoji
  - รูปแบบแนะนำ:  
    print("[System] message ...")  
    warn("[DataStore] Save failed")

globs:
  - "**/*.lua"
  - "default"

alwaysApply: true
