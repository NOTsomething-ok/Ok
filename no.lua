--[[
===============================================================
                    HAPPA TAS • MERGED
  FIRST SCRIPT UI + SAVE/LOAD/QUICK BUTTONS
  SECOND SCRIPT INPUT RECORD/PLAYBACK + FULL STOP
===============================================================

Core behavior:
  * UI/layout is based on the original HappaTAS script.
  * Recording stores controller input (move direction + jump), not
    character CFrames.
  * Playback injects the recorded input through PlayerModule's
    ControlModule when available, with Humanoid:Move() fallback.
  * ShiftLock detection uses UserGameSettings.ControlMode and the
    HappaTAS ShiftLock toggle can still be used visually.
  * Playback locks the camera to its starting CFrame.
  * FULL STOP clears recording/playback state, releases movement,
    disconnects playback/recording connections, and restores camera.
===============================================================
]]

----------------------------------------------------------------
-- SERVICES
----------------------------------------------------------------
local Players            = game:GetService("Players")
local UserInputService   = game:GetService("UserInputService")
local StarterGui         = game:GetService("StarterGui")
local HttpService        = game:GetService("HttpService")
local RunService         = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local UserGameSettings   = UserSettings():GetService("UserGameSettings")
local Workspace          = game:GetService("Workspace")

----------------------------------------------------------------
-- PLAYER
----------------------------------------------------------------
local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")
local Camera      = Workspace.CurrentCamera

pcall(function()
    StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.EmotesMenu, false)
end)

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local SAVE_FOLDER   = "HappaTAS"
local DISPLAY_ORDER = 9999
local MIN_SPEED     = 0.10
local MAX_SPEED     = 10
local DEFAULT_SPEED = 1
local UI_RATE       = 0.10
local SCRUB_BASE    = 20
local RECORD_HZ     = 20

----------------------------------------------------------------
-- GAME INFO
----------------------------------------------------------------
local GAME_ID   = tostring(game.PlaceId)
local GAME_NAME = tostring(game.Name)

task.spawn(function()
    pcall(function()
        local info = MarketplaceService:GetProductInfo(game.PlaceId)
        if info and type(info.Name) == "string" and info.Name ~= "" then
            GAME_NAME = info.Name
        end
    end)
end)

----------------------------------------------------------------
-- FILE API
----------------------------------------------------------------
local FILE_OK   = typeof(writefile) == "function" and typeof(readfile) == "function" and typeof(isfile) == "function"
local DELETE_OK = typeof(delfile) == "function"
local LIST_OK   = typeof(listfiles) == "function"
local MKDIR_OK  = typeof(makefolder) == "function"

if MKDIR_OK then pcall(function() makefolder(SAVE_FOLDER) end) end

----------------------------------------------------------------
-- CHARACTER
----------------------------------------------------------------
local Character
local Root
local Humanoid

local function BindCharacter()
    Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    Root      = Character:WaitForChild("HumanoidRootPart")
    Humanoid  = Character:WaitForChild("Humanoid")
end

BindCharacter()

----------------------------------------------------------------
-- GUI HELPERS / COLORS
----------------------------------------------------------------
local BG           = Color3.fromRGB(10,14,20)
local PANEL        = Color3.fromRGB(18,23,31)
local SIDEBAR_BG   = Color3.fromRGB(14,18,26)
local BUTTON       = Color3.fromRGB(31,40,54)
local BUTTON_HOVER = Color3.fromRGB(43,55,74)
local BORDER       = Color3.fromRGB(67,83,108)
local TEXT         = Color3.fromRGB(235,240,248)
local SUB          = Color3.fromRGB(145,160,180)
local GREEN        = Color3.fromRGB(120,255,170)
local RED          = Color3.fromRGB(255,115,115)
local BLUE         = Color3.fromRGB(120,180,255)
local ACCENT       = Color3.fromRGB(80,130,220)

local function AddCorner(obj, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 8)
    c.Parent = obj
end

local function AddStroke(obj, color, transparency)
    local s = Instance.new("UIStroke")
    s.Color = color or BORDER
    s.Transparency = transparency or 0
    s.Thickness = 1
    s.Parent = obj
end

local function MakeLabel(parent, text, pos, size, textSize, color)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Text = text or ""
    l.Position = pos
    l.Size = size
    l.Font = Enum.Font.Gotham
    l.TextSize = textSize or 12
    l.TextColor3 = color or TEXT
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextYAlignment = Enum.TextYAlignment.Center
    l.Parent = parent
    return l
end

local function MakeButton(parent, text, pos, size)
    local b = Instance.new("TextButton")
    b.Text = text
    b.Position = pos
    b.Size = size
    b.BackgroundColor3 = BUTTON
    b.BorderSizePixel = 0
    b.TextColor3 = TEXT
    b.Font = Enum.Font.GothamMedium
    b.TextSize = 13
    b.AutoButtonColor = false
    b.Parent = parent
    AddCorner(b, 8)
    AddStroke(b, BORDER, 0.3)
    b.MouseEnter:Connect(function() b.BackgroundColor3 = BUTTON_HOVER end)
    b.MouseLeave:Connect(function()
        if b:GetAttribute("ActiveButton") ~= true then b.BackgroundColor3 = BUTTON end
    end)
    return b
end

----------------------------------------------------------------
-- SHIFTLOCK UI / DETECTION
----------------------------------------------------------------
local IsItOn = false

local function IsShiftLockDetected()
    local controlMode = UserGameSettings.ControlMode
    local mouseLocked = false
    pcall(function()
        mouseLocked = UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
    end)
    return controlMode == Enum.ControlMode.MouseLockSwitch or (IsItOn and mouseLocked)
end

local ShiftLockUI = {
    MainGui                 = Instance.new("ScreenGui"),
    MouseLock               = Instance.new("Frame"),
    Container               = Instance.new("Frame"),
    Background              = Instance.new("Frame"),
    UICorner                = Instance.new("UICorner"),
    UIStroke                = Instance.new("UIStroke"),
    Icon                    = Instance.new("Frame"),
    ImageLabel              = Instance.new("ImageLabel"),
    UIAspectRatioConstraint = Instance.new("UIAspectRatioConstraint"),
    Button                  = Instance.new("TextButton"),
    Crosshair               = Instance.new("ImageLabel"),
}

ShiftLockUI.MainGui.Name = "MouseLockGui"
ShiftLockUI.MainGui.ResetOnSpawn = false
ShiftLockUI.MainGui.IgnoreGuiInset = true
ShiftLockUI.MainGui.DisplayOrder = 99999
ShiftLockUI.MainGui.Parent = PlayerGui

ShiftLockUI.MouseLock.Size = UDim2.new(0,44,0,44)
ShiftLockUI.MouseLock.BackgroundTransparency = 1
ShiftLockUI.MouseLock.BorderSizePixel = 0
ShiftLockUI.MouseLock.Position = UDim2.new(0,15,0,75)
ShiftLockUI.MouseLock.Parent = ShiftLockUI.MainGui

ShiftLockUI.Container.Size = UDim2.new(1,0,1,0)
ShiftLockUI.Container.BackgroundTransparency = 1
ShiftLockUI.Container.Parent = ShiftLockUI.MouseLock

ShiftLockUI.Background.Size = UDim2.new(1,0,1,0)
ShiftLockUI.Background.BackgroundColor3 = Color3.fromRGB(18,18,21)
ShiftLockUI.Background.BackgroundTransparency = 0.08
ShiftLockUI.Background.Parent = ShiftLockUI.Container

ShiftLockUI.UICorner.CornerRadius = UDim.new(1,0)
ShiftLockUI.UICorner.Parent = ShiftLockUI.Background
ShiftLockUI.UIStroke.Color = Color3.fromRGB(0,170,255)
ShiftLockUI.UIStroke.Thickness = 2
ShiftLockUI.UIStroke.Transparency = 0.2
ShiftLockUI.UIStroke.Enabled = false
ShiftLockUI.UIStroke.Parent = ShiftLockUI.Background

ShiftLockUI.Icon.Size = UDim2.new(1,0,1,0)
ShiftLockUI.Icon.BackgroundTransparency = 1
ShiftLockUI.Icon.ZIndex = 5
ShiftLockUI.Icon.Parent = ShiftLockUI.Container

ShiftLockUI.ImageLabel.AnchorPoint = Vector2.new(0.5,0.5)
ShiftLockUI.ImageLabel.Position = UDim2.new(0.5,0,0.5,0)
ShiftLockUI.ImageLabel.Size = UDim2.new(0.7,0,0.7,0)
ShiftLockUI.ImageLabel.BackgroundTransparency = 1
ShiftLockUI.ImageLabel.Image = "rbxassetid://80450981243325"
ShiftLockUI.ImageLabel.Parent = ShiftLockUI.Icon
ShiftLockUI.UIAspectRatioConstraint.Parent = ShiftLockUI.ImageLabel

ShiftLockUI.Button.Size = UDim2.new(1,0,1,0)
ShiftLockUI.Button.BackgroundTransparency = 1
ShiftLockUI.Button.ZIndex = 6
ShiftLockUI.Button.Text = ""
ShiftLockUI.Button.Parent = ShiftLockUI.Container

ShiftLockUI.Crosshair.Name = "Crosshair"
ShiftLockUI.Crosshair.Parent = ShiftLockUI.MainGui
ShiftLockUI.Crosshair.Size = UDim2.new(0,30,0,30)
ShiftLockUI.Crosshair.Position = UDim2.new(0.5,0,0.45,0)
ShiftLockUI.Crosshair.AnchorPoint = Vector2.new(0.5,0.5)
ShiftLockUI.Crosshair.BackgroundTransparency = 1
ShiftLockUI.Crosshair.Image = "rbxassetid://85514680408407"
ShiftLockUI.Crosshair.Visible = false
ShiftLockUI.Crosshair.ZIndex = 10

local CameraLocked = false
local LockedCameraCF = nil
local CameraLockConnection = nil

local function LockCamera()
    Camera = Workspace.CurrentCamera
    if not Camera or CameraLocked then return end
    LockedCameraCF = Camera.CFrame
    CameraLocked = true
    Camera.CameraType = Enum.CameraType.Scriptable
