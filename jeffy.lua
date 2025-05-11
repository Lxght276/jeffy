-- Optimized ESP Script with better performance and smoother rendering

local Settings = {
    Box_Color = Color3.fromRGB(255, 0, 0),
    Tracer_Color = Color3.fromRGB(255, 0, 0),
    Tracer_Thickness = 1,
    Box_Thickness = 1,
    Tracer_Origin = "Bottom", -- Middle or Bottom
    Tracer_FollowMouse = false,
    Tracers = true,
    MaxDistance = 1000, -- Added distance limit for performance
    UpdateRate = 0.016 -- ~60 FPS (seconds per update)
}

local Team_Check = {
    TeamCheck = false,
    Green = Color3.fromRGB(0, 255, 0),
    Red = Color3.fromRGB(255, 0, 0)
}

local TeamColor = true

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local Mouse = LocalPlayer:GetMouse()

-- Cache frequently used values
local ViewportSize = Camera.ViewportSize
local Black = Color3.new(0, 0, 0)
local ESPCache = {}

-- Optimized drawing object creation
local function CreateDrawing(type, props)
    local drawing = Drawing.new(type)
    for prop, value in pairs(props) do
        drawing[prop] = value
    end
    return drawing
end

local function NewQuad(thickness, color)
    return CreateDrawing("Quad", {
        Visible = false,
        Color = color,
        Thickness = thickness,
        Filled = false,
        Transparency = 1
    })
end

local function NewLine(thickness, color)
    return CreateDrawing("Line", {
        Visible = false,
        Color = color,
        Thickness = thickness,
        Transparency = 1
    })
end

-- Batch visibility updates
local function SetVisibility(drawings, state)
    for _, drawing in pairs(drawings) do
        drawing.Visible = state
    end
end

-- Optimized ESP class
local ESP = {}
ESP.__index = ESP

function ESP.new(player)
    local self = setmetatable({}, ESP)
    
    self.Player = player
    self.Visible = false
    
    -- Create all drawings at once
    self.Drawings = {
        blacktracer = NewLine(Settings.Tracer_Thickness * 2, Black),
        tracer = NewLine(Settings.Tracer_Thickness, Settings.Tracer_Color),
        black = NewQuad(Settings.Box_Thickness * 2, Black),
        box = NewQuad(Settings.Box_Thickness, Settings.Box_Color),
        healthbar = NewLine(3, Black),
        greenhealth = NewLine(1.5, Black)
    }
    
    -- Store connections for cleanup
    self.Connections = {}
    
    -- Start the update loop
    self:StartUpdater()
    
    return self
end

function ESP:Colorize(color)
    self.Drawings.tracer.Color = color
    self.Drawings.box.Color = color
end

