return function(env)
	local refs = env.require("runtime/instance_refs")
	local transport = env.require("tools/remote_transport")
	local values = env.require("runtime/values")
	local explorer = env.require("runtime/explorer")
	local H = env.require("tools/helpers")
	local N = env.require("tools/native_helpers").forGroup("remotes")
	local M = { run = {} }
	local function prepare(args)
		local remote, why = refs.select(args); if not remote then return nil, why end
		local packed, err = transport.arguments(args); if not packed then return nil, err end
		local graph = values.snapshot(packed); if not graph.complete then return nil, "Arguments exceed the supported snapshot budget" end
		return { remoteId = refs.id(remote), arguments = graph }
	end
	for name, method in pairs({ remote_fire = "FireServer", remote_invoke = "InvokeServer" }) do
		M.run[name] = function(args, ctx, prepared)
			local bound, why = prepared; if not bound then bound, why = prepare(args) end; if not bound then return N.fail(why) end
			local result = transport.call(bound.remoteId, method, bound.arguments, { timeout = args.timeout }, ctx)
			if result.results then
				result.data.results = { count = result.results.count, slots = {}, complete = result.results.complete }
				for i = 1, math.min(8, #result.results.slots) do result.data.results.slots[i] = { index = i, preview = values.format(result.results.slots[i]), kind = result.results.slots[i].kind } end
				result.results = nil
			end
			return result
		end
	end
	function M.run.remotes_list(args, ctx)
		local root, why = H.resolve(args.root or "game"); if not root then return N.fail(why) end
		local page, err = explorer.query({ rootId = refs.id(root), name = args.name, kind = "remote", cursor = args.cursor, limit = math.min(args.limit or 5, 5) }, ctx)
		if page then for _, item in ipairs(page.items) do item.methods = item.className == "RemoteFunction" and { "InvokeServer" } or { "FireServer", "OnClientEvent" } end end
		return N.result(N.page(page), err or "Remote references; capture was not started. Continue with nextCursor and the same filters.")
	end
	function M.extend(tool)
		if M.run[tool.name] then tool.run = M.run[tool.name] end
		if tool.name == "remotes_list" then
			tool.parameters.properties.cursor = { type = "string", description = "Continue the retained search snapshot with identical root/name filters." }
			tool.parameters.properties.limit = { type = "integer", minimum = 1, maximum = 5, description = "References per page; default 5. Follow nextCursor for the remaining matches." }
		end
		if tool.name == "remote_fire" or tool.name == "remote_invoke" then
			tool.prepare = prepare; tool.timeout = 65
			tool.parameters.properties.instance_id = { type = "string" }
			tool.parameters.properties.arguments = { type = "object", description = "Packed typed graph: count, slots, nodes. Explicit nil slots preserve argument arity." }
			tool.parameters.properties.args.description = "Legacy arguments: strings, numbers, booleans, or vec3:/vector3:/vec2:/color3:/cframe:/instance:/number: prefixes. Use string: to preserve literal prefix text (e.g. string:instance:hello), or use packed arguments for exact typed values."
			tool.parameters.properties.timeout = { type = "number", minimum = 1, maximum = 60 }
			tool.parameters.required = {}
		end
	end
	return M
end
