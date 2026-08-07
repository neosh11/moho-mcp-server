-- **************************************************
-- Provide Moho with the name of this script object
-- **************************************************

ScriptName = "MohoMCP_Server"

-- **************************************************
-- General information about this script
-- **************************************************

MohoMCP_Server = MohoMCP_Server or {}

-- Module references (preserve across re-loads)
if MohoMCP_Server.server == nil then
	MohoMCP_Server.server = nil
	MohoMCP_Server.isLoaded = false
	MohoMCP_Server.BASE_DIR = ""
	MohoMCP_Server.pollActive = false
	MohoMCP_Server.moho = nil
end

function MohoMCP_Server:Name()
	return "MohoMCP Server"
end

function MohoMCP_Server:Version()
	return "0.2.0"
end

function MohoMCP_Server:Description()
	return "Start or stop the MohoMCP server for AI clients"
end

function MohoMCP_Server:Creator()
	return "MohoMCP Project"
end

function MohoMCP_Server:UILabel()
	return "Start/Stop MohoMCP Server"
end

-- **************************************************
-- Helpers
-- **************************************************

--- Determine the directory this script lives in so we can load siblings.
local function getScriptDir()
	local info = debug.getinfo(1, "S")
	local path = info.source
	if path:sub(1, 1) == "@" then
		path = path:sub(2)
	end
	-- Normalize to forward slashes
	path = path:gsub("\\", "/")
	local dir = path:match("^(.*/)")
	return dir or "./"
end

--- Runtime modules live under Scripts/Modules so Moho does not expose every
--- implementation file as a command in the Scripts menu.
local function getRuntimeDir()
	return getScriptDir() .. "../../Modules/MohoMCP/"
end

--- Add the plugin directory to Lua's package.path.
local function setupPackagePath(baseDir)
	local sep = package.config:sub(1, 1)
	local pattern = baseDir .. "?.lua;" .. baseDir .. "?" .. sep .. "init.lua"
	if not package.path:find(baseDir, 1, true) then
		package.path = pattern .. ";" .. package.path
	end
end

-- **************************************************
-- Module loading
-- **************************************************

local function loadModules(baseDir)
	if MohoMCP_Server.isLoaded then
		return true
	end

	setupPackagePath(baseDir)

	-- Load the JSON library and make it globally available
	local jsonOk, jsonMod = pcall(require, "json")
	if not jsonOk then
		print("[MohoMCP] ERROR: Failed to load json.lua: " .. tostring(jsonMod))
		return false
	end
	_G.json = jsonMod

	-- Load core modules
	local protocolOk, protocolMod = pcall(require, "moho_mcp.protocol")
	if not protocolOk then
		print("[MohoMCP] ERROR: Failed to load protocol: " .. tostring(protocolMod))
		return false
	end

	local validatorOk, validatorMod = pcall(require, "moho_mcp.validator")
	if not validatorOk then
		print("[MohoMCP] ERROR: Failed to load validator: " .. tostring(validatorMod))
		return false
	end

	local serverOk, srv = pcall(require, "moho_mcp.server")
	if not serverOk then
		print("[MohoMCP] ERROR: Failed to load server: " .. tostring(srv))
		return false
	end

	-- Initialize server with dependencies
	srv.init({ protocol = protocolMod, validator = validatorMod, json = jsonMod })

	-- Load tool handlers
	local toolModules = {
		{ name = "moho_mcp.tools.document",  methods = { "document.getInfo", "document.getLayers", "document.setFrame", "document.screenshot" } },
		{ name = "moho_mcp.tools.layer",     methods = { "layer.getProperties", "layer.getChildren", "layer.getBones", "layer.setTransform", "layer.setVisibility", "layer.setOpacity", "layer.setName", "layer.selectLayer" } },
		{ name = "moho_mcp.tools.bone",      methods = { "bone.getProperties", "bone.setTransform", "bone.selectBone" } },
		{ name = "moho_mcp.tools.animation", methods = { "animation.getKeyframes", "animation.getFrameState", "animation.setKeyframe", "animation.deleteKeyframe", "animation.setInterpolation" } },
		{ name = "moho_mcp.tools.mesh",      methods = { "mesh.getPoints", "mesh.getShapes" } },
		{ name = "moho_mcp.tools.batch",     methods = { "batch.execute" } },
		{ name = "moho_mcp.tools.rig",       methods = { "rig.createCutout" } },
	}

	for _, toolDef in ipairs(toolModules) do
		local toolOk, toolMod = pcall(require, toolDef.name)
		if toolOk and toolMod then
			for _, method in ipairs(toolDef.methods) do
				local funcName = method:match("%.(.+)$")
				if funcName and toolMod[funcName] then
					srv.registerHandler(method, toolMod[funcName])
					print("[MohoMCP] Registered handler: " .. method)
				else
					print("[MohoMCP] WARNING: No handler for " .. method)
				end
			end
		else
			print("[MohoMCP] WARNING: Failed to load " .. toolDef.name .. ": " .. tostring(toolMod))
		end
	end

	MohoMCP_Server.server = srv
	MohoMCP_Server.isLoaded = true
	return true