function ESP:Update()
    local character = self.Player.Character
    if not character then return end
    
    local humanoid = character:FindFirstChild("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    local head = character:FindFirstChild("Head")
    
    if not humanoid or not rootPart or not head or humanoid.Health <= 0 then
        if self.Visible then
            SetVisibility(self.Drawings, false)
            self.Visible = false
        end
        return
    end
    
    -- Team checks
    if Team_Check.TeamCheck and self.Player.Team == LocalPlayer.Team then
        if self.Visible then
            SetVisibility(self.Drawings, false)
            self.Visible = false
        end
        return
    end
    
    -- Distance check
    local distance = (LocalPlayer.Character and LocalPlayer.Character.PrimaryPart) 
                     and (rootPart.Position - LocalPlayer.Character.PrimaryPart.Position).Magnitude 
                     or 0
    
    if distance > Settings.MaxDistance then
        if self.Visible then
            SetVisibility(self.Drawings, false)
            self.Visible = false
        end
        return
    end
    
    -- World to screen space conversion
    local rootPos, onScreen = Camera:WorldToViewportPoint(rootPart.Position)
    local headPos = Camera:WorldToViewportPoint(head.Position)
    
    if not onScreen then
        if self.Visible then
            SetVisibility(self.Drawings, false)
            self.Visible = false
        end
        return
    end
    
    -- Calculate box dimensions
    local distanceY = math.clamp((Vector2.new(headPos.X, headPos.Y) - Vector2.new(rootPos.X, rootPos.Y)).magnitude, 2, math.huge)
    
    -- Update box positions
    local function UpdateQuad(quad, x, y, sizeX, sizeY)
        quad.PointA = Vector2.new(x + sizeX, y - sizeY)
        quad.PointB = Vector2.new(x - sizeX, y - sizeY)
        quad.PointC = Vector2.new(x - sizeX, y + sizeY)
        quad.PointD = Vector2.new(x + sizeX, y + sizeY)
    end
    
    UpdateQuad(self.Drawings.box, rootPos.X, rootPos.Y, distanceY, distanceY * 2)
    UpdateQuad(self.Drawings.black, rootPos.X, rootPos.Y, distanceY, distanceY * 2)
    
    -- Update tracers
    if Settings.Tracers then
        local fromPoint
        if Settings.Tracer_FollowMouse then
            fromPoint = Vector2.new(Mouse.X, Mouse.Y + 36)
        elseif Settings.Tracer_Origin == "Middle" then
            fromPoint = ViewportSize * 0.5
        else -- Bottom
            fromPoint = Vector2.new(ViewportSize.X * 0.5, ViewportSize.Y)
        end
        
        self.Drawings.tracer.From = fromPoint
        self.Drawings.tracer.To = Vector2.new(rootPos.X, rootPos.Y + distanceY * 2)
        
        self.Drawings.blacktracer.From = fromPoint
        self.Drawings.blacktracer.To = Vector2.new(rootPos.X, rootPos.Y + distanceY * 2)
    else
        self.Drawings.tracer.From = Vector2.zero
        self.Drawings.tracer.To = Vector2.zero
        self.Drawings.blacktracer.From = Vector2.zero
        self.Drawings.blacktracer.To = Vector2.zero
    end
    
    -- Update health bar
    local healthBarLength = distanceY * 4
    local healthOffset = humanoid.Health / humanoid.MaxHealth * healthBarLength
    
    self.Drawings.healthbar.From = Vector2.new(rootPos.X - distanceY - 4, rootPos.Y + distanceY * 2)
    self.Drawings.healthbar.To = Vector2.new(rootPos.X - distanceY - 4, rootPos.Y - distanceY * 2)
    
    self.Drawings.greenhealth.From = Vector2.new(rootPos.X - distanceY - 4, rootPos.Y + distanceY * 2)
    self.Drawings.greenhealth.To = Vector2.new(rootPos.X - distanceY - 4, rootPos.Y + distanceY * 2 - healthOffset)
    
    -- Health bar color gradient
    local green = Color3.fromRGB(0, 255, 0)
    local red = Color3.fromRGB(255, 0, 0)
    self.Drawings.greenhealth.Color = red:lerp(green, humanoid.Health / humanoid.MaxHealth)
    
    -- Team coloring
    if Team_Check.TeamCheck then
        if self.Player.Team == LocalPlayer.Team then
            self:Colorize(Team_Check.Green)
        else
            self:Colorize(Team_Check.Red)
        end
    elseif TeamColor then
        self:Colorize(self.Player.TeamColor.Color)
    else
        self:Colorize(Settings.Box_Color)
    end
    
    -- Only update visibility if it changed
    if not self.Visible then
        SetVisibility(self.Drawings, true)
        self.Visible = true
    end
end

function ESP:StartUpdater()
    local lastUpdate = tick()
    
    self.Connections.update = RunService.RenderStepped:Connect(function()
        local now = tick()
        if now - lastUpdate >= Settings.UpdateRate then
            self:Update()
            lastUpdate = now
        end
    end)
    
    self.Connections.characterAdded = self.Player.CharacterAdded:Connect(function(character)
        self:Update()
    end)
    
    self.Connections.teamChanged = self.Player:GetPropertyChangedSignal("Team"):Connect(function()
        self:Update()
    end)
end

function ESP:Destroy()
    for _, connection in pairs(self.Connections) do
        connection:Disconnect()
    end
    
    for _, drawing in pairs(self.Drawings) do
        drawing:Remove()
    end
    
    ESPCache[self.Player] = nil
end

-- Player management
local function PlayerAdded(player)
    if player == LocalPlayer then return end
    
    local esp = ESP.new(player)
    ESPCache[player] = esp
    
    player.CharacterAdded:Connect(function(character)
        esp:Update()
    end)
end

local function PlayerRemoving(player)
    local esp = ESPCache[player]
    if esp then
        esp:Destroy()
    end
end

-- Initialize ESP for all players
for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then
        coroutine.wrap(PlayerAdded)(player)
    end
end

-- Connect events
Players.PlayerAdded:Connect(PlayerAdded)
Players.PlayerRemoving:Connect(PlayerRemoving)

-- Cleanup on script termination
local function Cleanup()
    for _, esp in pairs(ESPCache) do
        esp:Destroy()
    end
end

game:BindToClose(Cleanup)
