-- **************************************************
-- Runs MohoMCP requests that must not execute inside a poll (FileRender).
-- On macOS the MohoMCP KeepAlive applet presses this menu item through the
-- Accessibility API whenever <ipcDir>/jobs.pending exists; running from a
-- menu command is the context in which Moho's own exports render safely.
-- **************************************************

ScriptName = "MohoMCP_RunJobs"

MohoMCP_RunJobs = {}

function MohoMCP_RunJobs:Name()
	return "Run MohoMCP Jobs"
end

function MohoMCP_RunJobs:Version()
	return "0.1.0"
end

function MohoMCP_RunJobs:Description()
	return "Runs MohoMCP requests (such as renders) queued by the MohoMCP server."
end

function MohoMCP_RunJobs:Creator()
	return "MohoMCP Project"
end

function MohoMCP_RunJobs:UILabel()
	return "Run MohoMCP Jobs"
end

function MohoMCP_RunJobs:IsEnabled(moho)
	return true
end

function MohoMCP_RunJobs:Run(moho)
	if MohoMCP_Server and MohoMCP_Server.server and MohoMCP_Server.server.runJobs then
		local ok, err = pcall(MohoMCP_Server.server.runJobs, moho)
		if not ok then
			print("[MohoMCP] runJobs error: " .. tostring(err))
		end
	end
end
