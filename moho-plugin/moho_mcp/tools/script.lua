-- script.lua
-- Runs arbitrary Lua inside MOHO: script.run { code? , path?, args? }.
--
-- Disabled unless the bridge was started with MOHO_MCP_ALLOW_SCRIPTS=1; the
-- bridge then writes <ipcDir>/allow_scripts, and this handler refuses to run
-- anything without that file. The server runs this method from the
-- "Run MohoMCP Jobs" menu command when it can (see server.lua), so scripts
-- may create layers, shapes and bones like any menu script.
--
-- The chunk sees the globals plus:
--   moho  — the ScriptInterface
--   args  — params.args (a table, may be empty)
--   print — collected and returned as `output`
-- Its return value is returned as `result` (tables of strings, numbers and
-- booleans pass through; anything else is converted with tostring).

local script = {}

local SEP = package.config:sub(1, 1)

local function ipcDir()
	local tmp = os.getenv("TEMP") or os.getenv("TMP") or os.getenv("TMPDIR") or "/tmp"
	return tmp .. SEP .. "moho-mcp" .. SEP
end

local function allowed()
	local f = io.open(ipcDir() .. "allow_scripts", "r")
	if f then
		f:close()
		return true
	end
	return false
end

local function plain(value, depth)
	depth = depth or 0
	local t = type(value)
	if t == "nil" or t == "boolean" or t == "string" then
		return value
	end
	if t == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			return tostring(value)
		end
		return value
	end
	if t == "table" and depth < 8 then
		local out = {}
		for k, v in pairs(value) do
			local key = (type(k) == "number" or type(k) == "string") and k or tostring(k)
			out[key] = plain(v, depth + 1)
		end
		return out
	end
	return tostring(value)
end

function script.run(moho, params)
	if not allowed() then
		return nil, "script.run is disabled. Start the bridge with MOHO_MCP_ALLOW_SCRIPTS=1 to enable it."
	end
	params = params or {}

	local code, chunkName = params.code, "=mcp-script"
	if params.path ~= nil then
		if type(params.path) ~= "string" then
			return nil, "path must be a string"
		end
		local f, err = io.open(params.path, "r")
		if not f then
			return nil, "Cannot read " .. params.path .. ": " .. tostring(err)
		end
		code = f:read("*a")
		f:close()
		chunkName = "@" .. params.path
	end
	if type(code) ~= "string" or code == "" then
		return nil, "Pass either code (a string of Lua) or path (a .lua file)"
	end

	local output = {}
	local env = setmetatable({
		moho = moho,
		args = type(params.args) == "table" and params.args or {},
		print = function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				parts[#parts + 1] = tostring((select(i, ...)))
			end
			output[#output + 1] = table.concat(parts, "\t")
		end,
	}, { __index = _G })

	local chunk, loadErr = load(code, chunkName, "t", env)
	if not chunk then
		return nil, "Syntax error: " .. tostring(loadErr)
	end

	local ok, result = xpcall(chunk, debug and debug.traceback or tostring)
	if not ok then
		return nil, "Runtime error: " .. tostring(result) ..
			(#output > 0 and ("\nOutput so far:\n" .. table.concat(output, "\n")) or "")
	end

	pcall(function() moho:UpdateUI() end)
	return {
		success = true,
		result = plain(result),
		output = output,
	}
end

return script