end

local function UnlockCamera()
    CameraLocked = false
    LockedCameraCF = nil
    if CameraLockConnection then
        CameraLockConnection:Disconnect()
        CameraLockConnection = nil
    end
    Camera = Workspace.CurrentCamera
    if Camera then Camera.CameraType = Enum.CameraType.Custom end
end

RunService:BindToRenderStep("HappaTAS_ShiftLock", Enum.RenderPriority.Camera.Value + 1, function()
    if CameraLocked then
        ShiftLockUI.Crosshair.Visible = IsShiftLockDetected()
        return
    end
    if not IsItOn then return end
    local cc = Workspace.CurrentCamera
    if not cc then return end
    Camera = cc
    local dist = (cc.CFrame.Position - cc.Focus.Position).Magnitude
    if dist < 0.6 then
        ShiftLockUI.Crosshair.Visible = false
        return
    end
    local shifted = cc.CFrame * CFrame.new(1.7,0,0)
    cc.Focus = shifted * CFrame.new(0,0,-dist)
    cc.CFrame = shifted
    ShiftLockUI.Crosshair.Visible = true
end)

ShiftLockUI.Button.MouseButton1Click:Connect(function()
    IsItOn = not IsItOn
    if IsItOn then
        UserGameSettings.RotationType = Enum.RotationType.CameraRelative
        ShiftLockUI.UIStroke.Enabled = true
    else
        UserGameSettings.RotationType = Enum.RotationType.MovementRelative
        ShiftLockUI.UIStroke.Enabled = false
        ShiftLockUI.Crosshair.Visible = false
    end
end)

----------------------------------------------------------------
-- CONTROLS / CONTROLLER HOOK
----------------------------------------------------------------
local ctrlModule = nil
local activeCtrl = nil
local tjCtrl = nil
local isKeyboard = false

local function hookControllers()
    local ps = LocalPlayer:FindFirstChild("PlayerScripts")
    if not ps then return end
    local pm = ps:FindFirstChild("PlayerModule")
    if not pm then return end
    local cm = pm:FindFirstChild("ControlModule")
    if not cm then return end
    local ok, ctrl = pcall(require, cm)
    if not ok or type(ctrl) ~= "table" then return end

    ctrlModule = ctrl
    activeCtrl = nil
    tjCtrl = nil
    isKeyboard = false

    local ac = rawget(ctrl, "activeController") or ctrl.activeController
    if ac then
        activeCtrl = ac
        isKeyboard = rawget(ac, "jumpRequested") ~= nil
    end

    local tj = rawget(ctrl, "touchJumpController") or ctrl.touchJumpController
    if tj and type(tj) == "table" and rawget(tj, "isJumping") ~= nil then
        tjCtrl = tj
    end

    if not activeCtrl then
        for _, v in pairs(ctrl) do
            if type(v) == "table" and rawget(v, "moveVector") ~= nil then
                activeCtrl = v
                isKeyboard = rawget(v, "jumpRequested") ~= nil
                break
            end
        end
    end

    if not tjCtrl then
        for _, v in pairs(ctrl) do
            if type(v) == "table" and rawget(v, "isJumping") ~= nil and v ~= activeCtrl then
                tjCtrl = v
                break
            end
        end
    end
end

task.spawn(function()
    task.wait(0.5)
    hookControllers()
end)

----------------------------------------------------------------
-- INPUT / JUMP HELPERS
----------------------------------------------------------------
local jumpIndicatorActive = false
local jumpIndicatorTimeout = nil

local function flashJumpIndicator()
    jumpIndicatorActive = true
    if jumpIndicatorTimeout then task.cancel(jumpIndicatorTimeout) end
    jumpIndicatorTimeout = task.delay(0.25, function()
        jumpIndicatorActive = false
        jumpIndicatorTimeout = nil
    end)
end

local JumpStateConnection = nil
local function connectJumpDetection()
    if JumpStateConnection then JumpStateConnection:Disconnect() end
    if not Humanoid then return end
    JumpStateConnection = Humanoid.StateChanged:Connect(function(_, new)
        if new == Enum.HumanoidStateType.Jumping or new == Enum.HumanoidStateType.Freefall then
            flashJumpIndicator()
        end
    end)
end

connectJumpDetection()

local function worldToCameraRelative(worldDir)
    Camera = Workspace.CurrentCamera or Camera
    local cf = Camera and Camera.CFrame
    if not cf then return Vector3.zero end
    local fw = Vector3.new(cf.LookVector.X,0,cf.LookVector.Z)
    local rt = Vector3.new(cf.RightVector.X,0,cf.RightVector.Z)
    fw = fw.Magnitude > 0.001 and fw.Unit or Vector3.new(0,0,-1)
    rt = rt.Magnitude > 0.001 and rt.Unit or Vector3.new(1,0,0)
    return Vector3.new(worldDir:Dot(rt),0,-worldDir:Dot(fw))
end

local function applyMove(dir)
    dir = dir or Vector3.zero
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")

    if activeCtrl and rawget(activeCtrl, "moveVector") ~= nil then
        if dir.Magnitude < 0.01 then
            activeCtrl.moveVector = Vector3.zero
            return
        end
        local d = Vector3.new(dir.X,0,dir.Z)
        if d.Magnitude < 0.001 then
            activeCtrl.moveVector = Vector3.zero
            return
        end
        if IsShiftLockDetected() then
            activeCtrl.moveVector = d.Unit * math.clamp(dir.Magnitude,0,1)
        else
            activeCtrl.moveVector = worldToCameraRelative(d.Unit) * math.clamp(dir.Magnitude,0,1)
        end
        return
    end

    if hum then
        local d = Vector3.new(dir.X,0,dir.Z)
        if d.Magnitude < 0.01 then
            hum:Move(Vector3.zero,false)
        else
            hum:Move(d.Unit * math.clamp(dir.Magnitude,0,1), false)
        end
    end
end

local function stopMove()
    applyMove(Vector3.zero)
end

local function applyJump()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")

    if isKeyboard and activeCtrl and rawget(activeCtrl,"jumpRequested") ~= nil then
        activeCtrl.jumpRequested = true
        task.delay(0.12,function()
            if activeCtrl and rawget(activeCtrl,"jumpRequested") ~= nil then
                activeCtrl.jumpRequested = false
            end
        end)
    elseif tjCtrl and rawget(tjCtrl,"isJumping") ~= nil then
        tjCtrl.isJumping = true
        task.delay(0.08,function()
            if tjCtrl and rawget(tjCtrl,"isJumping") ~= nil then tjCtrl.isJumping = false end
        end)
    elseif activeCtrl and rawget(activeCtrl,"isJumping") ~= nil then
        activeCtrl.isJumping = true
        task.delay(0.08,function()
            if activeCtrl and rawget(activeCtrl,"isJumping") ~= nil then activeCtrl.isJumping = false end
        end)
    elseif hum then
        hum.Jump = true
        task.delay(0.1,function()
            local h2 = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            if h2 then h2.Jump = false end
        end)
    end
end

----------------------------------------------------------------
-- TAS STATE
----------------------------------------------------------------
local Frames = {}
local PlaybackFrames = Frames
local IsRecording = false
local IsPlaying = false
local CurrentFrame = 0
local PreviewFrame = nil
local ReturnFrame = nil
local RecordingTime = 0
local PlaybackTime = 0
local PlaybackSpeed = DEFAULT_SPEED
local PlaybackCursor = 1
local PlaybackAccumulator = 0
local HoldingBack = false
local HoldingForward = false
local ScrubDirection = 0
local ScrubAccumulator = 0
local PreviewMultiplier = 1
local SelectedSave = nil
local ClearConfirm = false
local DeleteSaveConfirm = nil
local DragButtonsEnabled = false
local PlaybackLoop = false

local FPSEMA = 60
local ActualFPS = 60
local function UpdateFPS(dt)
    if dt <= 0 then return end
    FPSEMA = FPSEMA * 0.90 + (1/dt) * 0.10
    ActualFPS = math.clamp(FPSEMA,1,1000)
end

----------------------------------------------------------------
-- MAIN GUI
----------------------------------------------------------------
local GUI = Instance.new("ScreenGui")
GUI.Name = "HappaTAS"
GUI.ResetOnSpawn = false
GUI.IgnoreGuiInset = true
GUI.DisplayOrder = DISPLAY_ORDER
GUI.ZIndexBehavior = Enum.ZIndexBehavior.Global
GUI.Parent = PlayerGui

----------------------------------------------------------------
-- WINDOWS
----------------------------------------------------------------
local function MakeWindow(name,title,size,pos)
    local win = Instance.new("Frame")
    win.Name = name
    win.Size = size
    win.Position = pos
    win.BackgroundColor3 = BG
    win.BorderSizePixel = 0
    win.Parent = GUI
    AddCorner(win,11)
    AddStroke(win,BORDER,0.15)

    local hdr = Instance.new("Frame")
    hdr.Size = UDim2.new(1,0,0,40)
    hdr.BackgroundColor3 = PANEL
    hdr.BorderSizePixel = 0
    hdr.Parent = win
    AddCorner(hdr,11)

    local titleLabel = MakeLabel(hdr,title,UDim2.new(0,14,0,0),UDim2.new(1,-52,1,0),13,TEXT)
    titleLabel.Font = Enum.Font.GothamBold

    local close = MakeButton(hdr,"×",UDim2.new(1,-36,0,6),UDim2.new(0,28,0,28))
    close.TextSize = 18

    local dragging = false
    local dragStart,origPos
    hdr.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            origPos = win.Position
        end
    end)
    hdr.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
        local d = input.Position - dragStart
        win.Position = UDim2.new(origPos.X.Scale,origPos.X.Offset+d.X,origPos.Y.Scale,origPos.Y.Offset+d.Y)
    end)
    close.MouseButton1Click:Connect(function() win.Visible = false end)
    return win
end

