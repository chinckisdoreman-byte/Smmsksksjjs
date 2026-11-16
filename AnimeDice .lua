local CONFIG = {
	UIUrl        = "https://raw.githubusercontent.com/csgo1compte-cloud/RayVoid/refs/heads/main/AirFlow",
	UIFile       = "Airflow.lua",
	Theme        = "Midnight",
	ConfigFolder = "AnimeDiceRemake",
	ConfigFile   = "Anime-Dice",
	Analytics    = false,
	Fleet        = false,
	Debug        = false,
}
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local LP                = Players.LocalPlayer
local Network           = ReplicatedStorage:WaitForChild("Network")
local Framework         = ReplicatedStorage:FindFirstChild("Framework")
local function dbg(...)
	if CONFIG.Debug then warn("[AnimeDice]", ...) end
end
local function num(v, default)
	v = tonumber(v)
	if v == nil or v ~= v then return default or 0 end
	return v
end
local SUFFIXES = { "k", "M", "B", "T", "Qd", "Qn", "Sx", "Sp", "Oc", "No", "Dc" }
local function fmt(n)
	n = tonumber(n)
	if n == nil or n ~= n then return "?" end
	local sign = ""
	if n < 0 then sign, n = "-", -n end
	if n < 1000 then
		if n == math.floor(n) then return sign .. string.format("%d", n) end
		return sign .. (string.format("%.1f", n):gsub("%.0$", ""))
	end
	local idx = math.min(math.floor(math.log(n, 10) / 3), #SUFFIXES)
	local text = string.format("%.2f", n / 10 ^ (idx * 3))
	text = text:gsub("0+$", ""):gsub("%.$", "")
	return sign .. text .. SUFFIXES[idx]
end
local function sortedKeys(t)
	local keys = {}
	for k in pairs(t) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	return keys
end
local function contains(list, value)
	for _, v in ipairs(list) do if v == value then return true end end
	return false
end
local function toSet(list)
	local set = {}
	if type(list) == "table" then
		for _, v in ipairs(list) do set[v] = true end
	end
	return set
end
local function setCount(set)
	local n = 0
	for _ in pairs(set) do n = n + 1 end
	return n
end
local throttles = {}
local function throttle(key, seconds)
	local now = os.clock()
	local last = throttles[key]
	if last and now - last < seconds then return false end
	throttles[key] = now
	return true
end
local moduleCache, moduleFailedAt = {}, {}
local function Module(name)
	local cached = moduleCache[name]
	if cached ~= nil then return cached end
	if moduleFailedAt[name] and os.clock() - moduleFailedAt[name] < 5 then return nil end
	local found
	for _, root in ipairs({ Framework, ReplicatedStorage }) do
		if root then
			for _, inst in ipairs(root:GetDescendants()) do
				if inst.Name == name and inst:IsA("ModuleScript") then found = inst break end
			end
		end
		if found then break end
	end
	if found then
		local ok, mod = pcall(require, found)
		if ok and mod ~= nil then
			moduleCache[name] = mod
			return mod
		end
		dbg("require failed", name, mod)
	end
	moduleFailedAt[name] = os.clock()
	return nil
end
local function callFn(mod, fname, ...)
	if type(mod) ~= "table" or type(mod[fname]) ~= "function" then return nil end
	local ok, r = pcall(mod[fname], ...)
	if ok and r ~= nil then return r end
	ok, r = pcall(mod[fname], mod, ...)
	if ok then return r end
	return nil
end
local remoteIndex, remoteCache = nil, {}
local function indexRemotes()
	remoteIndex = {}
	for _, inst in ipairs(Network:GetDescendants()) do
		if inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction") or inst:IsA("UnreliableRemoteEvent") then
			local list = remoteIndex[inst.Name]
			if not list then list = {} remoteIndex[inst.Name] = list end
			list[#list + 1] = inst
		end
	end
end
local function isUnder(inst, service)
	local p = inst.Parent
	while p and p ~= Network do
		if p.Name == service then return true end
		p = p.Parent
	end
	return false
end
local function Remote(service, name)
	local key = tostring(service) .. "/" .. name
	local hit = remoteCache[key]
	if hit and hit.Parent then return hit end
	for attempt = 1, 2 do
		if not remoteIndex or attempt == 2 then indexRemotes() end
		local list = remoteIndex[name]
		if list then
			if service then
				for _, r in ipairs(list) do
					if isUnder(r, service) then remoteCache[key] = r return r end
				end
			end
			if #list == 1 then remoteCache[key] = list[1] return list[1] end
		end
	end
	return nil
end
local function call(remote, ...)
	if not remote then return false, "remote not found" end
	if remote:IsA("RemoteFunction") then
		return pcall(remote.InvokeServer, remote, ...)
	end
	return pcall(remote.FireServer, remote, ...)
end
local function send(service, name, ...)
	local ok, res = call(Remote(service, name), ...)
	if not ok then dbg("remote failed", service, name, res) end
	return ok, res
end
local function Data()
	local dc = Module("DataController")
	if not dc then return nil end
	local d = dc.Data
	if type(d) == "function" then
		local ok, r = pcall(d, dc)
		d = ok and r or nil
	end
	if type(d) ~= "table" then d = dc.data end
	if type(d) ~= "table" then d = callFn(dc, "Get") end
	return type(d) == "table" and d or nil
end
local function dataField(...)
	local node = Data()
	for _, key in ipairs({ ... }) do
		if type(node) ~= "table" then return nil end
		node = node[key]
	end
	return node
end
local function money() return tonumber(dataField("Money")) end
local function rebirths() return num(dataField("Rebirth", "Rebirths"), 0) end
local RESERVED_INVENTORY_KEYS = { Slots = true, TowerTeam = true, Locked = true, EquippedGear = true }
local function Inventory()
	local inv = dataField("Inventory")
	return type(inv) == "table" and inv or nil
end
local function entries()
	local inv = Inventory()
	if not inv then return {} end
	if type(inv.Entries) == "table" then return inv.Entries end
	local out = {}
	for k, v in pairs(inv) do
		if not RESERVED_INVENTORY_KEYS[k] and type(v) == "table" then out[k] = v end
	end
	return out
end
local function amountOf(name)
	local inv = Inventory()
	local e = inv and inv[name]
	if type(e) == "table" then return num(e.amount, 0) end
	return num(e, 0)
end
local function entryConfig(entry, key)
	local reg = Module("EntryRegistry")
	if not reg then return nil end
	local name = type(entry) == "table" and (entry.name or entry.Name) or key
	for _, arg in ipairs({ name, entry }) do
		if arg ~= nil then
			local cfg = callFn(reg, "getEntryConfig", arg)
			if type(cfg) == "table" then return cfg end
		end
	end
	return nil
end
local function entriesOfKind(kind)
	local reg = Module("EntryRegistry")
	local r = callFn(reg, "entriesOfKind", kind)
	return type(r) == "table" and r or {}
end
local function buff(name)
	local bc = Module("BuffController")
	if not bc then return nil end
	local v = callFn(bc, "GetBuff", name)
	return tonumber(v)
end
local function slotTable()
	local d = Data()
	if not d then return {} end
	local plot = d.Plot
	if type(plot) == "table" and type(plot.Slots) == "table" then return plot.Slots end
	local inv = d.Inventory
	if type(inv) == "table" and type(inv.Slots) == "table" then return inv.Slots end
	return {}
end
local function slotUnitId(slot)
	if type(slot) == "string" then return slot end
	if type(slot) == "table" then return slot.unitId or slot.UnitId or slot.id end
	return nil
end
local function placedSet()
	local set = {}
	for _, slot in pairs(slotTable()) do
		local id = slotUnitId(slot)
		if id then set[id] = true end
	end
	local inv = Inventory()
	if inv and type(inv.TowerTeam) == "table" then
		for _, v in pairs(inv.TowerTeam) do
			local id = slotUnitId(v) or (type(v) ~= "table" and v) or nil
			if id then set[id] = true end
		end
	end
	return set
end
local RARITIES = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythical", "Divine",
	"Exotic", "Celestial", "Exclusive", "Secret1", "Secret2" }
local MUTATIONS = { "Silver", "Gold", "Emerald", "Diamond", "Ruby", "Rainbow", "Haunted" }
local BRANCHES = { "Luck", "Fortune", "Roll Speed", "Unit Storage", "Tower Speed", "Money", "Sell",
	"Damage", "Health", "Walkspeed", "Grade Luck", "Grade Rolls", "Trait Luck", "Trait Rolls" }
local RARITY_INDEX, MUTATION_INDEX = {}, {}
for i, n in ipairs(RARITIES) do RARITY_INDEX[n] = i end
for i, n in ipairs(MUTATIONS) do MUTATION_INDEX[n] = i end
local function nameOf(v)
	if type(v) == "string" then return v end
	if type(v) == "table" then return v.name or v.Name or v[1] end
	return nil
end
local rarityCache = {}
local function rarityOf(cfg, entry)
	if type(cfg) ~= "table" then return "Common" end
	if type(cfg.rarity) == "string" and RARITY_INDEX[cfg.rarity] then return cfg.rarity end
	local util = Module("UnitUtil")
	local id = tostring(cfg.name) .. "|" .. tostring(entry and entry.attributes and entry.attributes.mutation)
	if rarityCache[id] then return rarityCache[id] end
	local result
	for _, arg in ipairs({ cfg, cfg.chance, entry }) do
		local r = nameOf(callFn(util, "getRarity", arg))
		if r and RARITY_INDEX[r] then result = r break end
	end
	result = result or "Common"
	rarityCache[id] = result
	return result
end
local function listUnits()
	local out = {}
	for key, entry in pairs(entries()) do
		local cfg = entryConfig(entry, key)
		if cfg and cfg.kind == "Unit" then
			local attrs = type(entry.attributes) == "table" and entry.attributes or {}
			out[#out + 1] = {
				key = key, entry = entry, cfg = cfg, attrs = attrs,
				name = cfg.name or entry.name or tostring(key),
				amount = num(entry.amount, 1),
				chance = num(cfg.chance, 0),
				mutation = attrs.mutation,
				level = num(attrs.level, 1),
				locked = attrs.locked == true or entry.locked == true,
				rarity = rarityOf(cfg, entry),
			}
		end
	end
	return out
end
local function unitLabel(u)
	return string.format("1 in %s \194\183 %s%s", fmt(u.chance), u.name,
		u.mutation and (" (" .. tostring(u.mutation) .. ")") or "")
end
local function tiers(moduleName)
	local mod = Module(moduleName)
	local list = {}
	if type(mod) ~= "table" then return list end
	local src = type(mod.List) == "table" and mod.List or mod
	for k, v in pairs(src) do
		if type(v) == "table" and type(k) ~= "function" then
			list[#list + 1] = {
				name = v.name or v.Name or (type(k) == "string" and k) or nil,
				order = num(v.order or v.Order or v.rank or v.weight or v.tier, (type(k) == "number" and k) or 0),
				weight = num(v.weight or v.chance, 0),
				protected = v.protected == true,
			}
		end
	end
	table.sort(list, function(a, b)
		if a.order ~= b.order then return a.order < b.order end
		return tostring(a.name) < tostring(b.name)
	end)
	local clean = {}
	for _, t in ipairs(list) do if t.name then clean[#clean + 1] = t end end
	return clean
end
local function tierMap(list)
	local map = {}
	for i, t in ipairs(list) do map[t.name] = { index = i, protected = t.protected } end
	return map
end
local function rootPart()
	local c = LP.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end
local function humanoid()
	local c = LP.Character
	return c and c:FindFirstChildOfClass("Humanoid")
end
local function walkTo(target, timeout)
	local hrp, hum = rootPart(), humanoid()
	if not (hrp and hum) then return false end
	timeout = timeout or 25
	local started = os.clock()
	local path = PathfindingService:CreatePath({ AgentRadius = 2.5, AgentHeight = 5, AgentCanJump = true })
	local ok = pcall(function() path:ComputeAsync(hrp.Position, target) end)
	if ok and path.Status == Enum.PathStatus.Success then
		for _, wp in ipairs(path:GetWaypoints()) do
			if os.clock() - started > timeout then break end
			if wp.Action == Enum.PathWaypointAction.Jump then hum.Jump = true end
			hum:MoveTo(wp.Position)
			local t0 = os.clock()
			while (hrp.Position - wp.Position).Magnitude > 4 and os.clock() - t0 < 2.5 do task.wait(0.1) end
		end
	else
		hum:MoveTo(target)
		while (hrp.Position - target).Magnitude > 6 and os.clock() - started < timeout do task.wait(0.2) end
	end
	return (hrp.Position - target).Magnitude <= 12
end
local function zonePart(...)
	local zones = workspace:FindFirstChild("Zones")
	if not zones then return nil end
	for _, needle in ipairs({ ... }) do
		needle = string.lower(needle)
		for _, inst in ipairs(zones:GetDescendants()) do
			if inst:IsA("BasePart") and string.find(string.lower(inst.Name), needle, 1, true) then
				return inst
			end
		end
	end
	return nil
end
local State = {
	rollCount = 0, rollStartedAt = os.clock(), lastDrop = "\226\128\148",
	autoPlaceOn = false, towerHold = false, towerPrepare = false,
	busy = nil,
	dead = false,
}
local Toggles = {}
local Window
local function notify(title, content, kind, duration)
	if not Window then return end
	pcall(function()
		Window:Notify({ Title = title, Content = content, Type = kind or "Success", Duration = duration or 3 })
	end)
end
local function autoToggle(tab, o)
	local generation = 0
	local toggle = tab:CreateToggle({
		Name = o.name, Desc = o.desc, Default = false, Flag = o.flag,
		Callback = function(on)
			generation = generation + 1
			local mine = generation
			if o.onChange then pcall(o.onChange, on) end
			if not on then return end
			task.spawn(function()
				while generation == mine and not State.dead do
					local ok, err = pcall(o.pass)
					if not ok then dbg(o.name, err) end
					local p = o.period
					if type(p) == "function" then p = p() end
					task.wait(math.max(num(p, 1), 0.05))
				end
			end)
		end,
	})
	Toggles[#Toggles + 1] = toggle
	return toggle
end
local function withCharacter(name, fn)
	local waited = 0
	while (State.busy and State.busy ~= name) or State.towerHold do
		task.wait(0.5)
		waited = waited + 0.5
		if waited > 60 or State.dead then return false end
	end
	State.busy = name
	local ok, err = pcall(fn)
	if State.busy == name then State.busy = nil end
	if not ok then dbg(name, err) end
	return ok
end
local function goAndBack(name, zone, action)
	return withCharacter(name, function()
		local hrp = rootPart()
		if not hrp then return end
		local home = hrp.Position
		local part = zone()
		if part then walkTo(part.Position, 30) end
		action()
		task.wait(0.3)
		if rootPart() then walkTo(home, 30) end
	end)
end
local function loadUI()
	local source
	if type(isfile) == "function" and type(readfile) == "function" and isfile(CONFIG.UIFile) then
		source = readfile(CONFIG.UIFile)
	else
		source = game:HttpGet(CONFIG.UIUrl)
	end
	return loadstring(source)()
end
local Airflow = loadUI()
if not CONFIG.Fleet then Airflow.AutoFleet = false end
if not CONFIG.Analytics then Airflow.AnalyticsURL = "" end
if type(Airflow.SetTheme) == "function" then pcall(Airflow.SetTheme, Airflow, CONFIG.Theme) end
if type(Airflow.SetScriptName) == "function" then pcall(Airflow.SetScriptName, Airflow, "Anime-Dice") end
Window = Airflow:CreateWindow({
	Name = "Anime Dice",
	Subtitle = "Auto-farm hub",
	Icon = "dices",
	ToggleUIKeybind = "RightControl",
	Size = UDim2.fromOffset(680, 480),
	MinSize = Vector2.new(520, 340),
	KeepOnScreen = true,
	ConfigurationSaving = {
		Enabled = true,
		FolderName = CONFIG.ConfigFolder,
		FileName = CONFIG.ConfigFile,
		AutoLoad = true,
	},
	OpenButton = { Title = "Anime Dice", Icon = "dices" },
})
local function nextRebirth()
	for _, name in ipairs({ "RebirthConfig", "Rebirth", "RebirthUtil" }) do
		local r = callFn(Module(name), "GetNext", rebirths())
		if type(r) == "table" then return r end
	end
	return nil
end
local function dropdownOf(tab, o)
	return tab:CreateDropdown({
		Name = o.name, Desc = o.desc, Options = o.options or {}, Multi = o.multi == true,
		Default = o.default, Flag = o.flag, Callback = o.callback or function() end,
	})
end
local function sliderOf(tab, o)
	return tab:CreateSlider({
		Name = o.name, Desc = o.desc, Min = o.min, Max = o.max, Step = o.step or 1,
		Default = o.default, Suffix = o.suffix, Flag = o.flag, Callback = o.callback or function() end,
	})
end
do
	local tab = Window:CreateTab({ Name = "Dashboard", Desc = "Live account stats", Icon = "layout-dashboard" })
	tab:CreateSection("Account")
	tab:CreateLabel({ Text = "Money: \226\128\166", UpdateRate = 1, Update = function()
		local m = money()
		return m and ("Money: $" .. fmt(m)) or "Money: ?"
	end })
	tab:CreateLabel({ Text = "Rebirth: \226\128\166", UpdateRate = 2, Update = function()
		local r = dataField("Rebirth", "Rebirths")
		if r == nil then return "Rebirth: ?" end
		r = num(r)
		local nxt = nextRebirth()
		if not nxt then return string.format("Rebirth %d  \194\183  max reached", r) end
		local cost = num(nxt.cost, 0)
		local pct = cost > 0 and math.min((money() or 0) / cost, 1) * 100 or 100
		return string.format("Rebirth %d  \194\183  next $%s (%.0f%%)", r, fmt(cost), pct)
	end })
	tab:CreateLabel({ Text = "Currencies: \226\128\166", UpdateRate = 2, Update = function()
		return string.format("Gems %s  \194\183  Trait Rerolls %s  \194\183  Tickets %s",
			fmt(amountOf("Gems")), fmt(amountOf("Trait Reroll")), fmt(amountOf("Tickets")))
	end })
	tab:CreateSection("Multipliers")
	tab:CreateLabel({ Text = "Buffs: \226\128\166", UpdateRate = 2, Update = function()
		return string.format("Luck x%s  \194\183  Money x%s  \194\183  Damage x%s",
			fmt(buff("Luck") or 1), fmt(buff("Money Multiplier") or 1), fmt(buff("Damage Multiplier") or 1))
	end })
	tab:CreateSection("Session")
	tab:CreateLabel({ Text = "Rolls: \226\128\166", UpdateRate = 1, Update = function()
		local minutes = math.max((os.clock() - State.rollStartedAt) / 60, 1 / 60)
		return string.format("Rolls %d (%.1f/min)  \194\183  Last: %s", State.rollCount, State.rollCount / minutes, State.lastDrop)
	end })
	tab:CreateButton({
		Name = "Stop everything", Desc = "Turns every automation off at once", Icon = "octagon-x",
		Callback = function()
			Window:Confirm({
				Title = "Stop everything?", Content = "Every automation will be turned off.",
				Callback = function()
					for _, t in ipairs(Toggles) do pcall(t.Set, t, false) end
					notify("Stopped", "All automations are off.", "Warning", 4)
				end,
			})
		end,
	})
end
do
	local tab = Window:CreateTab({ Name = "Farm", Desc = "Rolling, dice and plot income", Icon = "dices" })
	tab:CreateSection("Rolling")
	local ALWAYS = "Always (even without an event)"
	local rollEvents = { ALWAYS }
	local function weatherEvents()
		local names = {}
		local folder = ReplicatedStorage:FindFirstChild("Weather Events", true)
		if folder then
			for _, child in ipairs(folder:GetChildren()) do
				if not string.find(child.Name, "Admin", 1, true) then names[#names + 1] = child.Name end
			end
		end
		table.sort(names)
		return names
	end
	local weatherComm
	local function activeWeather()
		local ok, value = pcall(function()
			if not weatherComm then
				local pk = ReplicatedStorage:FindFirstChild("Packages")
				local clientComm = require(pk.Network.ClientComm)
				weatherComm = clientComm.new(Network, false, "WeatherService")
			end
			return weatherComm:GetProperty("ActiveWeather"):Get()
		end)
		if ok and value ~= nil then return nameOf(value) or tostring(value) end
		local attr = ReplicatedStorage:GetAttribute("ActiveWeather")
		return attr ~= nil and tostring(attr) or nil
	end
	local function rollAllowed()
		if contains(rollEvents, ALWAYS) then return true end
		local weather = activeWeather()
		return weather ~= nil and contains(rollEvents, weather)
	end
	local function rollCooldown()
		local v = buff("Roll Duration")
		if v and v > 0.05 and v < 30 then return v end
		return 2.5
	end
	local function unitCapacity()
		local cap = 100 + num(buff("Unit Storage"), 0)
		local used = 0
		for _, u in ipairs(listUnits()) do used = used + u.amount end
		return used, cap
	end
	local rollWaiting = false
	autoToggle(tab, {
		name = "Fast Roll",
		desc = "Rolls as fast as the server cooldown allows, skipping the animation",
		flag = "AnimeDiceFastRoll",
		period = function() return 0.05 end,
		pass = function()
			if not rollAllowed() then rollWaiting = true task.wait(1) return end
			rollWaiting = false
			local ok, res = send("RollService", "RollDice")
			if ok and res ~= nil and res ~= false then
				local parts = {}
				local list = type(res) == "table" and (res.results or res.Results or res) or {}
				for _, r in ipairs(list) do
					if type(r) == "table" then
						local text = tostring(r.result or r.name or r.unit or "?")
						if r.mutation then text = tostring(r.mutation) .. " " .. text end
						parts[#parts + 1] = text
					end
				end
				State.rollCount = State.rollCount + math.max(#parts, 1)
				if #parts > 0 then State.lastDrop = table.concat(parts, ", ") end
				task.wait(math.max(rollCooldown() - 0.05, 0.1))
			else
				task.wait(0.25)
			end
		end,
	})
	local eventDropdown = dropdownOf(tab, {
		name = "Roll during events",
		desc = "Fast Roll only rolls while one of the ticked events is active. The default rolls all the time",
		options = { ALWAYS }, multi = true, default = { ALWAYS }, flag = "AnimeDiceRollEvents",
		callback = function(sel) rollEvents = type(sel) == "table" and sel or { sel } end,
	})
	task.spawn(function()
		local options = { ALWAYS }
		for _, n in ipairs(weatherEvents()) do options[#options + 1] = n end
		if #options > 1 then pcall(eventDropdown.Refresh, eventDropdown, options, true) end
	end)
	tab:CreateLabel({ Text = "Cooldown: \226\128\166", UpdateRate = 1, Update = function()
		if rollWaiting then return "Paused \226\128\148 waiting for a selected event" end
		local used, cap = unitCapacity()
		local inv = used > 0 and string.format("%d/%d units", used, cap) or "? units"
		if used >= cap then inv = inv .. " \226\128\148 FULL, enable Auto Sell" end
		return string.format("Cooldown %.2fs  \194\183  Inventory %s", rollCooldown(), inv)
	end })
	tab:CreateButton({
		Name = "Reset roll counter", Desc = "Restarts the rolls/min stat on the Dashboard",
		Callback = function() State.rollCount, State.rollStartedAt = 0, os.clock() end,
	})
	tab:CreateSection("Dice")
	local function diceList()
		local raw = callFn(Module("Dice"), "GetAll")
		local list = {}
		if type(raw) == "table" then
			for k, v in pairs(raw) do
				if type(v) == "table" then
					list[#list + 1] = {
						name = v.name or v.Name or (type(k) == "string" and k) or tostring(k),
						price = num(v.price or v.Price, 0), luck = num(v.luck or v.Luck, 0),
					}
				end
			end
		end
		table.sort(list, function(a, b)
			if a.price ~= b.price then return a.price < b.price end
			return a.name < b.name
		end)
		return list
	end
	local function ownedDice()
		local set, raw = {}, dataField("OwnedDice")
		if type(raw) == "table" then
			for k, v in pairs(raw) do
				if type(k) == "string" and v then set[k] = true elseif type(v) == "string" then set[v] = true end
			end
		end
		return set
	end
	local function equipBestDice(list, owned)
		local best
		for _, d in ipairs(list) do
			if owned[d.name] and (not best or d.luck > best.luck) then best = d end
		end
		if best and dataField("Dice") ~= best.name and throttle("equipdice:" .. best.name, 8) then
			send("DiceShopService", "EquipDice", best.name)
			return best.name
		end
		return nil
	end
	autoToggle(tab, {
		name = "Auto Buy Dice",
		desc = "Buys every dice you can afford, best first, then equips the best one",
		flag = "AnimeDiceAutoBuyDice", period = 0.6,
		pass = function()
			local list, owned, m = diceList(), ownedDice(), money() or 0
			for i = #list, 1, -1 do
				local d = list[i]
				if not owned[d.name] and d.price > 0 and m >= d.price then
					send("DiceShopService", "BuyDice", d.name)
					m, owned[d.name] = m - d.price, true
					task.wait(0.3)
				end
			end
			equipBestDice(list, owned)
		end,
	})
	tab:CreateLabel({ Text = "Dice: \226\128\166", UpdateRate = 2, Update = function()
		local list, owned = diceList(), ownedDice()
		local current = dataField("Dice")
		local equipped = current ~= nil and tostring(current) or "?"
		for _, d in ipairs(list) do
			if not owned[d.name] then
				return string.format("Equipped: %s  \194\183  next: %s ($%s)", equipped, d.name, fmt(d.price))
			end
		end
		if #list == 0 then return "Dice: ?" end
		return string.format("Equipped: %s  \194\183  every dice owned", equipped)
	end })
	tab:CreateButton({
		Name = "Equip best owned dice", Desc = "Use this if you bought a dice by hand",
		Callback = function()
			task.spawn(function()
				local list = diceList()
				local name = equipBestDice(list, ownedDice())
				notify("Dice", name and ("Equipped: " .. name) or "Already the best.", "Success")
			end)
		end,
	})
	tab:CreateSection("Plot")
	local collectInterval, equipInterval = 1, 10
	local function plotWaiting()
		local total, list = 0, {}
		for idx, slot in pairs(slotTable()) do
			if type(slot) == "table" then
				local b = num(slot.balance, 0)
				if b > 0 then total = total + b list[#list + 1] = idx end
			end
		end
		table.sort(list, function(a, b) return (tonumber(a) or 0) < (tonumber(b) or 0) end)
		return total, list
	end
	local function collectAll()
		local total, list = plotWaiting()
		for _, idx in ipairs(list) do
			send("PlotService", "CollectBalance", idx)
			task.wait(0.05)
		end
		return #list, total
	end
	autoToggle(tab, {
		name = "Auto Collect", desc = "Moves the money waiting on your plot slots into your balance",
		flag = "AnimeDiceAutoCollect", period = function() return collectInterval end,
		pass = collectAll,
	})
	sliderOf(tab, { name = "Collect interval", min = 0.1, max = 60, step = 0.1, default = 1, suffix = "s",
		flag = "AnimeDiceCollectInterval", callback = function(v) collectInterval = math.max(num(v, 1), 0.1) end })
	autoToggle(tab, {
		name = "Auto Equip Best",
		desc = "Keeps your highest-income units on the plot (paused while AutoPlace is on)",
		flag = "AnimeDiceAutoEquipBest", period = function() return equipInterval end,
		pass = function()
			if State.autoPlaceOn then return end
			send("PlotService", "EquipBest")
		end,
	})
	sliderOf(tab, { name = "Equip interval", min = 1, max = 120, step = 1, default = 10, suffix = "s",
		flag = "AnimeDiceEquipInterval", callback = function(v) equipInterval = math.max(num(v, 10), 1) end })
	tab:CreateLabel({ Text = "Waiting on plot: \226\128\166", UpdateRate = 1, Update = function()
		local total, list = plotWaiting()
		return string.format("Waiting on plot: $%s on %d slot(s)", fmt(total), #list)
	end })
	tab:CreateButton({
		Name = "Collect now",
		Callback = function()
			task.spawn(function()
				local n, total = collectAll()
				if n > 0 then notify("Collect", string.format("%d slots  \194\183  +$%s", n, fmt(total)))
				else notify("Collect", "Nothing to collect.", "Warning") end
			end)
		end,
	})
	tab:CreateSection("Gear")
	local gearPriority = "Luck"
	local function gearBuffNames()
		local set = {}
		local cfgMod = Module("GearConfig")
		local src = type(cfgMod) == "table" and (cfgMod.entries or cfgMod.Entries) or nil
		if type(src) ~= "table" then src = entriesOfKind("Gear") end
		for _, cfg in pairs(src) do
			local b = type(cfg) == "table" and (cfg.buffs or cfg.Buffs)
			if type(b) == "table" then for name in pairs(b) do set[name] = true end end
		end
		local list = sortedKeys(set)
		if #list == 0 then list = { "Luck" } end
		return list
	end
	local function equipBestGear()
		local best = {}
		for key, entry in pairs(entries()) do
			local cfg = entryConfig(entry, key)
			if cfg and cfg.kind == "Gear" and num(entry.amount, 1) > 0 then
				local b = type(cfg.buffs) == "table" and cfg.buffs[gearPriority]
				local score = type(b) == "table" and num(b.amount or b.value or b[1], 0) or num(b, 0)
				local slot = cfg.slot or "?"
				if not best[slot] or score > best[slot].score then
					best[slot] = { name = cfg.name or entry.name or key, score = score }
				end
			end
		end
		local equipped = dataField("EquippedGear")
		local changed = 0
		for slot, pick in pairs(best) do
			local current = type(equipped) == "table" and equipped[slot] or nil
			if nameOf(current) ~= pick.name and throttle("gear:" .. tostring(pick.name), 10) then
				send("GearService", "Equip", pick.name)
				changed = changed + 1
				task.wait(0.3)
			end
		end
		return changed
	end
	autoToggle(tab, {
		name = "Auto Equip Best Gear",
		desc = "Keeps the best owned gear in every slot for the stat picked below",
		flag = "AnimeDiceAutoGear", period = 5, pass = equipBestGear,
	})
	local gearOptions = gearBuffNames()
	dropdownOf(tab, { name = "Gear priority", desc = "Which bonus to favour when choosing gear",
		options = gearOptions, default = contains(gearOptions, "Luck") and "Luck" or gearOptions[1],
		flag = "AnimeDiceGearPriority", callback = function(v) gearPriority = nameOf(v) or "Luck" end })
	tab:CreateButton({
		Name = "Equip best gear now",
		Callback = function()
			task.spawn(function()
				local n = equipBestGear()
				notify("Gear", n > 0 and string.format("%d slot(s) changed", n) or "Already the best.")
			end)
		end,
	})
	tab:CreateSection("Spins")
	local chosenSpins = {}
	local function spinList()
		local list = {}
		for name, cfg in pairs(entriesOfKind("Spin")) do
			if type(cfg) == "table" then
				list[#list + 1] = { name = cfg.name or (type(name) == "string" and name) or tostring(name),
					luck = num(cfg.luckMultiplier or cfg.luck, 0) }
			end
		end
		table.sort(list, function(a, b)
			if a.luck ~= b.luck then return a.luck > b.luck end
			return a.name < b.name
		end)
		return list
	end
	local function spinActive()
		local active = dataField("ActiveEntries")
		if type(active) ~= "table" then return false end
		for key, e in pairs(active) do
			local cfg = entryConfig(type(e) == "table" and e or nil, key)
			if cfg and cfg.kind == "Spin" then return true end
		end
		return false
	end
	autoToggle(tab, {
		name = "Auto Use Spins",
		desc = "Queues one ticked spin at a time (best luck first). A spin makes that roll a single roll",
		flag = "AnimeDiceAutoSpins", period = 1,
		pass = function()
			if spinActive() then return end
			for _, s in ipairs(spinList()) do
				if contains(chosenSpins, s.name) and amountOf(s.name) > 0 then
					send("SpinService", "Use", s.name)
					return
				end
			end
		end,
	})
	local spinNames = {}
	for _, s in ipairs(spinList()) do spinNames[#spinNames + 1] = s.name end
	dropdownOf(tab, { name = "Spins to use", desc = "Nothing ticked = nothing used", options = spinNames,
		multi = true, default = {}, flag = "AnimeDiceSpinChoices",
		callback = function(sel) chosenSpins = type(sel) == "table" and sel or {} end })
end
local function unitPicker()
	local picker = { labelToKey = {} }
	function picker.build()
		local list = listUnits()
		table.sort(list, function(a, b)
			if a.chance ~= b.chance then return a.chance > b.chance end
			return a.name < b.name
		end)
		local labels, seen = {}, {}
		picker.labelToKey = {}
		for _, u in ipairs(list) do
			local label = unitLabel(u)
			seen[label] = (seen[label] or 0) + 1
			if seen[label] > 1 then label = label .. " #" .. seen[label] end
			labels[#labels + 1] = label
			picker.labelToKey[label] = u.key
		end
		return labels
	end
	return picker
end
do
	local tab = Window:CreateTab({ Name = "Units", Desc = "Level up, grades and traits", Icon = "sparkles" })
	tab:CreateSection("Level Up")
	local level = { target = 10, rarity = "Common", tried = {} }
	local function levelPrice(u)
		for _, modName in ipairs({ "PlotConfig", "UnitUtil" }) do
			local mod = Module(modName)
			for _, args in ipairs({ { u.cfg, u.level }, { u.level, u.cfg }, { u.level } }) do
				local p = tonumber(callFn(mod, "GetLevelPrice", table.unpack(args)))
				if p and p >= 0 then return p end
			end
		end
		return nil
	end
	local function levelUpPass()
		local units = {}
		for _, u in ipairs(listUnits()) do units[u.key] = u end
		local slots, idxs = slotTable(), {}
		for idx in pairs(slots) do idxs[#idxs + 1] = idx end
		table.sort(idxs, function(a, b) return (tonumber(a) or 0) < (tonumber(b) or 0) end)
		local m, done, minIdx = money() or 0, 0, RARITY_INDEX[level.rarity] or 1
		for _, idx in ipairs(idxs) do
			local u = units[slotUnitId(slots[idx])]
			if u and (RARITY_INDEX[u.rarity] or 1) >= minIdx and u.level < level.target then
				local price, now = levelPrice(u), os.clock()
				if price then
					if m >= price then
						send("PlotService", "LevelUpSlot", idx)
						m, done = m - price, done + 1
						task.wait(0.15)
					end
				elseif now - (level.tried[idx] or 0) > 2 and m > 0 then
					level.tried[idx] = now
					send("PlotService", "LevelUpSlot", idx)
					done = done + 1
					task.wait(0.15)
				end
			end
		end
		return done
	end
	autoToggle(tab, {
		name = "Auto Level Up", desc = "Levels up your plotted units while you can afford it",
		flag = "AnimeDiceAutoLevelUp", period = 0.5, pass = levelUpPass,
	})
	tab:CreateStepper({
		Name = "Target level", Desc = "Stops leveling a unit once it reaches this level",
		Min = 1, Max = 1000, Step = 1, Default = 10, Flag = "AnimeDiceLevelUpTarget",
		Callback = function(v) level.target = num(v, 10) end,
	})
	dropdownOf(tab, {
		name = "Minimum rarity", desc = "Plotted units below this rarity are left alone",
		options = RARITIES, default = "Common", flag = "AnimeDiceLevelUpRarity",
		callback = function(v) level.rarity = nameOf(v) or "Common" end,
	})
	tab:CreateButton({
		Name = "Level up now",
		Callback = function()
			task.spawn(function()
				local n = levelUpPass()
				notify("Level Up", n > 0 and string.format("%d level(s)", n) or "Nothing to level.",
					n > 0 and "Success" or "Warning")
			end)
		end,
	})
	local function rerollSection(spec)
		tab:CreateSection(string.format("%s (uses %s)", spec.title, spec.currency))
		local lower = string.lower(spec.title)
		local tierList = tiers(spec.tiersModule)
		local map, names, firstProtected = tierMap(tierList), {}, nil
		for _, t in ipairs(tierList) do
			names[#names + 1] = t.name
			if t.protected and not firstProtected then firstProtected = t.name end
		end
		local st = { units = {}, target = map[spec.defaultTarget] and spec.defaultTarget or names[#names], overwrite = false }
		local picker = unitPicker()
		local labels = picker.build()
		local function pass()
			local count, target = 0, map[st.target]
			if not target then return 0 end
			local all = entries()
			for _, label in ipairs(st.units) do
				local key = picker.labelToKey[label]
				local entry = key and all[key]
				if entry then
					if amountOf(spec.currency) <= 0 then return count end
					local attrs = type(entry.attributes) == "table" and entry.attributes or {}
					local cur = map[attrs[spec.attribute]]
					local blocked = cur and cur.protected and not st.overwrite
					if (cur and cur.index or 0) < target.index and not blocked then
						send(spec.service, "Roll", key)
						count = count + 1
						task.wait(0.15)
					end
				end
			end
			return count
		end
		autoToggle(tab, {
			name = "Auto " .. spec.title,
			desc = string.format("Rerolls the ticked units' %ss until they reach the minimum", lower),
			flag = spec.flags.enabled, period = 0.3, pass = pass,
		})
		local unitsDropdown = dropdownOf(tab, {
			name = "Units to " .. lower, desc = "Your units by drop chance, rarest first \226\128\148 rolled in that order",
			options = labels, multi = true, default = {}, flag = spec.flags.units,
			callback = function(sel) st.units = type(sel) == "table" and sel or {} end,
		})
		tab:CreateButton({
			Name = "Refresh unit list",
			Callback = function() pcall(unitsDropdown.Refresh, unitsDropdown, picker.build(), true) end,
		})
		dropdownOf(tab, {
			name = "Minimum " .. lower, desc = "Rerolling stops once a unit reaches this " .. lower,
			options = names, default = st.target, flag = spec.flags.target,
			callback = function(v) st.target = nameOf(v) or st.target end,
		})
		tab:CreateToggle({
			Name = "Overwrite protected " .. lower .. "s",
			Desc = string.format("Allows rerolling %s and above \226\128\148 you can lose them", tostring(firstProtected or "protected tiers")),
			Default = false, Flag = spec.flags.overwrite,
			Callback = function(on) st.overwrite = on == true end,
		})
		tab:CreateButton({
			Name = "Roll " .. lower .. "s now",
			Callback = function()
				task.spawn(function()
					local n = pass()
					notify(spec.title, n > 0 and string.format("%d roll(s)", n) or "Nothing to roll.", n > 0 and "Success" or "Warning")
				end)
			end,
		})
	end
	rerollSection({ title = "Grade", service = "GradeService", currency = "Gems", attribute = "grade",
		tiersModule = "Grades", defaultTarget = "S",
		flags = { enabled = "AnimeDiceAutoGrade", units = "AnimeDiceGradeUnits", target = "AnimeDiceGradeTarget", overwrite = "AnimeDiceGradeOverwrite" } })
	rerollSection({ title = "Trait", service = "TraitService", currency = "Trait Reroll", attribute = "trait",
		tiersModule = "Traits", defaultTarget = "Damage I",
		flags = { enabled = "AnimeDiceAutoTrait", units = "AnimeDiceTraitUnits", target = "AnimeDiceTraitTarget", overwrite = "AnimeDiceTraitOverwrite" } })
	tab:CreateSection("Quirk (costs Money)")
	local quirkTiers = tiers("Quirks")
	table.sort(quirkTiers, function(a, b)
		if a.weight ~= b.weight then return a.weight < b.weight end
		return tostring(a.name) < tostring(b.name)
	end)
	local quirkNames = {}
	for _, q in ipairs(quirkTiers) do quirkNames[#quirkNames + 1] = q.name end
	local quirk = { units = {}, targets = {}, maxPercent = 5, overwrite = false }
	local quirkPicker = unitPicker()
	local quirkLabels = quirkPicker.build()
	local function quirkProtected(name)
		local util = Module("QuirkUtil")
		local list = type(util) == "table" and util.ProtectedQuirks or nil
		if type(list) ~= "table" then return false end
		return list[name] == true or contains(list, name)
	end
	local function quirkPass()
		local util, wanted, all, m, count = Module("QuirkUtil"), toSet(quirk.targets), entries(), money() or 0, 0
		if next(wanted) == nil then return 0 end
		for _, label in ipairs(quirk.units) do
			local key = quirkPicker.labelToKey[label]
			local entry = key and all[key]
			if entry then
				local attrs = type(entry.attributes) == "table" and entry.attributes or {}
				local held = attrs.quirk
				local skip = (held and wanted[held]) or (held and quirkProtected(held) and not quirk.overwrite)
				if not skip then
					local cost = tonumber(callFn(util, "GetRollCost", entry)) or tonumber(callFn(util, "GetRollCost", key))
					if cost and cost > m * quirk.maxPercent / 100 then return count end
					send("QuirkService", "Roll", key)
					if cost then m = m - cost end
					count = count + 1
					task.wait(0.3)
				end
			end
		end
		return count
	end
	autoToggle(tab, {
		name = "Auto Quirk", desc = "Rerolls the ticked units until they hold one of the wanted quirks",
		flag = "AnimeDiceAutoQuirk", period = 1, pass = quirkPass,
	})
	local quirkUnitsDropdown = dropdownOf(tab, {
		name = "Units to quirk", desc = "Your units by drop chance, rarest first",
		options = quirkLabels, multi = true, default = {}, flag = "AnimeDiceQuirkUnits",
		callback = function(sel) quirk.units = type(sel) == "table" and sel or {} end,
	})
	tab:CreateButton({
		Name = "Refresh quirk unit list",
		Callback = function() pcall(quirkUnitsDropdown.Refresh, quirkUnitsDropdown, quirkPicker.build(), true) end,
	})
	dropdownOf(tab, {
		name = "Wanted quirks", desc = "Rarest first. A unit holding any ticked quirk is left alone",
		options = quirkNames, multi = true, default = {}, flag = "AnimeDiceQuirkTargets",
		callback = function(sel) quirk.targets = type(sel) == "table" and sel or {} end,
	})
	sliderOf(tab, {
		name = "Max cost per roll", desc = "Stops when one roll would cost more than this share of your Money",
		min = 0, max = 100, step = 1, default = 5, suffix = "%", flag = "AnimeDiceQuirkMaxPercent",
		callback = function(v) quirk.maxPercent = num(v, 5) end,
	})
	tab:CreateToggle({
		Name = "Overwrite protected quirks",
		Desc = "Rare quirks are protected by default in the game; this lets the script replace them",
		Default = false, Flag = "AnimeDiceQuirkOverwrite",
		Callback = function(on) quirk.overwrite = on == true end,
	})
	tab:CreateSection("Fuse (destroys 3 units per fusion)")
	local fuse = { rarity = "Common", mutated = false, maxPercent = 10, count = 0, eligible = 0, last = "\226\128\148" }
	local function fuseCandidates()
		local placed, maxIdx, out = placedSet(), RARITY_INDEX[fuse.rarity] or 1, {}
		for _, u in ipairs(listUnits()) do
			if not placed[u.key] and not u.locked and (RARITY_INDEX[u.rarity] or 1) <= maxIdx
				and (not u.mutation or fuse.mutated) then
				for _ = 1, math.max(math.floor(u.amount), 1) do out[#out + 1] = u end
			end
		end
		table.sort(out, function(a, b)
			if a.chance ~= b.chance then return a.chance < b.chance end
			return tostring(a.key) < tostring(b.key)
		end)
		return out
	end
	local function describeUnit(v)
		if type(v) ~= "table" then return tostring(v) end
		local a = type(v.attributes) == "table" and v.attributes or v
		return (a.mutation and (tostring(a.mutation) .. " ") or "") .. tostring(v.name or v.unit or "?")
	end
	task.spawn(function()
		local r = Remote("FusingService", "Result")
		if r and r:IsA("RemoteEvent") then
			pcall(function()
				r.OnClientEvent:Connect(function(...)
					local first = ...
					fuse.last = "\226\134\146 " .. describeUnit(first)
				end)
			end)
		end
	end)
	autoToggle(tab, {
		name = "Auto Fuse",
		desc = "Fuses the three lowest-chance eligible units into one better unit. Plotted, tower-team and locked units are never used",
		flag = "AnimeDiceAutoFuse", period = 1,
		pass = function()
			local list = fuseCandidates()
			fuse.eligible = #list
			if #list < 3 then return end
			local group = { list[1], list[2], list[3] }
			local fusing = Module("FusingUtil") or Module("Fusing")
			local cost = tonumber(callFn(fusing, "GetCost", group[3].chance))
			if cost and cost > (money() or 0) * fuse.maxPercent / 100 then task.wait(3) return end
			if not throttle("fuse:" .. tostring(group[1].key) .. tostring(group[2].key) .. tostring(group[3].key), 6) then
				task.wait(1)
				return
			end
			send("FusingService", "Fuse", { group[1].key, group[2].key, group[3].key })
			fuse.count = fuse.count + 1
			task.wait(0.5)
		end,
	})
	dropdownOf(tab, {
		name = "Fuse units up to rarity", desc = "Shown rarity, mutation included",
		options = RARITIES, default = "Common", flag = "AnimeDiceFuseRarity",
		callback = function(v) fuse.rarity = nameOf(v) or "Common" end,
	})
	tab:CreateToggle({
		Name = "Fuse mutated units too", Default = false, Flag = "AnimeDiceFuseMutated",
		Callback = function(on) fuse.mutated = on == true end,
	})
	sliderOf(tab, {
		name = "Max fusion cost", desc = "Stops when a fusion would cost more than this share of your Money",
		min = 0, max = 100, step = 1, default = 10, suffix = "%", flag = "AnimeDiceFuseMaxPercent",
		callback = function(v) fuse.maxPercent = num(v, 10) end,
	})
	tab:CreateLabel({ Text = "Fuse: \226\128\166", UpdateRate = 2, Update = function()
		return string.format("Fused %d  \194\183  %d eligible  \194\183  last: %s", fuse.count, fuse.eligible, fuse.last)
	end })
	tab:CreateSection("Awakening (needs spare copies of the unit)")
	local awaken = { plottedOnly = true, maxPercent = 25, count = 0, last = "\226\128\148", nextText = "none ready", refused = {} }
	local function awakenCandidates()
		local util = Module("AwakeningUtil")
		local cfgMod = Module("AwakeningConfig")
		if not util then return {} end
		local maxStars = num(util.MAX_STARS or (type(cfgMod) == "table" and cfgMod.MAX_STARS), 5)
		local placed, m, out = placedSet(), money() or 0, {}
		local moneyMult = num(buff("Money Multiplier"), 1)
		local budget = m * awaken.maxPercent / 100
		for _, u in ipairs(listUnits()) do
			local eligible = not awaken.plottedOnly or placed[u.key]
			local refusedAt = awaken.refused[u.key]
			if eligible and not (refusedAt and os.clock() - refusedAt < 60) then
				local stars = num(callFn(util, "GetStars", u.entry) or callFn(util, "GetStars", u.key), 0)
				if stars < maxStars then
					local nxt = callFn(util, "GetNextStar", u.entry) or callFn(util, "GetNextStar", stars)
					local copies = num(callFn(util, "GetCopies", u.entry) or callFn(util, "GetCopies", u.key), 0)
					local need = type(nxt) == "table" and num(nxt.copies, 1) or 1
					local cost = type(nxt) == "table" and num(nxt.cost, 0) or 0
					if copies >= need and cost <= budget and (nxt ~= nil) then
						out[#out + 1] = { key = u.key, name = u.name, star = stars + 1,
							income = num(u.cfg.income, 0) * moneyMult }
					end
				end
			end
		end
		table.sort(out, function(a, b) return a.income > b.income end)
		return out
	end
	local function awakenRun()
		local list = awakenCandidates()
		if #list == 0 then return 0 end
		local done = 0
		goAndBack("Awakening", function() return zonePart("awaken", "altar") end, function()
			for _, c in ipairs(list) do
				local ok, res = call(Remote("AwakeningService", "Awaken"), c.key)
				if ok and res ~= false and res ~= nil then
					done = done + 1
					awaken.count = awaken.count + 1
					awaken.last = string.format("%s \226\134\146 %d\226\152\133", c.name, c.star)
				else
					awaken.refused[c.key] = os.clock()
				end
				task.wait(0.6)
			end
		end)
		return done
	end
	autoToggle(tab, {
		name = "Auto Awaken",
		desc = "Walks to the Awakening Altar when a unit can rank up, then walks back. Copies are consumed: turn off Auto Sell for the rarities you want to awaken",
		flag = "AnimeDiceAutoAwaken", period = 5, pass = awakenRun,
	})
	tab:CreateToggle({
		Name = "Only plotted and tower-team units", Desc = "Skips units that are only sitting in the inventory",
		Default = true, Flag = "AnimeDiceAwakenPlottedOnly",
		Callback = function(on) awaken.plottedOnly = on == true end,
	})
	sliderOf(tab, {
		name = "Max awaken cost", desc = "Skips an awakening that would cost more than this share of your Money",
		min = 0, max = 100, step = 1, default = 25, suffix = "%", flag = "AnimeDiceAwakenMaxPercent",
		callback = function(v) awaken.maxPercent = num(v, 25) end,
	})
	tab:CreateButton({
		Name = "Awaken now",
		Callback = function()
			task.spawn(function()
				local n = awakenRun()
				notify("Awakening", n > 0 and string.format("%d unit(s) awakened", n) or "Nothing ready to awaken.",
					n > 0 and "Success" or "Warning")
			end)
		end,
	})
	tab:CreateLabel({ Text = "Awakening: \226\128\166", UpdateRate = 3, Update = function()
		local list = awakenCandidates()
		local nxt = list[1] and string.format("%s \226\134\146 %d\226\152\133", list[1].name, list[1].star) or "none ready"
		return string.format("Awakened %d  \194\183  next: %s  \194\183  last: %s", awaken.count, nxt, awaken.last)
	end })
end
do
	local tab = Window:CreateTab({ Name = "AutoPlace", Desc = "Choose which units sit on your plot", Icon = "layout-grid" })
	local MODES = { "Best base (level 1 income)", "Best current income", "Rarest unit (1 in N)",
		"Best mutation", "Best grade", "Best trait", "Wanted quirks first" }
	local NONE = "None"
	local place = { mode = MODES[2], thenMode = NONE, quirks = {}, status = "Off." }
	local function incomeOf(u, base)
		if base then return num(u.cfg.income or u.cfg.baseIncome or u.cfg.Income, 0) end
		for _, modName in ipairs({ "UnitUtil", "PlotConfig" }) do
			local mod = Module(modName)
			for _, fname in ipairs({ "GetIncome", "GetUnitIncome", "CalculateIncome", "getIncome" }) do
				for _, arg in ipairs({ u.entry, u.cfg }) do
					local v = tonumber(callFn(mod, fname, arg))
					if v and v > 0 then return v end
				end
			end
		end
		return num(u.cfg.income or u.cfg.baseIncome or u.cfg.Income, 0) * math.max(u.level, 1)
	end
	local function unlockedSlots()
		local pc = Module("PlotConfig")
		local total = tonumber(callFn(pc, "GetMaxSlots", rebirths()))
		if total and total > 0 then
			local r, n = rebirths(), 0
			for i = 1, total do
				local req = tonumber(callFn(pc, "GetSlotRebirthRequirement", i)) or math.huge
				if req <= r then n = n + 1 end
			end
			if n > 0 then return n end
		end
		local n = 0
		for _ in pairs(slotTable()) do n = n + 1 end
		return n
	end
	local function buildContext()
		local rank = {}
		local order = {}
		for _, t in ipairs(tiers("Quirks")) do order[#order + 1] = t end
		table.sort(order, function(a, b)
			if a.weight ~= b.weight then return a.weight < b.weight end
			return tostring(a.name) < tostring(b.name)
		end)
		local wanted = toSet(place.quirks)
		local r = 0
		for _, t in ipairs(order) do
			if wanted[t.name] then r = r + 1 rank[t.name] = r end
		end
		return { grades = tierMap(tiers("Grades")), traits = tierMap(tiers("Traits")), quirkRank = rank, wanted = next(wanted) ~= nil }
	end
	local function scoreOf(u, mode, ctx)
		if mode == MODES[1] then return incomeOf(u, true)
		elseif mode == MODES[2] then return incomeOf(u, false)
		elseif mode == MODES[3] then return u.chance
		elseif mode == MODES[4] then return MUTATION_INDEX[tostring(u.mutation)] or 0
		elseif mode == MODES[5] then local t = ctx.grades[u.attrs.grade] return t and t.index or 0
		elseif mode == MODES[6] then local t = ctx.traits[u.attrs.trait] return t and t.index or 0
		elseif mode == MODES[7] then local r = ctx.quirkRank[u.attrs.quirk] return r and (1000 - r) or 0
		end
		return 0
	end
	local function autoPlacePass()
		if place.mode == MODES[7] and #place.quirks == 0 then
			place.status = "Tick at least one quirk."
			return 0
		end
		local slotCount = unlockedSlots()
		if slotCount <= 0 then place.status = "No slots found." return 0 end
		local ctx = buildContext()
		local inv = Inventory()
		local tower = {}
		if inv and type(inv.TowerTeam) == "table" then
			for _, v in pairs(inv.TowerTeam) do
				local id = slotUnitId(v) or (type(v) ~= "table" and v) or nil
				if id then tower[id] = true end
			end
		end
		local units = {}
		for _, u in ipairs(listUnits()) do
			if not tower[u.key] then
				u.p = scoreOf(u, place.mode, ctx)
				u.s = place.thenMode ~= NONE and scoreOf(u, place.thenMode, ctx) or 0
				u.income = incomeOf(u, false)
				units[#units + 1] = u
			end
		end
		table.sort(units, function(a, b)
			if a.p ~= b.p then return a.p > b.p end
			if a.s ~= b.s then return a.s > b.s end
			if a.income ~= b.income then return a.income > b.income end
			return tostring(a.key) < tostring(b.key)
		end)
		local desired, desiredSet = {}, {}
		for i = 1, math.min(slotCount, #units) do desired[i] = units[i] desiredSet[units[i].key] = true end
		local moved, stillPlaced = 0, {}
		local slots = slotTable()
		local idxs = {}
		for idx in pairs(slots) do idxs[#idxs + 1] = idx end
		table.sort(idxs, function(a, b) return (tonumber(a) or 0) < (tonumber(b) or 0) end)
		for _, idx in ipairs(idxs) do
			local id = slotUnitId(slots[idx])
			if id and not desiredSet[id] and not tower[id] then
				if throttle("pick:" .. tostring(idx), 8) then
					send("PlotService", "InteractSlot", idx)
					moved = moved + 1
					task.wait(0.15)
				end
			elseif id then
				stillPlaced[id] = true
			end
		end
		for _, u in ipairs(desired) do
			if not stillPlaced[u.key] and throttle("place:" .. tostring(u.key), 8) then
				send("UnitService", "Equip", u.key)
				moved = moved + 1
				task.wait(0.15)
			end
		end
		place.status = string.format("%d slot(s) unlocked  \194\183  %d unit(s) moved this pass", slotCount, moved)
		return moved
	end
	autoToggle(tab, {
		name = "Auto Place",
		desc = "Keeps the best units for the chosen strategy on your plot. Replaces Auto Equip Best while on",
		flag = "AnimeDiceAutoPlace", period = 3,
		onChange = function(on)
			State.autoPlaceOn = on
			if not on then place.status = "Off." end
		end,
		pass = autoPlacePass,
	})
	local thenOptions = { NONE }
	for _, m in ipairs(MODES) do thenOptions[#thenOptions + 1] = m end
	dropdownOf(tab, {
		name = "Place by",
		desc = "Base ignores level: a level 1 Secret beats a level 50 Legendary. Current income is what the game's own Equip Best uses",
		options = MODES, default = place.mode, flag = "AnimeDicePlaceMode",
		callback = function(v) place.mode = nameOf(v) or MODES[2] end,
	})
	dropdownOf(tab, {
		name = "Then by", desc = "Breaks ties between units that score the same on the first choice",
		options = thenOptions, default = NONE, flag = "AnimeDicePlaceThen",
		callback = function(v) place.thenMode = nameOf(v) or NONE end,
	})
	local quirkNames = {}
	for _, q in ipairs(tiers("Quirks")) do quirkNames[#quirkNames + 1] = q.name end
	dropdownOf(tab, {
		name = "Wanted quirks",
		desc = "Used by 'Wanted quirks first'. Rarest first; a unit holding any ticked quirk outranks the others",
		options = quirkNames, multi = true, default = {}, flag = "AnimeDicePlaceQuirks",
		callback = function(sel) place.quirks = type(sel) == "table" and sel or {} end,
	})
	tab:CreateLabel({ Text = "Status: \226\128\166", UpdateRate = 1, Update = function() return "Status: " .. place.status end })
	tab:CreateButton({
		Name = "Place now", Desc = "Runs one pass with the current strategy",
		Callback = function()
			task.spawn(function()
				local ok = pcall(autoPlacePass)
				if ok then place.status = place.status == "Off." and "Done." or place.status end
			end)
		end,
	})
end
do
	local tab = Window:CreateTab({ Name = "Sell", Desc = "Automatic selling rules", Icon = "coins" })
	local NO_MUT = "No mutation"
	local rule = { all = {}, rarities = {}, mutations = {}, interval = 10 }
	tab:CreateParagraph({
		Name = "How it works",
		Content = "A unit is sold if rule 1 OR rule 2 matches. Plotted and locked units are never sold. Rarity = the one shown in game.",
	})
	local function candidates()
		local placed = placedSet()
		local allSet, rarSet, mutSet = toSet(rule.all), toSet(rule.rarities), toSet(rule.mutations)
		local keys, count = {}, 0
		for _, u in ipairs(listUnits()) do
			if not placed[u.key] and not u.locked then
				local hit = allSet[u.rarity]
				if not hit and rarSet[u.rarity] then
					if u.mutation then hit = mutSet[tostring(u.mutation)] else hit = mutSet[NO_MUT] end
				end
				if hit then keys[#keys + 1] = u.key count = count + u.amount end
			end
		end
		return keys, count
	end
	local function sellNow()
		local keys, count = candidates()
		if #keys == 0 then return 0, 0 end
		local ok, res = send("SellService", "SellInventory", keys)
		if not ok then return 0, 0 end
		local sold, gained = count, 0
		if type(res) == "table" then
			sold = num(res.sold or res.count or res.amount, count)
			gained = num(res.money or res.earned or res.gained or res.total, 0)
		end
		return sold, gained
	end
	autoToggle(tab, {
		name = "Auto Sell", desc = "Sells matching units on a timer",
		flag = "AnimeDiceAutoSell", period = function() return rule.interval end,
		pass = sellNow,
	})
	sliderOf(tab, { name = "Interval", min = 1, max = 600, step = 1, default = 10, suffix = "s",
		flag = "AnimeDiceSellInterval", callback = function(v) rule.interval = math.max(num(v, 10), 1) end })
	tab:CreateLabel({ Text = "Would sell now: \226\128\166", UpdateRate = 2, Update = function()
		local _, count = candidates()
		return string.format("Would sell now: %d unit(s)", count)
	end })
	tab:CreateSection("Rule 1 \226\128\148 whole rarity")
	dropdownOf(tab, { name = "Rarities to sell", desc = "Every unit of these rarities is sold, whatever its mutation",
		options = RARITIES, multi = true, default = {}, flag = "AnimeDiceSellRaritiesAll",
		callback = function(sel) rule.all = type(sel) == "table" and sel or {} end })
	tab:CreateSection("Rule 2 \226\128\148 rarity + mutation")
	dropdownOf(tab, { name = "Rarities", desc = "Only units of these rarities...",
		options = RARITIES, multi = true, default = {}, flag = "AnimeDiceSellMutatedRarities",
		callback = function(sel) rule.rarities = type(sel) == "table" and sel or {} end })
	local mutOptions = { NO_MUT }
	for _, m in ipairs(MUTATIONS) do mutOptions[#mutOptions + 1] = m end
	dropdownOf(tab, { name = "Mutations", desc = "...that also have one of these mutations",
		options = mutOptions, multi = true, default = {}, flag = "AnimeDiceSellMutations",
		callback = function(sel) rule.mutations = type(sel) == "table" and sel or {} end })
	tab:CreateButton({
		Name = "Sell now", Style = "Primary",
		Callback = function()
			local _, count = candidates()
			if count <= 0 then notify("Sell", "Nothing to sell.", "Warning") return end
			Window:Confirm({
				Title = string.format("Sell %d unit(s)?", count), Content = "This can't be undone.",
				Callback = function()
					task.spawn(function()
						local sold, gained = sellNow()
						if sold > 0 then notify("Sell", string.format("%d units  \194\183  +$%s", sold, fmt(gained)))
						else notify("Sell", "Nothing sold.", "Warning") end
					end)
				end,
			})
		end,
	})
end
local function firstRemoteIn(service)
	local folder = Network:FindFirstChild(service, true)
	if not folder then return nil end
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then return d end
	end
	return nil
end
local function stringSet(raw)
	local set = {}
	if type(raw) == "table" then
		for k, v in pairs(raw) do
			if type(k) == "string" and v then set[k] = true elseif type(v) == "string" then set[v] = true end
		end
	end
	return set
end
do
	local tab = Window:CreateTab({ Name = "Progression", Desc = "Upgrades, rebirth and quests", Icon = "trending-up" })
	tab:CreateSection("Skill tree")
	local tree = { branches = table.clone(BRANCHES) }
	local function branchOf(name, cfg)
		local b = type(cfg) == "table" and (cfg.branch or cfg.Branch or cfg.category or cfg.stat) or nil
		if type(b) == "string" then return b end
		local best
		for _, candidate in ipairs(BRANCHES) do
			if string.find(name, candidate, 1, true) and (not best or #candidate > #best) then best = candidate end
		end
		return best
	end
	local function upgradeNodes()
		local mod = Module("Upgrades")
		local nodes = {}
		if type(mod) ~= "table" then return nodes end
		local src = mod.Nodes or mod.List or mod.Upgrades or mod
		if type(src) ~= "table" then return nodes end
		for k, v in pairs(src) do
			if type(v) == "table" and tonumber(v.price or v.Price or v.cost) then
				local name = v.name or v.Name or (type(k) == "string" and k) or nil
				if name then nodes[#nodes + 1] = { name = name, price = tonumber(v.price or v.Price or v.cost), cfg = v } end
			end
		end
		table.sort(nodes, function(a, b)
			if a.price ~= b.price then return a.price < b.price end
			return a.name < b.name
		end)
		return nodes
	end
	local function parentName(name)
		local p = callFn(Module("TreeStructure"), "GetParent", name)
		return type(p) == "string" and p or nil
	end
	local function branchAllowed(name, cfgByName, allowed)
		local current, guard = name, 0
		while current and current ~= "Start" and guard < 40 do
			local b = branchOf(current, cfgByName[current])
			if b and not allowed[b] then return false end
			current = parentName(current)
			guard = guard + 1
		end
		return true
	end
	local function buyUpgrades()
		local nodes, owned, m, bought = upgradeNodes(), stringSet(dataField("Upgrades")), money() or 0, 0
		local allowed, cfgByName = toSet(tree.branches), {}
		for _, n in ipairs(nodes) do cfgByName[n.name] = n.cfg end
		for _, n in ipairs(nodes) do
			if not owned[n.name] and n.price <= m and branchAllowed(n.name, cfgByName, allowed) then
				local parent = parentName(n.name)
				if (parent == nil or parent == "Start" or owned[parent]) and throttle("upgrade:" .. n.name, 20) then
					send("RebirthService", "BuyUpgrade", n.name)
					owned[n.name], m, bought = true, m - n.price, bought + 1
					task.wait(0.1)
				end
			end
		end
		return bought
	end
	autoToggle(tab, {
		name = "Auto Upgrades", desc = "Buys skill tree nodes from the cheapest up",
		flag = "AnimeDiceAutoUpgrades", period = 1, pass = buyUpgrades,
	})
	dropdownOf(tab, {
		name = "Branches", desc = "Unticking a branch also blocks the branches that grow from it",
		options = table.clone(BRANCHES), multi = true, default = table.clone(BRANCHES), flag = "AnimeDiceUpgradeBranches",
		callback = function(sel) tree.branches = type(sel) == "table" and sel or {} end,
	})
	tab:CreateButton({
		Name = "Buy upgrades now",
		Callback = function()
			task.spawn(function()
				local n = buyUpgrades()
				notify("Upgrades", n > 0 and string.format("%d upgrade(s) bought", n) or "Nothing affordable.", n > 0 and "Success" or "Warning")
			end)
		end,
	})
	tab:CreateSection("Rebirth")
	local function tryRebirth(force)
		local nxt = nextRebirth()
		if not nxt then return "max" end
		local cost = num(nxt.cost, 0)
		if (money() or 0) < cost then return "poor", cost end
		send("RebirthService", "Rebirth")
		return "ok", nxt
	end
	autoToggle(tab, {
		name = "Auto Rebirth", desc = "Rebirths as soon as you can afford it \226\128\148 your money resets to 0",
		flag = "AnimeDiceAutoRebirth", period = 1,
		pass = function()
			local status, info = tryRebirth()
			if status == "ok" then
				notify("Rebirth", string.format("Rebirth %d  \194\183  luck x%s", rebirths() + 1, tostring(type(info) == "table" and info.luckMultiplier or "?")))
				task.wait(3)
			end
		end,
	})
	tab:CreateButton({
		Name = "Rebirth now",
		Callback = function()
			local nxt = nextRebirth()
			if not nxt then notify("Rebirth", string.format("Max level reached (%d).", rebirths()), "Warning") return end
			local cost = num(nxt.cost, 0)
			if (money() or 0) < cost then notify("Rebirth", string.format("Missing $%s.", fmt(cost - (money() or 0))), "Warning") return end
			Window:Confirm({
				Title = "Rebirth now?", Content = "Your money will be reset to $0.",
				Callback = function() send("RebirthService", "Rebirth") end,
			})
		end,
	})
	tab:CreateSection("Quests")
	local function periodState(period)
		local q = dataField("Quests")
		if type(q) ~= "table" then return nil end
		return q[period] or q[string.lower(period)]
	end
	local function claimQuests()
		local claimed = 0
		local cfg = Module("QuestConfig")
		for _, period in ipairs({ "Daily", "Weekly" }) do
			local state = periodState(period)
			local list = type(state) == "table" and (state.quests or state.Quests) or nil
			if type(list) == "table" then
				for _, q in ipairs(list) do
					if type(q) == "table" and not q.claimed then
						local target = tonumber(q.target)
						if not target and type(cfg) == "table" then
							local def = (type(cfg.Quests) == "table" and cfg.Quests[q.id]) or callFn(cfg, "GetQuest", q.id)
							target = type(def) == "table" and tonumber(def.target) or nil
						end
						if target and target > 0 and num(q.progress, 0) >= target then
							send("QuestService", "Claim", q.id, state.expiresAt)
							claimed = claimed + 1
							task.wait(0.25)
						end
					end
				end
			end
		end
		return claimed
	end
	autoToggle(tab, {
		name = "Auto Claim Quests", desc = "Claims finished daily and weekly quests (rewards Tickets)",
		flag = "AnimeDiceAutoClaimQuests", period = 10, pass = claimQuests,
	})
	tab:CreateButton({
		Name = "Claim now",
		Callback = function()
			task.spawn(function()
				local n = claimQuests()
				notify("Quests", n > 0 and string.format("%d quest(s) claimed", n) or "Nothing to claim.", n > 0 and "Success" or "Warning")
			end)
		end,
	})
	tab:CreateSection("Rebirth points")
	local points = { stats = {} }
	local function statNames()
		local cfg = Module("RebirthStatsConfig")
		local list = {}
		local src = type(cfg) == "table" and cfg.Stats or nil
		if type(src) == "table" then
			for k, v in pairs(src) do
				local n = nameOf(v)
				if n then list[#list + 1] = n elseif type(k) == "string" then list[#list + 1] = k end
			end
		end
		table.sort(list)
		return list
	end
	local function pointsLeft()
		local cfg = Module("RebirthStatsConfig")
		local spent = dataField("Rebirth", "RebirthStats")
		for _, args in ipairs({ { spent }, { rebirths(), spent }, { dataField("Rebirth") } }) do
			local n = tonumber(callFn(cfg, "GetRemaining", table.unpack(args)))
			if n then return math.max(math.floor(n), 0) end
		end
		return 0
	end
	autoToggle(tab, {
		name = "Auto Spend Rebirth Points", desc = "Puts every unspent rebirth point into the ticked stats",
		flag = "AnimeDiceAutoRebirthPoints", period = 5,
		pass = function()
			if #points.stats == 0 then return end
			local before = pointsLeft()
			local left, i = math.min(before, 100), 0
			while left > 0 do
				i = i % #points.stats + 1
				send("RebirthService", "AddStat", points.stats[i])
				left = left - 1
				task.wait(0.15)
			end
			if before > 0 then
				task.wait(1)
				if pointsLeft() >= before then task.wait(30) end
			end
		end,
	})
	dropdownOf(tab, {
		name = "Stats to raise", desc = "Nothing ticked = nothing spent. Resetting points needs a Reset Token",
		options = statNames(), multi = true, default = {}, flag = "AnimeDiceRebirthPointStats",
		callback = function(sel) points.stats = type(sel) == "table" and sel or {} end,
	})
	tab:CreateLabel({ Text = "Points: \226\128\166", UpdateRate = 3, Update = function()
		return string.format("Unspent rebirth points: %d", pointsLeft())
	end })
	tab:CreateSection("Free rewards")
	autoToggle(tab, {
		name = "Auto Claim Daily Reward", desc = "Claims the daily gift every time its 23h timer ends",
		flag = "AnimeDiceAutoDaily", period = 60,
		pass = function()
			local cfg = Module("DailyRewardConfig")
			local cooldown = num(type(cfg) == "table" and cfg.Cooldown, 23 * 3600)
			local last = tonumber(dataField("LastDailyRewardClaim"))
			if last == nil or os.time() - last >= cooldown then send("DailyRewardService", "Claim") end
		end,
	})
	autoToggle(tab, {
		name = "Auto Claim Offline Earnings", desc = "Collects the Money earned while you were away",
		flag = "AnimeDiceAutoOffline", period = 60,
		pass = function()
			if num(dataField("PendingOfflineEarnings"), 0) > 0 then send("OfflineEarningsService", "Claim") end
		end,
	})
	autoToggle(tab, {
		name = "Auto Redeem Codes",
		desc = "Redeems every built-in code you haven't used (Gems, Trait Rerolls, Lucky Spins)",
		flag = "AnimeDiceAutoCodes", period = 120,
		pass = function()
			local cfg = Module("CodesConfig")
			local codes = type(cfg) == "table" and (cfg.Codes or cfg) or nil
			if type(codes) ~= "table" then return end
			local used = stringSet(dataField("RedeemedCodes"))
			for k, v in pairs(codes) do
				local code = (type(k) == "string" and k) or (type(v) == "string" and v) or (type(v) == "table" and (v.code or v.Code))
				if type(code) == "string" and not used[code] then
					send("CodesService", "RedeemCode", code)
					task.wait(0.7)
				end
			end
		end,
	})
	tab:CreateButton({
		Name = "Claim group reward", Desc = "Needs you to be in the game's group; the server refuses otherwise",
		Callback = function()
			local ok = call(Remote("GroupRewardService", "Claim") or firstRemoteIn("GroupRewardService"))
			notify("Group reward", ok and "Request sent." or "Remote not found.", ok and "Success" or "Warning")
		end,
	})
end
do
	local tab = Window:CreateTab({ Name = "Boosts", Desc = "Automatic potion use", Icon = "flask-conical" })
	local potion = { keepMinutes = 0, chosen = {} }
	local function boostEntries()
		local out = {}
		for key, entry in pairs(entries()) do
			local cfg = entryConfig(entry, key)
			if cfg and cfg.kind == "Boost" and cfg.category then
				out[#out + 1] = { key = key, cfg = cfg, amount = math.floor(num(entry.amount, 0)),
					tier = num(cfg.tier, 0), duration = num(cfg.duration, 0), category = tostring(cfg.category) }
			end
		end
		return out
	end
	local function categories()
		local set = {}
		for _, cfg in pairs(entriesOfKind("Boost")) do
			if type(cfg) == "table" and cfg.category then set[tostring(cfg.category)] = true end
		end
		for _, b in ipairs(boostEntries()) do set[b.category] = true end
		return sortedKeys(set)
	end
	local function activeSeconds()
		local active, out = dataField("ActiveEntries"), {}
		if type(active) ~= "table" then return out end
		local now = workspace:GetServerTimeNow()
		for key, e in pairs(active) do
			if type(e) == "table" then
				local cfg = entryConfig(e, key)
				if cfg and cfg.kind == "Boost" and cfg.category then
					local rem = tonumber(e.remaining)
					if not rem and type(e.startedAt) == "number" then rem = e.startedAt + num(cfg.duration, 0) - now end
					if rem and rem > 0 then out[tostring(cfg.category)] = (out[tostring(cfg.category)] or 0) + rem end
				end
			end
		end
		return out
	end
	local function wantedCategories()
		return toSet(potion.chosen)
	end
	local usedUntil = {}
	local function usePotions(everything)
		local wanted, remaining, used = wantedCategories(), activeSeconds(), 0
		local byCategory = {}
		for _, b in ipairs(boostEntries()) do
			if wanted[b.category] and b.amount > 0 then
				local list = byCategory[b.category] or {}
				byCategory[b.category] = list
				list[#list + 1] = b
			end
		end
		for category, list in pairs(byCategory) do
			table.sort(list, function(a, b) return a.tier > b.tier end)
			local mine = math.max((usedUntil[category] or 0) - os.clock(), 0)
			local have, target = math.max(remaining[category] or 0, mine), potion.keepMinutes * 60
			for _, b in ipairs(list) do
				local copies = 0
				while b.amount - copies > 0 and copies < 100 do
					if not everything then
						if target <= 0 then if have > 0 then break end
						elseif have >= target then break end
					end
					send("BoostService", "Use", b.key)
					local dur = b.duration > 0 and b.duration or 300
					usedUntil[category] = math.max(usedUntil[category] or 0, os.clock()) + dur
					copies, used, have = copies + 1, used + 1, have + dur
					task.wait(0.15)
				end
				if not everything and have > 0 and (target <= 0 or have >= target) then break end
			end
		end
		return used
	end
	tab:CreateParagraph({
		Name = "How potions stack",
		Content = "Using a potion adds its time, nothing is wasted: in one family the best tier runs first and the others wait their turn. Different families multiply together \226\128\148 tick several.",
	})
	autoToggle(tab, {
		name = "Auto Use Potions", desc = "Keeps every ticked family stocked with the time below, best tier first",
		flag = "AnimeDiceAutoPotions", period = 1, pass = function() usePotions(false) end,
	})
	tab:CreateLabel({ Text = "Running: \226\128\166", UpdateRate = 2, Update = function()
		local parts = {}
		for name, sec in pairs(activeSeconds()) do parts[#parts + 1] = string.format("%s %dm", name, math.floor(sec / 60)) end
		table.sort(parts)
		return "Running: " .. (#parts > 0 and table.concat(parts, ", ") or "none")
	end })
	sliderOf(tab, {
		name = "Keep stacked per potion type", desc = "0 = only use one when the previous ran out",
		min = 0, max = 180, step = 1, default = 0, suffix = "min", flag = "AnimeDicePotionStackMinutes",
		callback = function(v) potion.keepMinutes = num(v, 0) end,
	})
	tab:CreateSection("Families to use")
	dropdownOf(tab, {
		name = "Potions", desc = "Every family is kept running on its own", options = categories(),
		multi = true, default = {}, flag = "AnimeDicePotion",
		callback = function(sel) potion.chosen = type(sel) == "table" and sel or {} end,
	})
	tab:CreateButton({
		Name = "Use potions now", Desc = "Use ALL ticked potions",
		Callback = function()
			Window:Confirm({
				Title = "Use every potion?", Content = "Every ticked potion you own is used now; their time stacks up.",
				Callback = function()
					task.spawn(function()
						local n = usePotions(true)
						notify("Potions", n > 0 and string.format("%d potion(s) used", n) or "Nothing to use.", n > 0 and "Success" or "Warning")
					end)
				end,
			})
		end,
	})
	tab:CreateSection("Potion fusing (5 of a tier -> 1 of the next)")
	local pf = { types = {}, keep = 0, count = 0, last = "\226\128\148" }
	local function fusable()
		local util, out = Module("PotionFusingUtil"), {}
		if not util then return out end
		local cost = num(util.FUSE_COST, 5)
		for _, b in ipairs(boostEntries()) do
			if contains(pf.types, b.category) then
				local nextTier = callFn(util, "GetNextTier", b.cfg) or callFn(util, "GetNextTier", b.key)
				local n = math.floor((b.amount - pf.keep) / cost)
				if nextTier and n > 0 then out[#out + 1] = { key = b.key, name = b.cfg.name or b.key, times = n } end
			end
		end
		return out
	end
	local function fusePotions()
		local list, done = fusable(), 0
		if #list == 0 then return 0 end
		goAndBack("PotionFusing", function() return zonePart("fuser", "potion") end, function()
			for _, f in ipairs(list) do
				for _ = 1, f.times do
					local ok, res = call(Remote("PotionFusingService", "Fuse"), f.key)
					if not ok or res == false or res == nil then break end
					done, pf.count, pf.last = done + 1, pf.count + 1, tostring(f.name)
					task.wait(0.6)
				end
			end
		end)
		return done
	end
	autoToggle(tab, {
		name = "Auto Fuse Potions", desc = "Walks to the Potion Fuser when there is something to fuse, then walks back",
		flag = "AnimeDiceAutoPotionFuse", period = 10, pass = fusePotions,
	})
	dropdownOf(tab, {
		name = "Potion types to fuse", options = table.clone(normal), multi = true, default = {},
		flag = "AnimeDicePotionFuseTypes",
		callback = function(sel) pf.types = type(sel) == "table" and sel or {} end,
	})
	sliderOf(tab, {
		name = "Keep per potion", desc = "Never fuse the last copies of each potion",
		min = 0, max = 100, step = 1, default = 0, flag = "AnimeDicePotionFuseKeep",
		callback = function(v) pf.keep = num(v, 0) end,
	})
	tab:CreateButton({
		Name = "Fuse potions now",
		Callback = function()
			task.spawn(function()
				local n = fusePotions()
				notify("Potion fusing", string.format("%d fusion(s)", n), n > 0 and "Success" or "Warning")
			end)
		end,
	})
	tab:CreateLabel({ Text = "Potion fusing: \226\128\166", UpdateRate = 3, Update = function()
		return string.format("Fused %d  \194\183  %d ready  \194\183  last: %s", pf.count, #fusable(), pf.last)
	end })
end
do
	local tab = Window:CreateTab({ Name = "Towers", Desc = "Automatic tower runs", Icon = "castle" })
	local tower = { name = "Dragon Tower", reEquip = true, running = false }
	local function towerNames()
		local raw, list = callFn(Module("Towers"), "GetAll"), {}
		if type(raw) == "table" then
			for k, v in pairs(raw) do
				if type(v) == "table" then
					list[#list + 1] = { name = v.name or v.Name or (type(k) == "string" and k) or tostring(k), order = num(v.order or v.Order, 0) }
				end
			end
		end
		table.sort(list, function(a, b)
			if a.order ~= b.order then return a.order < b.order end
			return a.name < b.name
		end)
		local names = {}
		for _, t in ipairs(list) do names[#names + 1] = t.name end
		return names
	end
	local function hasEnded(res)
		if type(res) ~= "table" then return false end
		if res.ended == true then return true end
		for _, a in ipairs(res) do
			if type(a) == "table" and a.action == "ended" then return true end
		end
		return false
	end
	local enabled = false
	local function runOnce()
		State.towerPrepare = true
		if tower.reEquip then send("Towers", "EquipBestTowerTeam") task.wait(0.5) end
		local ok, res = call(Remote("Towers", "PlayTower"), tower.name)
		State.towerPrepare = false
		if not ok or res == false or res == nil then task.wait(3) return end
		tower.running = true
		local ended, failures, started = hasEnded(res), 0, os.clock()
		while not ended and enabled and not State.dead and os.clock() - started < 900 do
			local ok2, r2 = call(Remote("Towers", "CompleteTowerFloor"))
			if not ok2 or r2 == false then failures = failures + 1 else failures = 0 end
			if failures >= 5 then break end
			if ok2 and hasEnded(r2) then ended = true end
			task.wait(1.1)
		end
		if not ended then send("Towers", "CancelTower") end
		tower.running = false
		task.wait(3.1)
	end
	autoToggle(tab, {
		name = "Auto Tower", desc = "Runs the chosen tower over and over, collecting floor rewards",
		flag = "AnimeDiceAutoTower", period = 0.5,
		onChange = function(on)
			enabled = on
			State.towerHold = on
			if not on then
				State.towerPrepare = false
				if tower.running then task.spawn(function() send("Towers", "CancelTower") end) tower.running = false end
			end
		end,
		pass = runOnce,
	})
	local names = towerNames()
	dropdownOf(tab, {
		name = "Tower", desc = "Towers get harder down the list; Infinity never ends until your team wipes",
		options = names, default = contains(names, "Dragon Tower") and "Dragon Tower" or names[1],
		flag = "AnimeDiceTowerDifficulty", callback = function(v) tower.name = nameOf(v) or tower.name end,
	})
	tab:CreateToggle({
		Name = "Re-equip before each run", Desc = "Puts your highest-damage units in the team before every run",
		Default = true, Flag = "AnimeDiceTowerReEquip", Callback = function(on) tower.reEquip = on == true end,
	})
	tab:CreateButton({
		Name = "Equip best team now",
		Callback = function()
			task.spawn(function()
				send("Towers", "EquipBestTowerTeam")
				notify("Towers", "Team updated.")
			end)
		end,
	})
end
local function callOk(remote, ...)
	if not remote then return false end
	local ok, res = call(remote, ...)
	if not ok then return false end
	if remote:IsA("RemoteFunction") then return res ~= false and res ~= nil end
	return true
end
do
	local tab = Window:CreateTab({ Name = "Autumn", Desc = "Apple orchard, apple tree, shop, quests, Leaf Dice", Icon = "leaf" })
	local present = Module("AppleConfig") or Module("AutumnQuestConfig") or Remote("AutumnService", "Travel")
	if not present then
		tab:CreateLabel({ Text = "The Autumn event is not in this server right now." })
	else
		local au = { status = "Idle", applesPicked = 0, leafRolls = 0, soldOut = {}, shopPicked = {}, leafSell = {} }
		local workerOn = { apples = false, board = false, tree = false, shop = false, quests = false, leaf = false }
		local leafMulti = false
		local function zones() return workspace:FindFirstChild("Zones") end
		local function inWorld()
			local hrp, z = rootPart(), zones()
			local part = z and z:FindFirstChild("AutumnWorld")
			if not (hrp and part and part:IsA("BasePart")) then return false end
			local rel, half = part.CFrame:PointToObjectSpace(hrp.Position), part.Size / 2
			return math.abs(rel.X) <= half.X and math.abs(rel.Z) <= half.Z and math.abs(rel.Y) <= half.Y + 80
		end
		local function travelTo(where)
			local ok = callOk(Remote("AutumnService", "Travel"), where)
			if ok then
				local t0 = os.clock()
				while os.clock() - t0 < 6 and (where == "Autumn") ~= inWorld() do task.wait(0.25) end
			end
			return ok
		end
		local function goZone(name)
			local z = zones()
			local part = z and (z:FindFirstChild(name) or z:FindFirstChild(name, true))
			local hrp = rootPart()
			if part and part:IsA("BasePart") and hrp and (hrp.Position - part.Position).Magnitude > 40 then
				walkTo(part.Position, 25)
			end
		end
		local function pickApples(go)
			go("AppleArea")
			local hum, hrp = humanoid(), rootPart()
			if not (hum and hrp) then return false end
			local ok, res = call(Remote("AppleService", "Sync"))
			local list = ok and type(res) == "table" and (res.apples or res) or {}
			local cfg = Module("AppleConfig")
			local reach = 4.75 + num(type(cfg) == "table" and cfg.REACH_SLACK, 1.5)
			local apples = {}
			for _, a in ipairs(list) do
				local pos = type(a) == "table" and (a.position or a.Position) or nil
				if typeof(pos) == "Vector3" then apples[#apples + 1] = { id = a.id, pos = pos, dist = (pos - hrp.Position).Magnitude } end
			end
			table.sort(apples, function(a, b) return a.dist < b.dist end)
			local picked = 0
			for i = 1, math.min(#apples, 12) do
				local a = apples[i]
				hrp = rootPart()
				if not hrp or State.towerHold then break end
				if (a.pos - hrp.Position).Magnitude > reach then
					hum:MoveTo(a.pos)
					local t0 = os.clock()
					while (rootPart() and (rootPart().Position - a.pos).Magnitude > reach * 0.8) and os.clock() - t0 < 2.5 do task.wait(0.1) end
				end
				local okc, resc = call(Remote("AppleService", "Collect"), a.id)
				if okc and resc ~= false then
					picked, au.applesPicked = picked + 1, au.applesPicked + 1
				end
				task.wait(0.15)
			end
			return picked > 0
		end
		local function buyBoard(go)
			local cfg = Module("AppleConfig")
			local list = type(cfg) == "table" and cfg.Upgrades or nil
			if type(list) ~= "table" then return false end
			local apples, best = amountOf("Apples"), nil
			for k, v in pairs(list) do
				local name = type(v) == "table" and (v.name or v.Name) or (type(k) == "string" and k) or (type(v) == "string" and v)
				if name then
					local level = num(callFn(cfg, "GetLevel", name), 0)
					local max = type(v) == "table" and tonumber(v.max or v.Max) or nil
					local unlocked = callFn(cfg, "IsUnlocked", name)
					local cost = tonumber(callFn(cfg, "GetCost", name, level)) or tonumber(callFn(cfg, "GetCost", name))
					if cost and cost <= apples and unlocked ~= false and (not max or level < max) and (not best or cost < best.cost) then
						best = { name = name, cost = cost }
					end
				end
			end
			if not best or not throttle("board:" .. tostring(best.name), 4) then return false end
			go("AppleBoard")
			call(Remote("AppleService", "BuyUpgrade"), best.name)
			task.wait(0.35)
			return true
		end
		local function buyTree(go)
			local mod = Module("AppleTree")
			if type(mod) ~= "table" or type(mod.Nodes) ~= "table" then return false end
			local owned = stringSet(dataField("AppleTree") or dataField("AppleTreeUpgrades"))
			owned[tostring(mod.Root or "Seedling")], owned.Seedling = true, true
			local apples, best = amountOf("Apples"), nil
			for name, node in pairs(mod.Nodes) do
				if type(name) == "string" and type(node) == "table" and not owned[name] then
					local price = tonumber(node.price)
					local parents = (type(mod.Structure) == "table" and mod.Structure[name]) or node.parents or node.parent
					if type(parents) == "string" then parents = { parents } end
					local reachable = parents == nil
					if type(parents) == "table" then
						reachable = false
						for _, p in pairs(parents) do if owned[tostring(p)] then reachable = true end end
					end
					if price and price <= apples and reachable and (not best or price < best.price) then
						best = { name = name, price = price }
					end
				end
			end
			if not best or not throttle("tree:" .. tostring(best.name), 4) then return false end
			go("AppleTree")
			call(Remote("AppleTreeService", "BuyAppleUpgrade"), best.name)
			task.wait(0.3)
			return true
		end
		local function shopOffers()
			local cfg = Module("AppleShopConfig")
			local list = {}
			local src = type(cfg) == "table" and (cfg.Offers or cfg.ById) or nil
			if type(src) == "table" then
				for k, v in pairs(src) do
					if type(v) == "table" and tonumber(v.price) then
						list[#list + 1] = { id = v.id or k, name = tostring(v.name or k), price = tonumber(v.price),
							label = string.format("%s (%s)", tostring(v.name or k), fmt(v.price)) }
					end
				end
			end
			table.sort(list, function(a, b)
				if a.price ~= b.price then return a.price < b.price end
				return a.label < b.label
			end)
			return list
		end
		local function buyShop(go)
			local apples, picked, acted = amountOf("Apples"), toSet(au.shopPicked), false
			for _, o in ipairs(shopOffers()) do
				local retryAt = au.soldOut[o.id]
				if picked[o.label] and o.price <= apples and not (retryAt and os.clock() - retryAt < 600) and throttle("appleshop:" .. tostring(o.id), 3) then
					go("AppleShop")
					local ok, res = call(Remote("AppleShopService", "Buy"), o.id)
					if ok and res ~= false and res ~= nil then apples, acted = apples - o.price, true else au.soldOut[o.id] = os.clock() end
					task.wait(0.3)
				end
			end
			return acted
		end
		local function claimQuests(go)
			local cfg, d = Module("AutumnQuestConfig"), Data()
			if type(cfg) ~= "table" or not d then return false end
			local todo = {}
			for _, p in ipairs(type(cfg.Periods) == "table" and cfg.Periods or {}) do
				local st = d[p.dataKey or p.DataKey or ""]
				local list = type(st) == "table" and st.quests or nil
				if type(list) == "table" then
					for _, q in ipairs(list) do
						local target = tonumber(q.target)
						if target and not q.claimed and num(q.progress, 0) >= target then todo[#todo + 1] = { id = q.id, bonus = false } end
						if q.bonus and not q.bonusClaimed and target and num(q.progress, 0) >= target then todo[#todo + 1] = { id = q.id, bonus = true } end
					end
				end
			end
			if #todo == 0 then return false end
			go("AutumnQuests")
			for _, t in ipairs(todo) do
				call(Remote("AutumnQuestService", t.bonus and "ClaimBonus" or "Claim"), t.id)
				task.wait(0.4)
			end
			return true
		end
		local function leafPool()
			local mod = Module("LeafDice")
			local src = type(mod) == "table" and (mod.Pool or mod.Units) or nil
			local list = {}
			if type(src) == "table" then
				for k, v in pairs(src) do
					local id = type(v) == "table" and (v.id or v.name) or (type(k) == "string" and k) or v
					if id ~= nil then list[#list + 1] = { id = id, name = tostring(type(v) == "table" and (v.name or v.id) or id) } end
				end
			end
			table.sort(list, function(a, b) return a.name < b.name end)
			return list
		end
		local function rollLeaf(go)
			local mod = Module("LeafDice")
			if type(mod) ~= "table" then return false end
			local cost, multi = num(mod.COST, 100), num(mod.MULTI, 5)
			local leaves = amountOf("Leaves")
			local count = (leafMulti and leaves >= cost * multi) and multi or 1
			if leaves < cost * count then return false end
			go("LeafDice")
			local signature = ""
			for _, u in ipairs(leafPool()) do signature = signature .. u.name .. tostring(au.leafSell[u.name] == true) end
			if signature ~= au.leafSigApplied then
				for _, u in ipairs(leafPool()) do call(Remote("LeafDiceService", "SetAutoSell"), u.id, au.leafSell[u.name] == true) end
				au.leafSigApplied = signature
			end
			local ok, res = call(Remote("LeafDiceService", "Roll"), count)
			if ok and res ~= false then au.leafRolls = au.leafRolls + count end
			task.wait(math.max(num(mod.ROLL_DURATION, 1.6), 0.15))
			return ok
		end
		local workers = {
			{ key = "quests", status = "Claiming quests", run = claimQuests },
			{ key = "tree",   status = "Buying Apple Tree nodes", run = buyTree },
			{ key = "shop",   status = "Shopping at the Apple Shop", run = buyShop },
			{ key = "leaf",   status = "Rolling the Leaf Dice", run = rollLeaf },
			{ key = "board",  status = "Buying Apple Board levels", run = buyBoard },
			{ key = "apples", status = "Picking apples", run = pickApples },
		}
		task.spawn(function()
			while not State.dead do
				task.wait(1)
				local any = false
				for _, w in ipairs(workers) do if workerOn[w.key] then any = true end end
				if not any then
					au.status = "Idle"
				elseif State.towerHold or State.towerPrepare then
					au.status = "Paused: Auto Tower is using the character"
				elseif not inWorld() then
					au.status = "Travelling to the event\226\128\166"
					travelTo("Autumn")
				else
					local acted = false
					for _, w in ipairs(workers) do
						if workerOn[w.key] and not State.towerHold then
							au.status = w.status
							withCharacter("Autumn", function()
								if w.run(goZone) then acted = true end
							end)
						end
					end
					if not acted then au.status = "Waiting" end
				end
			end
		end)
		tab:CreateSection("Status")
		tab:CreateLabel({ Text = "Currencies: \226\128\166", UpdateRate = 2, Update = function()
			return string.format("Apples %s  \194\183  Leaves %s  \194\183  picked %d  \194\183  leaf rolls %d",
				fmt(amountOf("Apples")), fmt(amountOf("Leaves")), au.applesPicked, au.leafRolls)
		end })
		tab:CreateLabel({ Text = "Status: \226\128\166", UpdateRate = 1, Update = function() return "Status: " .. au.status end })
		tab:CreateButton({
			Name = "Go to the event", Desc = "Server travel to the Autumn world",
			Callback = function()
				task.spawn(function()
					local ok = travelTo("Autumn")
					notify("Autumn", ok and "In the event world." or "Travel refused.", ok and "Success" or "Warning")
				end)
			end,
		})
		tab:CreateButton({
			Name = "Back to the hub",
			Callback = function()
				task.spawn(function()
					local ok = travelTo("Hub")
					notify("Autumn", ok and "Back at the hub." or "Travel refused.", ok and "Success" or "Warning")
				end)
			end,
		})
		local function workerToggle(o)
			local toggle = tab:CreateToggle({
				Name = o.name, Desc = o.desc, Default = false, Flag = o.flag,
				Callback = function(on) workerOn[o.key] = on == true end,
			})
			Toggles[#Toggles + 1] = toggle
		end
		tab:CreateSection("Orchard")
		workerToggle({ key = "apples", flag = "AnimeDiceAutumnApples", name = "Auto Pick Apples",
			desc = "Walks the orchard and picks apples (travels to the event first). Apples buy everything else here" })
		workerToggle({ key = "board", flag = "AnimeDiceAutumnBoard", name = "Auto Apple Board",
			desc = "Buys the cheapest unlocked Apple Board level whenever you can afford it" })
		workerToggle({ key = "tree", flag = "AnimeDiceAutumnTree", name = "Auto Apple Tree",
			desc = "Buys the cheapest Apple Tree node whose parent you own" })
		tab:CreateSection("Shop")
		workerToggle({ key = "shop", flag = "AnimeDiceAutumnShop", name = "Auto Apple Shop",
			desc = "Buys the ticked offers with Apples (cheapest first; a sold-out offer is retried later)" })
		local offerLabels = {}
		for _, o in ipairs(shopOffers()) do offerLabels[#offerLabels + 1] = o.label end
		dropdownOf(tab, {
			name = "Offers to buy",
			desc = "Nothing is bought until you tick offers. Potions go to your inventory, Auto Use Potions can drink them",
			options = offerLabels, multi = true, default = {}, flag = "AnimeDiceAutumnShopOffers",
			callback = function(sel) au.shopPicked = type(sel) == "table" and sel or {} end,
		})
		tab:CreateSection("Quests & Leaf Dice")
		workerToggle({ key = "quests", flag = "AnimeDiceAutumnQuests", name = "Auto Claim Autumn Quests",
			desc = "Claims finished daily and hourly quests and their bonuses at the Quest Board" })
		workerToggle({ key = "leaf", flag = "AnimeDiceAutumnLeafDice", name = "Auto Leaf Dice",
			desc = "Rolls the Leaf Dice with your Leaves (100 each, Leaves come from the Leaf Towers)" })
		tab:CreateToggle({
			Name = "Leaf Dice multi-roll x5", Desc = "Rolls five at a time when you have the Leaves",
			Default = false, Flag = "AnimeDiceAutumnLeafMulti", Callback = function(on) leafMulti = on == true end,
		})
		local poolNames = {}
		for _, u in ipairs(leafPool()) do poolNames[#poolNames + 1] = u.name end
		dropdownOf(tab, {
			name = "Auto-sell these Leaf Dice units",
			desc = "Server-side auto sell, applied next time the script visits the Leaf Dice. Empty touches nothing",
			options = poolNames, multi = true, default = {}, flag = "AnimeDiceAutumnLeafSell",
			callback = function(sel)
				au.leafSell = toSet(type(sel) == "table" and sel or {})
			end,
		})
		tab:CreateParagraph({
			Name = "Autumn Towers",
			Content = "Autumn Towers (Harvest Fields\226\128\166) are in the Towers tab. While Auto Tower is on it owns the character and the workers above wait.",
		})
	end
end
do
	local tab = Window:CreateTab({ Name = "Settings", Desc = "Anti-AFK, menu key and configs", Icon = "settings" })
	local connections = {}
	local function keep(conn)
		if conn then connections[#connections + 1] = conn end
		return conn
	end
	tab:CreateSection("Anti-AFK")
	do
		local afk = { gen = 0, on = false }
		local function nudge()
			local vim = game:GetService("VirtualInputManager")
			local cam = workspace.CurrentCamera
			local size = cam and cam.ViewportSize or Vector2.new(800, 600)
			vim:SendMouseMoveEvent(size.X / 2, size.Y / 2, game)
			task.wait(0.05)
			vim:SendKeyEvent(true, Enum.KeyCode.F13, false, game)
			task.wait(0.05)
			vim:SendKeyEvent(false, Enum.KeyCode.F13, false, game)
		end
		keep(LP.Idled:Connect(function()
			if not afk.on then return end
			task.spawn(function()
				pcall(function()
					local vu = game:GetService("VirtualUser")
					vu:CaptureController()
					vu:ClickButton2(Vector2.new())
				end)
			end)
		end))
		local toggle = tab:CreateToggle({
			Name = "Anti-AFK",
			Desc = "Sends a virtual mouse move + key press every 60s (works with Roblox in background)",
			Default = false, Flag = "AnimeDiceAntiAfk",
			Callback = function(on)
				afk.gen = afk.gen + 1
				local mine = afk.gen
				afk.on = on == true
				if not on then return end
				task.spawn(function()
					while afk.gen == mine and not State.dead do
						local ok, err = pcall(nudge)
						if not ok then warn("[AntiAFK] input failed: " .. tostring(err)) end
						for _ = 1, 60 do
							if afk.gen ~= mine or State.dead then break end
							task.wait(1)
						end
					end
				end)
			end,
		})
		Toggles[#Toggles + 1] = toggle
	end
	tab:CreateSection("Interface")
	tab:CreateKeybind({
		Name = "Menu key", Desc = "Shows and hides this window",
		Default = "RightControl", Flag = "AnimeDiceMenuKey",
		OnChanged = function(key)
			if key then pcall(function() Window:SetKeybind(key) end) end
		end,
	})
	tab:CreateToggle({
		Name = "Debug log", Desc = "Prints failed remote calls and errors from the automations to the console (F9)",
		Default = CONFIG.Debug, Flag = "AnimeDiceDebug",
		Callback = function(on) CONFIG.Debug = on == true end,
	})
	tab:CreateConfigManager({ Name = "Configs" })
	tab:CreateSection("Troubleshooting")
	local EXPECT_MODULES = {
		"DataController", "EntryRegistry", "Dice", "Upgrades", "TreeStructure", "QuestConfig", "RebirthStatsConfig",
		"PlotConfig", "GearConfig", "UnitUtil", "QuirkUtil", "Fusing", "FusingUtil", "AwakeningConfig", "AwakeningUtil",
		"PotionFusingUtil", "BuffController", "Towers", "DailyRewardConfig", "CodesConfig",
		"AppleConfig", "AppleShopConfig", "AppleTree", "AutumnQuestConfig", "LeafDice",
	}
	local EXPECT_REMOTES = {
		{ "RollService", "RollDice" }, { "DiceShopService", "BuyDice" }, { "DiceShopService", "EquipDice" },
		{ "PlotService", "CollectBalance" }, { "PlotService", "EquipBest" }, { "PlotService", "InteractSlot" },
		{ "PlotService", "LevelUpSlot" }, { "UnitService", "Equip" }, { "GearService", "Equip" }, { "SpinService", "Use" },
		{ "SellService", "SellInventory" }, { "FusingService", "Fuse" }, { "FusingService", "Result" },
		{ "QuirkService", "Roll" }, { "AwakeningService", "Awaken" },
		{ "RebirthService", "Rebirth" }, { "RebirthService", "BuyUpgrade" }, { "RebirthService", "AddStat" },
		{ "QuestService", "Claim" }, { "BoostService", "Use" }, { "PotionFusingService", "Fuse" },
		{ "DailyRewardService", "Claim" }, { "OfflineEarningsService", "Claim" }, { "CodesService", "RedeemCode" },
		{ "GroupRewardService", "Claim" },
		{ "Towers", "PlayTower" }, { "Towers", "CompleteTowerFloor" }, { "Towers", "CancelTower" }, { "Towers", "EquipBestTowerTeam" },
		{ "AutumnService", "Travel" }, { "AppleService", "Sync" }, { "AppleService", "Collect" }, { "AppleService", "BuyUpgrade" },
		{ "AppleTreeService", "BuyAppleUpgrade" }, { "AppleShopService", "Buy" }, { "LeafDiceService", "Roll" },
	}
	tab:CreateButton({
		Name = "Run diagnostics",
		Desc = "Checks which game modules and remotes this script can find (full list in the console, F9)",
		Callback = function()
			task.spawn(function()
				local missingModules, missingRemotes = {}, {}
				for _, name in ipairs(EXPECT_MODULES) do
					moduleFailedAt[name] = nil
					if not Module(name) then missingModules[#missingModules + 1] = name end
				end
				for _, pair in ipairs(EXPECT_REMOTES) do
					if not Remote(pair[1], pair[2]) then missingRemotes[#missingRemotes + 1] = pair[1] .. "." .. pair[2] end
				end
				local mTotal, rTotal = #EXPECT_MODULES, #EXPECT_REMOTES
				local mFound, rFound = mTotal - #missingModules, rTotal - #missingRemotes
				warn(string.format("[AnimeDice] diagnostics: %d/%d modules, %d/%d remotes found", mFound, mTotal, rFound, rTotal))
				if #missingModules > 0 then warn("[AnimeDice] missing modules: " .. table.concat(missingModules, ", ")) end
				if #missingRemotes > 0 then warn("[AnimeDice] missing remotes: " .. table.concat(missingRemotes, ", ")) end
				local data = Data()
				warn("[AnimeDice] player data: " .. (data and "readable" or "NOT readable (DataController.Data)"))
				local clean = #missingModules == 0 and #missingRemotes == 0 and data ~= nil
				notify("Diagnostics",
					string.format("Modules %d/%d  \194\183  Remotes %d/%d  \194\183  Data %s%s",
						mFound, mTotal, rFound, rTotal, data and "ok" or "missing",
						clean and "" or "\nMissing names are listed in the console (F9). Event tabs are optional."),
					clean and "Success" or "Warning", 6)
			end)
		end,
	})
	tab:CreateButton({
		Name = "Unload script",
		Desc = "Stops every automation, undoes the hooks and closes this window",
		Callback = function()
			Window:Confirm({
				Title = "Unload script", Content = "Turn everything off and close the window?", Icon = "power",
				ConfirmText = "Unload",
				Callback = function()
					State.dead = true
					for _, t in ipairs(Toggles) do pcall(t.Set, t, false) end
					for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
					State.towerHold, State.towerPrepare, State.busy = false, false, nil
					task.delay(0.2, function() pcall(function() Window:Destroy() end) end)
				end,
			})
		end,
	})
end
notify("Anime Dice", "Loaded. Open Settings > Run diagnostics if something does nothing.", "Info", 5)