end

local MODULE_NAMES = {
	"json",
	"moho_mcp.protocol",
	"moho_mcp.validator",
	"moho_mcp.server",
	"moho_mcp.tools.document",
	"moho_mcp.tools.layer",
	"moho_mcp.tools.bone",
	"moho_mcp.tools.animation",
	"moho_mcp.tools.mesh",
	"moho_mcp.tools.batch",
	"moho_mcp.tools.rig",
}

--- Forget runtime modules after a stop so the next start loads edited Lua files.
--- This makes the normal development loop: install once, edit, Stop, Start.
local function unloadModules()
	for _, moduleName in ipairs(MODULE_NAMES) do
		package.loaded[moduleName] = nil
	end
	_G.json = nil
	MohoMCP_Server.server = nil
	MohoMCP_Server.isLoaded = false
end

-- **************************************************
-- Polling through Moho's application-wide update table
-- **************************************************

local function pollFromUpdateTable(moho)
	if not MohoMCP_Server.pollActive or not MohoMCP_Server.server or MohoMCP_Server._polling then
		return
	end
	-- Some Moho menu refreshes call IsEnabled without a ScriptInterface.
	-- Keep the valid reference received by Run and use it for those callbacks.
	moho = moho or MohoMCP_Server.moho
	local helper = nil
	if not moho or not moho.document then
		local helperOk, helperOrError = pcall(function()
			return MOHO.ScriptInterfaceHelper:new_local()
		end)
		if helperOk and helperOrError then
			helper = helperOrError
			moho = helper:MohoObject()
		end
	end
	if not moho then
		if helper then helper:delete() end
		return
	end
	MohoMCP_Server._polling = true
	local pollOk, pollErr = pcall(MohoMCP_Server.server.poll, moho)
	MohoMCP_Server._polling = false
	if helper then helper:delete() end
	if not pollOk then
		print("[MohoMCP] Poll error (non-fatal): " .. tostring(pollErr))
	end
end

local function installUpdateHook()
	if MohoMCP_Server._updateHookInstalled then
		return
	end
	if type(MOHO.UpdateTable) ~= "table" then
		MOHO.UpdateTable = {}
	end
	table.insert(MOHO.UpdateTable, pollFromUpdateTable)
	MohoMCP_Server._updateHook = pollFromUpdateTable
	MohoMCP_Server._updateHookInstalled = true
	print("[MohoMCP] Registered application update hook")
end

-- **************************************************
-- IsEnabled — called by MOHO to update menu state.
-- We piggyback on this for reliable polling since it
-- fires periodically even without viewport interaction.
-- **************************************************

function MohoMCP_Server:IsEnabled(moho)
	if moho then
		MohoMCP_Server.moho = moho
	end
	pollFromUpdateTable(moho)
	return true
end

-- **************************************************
-- The guts of this script
-- **************************************************

function MohoMCP_Server:Run(moho)
	-- Run always receives a valid ScriptInterface. Preserve it for callbacks
	-- where Moho omits the argument.
	MohoMCP_Server.moho = moho
	-- Determine base directory on first run
	if MohoMCP_Server.BASE_DIR == "" then
		MohoMCP_Server.BASE_DIR = getRuntimeDir()
	end

	-- Load modules on first run
	if not MohoMCP_Server.isLoaded then
		local loaded = loadModules(MohoMCP_Server.BASE_DIR)
		if not loaded then
			LM.GUI.Alert(LM.GUI.ALERT_WARNING,
				"MohoMCP failed to load modules.",
				"Check the script console (Window > Script Console) for details.",
				nil,
				MOHO.Localize("/Scripts/OK=OK"),
				nil, nil)
			return
		end
	end

	local srv = MohoMCP_Server.server

	if srv.isRunning() then
		-- Stop the server
		srv.stop()
		MohoMCP_Server.pollActive = false
		unloadModules()
		LM.GUI.Alert(LM.GUI.ALERT_INFO,
			"MohoMCP Server stopped.",
			nil, nil,
			MOHO.Localize("/Scripts/OK=OK"),
			nil, nil)
	else
		-- Start the server
		local ok, err = srv.start()
		if ok then
			MohoMCP_Server.pollActive = true
			-- Use Moho's application-wide update callback instead of patching tools.
			installUpdateHook()
			-- Do an initial poll with the current moho reference
			srv.poll(moho)
			LM.GUI.Alert(LM.GUI.ALERT_INFO,
				"MohoMCP Server started!",
				"IPC directory: " .. srv.getInfo().ipcDir,
				"Start your MCP client to connect.",
				MOHO.Localize("/Scripts/OK=OK"),
				nil, nil)
		else
			LM.GUI.Alert(LM.GUI.ALERT_WARNING,
				"MohoMCP Server failed to start.",
				tostring(err),
				nil,
				MOHO.Localize("/Scripts/OK=OK"),
				nil, nil)
		end
	end
end