local LiveWindow = MakeWindow("LiveStats","HAPPA TAS • LIVE STATS",UDim2.new(0,390,0,260),UDim2.new(1,-410,0,15))
local EditorWindow = MakeWindow("TASEditor","HAPPA TAS • TAS EDITOR",UDim2.new(0,490,0,420),UDim2.new(0,180,0,55))
local PlaybackWindow = MakeWindow("Playback","HAPPA TAS • PLAYBACK",UDim2.new(0,440,0,320),UDim2.new(0,685,0,280))
local SaveWindow = MakeWindow("SaveManager","HAPPA TAS • SAVE MANAGER",UDim2.new(0,560,0,485),UDim2.new(0.5,-280,0.5,-242))
local QuickWindow = MakeWindow("QuickToggles","HAPPA TAS • QUICK TOGGLES",UDim2.new(0,390,0,540),UDim2.new(0,175,0,420))
local ExtraWindow = MakeWindow("Extra","HAPPA TAS • EXTRA",UDim2.new(0,360,0,320),UDim2.new(0,530,0,490))

EditorWindow.Visible=false
PlaybackWindow.Visible=false
SaveWindow.Visible=false
QuickWindow.Visible=false
ExtraWindow.Visible=false

----------------------------------------------------------------
-- SIDEBAR
----------------------------------------------------------------
local SidebarFrame = Instance.new("Frame")
SidebarFrame.Size = UDim2.new(0,160,0,10)
SidebarFrame.Position = UDim2.new(0,10,1,-10)
SidebarFrame.AnchorPoint = Vector2.new(0,1)
SidebarFrame.BackgroundColor3 = SIDEBAR_BG
SidebarFrame.BorderSizePixel = 0
SidebarFrame.Parent = GUI
AddCorner(SidebarFrame,12)
AddStroke(SidebarFrame,BORDER,0.1)

local sbDragging=false
local sbDragStart,sbOrigPos
SidebarFrame.InputBegan:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
    local relY = input.Position.Y - SidebarFrame.AbsolutePosition.Y
    if relY > 36 then return end
    sbDragging=true; sbDragStart=input.Position; sbOrigPos=SidebarFrame.Position
end)
SidebarFrame.InputEnded:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then sbDragging=false end
end)
UserInputService.InputChanged:Connect(function(input)
    if not sbDragging then return end
    if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
    local d=input.Position-sbDragStart
    SidebarFrame.Position=UDim2.new(sbOrigPos.X.Scale,sbOrigPos.X.Offset+d.X,sbOrigPos.Y.Scale,sbOrigPos.Y.Offset+d.Y)
end)

local SidebarHeader = MakeLabel(SidebarFrame,"HAPPA TAS",UDim2.new(0,10,0,10),UDim2.new(1,-20,0,20),10,ACCENT)
SidebarHeader.Font=Enum.Font.GothamBold
SidebarHeader.TextXAlignment=Enum.TextXAlignment.Center

local SidebarSep=Instance.new("Frame")
SidebarSep.Size=UDim2.new(1,-20,0,1)
SidebarSep.Position=UDim2.new(0,10,0,34)
SidebarSep.BackgroundColor3=BORDER
SidebarSep.BackgroundTransparency=0.5
SidebarSep.BorderSizePixel=0
SidebarSep.Parent=SidebarFrame

local SidebarList=Instance.new("Frame")
SidebarList.BackgroundTransparency=1
SidebarList.Position=UDim2.new(0,10,0,42)
SidebarList.Size=UDim2.new(1,-20,0,0)
SidebarList.Parent=SidebarFrame

local SidebarLayout=Instance.new("UIListLayout")
SidebarLayout.Padding=UDim.new(0,6)
SidebarLayout.Parent=SidebarList

local function ResizeSidebar()
    local h=SidebarLayout.AbsoluteContentSize.Y
    SidebarList.Size=UDim2.new(1,-20,0,h)
    SidebarFrame.Size=UDim2.new(0,160,0,h+52)
end
SidebarLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(ResizeSidebar)

local SidebarButtonRefs={}
local function SidebarButton(labelText,order,window)
    local b=Instance.new("TextButton")
    b.Text=labelText
    b.Size=UDim2.new(1,0,0,42)
    b.BackgroundColor3=BUTTON
    b.BorderSizePixel=0
    b.TextColor3=TEXT
    b.Font=Enum.Font.GothamMedium
    b.TextSize=13
    b.AutoButtonColor=false
    b.LayoutOrder=order
    b.Parent=SidebarList
    AddCorner(b,8); AddStroke(b,BORDER,0.3)
    SidebarButtonRefs[labelText]={btn=b,win=window,active=false}
    b.MouseEnter:Connect(function() b.BackgroundColor3=BUTTON_HOVER end)
    b.MouseLeave:Connect(function() if not SidebarButtonRefs[labelText].active then b.BackgroundColor3=BUTTON end end)
    b.MouseButton1Click:Connect(function()
        window.Visible=not window.Visible
        local ref=SidebarButtonRefs[labelText]
        ref.active=window.Visible
        b.BackgroundColor3=ref.active and Color3.fromRGB(38,60,95) or BUTTON
    end)
end

SidebarButton("LIVE STATS",1,LiveWindow)
SidebarButton("TAS EDITOR",2,EditorWindow)
SidebarButton("PLAYBACK",3,PlaybackWindow)
SidebarButton("SAVE MANAGER",4,SaveWindow)
SidebarButton("QUICK TOGGLES",5,QuickWindow)
SidebarButton("EXTRA",6,ExtraWindow)

local ListSep=Instance.new("Frame")
ListSep.Size=UDim2.new(1,0,0,1)
ListSep.BackgroundColor3=BORDER
ListSep.BackgroundTransparency=0.5
ListSep.BorderSizePixel=0
ListSep.LayoutOrder=7
ListSep.Parent=SidebarList

local DragToggle=Instance.new("TextButton")
DragToggle.Text="DRAG BTNS: OFF"
DragToggle.Size=UDim2.new(1,0,0,42)
DragToggle.BackgroundColor3=BUTTON
DragToggle.BorderSizePixel=0
DragToggle.TextColor3=SUB
DragToggle.Font=Enum.Font.Gotham
DragToggle.TextSize=11
DragToggle.AutoButtonColor=false
DragToggle.LayoutOrder=8
DragToggle.Parent=SidebarList
AddCorner(DragToggle,8); AddStroke(DragToggle,BORDER,0.4)
DragToggle.MouseButton1Click:Connect(function()
    DragButtonsEnabled=not DragButtonsEnabled
    DragToggle.Text=DragButtonsEnabled and "DRAG BTNS: ON" or "DRAG BTNS: OFF"
    DragToggle.TextColor3=DragButtonsEnabled and GREEN or SUB
    DragToggle.BackgroundColor3=DragButtonsEnabled and Color3.fromRGB(28,52,38) or BUTTON
end)

----------------------------------------------------------------
-- LIVE / EDITOR / PLAYBACK GUI
----------------------------------------------------------------
local function LiveStat(text,y,size)
    return MakeLabel(LiveWindow,text,UDim2.new(0,14,0,y),UDim2.new(1,-28,0,20),size or 9,TEXT)
end
local LiveMode=LiveStat("Mode: IDLE",48,11)
local LiveFPS=LiveStat("FPS: 60.00",70,11)
local LiveFrame=LiveStat("Frame: 0 / 0",92,11)
local LivePosition=LiveStat("Position: --",114,9)
local LiveVelocity=LiveStat("Velocity: --",134,9)
local LiveRotation=LiveStat("Rotation: --",154,9)
local LiveCamera=LiveStat("Camera: --",174,9)
local LiveState=LiveStat("State: --",194,9)
local LiveShift=LiveStat("ShiftLock: OFF",214,9)
local LiveRecord=LiveStat("Recording: NO",234,9)

local EditorInfo=MakeLabel(EditorWindow,"Frame: 0 / 0",UDim2.new(0,14,0,50),UDim2.new(1,-28,0,24),13,TEXT)
local EditorTime=MakeLabel(EditorWindow,"Time: 0.000000",UDim2.new(0,14,0,76),UDim2.new(1,-28,0,20),9,SUB)
local EditorRecord=MakeButton(EditorWindow,"● RECORD",UDim2.new(0,14,0,108),UDim2.new(0,146,0,42))
local EditorStop=MakeButton(EditorWindow,"■ STOP",UDim2.new(0,169,0,108),UDim2.new(0,146,0,42))
local EditorInsert=MakeButton(EditorWindow,"+ 1 FRAME",UDim2.new(0,324,0,108),UDim2.new(0,146,0,42))
local EditorBack=MakeButton(EditorWindow,"‹ BACK 1",UDim2.new(0,14,0,160),UDim2.new(0,146,0,42))
local EditorForward=MakeButton(EditorWindow,"FORWARD 1 ›",UDim2.new(0,169,0,160),UDim2.new(0,146,0,42))
local EditorHoldBack=MakeButton(EditorWindow,"HOLD BACK",UDim2.new(0,324,0,160),UDim2.new(0,146,0,42))
local EditorHoldForward=MakeButton(EditorWindow,"HOLD FORWARD",UDim2.new(0,14,0,212),UDim2.new(0,146,0,42))
local EditorReturn=MakeButton(EditorWindow,"RETURN",UDim2.new(0,169,0,212),UDim2.new(0,146,0,42))
local EditorClear=MakeButton(EditorWindow,"CLEAR TAS",UDim2.new(0,324,0,212),UDim2.new(0,146,0,42))
local EditorStatus=MakeLabel(EditorWindow,"Ready",UDim2.new(0,14,0,268),UDim2.new(1,-28,0,20),10,GREEN)
local EditorFPS=MakeLabel(EditorWindow,"Detected FPS: 60.00",UDim2.new(0,14,0,292),UDim2.new(1,-28,0,20),9,SUB)
local EditorShift=MakeLabel(EditorWindow,"ShiftLock: OFF",UDim2.new(0,14,0,316),UDim2.new(1,-28,0,20),9,SUB)
local EditorScrub=MakeLabel(EditorWindow,"Scrub: 1.00x",UDim2.new(0,14,0,340),UDim2.new(1,-28,0,20),9,ACCENT)

local PlaybackFrameLabel=MakeLabel(PlaybackWindow,"Frame: 0 / 0",UDim2.new(0,14,0,50),UDim2.new(1,-28,0,24),13,TEXT)
local PlaybackTimeLabel=MakeLabel(PlaybackWindow,"Time: 0.000000",UDim2.new(0,14,0,76),UDim2.new(1,-28,0,20),10,TEXT)
local PlaybackFPS=MakeLabel(PlaybackWindow,"Live FPS: 60.00",UDim2.new(0,14,0,100),UDim2.new(0,200,0,20),9,SUB)
local PlaybackRecordedFPS=MakeLabel(PlaybackWindow,"Recorded FPS: --",UDim2.new(0,220,0,100),UDim2.new(0,200,0,20),9,SUB)
local PlaybackShift=MakeLabel(PlaybackWindow,"ShiftLock: OFF",UDim2.new(0,14,0,124),UDim2.new(1,-28,0,20),9,SUB)
local PlaybackSpeedLabel=MakeLabel(PlaybackWindow,"Speed: 1.00x",UDim2.new(0,14,0,148),UDim2.new(1,-28,0,20),10,TEXT)
local PlaybackPlay=MakeButton(PlaybackWindow,"▶ PLAY",UDim2.new(0,14,0,182),UDim2.new(0,126,0,42))
local PlaybackStop=MakeButton(PlaybackWindow,"■ STOP",UDim2.new(0,150,0,182),UDim2.new(0,126,0,42))
local PlaybackDown=MakeButton(PlaybackWindow,"− SPEED",UDim2.new(0,286,0,182),UDim2.new(0,126,0,42))
local PlaybackUp=MakeButton(PlaybackWindow,"+ SPEED",UDim2.new(0,14,0,234),UDim2.new(0,126,0,42))

----------------------------------------------------------------
-- SAVE MANAGER GUI
----------------------------------------------------------------
MakeLabel(SaveWindow,"NAME OF SAVE",UDim2.new(0,14,0,50),UDim2.new(1,-28,0,18),11,TEXT)
local SaveNameBox=Instance.new("TextBox")
SaveNameBox.Position=UDim2.new(0,14,0,72)
SaveNameBox.Size=UDim2.new(1,-28,0,38)
SaveNameBox.BackgroundColor3=Color3.fromRGB(24,30,41)
SaveNameBox.BorderSizePixel=0
SaveNameBox.TextColor3=TEXT
SaveNameBox.PlaceholderColor3=SUB
SaveNameBox.PlaceholderText="Enter TAS name..."
SaveNameBox.ClearTextOnFocus=false
SaveNameBox.Font=Enum.Font.Gotham
SaveNameBox.TextSize=12
SaveNameBox.Parent=SaveWindow
AddCorner(SaveNameBox,7); AddStroke(SaveNameBox)
MakeLabel(SaveWindow,GAME_ID.." • "..GAME_NAME,UDim2.new(0,14,0,116),UDim2.new(1,-28,0,10),5,SUB)
local SaveNew=MakeButton(SaveWindow,"SAVE NEW",UDim2.new(0,14,0,139),UDim2.new(0,125,0,36))
local SaveOverwrite=MakeButton(SaveWindow,"OVERWRITE",UDim2.new(0,149,0,139),UDim2.new(0,125,0,36))
local SaveLoad=MakeButton(SaveWindow,"LOAD",UDim2.new(0,284,0,139),UDim2.new(0,125,0,36))
local SaveDelete=MakeButton(SaveWindow,"DELETE",UDim2.new(0,419,0,139),UDim2.new(0,125,0,36))
local SaveStatus=MakeLabel(SaveWindow,"Ready",UDim2.new(0,14,0,190),UDim2.new(1,-28,0,20),9,SUB)
local SaveList=Instance.new("ScrollingFrame")
SaveList.Position=UDim2.new(0,14,0,218)
SaveList.Size=UDim2.new(0,310,0,200)
SaveList.BackgroundColor3=Color3.fromRGB(13,17,24)
SaveList.BorderSizePixel=0
SaveList.ScrollBarThickness=5
SaveList.Parent=SaveWindow
AddCorner(SaveList,7); AddStroke(SaveList)
local SaveLayout=Instance.new("UIListLayout")
SaveLayout.Padding=UDim.new(0,4)
SaveLayout.Parent=SaveList
local SaveRefresh=MakeButton(SaveWindow,"↻ REFRESH",UDim2.new(0,14,0,430),UDim2.new(0,310,0,30))
local SaveDetails=Instance.new("Frame")
SaveDetails.Position=UDim2.new(0,338,0,218)
SaveDetails.Size=UDim2.new(1,-352,0,242)
SaveDetails.BackgroundColor3=PANEL
SaveDetails.BorderSizePixel=0
SaveDetails.Parent=SaveWindow
AddCorner(SaveDetails,8); AddStroke(SaveDetails)
MakeLabel(SaveDetails,"SAVE INFORMATION",UDim2.new(0,12,0,12),UDim2.new(1,-24,0,18),9,SUB)
local SaveDetailName=MakeLabel(SaveDetails,"Selected: none",UDim2.new(0,12,0,42),UDim2.new(1,-24,0,22),12,TEXT)
local SaveDetailFrames=MakeLabel(SaveDetails,"Frames: 0",UDim2.new(0,12,0,78),UDim2.new(1,-24,0,20),9,TEXT)
local SaveDetailTime=MakeLabel(SaveDetails,"Time: 0.000000",UDim2.new(0,12,0,104),UDim2.new(1,-24,0,20),9,TEXT)
local SaveDetailFPS=MakeLabel(SaveDetails,"FPS: 60.00",UDim2.new(0,12,0,130),UDim2.new(1,-24,0,20),9,TEXT)

----------------------------------------------------------------
-- QUICK WINDOW
----------------------------------------------------------------
MakeLabel(QuickWindow,"BUILT-IN ACTIONS",UDim2.new(0,14,0,50),UDim2.new(1,-28,0,18),10,SUB)
MakeLabel(QuickWindow,"Toggle an action to create its floating button.",UDim2.new(0,14,0,68),UDim2.new(1,-28,0,20),9,SUB)
local BuiltInScroll=Instance.new("ScrollingFrame")
BuiltInScroll.Position=UDim2.new(0,14,0,94)
BuiltInScroll.Size=UDim2.new(1,-28,0,210)
BuiltInScroll.BackgroundColor3=Color3.fromRGB(13,17,24)
BuiltInScroll.BorderSizePixel=0
BuiltInScroll.ScrollBarThickness=5
BuiltInScroll.Parent=QuickWindow
AddCorner(BuiltInScroll,7); AddStroke(BuiltInScroll)
local BuiltInLayout=Instance.new("UIListLayout")
BuiltInLayout.Padding=UDim.new(0,4)
BuiltInLayout.Parent=BuiltInScroll
BuiltInLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    BuiltInScroll.CanvasSize=UDim2.new(0,0,0,BuiltInLayout.AbsoluteContentSize.Y+8)
end)

MakeLabel(QuickWindow,"CUSTOM ACTIONS",UDim2.new(0,14,0,314),UDim2.new(1,-28,0,18),10,SUB)
local CustomDropdown=Instance.new("TextButton")
CustomDropdown.Position=UDim2.new(0,14,0,336)
CustomDropdown.Size=UDim2.new(1,-28,0,36)
CustomDropdown.BackgroundColor3=Color3.fromRGB(20,26,36)
CustomDropdown.BorderSizePixel=0
CustomDropdown.Text="Select custom action ▼"
CustomDropdown.TextColor3=TEXT
CustomDropdown.Font=Enum.Font.Gotham
CustomDropdown.TextSize=11
CustomDropdown.TextXAlignment=Enum.TextXAlignment.Left
CustomDropdown.AutoButtonColor=false
CustomDropdown.Parent=QuickWindow
AddCorner(CustomDropdown,7); AddStroke(CustomDropdown)
local CustomDropdownPad=Instance.new("UIPadding")
CustomDropdownPad.PaddingLeft=UDim.new(0,12)
CustomDropdownPad.Parent=CustomDropdown
local CustomDropdownMenu=Instance.new("ScrollingFrame")
CustomDropdownMenu.Position=UDim2.new(0,14,0,376)
CustomDropdownMenu.Size=UDim2.new(1,-28,0,105)
CustomDropdownMenu.BackgroundColor3=Color3.fromRGB(13,17,24)
CustomDropdownMenu.BorderSizePixel=0
CustomDropdownMenu.ScrollBarThickness=4
CustomDropdownMenu.Visible=false
CustomDropdownMenu.ZIndex=100
CustomDropdownMenu.Parent=QuickWindow
AddCorner(CustomDropdownMenu,7); AddStroke(CustomDropdownMenu)
local CustomDropdownLayout=Instance.new("UIListLayout")
CustomDropdownLayout.Padding=UDim.new(0,3)
CustomDropdownLayout.Parent=CustomDropdownMenu
local CustomSelectedLabel=MakeLabel(QuickWindow,"Selected: none",UDim2.new(0,14,0,390),UDim2.new(1,-150,0,20),9,TEXT)
local CustomScreenToggle=MakeButton(QuickWindow,"ADD TO SCREEN",UDim2.new(1,-142,0,388),UDim2.new(0,128,0,28))
MakeLabel(QuickWindow,"CREATE CUSTOM ACTION",UDim2.new(0,14,0,420),UDim2.new(1,-28,0,18),10,SUB)
local QTNameBox=Instance.new("TextBox")
QTNameBox.Position=UDim2.new(0,14,0,442)
QTNameBox.Size=UDim2.new(0.38,0,0,30)
QTNameBox.BackgroundColor3=Color3.fromRGB(20,26,36)
QTNameBox.BorderSizePixel=0
QTNameBox.TextColor3=TEXT
QTNameBox.PlaceholderColor3=SUB
QTNameBox.PlaceholderText="Name"
QTNameBox.ClearTextOnFocus=false
QTNameBox.Font=Enum.Font.Gotham
QTNameBox.TextSize=10
QTNameBox.Parent=QuickWindow
AddCorner(QTNameBox,7); AddStroke(QTNameBox)
local QTCodeBox=Instance.new("TextBox")
QTCodeBox.Position=UDim2.new(0.40,0,0,442)
QTCodeBox.Size=UDim2.new(0.38,0,0,30)
QTCodeBox.BackgroundColor3=Color3.fromRGB(15,20,28)
QTCodeBox.BorderSizePixel=0
QTCodeBox.TextColor3=TEXT
QTCodeBox.PlaceholderColor3=SUB
QTCodeBox.PlaceholderText="Lua code"
QTCodeBox.ClearTextOnFocus=false
QTCodeBox.Font=Enum.Font.Code
QTCodeBox.TextSize=10
QTCodeBox.Parent=QuickWindow
AddCorner(QTCodeBox,7); AddStroke(QTCodeBox)
local QTAdd=MakeButton(QuickWindow,"+ ADD",UDim2.new(0.80,0,0,442),UDim2.new(0.20,-14,0,30))
local QuickStatus=MakeLabel(QuickWindow,"Ready",UDim2.new(0,14,0,478),UDim2.new(1,-28,0,18),9,GREEN)

----------------------------------------------------------------
-- QUICK BUTTONS
----------------------------------------------------------------
local ScreenQuickGui=Instance.new("ScreenGui")
ScreenQuickGui.Name="HappaTAS_QuickButtons"
ScreenQuickGui.ResetOnSpawn=false
ScreenQuickGui.IgnoreGuiInset=true
ScreenQuickGui.DisplayOrder=DISPLAY_ORDER+5
ScreenQuickGui.ZIndexBehavior=Enum.ZIndexBehavior.Global
ScreenQuickGui.Parent=PlayerGui
local ScreenButtonData={}
local ScreenButtonContainer=Instance.new("Frame")
ScreenButtonContainer.Name="Container"
ScreenButtonContainer.Size=UDim2.new(1,0,1,0)
ScreenButtonContainer.BackgroundTransparency=1
ScreenButtonContainer.Parent=ScreenQuickGui
local ScreenButtonIndex=0
local function GetDefaultButtonPosition()
    ScreenButtonIndex += 1
    local col=(ScreenButtonIndex-1)%3
    local row=math.floor((ScreenButtonIndex-1)/3)
    return UDim2.new(0,15+col*110,0,110+row*44)
end
local function CreateScreenButton(id,labelText,callback,existingPos)
    if ScreenButtonData[id] then
        ScreenButtonData[id].button.Visible=true
        return ScreenButtonData[id].button
    end
    local b=Instance.new("TextButton")
    b.Name="QuickButton_"..id
    b.Size=UDim2.new(0,102,0,34)
    b.Position=existingPos or GetDefaultButtonPosition()
    b.BackgroundColor3=Color3.fromRGB(22,30,43)
    b.BorderSizePixel=0
    b.TextColor3=TEXT
    b.Text=labelText
    b.Font=Enum.Font.GothamMedium
    b.TextSize=10
    b.AutoButtonColor=false
    b.Active=true
    b.Draggable=false
    b.ZIndex=50
    b.Parent=ScreenButtonContainer
    AddCorner(b,8); AddStroke(b,BORDER,0.15)
    local dragging=false
    local dragStart,startPos
    b.InputBegan:Connect(function(input)
        if not DragButtonsEnabled then return end
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
            dragging=true; dragStart=input.Position; startPos=b.Position
        end
    end)
    b.InputEnded:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then dragging=false end
    end)
    local moveConnection=UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType~=Enum.UserInputType.MouseMovement and input.UserInputType~=Enum.UserInputType.Touch then return end
        local d=input.Position-dragStart
        b.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
    end)
    b.MouseEnter:Connect(function() b.BackgroundColor3=Color3.fromRGB(38,60,95) end)
    b.MouseLeave:Connect(function() b.BackgroundColor3=Color3.fromRGB(22,30,43) end)
    b.MouseButton1Click:Connect(function()
        if DragButtonsEnabled then return end
        local ok,err=pcall(callback)
        if not ok then QuickStatus.Text="Error: "..tostring(err); QuickStatus.TextColor3=RED; return end
        QuickStatus.Text="▶ "..labelText
        QuickStatus.TextColor3=GREEN
    end)
    ScreenButtonData[id]={button=b,callback=callback,label=labelText,moveConnection=moveConnection,custom=false}
    return b
end
local function RemoveScreenButton(id)
    local info=ScreenButtonData[id]
    if not info then return end
    if info.moveConnection then info.moveConnection:Disconnect() end
    if info.button then info.button:Destroy() end
    ScreenButtonData[id]=nil
end

----------------------------------------------------------------
-- EXTRA
----------------------------------------------------------------
MakeLabel(ExtraWindow,"EDITOR SCRUB SPEED",UDim2.new(0,14,0,50),UDim2.new(1,-28,0,18),11,TEXT)
MakeLabel(ExtraWindow,"Controls Hold Back / Hold Forward speed.",UDim2.new(0,14,0,70),UDim2.new(1,-28,0,24),9,SUB)
local ExtraMultBox=Instance.new("TextBox")
ExtraMultBox.Position=UDim2.new(0,14,0,110)
ExtraMultBox.Size=UDim2.new(1,-28,0,40)
ExtraMultBox.BackgroundColor3=Color3.fromRGB(20,26,36)
ExtraMultBox.BorderSizePixel=0
ExtraMultBox.TextColor3=TEXT
ExtraMultBox.PlaceholderColor3=SUB
ExtraMultBox.PlaceholderText="e.g. 0.25 / 1 / 3"
ExtraMultBox.ClearTextOnFocus=false
ExtraMultBox.Font=Enum.Font.Code
ExtraMultBox.TextSize=16
ExtraMultBox.Text="1"
ExtraMultBox.Parent=ExtraWindow
AddCorner(ExtraMultBox,8); AddStroke(ExtraMultBox)
local ExtraMultLabel=MakeLabel(ExtraWindow,"Current: 1.00x (~20 frames/sec)",UDim2.new(0,14,0,158),UDim2.new(1,-28,0,20),10,ACCENT)
local ExtraApply=MakeButton(ExtraWindow,"APPLY",UDim2.new(0,14,0,186),UDim2.new(0,106,0,36))
local ExtraReset=MakeButton(ExtraWindow,"RESET (1x)",UDim2.new(0,130,0,186),UDim2.new(0,116,0,36))
local ExtraStatus=MakeLabel(ExtraWindow,"",UDim2.new(0,14,0,230),UDim2.new(1,-28,0,18),9,GREEN)
local function SetMultiplier(v)
    v=math.clamp(v,0.01,20)
    PreviewMultiplier=v
    ExtraMultBox.Text=tostring(v)
    ExtraMultLabel.Text=string.format("Current: %.2fx (~%.0f input frames/sec)",v,SCRUB_BASE*v)
    EditorScrub.Text=string.format("Scrub: %.2fx",v)
end
ExtraApply.MouseButton1Click:Connect(function()
    local v=tonumber(ExtraMultBox.Text)
    if not v or v<=0 then ExtraStatus.Text="Invalid number"; ExtraStatus.TextColor3=RED; return end
    SetMultiplier(v); ExtraStatus.Text="Applied"; ExtraStatus.TextColor3=GREEN
end)
ExtraReset.MouseButton1Click:Connect(function() SetMultiplier(1); ExtraStatus.Text="Reset"; ExtraStatus.TextColor3=SUB end)

----------------------------------------------------------------
-- INPUT TAS CORE
----------------------------------------------------------------
local RecordConnection=nil
local RecordStart=0
local LastRecordDir=Vector3.zero
local LastRecordJump=false

local function CaptureLiveInput()
    local dir=Vector3.zero
    if activeCtrl and rawget(activeCtrl,"moveVector") ~= nil then
        local mv=activeCtrl.moveVector
        if mv and mv.Magnitude>0.01 then
            Camera=Workspace.CurrentCamera or Camera
            local cf=Camera and Camera.CFrame
            if cf then
                local fw=Vector3.new(cf.LookVector.X,0,cf.LookVector.Z)
                local rt=Vector3.new(cf.RightVector.X,0,cf.RightVector.Z)
                fw=fw.Magnitude>0.001 and fw.Unit or Vector3.new(0,0,-1)
                rt=rt.Magnitude>0.001 and rt.Unit or Vector3.new(1,0,0)
                if IsShiftLockDetected() then
                    dir=Vector3.new(mv.X,0,mv.Z)
                else
                    dir=(rt*mv.X + fw*(-mv.Z))
                end
                if dir.Magnitude>1e-3 then dir=dir.Unit*math.clamp(mv.Magnitude,0,1) end
            end
        end
    else
        local vel=Root and Root.AssemblyLinearVelocity or Vector3.zero
        local flat=Vector3.new(vel.X,0,vel.Z)
        if flat.Magnitude>1 then dir=flat.Unit end
    end
    return dir,jumpIndicatorActive
end

local function ApplyFrame(frame)
    if not frame then return end
    applyMove(frame.dir or Vector3.zero)
    if frame.jump then applyJump() end
end

local function SoftStopRecording()
    if not IsRecording then return end
    IsRecording=false
    if RecordConnection then RecordConnection:Disconnect(); RecordConnection=nil end
    stopMove()
    PreviewFrame=CurrentFrame
end

local function StartRecording()
    if IsPlaying then
        IsPlaying=false
        PlaybackLoop=false
        stopMove()
        UnlockCamera()
    end
    if IsRecording then return end

    if PreviewFrame and PreviewFrame < #Frames then
        for i=#Frames,PreviewFrame+1,-1 do Frames[i]=nil end
    end

    CurrentFrame=#Frames
    RecordingTime=(#Frames>0 and Frames[#Frames].t) or 0
    ReturnFrame=PreviewFrame or CurrentFrame
    IsRecording=true
    RecordStart=os.clock()-RecordingTime
    LastRecordDir=Vector3.zero
    LastRecordJump=false

    if RecordConnection then RecordConnection:Disconnect() end
    RecordConnection=RunService.Heartbeat:Connect(function(dt)
        if not IsRecording then return end
        UpdateFPS(dt)
        local dir,jump=CaptureLiveInput()
        local t=os.clock()-RecordStart
        local last=Frames[#Frames]
        if (not last)
            or (dir-LastRecordDir).Magnitude>0.05
            or jump~=LastRecordJump
            or (t-last.t)>=1/RECORD_HZ then
            CurrentFrame+=1
            Frames[CurrentFrame]={t=t,dir=dir,jump=jump,dt=(last and (t-last.t) or dt)}
            RecordingTime=t
            PreviewFrame=CurrentFrame
            LastRecordDir=dir
            LastRecordJump=jump
        else
            RecordingTime=t
        end
    end)
end

local function StopPlayback()
    IsPlaying=false
    PlaybackLoop=false
    PlaybackCursor=1
    PlaybackAccumulator=0
    PlaybackTime=0
    stopMove()
    UnlockCamera()
end

local function StartPlayback(looped)
    if #Frames==0 then return end
    if IsRecording then SoftStopRecording() end
    if IsPlaying then StopPlayback() end
    PlaybackFrames=Frames
    PlaybackCursor=1
    PlaybackAccumulator=0
    PlaybackTime=0
    CurrentFrame=1
    IsPlaying=true
    PlaybackLoop=looped==true
    LockCamera()
    ApplyFrame(PlaybackFrames[1])
end

local function FullStop()
    -- This is the second script's "tasFullStop" semantics,
    -- applied to the first script's state model.
    if RecordConnection then RecordConnection:Disconnect(); RecordConnection=nil end
    IsRecording=false
    IsPlaying=false
    PlaybackLoop=false
    PlaybackCursor=1
    PlaybackAccumulator=0
    PlaybackTime=0
    ScrubDirection=0
    ScrubAccumulator=0
    HoldingBack=false
    HoldingForward=false
    CurrentFrame=0
    PreviewFrame=nil
    ReturnFrame=nil
    RecordingTime=0
    Frames={}
    PlaybackFrames=Frames
    LastRecordDir=Vector3.zero
    LastRecordJump=false
    stopMove()
    UnlockCamera()
end

local function InsertFrame()
    if IsRecording or IsPlaying then return end
    local dir,jump=CaptureLiveInput()
    local dt=1/math.max(ActualFPS,1)
    local t=(#Frames>0 and Frames[#Frames].t or 0)+dt
    CurrentFrame=(PreviewFrame or CurrentFrame)+1
    table.insert(Frames,CurrentFrame,{t=t,dir=dir,jump=jump,dt=dt})
    RecordingTime=t
    PreviewFrame=CurrentFrame
end

local function ShowFrame(index)
    if #Frames==0 then return end
    index=math.clamp(index,1,#Frames)
    CurrentFrame=index
    PreviewFrame=index
    ApplyFrame(Frames[index])
end

local function PreviousFrame()
    if IsRecording or IsPlaying or #Frames==0 then return end
    ShowFrame(math.max(1,(PreviewFrame or CurrentFrame)-1))
end
local function NextFrame()
    if IsRecording or IsPlaying or #Frames==0 then return end
    ShowFrame(math.min(#Frames,(PreviewFrame or CurrentFrame)+1))
end
local function ReturnToPoint()
    if IsRecording or IsPlaying or not ReturnFrame then return end
    if ReturnFrame<#Frames then
        for i=#Frames,ReturnFrame+1,-1 do Frames[i]=nil end
    end
    CurrentFrame=#Frames
    PreviewFrame=(#Frames>0 and #Frames or nil)
    RecordingTime=(#Frames>0 and Frames[#Frames].t or 0)
    if #Frames>0 then ApplyFrame(Frames[#Frames]) end
end
local function ClearTAS()
    if not ClearConfirm then
        ClearConfirm=true
        EditorStatus.Text="Press CLEAR again"
        EditorStatus.TextColor3=RED
        task.delay(2,function() ClearConfirm=false end)
        return
    end
    ClearConfirm=false
    FullStop()
    EditorStatus.Text="TAS cleared"
    EditorStatus.TextColor3=GREEN
end

local function BeginScrub(direction)
    if IsRecording or IsPlaying or #Frames==0 then return end
    HoldingBack=direction<0
    HoldingForward=direction>0
    ScrubDirection=direction
    ScrubAccumulator=0
end
local function EndScrub(direction)
    if direction<0 then HoldingBack=false else HoldingForward=false end
    if not HoldingBack and not HoldingForward then ScrubDirection=0; ScrubAccumulator=0 end
end

----------------------------------------------------------------
-- SERIALIZATION
----------------------------------------------------------------
local function VecToTable(v) return {v.X,v.Y,v.Z} end
local function TableToVec(t)
    if type(t)~="table" or #t<3 then return Vector3.zero end
    return Vector3.new(tonumber(t[1]) or 0,tonumber(t[2]) or 0,tonumber(t[3]) or 0)
end
local function SerializeFrame(f)
    return {
        t=tonumber(f.t) or 0,
        dt=tonumber(f.dt) or 1/RECORD_HZ,
        dir=VecToTable(f.dir or Vector3.zero),
        jump=f.jump==true,
        shiftLock=IsShiftLockDetected(),
    }
end
local function DeserializeFrame(data)
    if type(data)~="table" then return nil end
    return {
        t=tonumber(data.t) or 0,
        dt=tonumber(data.dt) or 1/RECORD_HZ,
        dir=TableToVec(data.dir),
        jump=data.jump==true,
    }
end

----------------------------------------------------------------
-- SAVE HELPERS
----------------------------------------------------------------
local function SanitizeName(name)
    name=tostring(name or "")
    name=name:gsub("[\\/:*?\"<>|]","_"):gsub("%s+"," "):gsub("^%s+",""):gsub("%s+$",""):gsub("%.json$","")
    if name=="" then name="Unnamed TAS" end
    return name
end
local function SavePath(name) return SAVE_FOLDER.."/"..SanitizeName(name)..".json" end
local function BaseName(path)
    local file=tostring(path):match("[^/\\]+$")
    if not file then return nil end
    return file:gsub("%.json$","")
end
local function FindSavePath(name)
    if not LIST_OK then return nil end
    local wanted=SanitizeName(name):lower()
    local ok,files=pcall(listfiles,SAVE_FOLDER)
    if not ok or type(files)~="table" then return nil end
    for _,path in ipairs(files) do
        if tostring(path):lower():sub(-5)==".json" then
            local n=BaseName(path)
            if n and SanitizeName(n):lower()==wanted then return path end
        end
    end
    return nil
end
local function BuildSaveData(name)
    local serialized=table.create(#Frames)
    for i=1,#Frames do serialized[i]=SerializeFrame(Frames[i]) end
    return {
        format="HappaTASInput",
        version=4,
        name=name,
        game={id=GAME_ID,name=GAME_NAME},
        detectedFPS=ActualFPS,
        totalTime=RecordingTime,
        playbackSpeed=PlaybackSpeed,
        frameCount=#serialized,
        shiftLockActive=IsShiftLockDetected(),
        frames=serialized,
    }
end
local function SaveTAS(requestedName,overwrite)
    if not FILE_OK then SaveStatus.Text="File API unavailable"; SaveStatus.TextColor3=RED; return false end
    if #Frames==0 then SaveStatus.Text="Nothing to save"; SaveStatus.TextColor3=RED; return false end
    local name=SanitizeName(requestedName)
    local path=SavePath(name)
    local exists=false
    pcall(function() exists=isfile(path) end)
    if exists and not overwrite then SaveStatus.Text="Already exists — use OVERWRITE"; SaveStatus.TextColor3=RED; return false end
    local okEncode,encoded=pcall(HttpService.JSONEncode,HttpService,BuildSaveData(name))
    if not okEncode or type(encoded)~="string" then SaveStatus.Text="JSON encode failed"; SaveStatus.TextColor3=RED; return false end
    local okWrite,err=pcall(writefile,path,encoded)
    if not okWrite then SaveStatus.Text="Write failed: "..tostring(err); SaveStatus.TextColor3=RED; return false end
    SelectedSave=name
    SaveNameBox.Text=name
    SaveStatus.Text=string.format("Saved %s (%d frames)",name,#Frames)
    SaveStatus.TextColor3=GREEN
    return true
end
local function LoadTAS(requestedName)
    if not FILE_OK then SaveStatus.Text="File API unavailable"; SaveStatus.TextColor3=RED; return false end
    if IsRecording or IsPlaying then FullStop() end
    local name=SanitizeName(requestedName)
    local path=SavePath(name)
    local exists=false
    pcall(function() exists=isfile(path) end)
    if not exists then
        local found=FindSavePath(name)
        if found then path=found; exists=true end
    end
    if not exists then SaveStatus.Text="Save not found: "..name; SaveStatus.TextColor3=RED; return false end
    local okRead,raw=pcall(readfile,path)
    if not okRead or type(raw)~="string" then SaveStatus.Text="Read failed"; SaveStatus.TextColor3=RED; return false end
    local okDecode,data=pcall(HttpService.JSONDecode,HttpService,raw)
    if not okDecode or type(data)~="table" or type(data.frames)~="table" then SaveStatus.Text="Invalid save"; SaveStatus.TextColor3=RED; return false end
    local loaded={}
    for i=1,#data.frames do
        local frame=DeserializeFrame(data.frames[i])
        if frame then loaded[#loaded+1]=frame end
    end
    if #loaded==0 then SaveStatus.Text="No valid frames"; SaveStatus.TextColor3=RED; return false end
    Frames=loaded
    PlaybackFrames=Frames
    CurrentFrame=#Frames
    PreviewFrame=#Frames
    ReturnFrame=nil
    RecordingTime=tonumber(data.totalTime) or Frames[#Frames].t
    PlaybackTime=0
    PlaybackSpeed=math.clamp(tonumber(data.playbackSpeed) or DEFAULT_SPEED,MIN_SPEED,MAX_SPEED)
    SelectedSave=SanitizeName(data.name or BaseName(path) or name)
    SaveNameBox.Text=SelectedSave
    ApplyFrame(Frames[#Frames])
    SaveStatus.Text=string.format("Loaded %s (%d frames)",SelectedSave,#Frames)
    SaveStatus.TextColor3=GREEN
    return true
end

----------------------------------------------------------------
-- REFRESH SAVE LIST
----------------------------------------------------------------
local RefreshingSaves=false
local function RefreshSaveList()
    if RefreshingSaves then return end
    RefreshingSaves=true
    for _,child in ipairs(SaveList:GetChildren()) do if child:IsA("TextButton") then child:Destroy() end end
    if not LIST_OK then SaveStatus.Text="listfiles unavailable"; SaveStatus.TextColor3=RED; RefreshingSaves=false; return end
    local ok,files=pcall(listfiles,SAVE_FOLDER)
    if not ok or type(files)~="table" then SaveStatus.Text="Could not list saves"; SaveStatus.TextColor3=RED; RefreshingSaves=false; return end
    local saves={}
    for _,path in ipairs(files) do
        if tostring(path):lower():sub(-5)==".json" then
            local n=BaseName(path)
            if n then saves[#saves+1]=n end
        end
    end
    table.sort(saves)
    for i=1,#saves do
        local name=saves[i]
        local item=MakeButton(SaveList,name,UDim2.new(0,4,0,0),UDim2.new(1,-8,0,30))
        item.LayoutOrder=i
        if SelectedSave and name:lower()==SelectedSave:lower() then item.BackgroundColor3=Color3.fromRGB(45,64,90) end
        item.MouseButton1Click:Connect(function()
            SelectedSave=name
            SaveNameBox.Text=name
            SaveStatus.Text="Selected: "..name
            SaveStatus.TextColor3=SUB
            RefreshSaveList()
        end)
    end
    SaveList.CanvasSize=UDim2.new(0,0,0,#saves*34+5)
    RefreshingSaves=false
end

----------------------------------------------------------------
-- BUILT-IN ACTIONS / CUSTOM QUICK BUTTONS
----------------------------------------------------------------
local BuiltInActions={
    {id="back1",label="BACK 1",callback=PreviousFrame},
    {id="forward1",label="FORWARD 1",callback=NextFrame},
    {id="holdback",label="HOLD BACK",callback=function() if HoldingBack then EndScrub(-1) else BeginScrub(-1) end end},
    {id="holdforward",label="HOLD FORWARD",callback=function() if HoldingForward then EndScrub(1) else BeginScrub(1) end end},
    {id="record",label="RECORD",callback=StartRecording},
    {id="stop",label="STOP",callback=FullStop},
    {id="insert",label="INSERT",callback=InsertFrame},
    {id="return",label="RETURN",callback=ReturnToPoint},
    {id="play",label="PLAY",callback=function() StartPlayback(false) end},
    {id="stopplayback",label="STOP PLAYBACK",callback=FullStop},
    {id="clear",label="CLEAR",callback=ClearTAS},
    {id="slower",label="SLOWER SCRUB",callback=function() SetMultiplier(math.max(0.1,PreviewMultiplier-0.1)) end},
    {id="faster",label="FASTER SCRUB",callback=function() SetMultiplier(math.min(20,PreviewMultiplier+0.5)) end},
}
local BuiltInButtonRefs={}
local function UpdateBuiltInRow(action)
    local ref=BuiltInButtonRefs[action.id]
    if not ref then return end
    local visible=ScreenButtonData[action.id]~=nil
    ref.toggle.Text=visible and "ON SCREEN" or "OFF SCREEN"
    ref.toggle.TextColor3=visible and GREEN or SUB
    ref.toggle.BackgroundColor3=visible and Color3.fromRGB(28,52,38) or BUTTON
end
for order,action in ipairs(BuiltInActions) do
    local row=Instance.new("Frame")
    row.Size=UDim2.new(1,-8,0,34)
    row.BackgroundTransparency=1
    row.LayoutOrder=order
    row.Parent=BuiltInScroll
    MakeLabel(row,action.label,UDim2.new(0,4,0,0),UDim2.new(1,-100,1,0),10,TEXT)
    local toggle=MakeButton(row,"OFF SCREEN",UDim2.new(1,-92,0,1),UDim2.new(0,88,0,32))
    toggle.TextSize=9
    BuiltInButtonRefs[action.id]={row=row,toggle=toggle}
    toggle.MouseButton1Click:Connect(function()
        if ScreenButtonData[action.id] then RemoveScreenButton(action.id) else CreateScreenButton(action.id,action.label,action.callback) end
        UpdateBuiltInRow(action)
    end)
end

local CustomActions={}
local SelectedCustomAction=nil
local function RefreshCustomDropdown()
    for _,child in ipairs(CustomDropdownMenu:GetChildren()) do if child:IsA("TextButton") then child:Destroy() end end
    for order,action in ipairs(CustomActions) do
        local item=Instance.new("TextButton")
        item.Size=UDim2.new(1,-8,0,30)
        item.BackgroundColor3=BUTTON
        item.BorderSizePixel=0
        item.TextColor3=TEXT
        item.Font=Enum.Font.GothamMedium
        item.TextSize=10
        item.TextXAlignment=Enum.TextXAlignment.Left
        item.Text="   "..action.name
        item.LayoutOrder=order
        item.AutoButtonColor=false
        item.ZIndex=101
        item.Parent=CustomDropdownMenu
        AddCorner(item,6)
        item.MouseEnter:Connect(function() item.BackgroundColor3=BUTTON_HOVER end)
        item.MouseLeave:Connect(function() item.BackgroundColor3=BUTTON end)
        item.MouseButton1Click:Connect(function()
            SelectedCustomAction=action
            CustomDropdown.Text=action.name.." ▼"
            CustomSelectedLabel.Text="Selected: "..action.name
            CustomDropdownMenu.Visible=false
        end)
    end
    CustomDropdownMenu.CanvasSize=UDim2.new(0,0,0,#CustomActions*33+6)
end
CustomDropdown.MouseButton1Click:Connect(function()
    CustomDropdownMenu.Visible=not CustomDropdownMenu.Visible
    CustomDropdown.Text=CustomDropdownMenu.Visible and "Select custom action ▲" or (SelectedCustomAction and SelectedCustomAction.name.." ▼" or "Select custom action ▼")
end)
CustomScreenToggle.MouseButton1Click:Connect(function()
    local action=SelectedCustomAction
    if not action then QuickStatus.Text="Select a custom action first"; QuickStatus.TextColor3=RED; return end
    local id="custom_"..action.id
    if ScreenButtonData[id] then
        RemoveScreenButton(id)
        QuickStatus.Text="Removed: "..action.name
        QuickStatus.TextColor3=SUB
    else
        CreateScreenButton(id,action.name,action.callback)
        if ScreenButtonData[id] then ScreenButtonData[id].custom=true end
        QuickStatus.Text="Added: "..action.name
        QuickStatus.TextColor3=GREEN
    end
end)
QTAdd.MouseButton1Click:Connect(function()
    local name=QTNameBox.Text:gsub("^%s+",""):gsub("%s+$","")
    local code=QTCodeBox.Text:gsub("^%s+",""):gsub("%s+$","")
    if name=="" or code=="" then QuickStatus.Text="Name and code required"; QuickStatus.TextColor3=RED; return end
    for _,a in ipairs(CustomActions) do if a.name:lower()==name:lower() then QuickStatus.Text="Name already exists"; QuickStatus.TextColor3=RED; return end end
    local fn,syntaxError=loadstring(code)
    if not fn then QuickStatus.Text="Syntax: "..tostring(syntaxError); QuickStatus.TextColor3=RED; return end
    local action={id=tostring(os.clock()):gsub("%.",""),name=name,code=code}
    action.callback=function()
        local func,err=loadstring(action.code)
        if not func then error(err) end
        local ok,runErr=pcall(func)
        if not ok then error(runErr) end
    end
    table.insert(CustomActions,action)
    QTNameBox.Text=""; QTCodeBox.Text=""
    RefreshCustomDropdown()
    QuickStatus.Text="Added custom: "..name
    QuickStatus.TextColor3=GREEN
end)
local function UpdateCustomButtonState()
    if not SelectedCustomAction then CustomScreenToggle.Text="ADD TO SCREEN"; CustomScreenToggle.TextColor3=TEXT; return end
    local id="custom_"..SelectedCustomAction.id
    local on=ScreenButtonData[id]~=nil
    CustomScreenToggle.Text=on and "REMOVE FROM SCREEN" or "ADD TO SCREEN"
    CustomScreenToggle.TextColor3=on and GREEN or TEXT
end

----------------------------------------------------------------
-- SCRUB / PLAYBACK LOOPS
----------------------------------------------------------------
RunService:BindToRenderStep("HappaTAS_Scrub",Enum.RenderPriority.Input.Value,function(dt)
    local direction=ScrubDirection
    if direction==0 then return end
    if IsRecording or IsPlaying or #Frames==0 then ScrubAccumulator=0; return end
    ScrubAccumulator += dt*SCRUB_BASE*PreviewMultiplier
    while ScrubAccumulator>=1 do
        ScrubAccumulator-=1
        local current=PreviewFrame or CurrentFrame
        if direction<0 then
            if current>1 then ShowFrame(current-1) else EndScrub(-1); break end
        else
            if current<#Frames then ShowFrame(current+1) else EndScrub(1); break end
        end
    end
end)

RunService:BindToRenderStep("HappaTAS_Playback",Enum.RenderPriority.Camera.Value+3,function(dt)
    if not IsPlaying then return end
    local count=#PlaybackFrames
    if count==0 then FullStop(); return end

    if CameraLocked and LockedCameraCF then
        Camera=Workspace.CurrentCamera
        if Camera then Camera.CFrame=LockedCameraCF end
    end

    PlaybackAccumulator += dt*PlaybackSpeed
    local cur=PlaybackFrames[PlaybackCursor]
    while PlaybackCursor<count do
        local nxt=PlaybackFrames[PlaybackCursor+1]
        local needed=tonumber(nxt.dt) or 1/RECORD_HZ
        if PlaybackAccumulator<needed then break end
        PlaybackAccumulator-=needed
        PlaybackCursor+=1
        cur=nxt
        CurrentFrame=PlaybackCursor
    end

    cur=PlaybackFrames[PlaybackCursor]
    if cur then
        ApplyFrame(cur)
        PlaybackTime=cur.t
    end

    if PlaybackCursor>=count then
        if PlaybackLoop then
            PlaybackCursor=1
            PlaybackAccumulator=0
            PlaybackTime=0
            CurrentFrame=1
            ApplyFrame(PlaybackFrames[1])
        else
            StopPlayback()
        end
    end
end)

----------------------------------------------------------------
-- EVENTS
----------------------------------------------------------------
EditorRecord.MouseButton1Click:Connect(function() if IsRecording then SoftStopRecording() else StartRecording() end end)
EditorStop.MouseButton1Click:Connect(FullStop)
EditorInsert.MouseButton1Click:Connect(InsertFrame)
EditorBack.MouseButton1Click:Connect(PreviousFrame)
EditorForward.MouseButton1Click:Connect(NextFrame)
EditorReturn.MouseButton1Click:Connect(ReturnToPoint)
EditorClear.MouseButton1Click:Connect(ClearTAS)
EditorHoldBack.MouseButton1Down:Connect(function() BeginScrub(-1) end)
EditorHoldBack.MouseButton1Up:Connect(function() EndScrub(-1) end)
EditorHoldBack.MouseLeave:Connect(function() EndScrub(-1) end)
EditorHoldForward.MouseButton1Down:Connect(function() BeginScrub(1) end)
EditorHoldForward.MouseButton1Up:Connect(function() EndScrub(1) end)
EditorHoldForward.MouseLeave:Connect(function() EndScrub(1) end)
PlaybackPlay.MouseButton1Click:Connect(function() StartPlayback(false) end)
PlaybackStop.MouseButton1Click:Connect(FullStop)
PlaybackDown.MouseButton1Click:Connect(function() PlaybackSpeed=math.max(MIN_SPEED,PlaybackSpeed-0.10) end)
PlaybackUp.MouseButton1Click:Connect(function() PlaybackSpeed=math.min(MAX_SPEED,PlaybackSpeed+0.10) end)

SaveNew.MouseButton1Click:Connect(function() if SaveTAS(SaveNameBox.Text,false) then RefreshSaveList() end end)
SaveOverwrite.MouseButton1Click:Connect(function()
    local name=SaveNameBox.Text~="" and SaveNameBox.Text or SelectedSave
    if not name then SaveStatus.Text="Enter a save name"; SaveStatus.TextColor3=RED; return end
    if SaveTAS(name,true) then RefreshSaveList() end
end)
SaveLoad.MouseButton1Click:Connect(function()
    local name=SaveNameBox.Text~="" and SaveNameBox.Text or SelectedSave
    if not name then SaveStatus.Text="Select a save"; SaveStatus.TextColor3=RED; return end
    LoadTAS(name); RefreshSaveList()
end)
SaveRefresh.MouseButton1Click:Connect(RefreshSaveList)
SaveDelete.MouseButton1Click:Connect(function()
    if not DELETE_OK then SaveStatus.Text="Delete unavailable"; SaveStatus.TextColor3=RED; return end
    local name=SaveNameBox.Text~="" and SaveNameBox.Text or SelectedSave
    if not name then SaveStatus.Text="Select a save"; SaveStatus.TextColor3=RED; return end
    name=SanitizeName(name)
    if DeleteSaveConfirm~=name then
        DeleteSaveConfirm=name
        SaveStatus.Text="Press DELETE again"; SaveStatus.TextColor3=RED
        task.delay(2,function() if DeleteSaveConfirm==name then DeleteSaveConfirm=nil end end)
        return
    end
    local path=FindSavePath(name) or SavePath(name)
    local ok,err=pcall(delfile,path)
    if not ok then SaveStatus.Text="Delete failed: "..tostring(err); SaveStatus.TextColor3=RED; return end
    DeleteSaveConfirm=nil; SelectedSave=nil; SaveNameBox.Text=""
    SaveStatus.Text="Deleted: "..name; SaveStatus.TextColor3=GREEN
    RefreshSaveList()
end)

----------------------------------------------------------------
-- KEYBOARD
----------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input,gp)
    if gp then return end
    local key=input.KeyCode
    if key==Enum.KeyCode.E then
        if IsRecording then SoftStopRecording() else StartRecording() end
    elseif key==Enum.KeyCode.F then PreviousFrame()
    elseif key==Enum.KeyCode.G then NextFrame()
    elseif key==Enum.KeyCode.V then InsertFrame()
    elseif key==Enum.KeyCode.X then ReturnToPoint()
    elseif key==Enum.KeyCode.Three then StartPlayback(false)
    elseif key==Enum.KeyCode.Four then SaveWindow.Visible=not SaveWindow.Visible
    elseif key==Enum.KeyCode.Minus then ClearTAS()
    elseif key==Enum.KeyCode.R then BeginScrub(-1)
    elseif key==Enum.KeyCode.T then BeginScrub(1)
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode==Enum.KeyCode.R then EndScrub(-1)
    elseif input.KeyCode==Enum.KeyCode.T then EndScrub(1) end
end)

----------------------------------------------------------------
-- RESPawn / CONTROLLER REHOOK
----------------------------------------------------------------
LocalPlayer.CharacterAdded:Connect(function(char)
    task.defer(function()
        pcall(function()
            Character=char
            Root=char:WaitForChild("HumanoidRootPart")
            Humanoid=char:WaitForChild("Humanoid")
            connectJumpDetection()
            task.wait(0.5)
            hookControllers()
        end)
    end)
end)

----------------------------------------------------------------
-- UI UPDATE
----------------------------------------------------------------
local UIAccumulator=0
RunService:BindToRenderStep("HappaTAS_UI",Enum.RenderPriority.Last.Value,function(dt)
    UpdateFPS(dt)
    UIAccumulator += dt
    if UIAccumulator<UI_RATE then return end
    UIAccumulator=0
    Camera=Workspace.CurrentCamera

    local mode=IsPlaying and (PlaybackLoop and "LOOP" or "PLAYBACK") or IsRecording and "RECORDING" or "EDITOR"
    local shift=IsShiftLockDetected()

    if Root and Humanoid and Camera then
        local rx,ry,rz=Root.Orientation.X,Root.Orientation.Y,Root.Orientation.Z
        local cx,cy,cz=Camera.CFrame:ToEulerAnglesYXZ()
        local zoom=(Camera.CFrame.Position-Camera.Focus.Position).Magnitude
        local velocity=Root.AssemblyLinearVelocity
        LiveMode.Text="Mode: "..mode
        LiveFPS.Text=string.format("FPS: %.2f",ActualFPS)
        LiveFrame.Text=string.format("Frame: %d / %d",CurrentFrame,#Frames)
        LivePosition.Text=string.format("Position: %.3f, %.3f, %.3f",Root.Position.X,Root.Position.Y,Root.Position.Z)
        LiveVelocity.Text=string.format("Velocity: %.3f, %.3f, %.3f",velocity.X,velocity.Y,velocity.Z)
        LiveRotation.Text=string.format("Rotation: %.2f, %.2f, %.2f",rx,ry,rz)
        LiveCamera.Text=string.format("Camera: %.2f, %.2f, %.2f  Zoom %.2f",math.deg(cx),math.deg(cy),math.deg(cz),zoom)
        LiveState.Text="State: "..Humanoid:GetState().Name
        LiveShift.Text=shift and "ShiftLock: ON" or "ShiftLock: OFF"
        LiveShift.TextColor3=shift and BLUE or SUB
        LiveRecord.Text=IsRecording and "Recording: YES" or "Recording: NO"
    end

    EditorInfo.Text=string.format("Frame: %d / %d",CurrentFrame,#Frames)
    EditorTime.Text=string.format("Time: %.6f",RecordingTime)
    EditorFPS.Text=string.format("Detected FPS: %.2f",ActualFPS)
    EditorShift.Text=shift and "ShiftLock: ON" or "ShiftLock: OFF"
    EditorStatus.Text=IsRecording and "● RECORDING" or IsPlaying and (PlaybackLoop and "↻ LOOP" or "▶ PLAYBACK") or "Ready"
    EditorStatus.TextColor3=IsRecording and RED or GREEN
    EditorScrub.Text=string.format("Scrub: %.2fx",PreviewMultiplier)

    PlaybackFrameLabel.Text=string.format("Frame: %d / %d",CurrentFrame,#Frames)
    PlaybackTimeLabel.Text=string.format("Time: %.6f / %.6f",PlaybackTime,RecordingTime)
    PlaybackFPS.Text=string.format("Live FPS: %.2f",ActualFPS)
    local recordedFPS=(#Frames>1 and RecordingTime>0) and ((#Frames-1)/RecordingTime) or 0
    PlaybackRecordedFPS.Text=string.format("Recorded FPS: %.2f",recordedFPS)
    PlaybackShift.Text=shift and "ShiftLock: ON" or "ShiftLock: OFF"
    PlaybackSpeedLabel.Text=string.format("Speed: %.2fx",PlaybackSpeed)
    SaveDetailName.Text="Selected: "..(SelectedSave or "none")
    SaveDetailFrames.Text="Frames: "..tostring(#Frames)
    SaveDetailTime.Text=string.format("Time: %.6f",RecordingTime)
    SaveDetailFPS.Text=string.format("FPS: %.2f",ActualFPS)
    UpdateCustomButtonState()
end)

RefreshSaveList()

----------------------------------------------------------------
-- INITIAL STATE
----------------------------------------------------------------
LiveWindow.Visible=true
EditorWindow.Visible=false
PlaybackWindow.Visible=false
SaveWindow.Visible=false
QuickWindow.Visible=false
ExtraWindow.Visible=false
ShiftLockUI.MainGui.Enabled=true
ResizeSidebar()

-- Make sure the new controller/camera system starts in a clean state.
stopMove()
UnlockCamera()
