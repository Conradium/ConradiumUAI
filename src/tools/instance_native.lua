-- Compatibility adapters bind old path forms to exact native targets before approval.
return function(env)
	local refs = env.require("runtime/instance_refs")
	local values = env.require("runtime/values")
	local edits = env.require("runtime/instance_edits")
	local fields = env.require("runtime/instance_fields")
	local schema = env.require("runtime/instance_schema")
	local H = env.require("tools/helpers")
	local N = env.require("tools/native_helpers").forGroup("instance")
	local util = env.require("runtime/util")
	local M = { run = {}, prepare = {} }
	local function binding(args)
		local object, why = refs.select(args); if not object then return nil, why end
		return { instanceId = refs.id(object), expectedParent = values.node(object.Parent) }
	end
	function M.prepare.instance_set(args)
		local bound, why = binding(args); if not bound then return nil, why end
		local object = refs.resolve(bound.instanceId)
		local ok, before = fields.read(object, "property", args.property); if not ok then return nil, "Could not read property" end
		if args.typed_value and args.value ~= nil then return nil, "Choose typed_value or legacy value, not both" end
		local node = args.typed_value
		if not node then local value, err = H.coerce(args.value, before); if value == nil then return nil, err end; node = values.node(value) end
		bound.operations = { { instanceId = bound.instanceId, kind = "property", key = args.property, expected = args.expected_value or values.node(before), value = node } }
		return bound
	end
	function M.run.instance_set(args, ctx, prepared)
		local bound, why = prepared; if not bound then bound, why = M.prepare.instance_set(args) end; if not bound then return N.fail(why) end
		ctx = ctx or {}; ctx.origin = "tool"; return N.result(edits.apply(bound.operations, ctx))
	end
	function M.prepare.instance_attribute(args)
		local bound, why = binding(args); if not bound then return nil, why end
		if args.value == nil and args.typed_value == nil and not args.remove then return bound end
		if (args.value ~= nil and args.typed_value ~= nil) or (args.remove and (args.value ~= nil or args.typed_value ~= nil)) then return nil, "Choose value, typed_value, or explicit removal" end
		local target = refs.resolve(bound.instanceId); local ok, before = fields.read(target, "attribute", args.name); if not ok then return nil, "Attribute cannot be read" end
		local node = args.typed_value
		if args.remove then node = { kind = "nil" }
		elseif not node then
			local text = util.trim(args.value); local value = tonumber(text)
			if value == nil then if text:lower() == "true" then value = true elseif text:lower() == "false" then value = false else value = text end end
			node = values.node(value)
		end
		bound.operations = { { instanceId = bound.instanceId, kind = "attribute", key = args.name, expected = args.expected_value or values.node(before), value = node } }
		return bound
	end
	function M.run.instance_attribute(args, ctx, prepared)
		local bound, why = prepared; if not bound then bound, why = M.prepare.instance_attribute(args) end; if not bound then return N.fail(why) end
		if bound.operations then ctx = ctx or {}; ctx.origin = "tool"; return N.result(edits.apply(bound.operations, ctx)) end
		local object, err = refs.resolve(bound.instanceId); if not object then return N.fail(err) end
		local ok, value = fields.read(object, "attribute", args.name); if not ok then return N.fail("Cannot read attribute") end
		return N.result({ instanceId = bound.instanceId, value = values.node(value) }, args.name .. " = " .. H.show(value))
	end
	function M.run.instance_get(args)
		local object, why = refs.select(args); if not object then return N.fail(why) end
		local out = { H.pathOf(object) .. " [" .. object.ClassName .. "]" }
		local unreadable, omitted, seen = {}, 0, {}
		for _, name in ipairs(args.only_properties and (args.properties or {}) or schema.names(object, args.properties)) do
			if not seen[name] then
				seen[name] = true
				if name == "Source" then out[#out + 1] = "Source = <use script_source; source was not read>"
				else
					local ok, value = fields.read(object, "property", name)
					if ok then out[#out + 1] = name .. " = " .. values.format(values.node(value))
					else unreadable[#unreadable + 1] = name end
				end
			end
		end
		if args.attributes ~= false then
			local ok, attributes = pcall(function() return object:GetAttributes() end)
			if ok and type(attributes) == "table" then
				for index, key in ipairs(util.keys(attributes, true)) do
					if index <= 100 then out[#out + 1] = "Attribute " .. key .. " = " .. values.format(values.node(attributes[key])) else omitted = omitted + 1 end
				end
			else unreadable[#unreadable + 1] = "attributes" end
		end
		if args.tags ~= false then
			local ok, tags = pcall(function() return object:GetTags() end)
			if ok and type(tags) == "table" then
				for index, tag in ipairs(tags) do if index <= 100 then out[#out + 1] = "Tag = " .. tag else omitted = omitted + 1 end end
			else unreadable[#unreadable + 1] = "tags" end
		end
		return N.result({ instanceId = refs.id(object), metadata = schema.coverage, unreadable = unreadable, omitted = omitted }, table.concat(out, "\n"))
	end
	for _, name in ipairs({ "instance_clone", "instance_parent", "instance_destroy" }) do
		M.prepare[name] = function(args)
			local bound, why = binding(args); if not bound then return nil, why end
			if args.parent_id and args.parent then return nil, "Choose parent_id or parent path" end
			if args.parent_id then local object, err = refs.resolve(args.parent_id); if not object then return nil, err end; bound.parentId = refs.id(object)
			elseif args.parent and args.parent:lower() ~= "nil" then local parent, err = H.resolve(args.parent); if not parent then return nil, err end; bound.parentId = refs.id(parent) end
			if name == "instance_clone" and not args.parent and not args.parent_id then
				local target, err = refs.resolve(bound.instanceId); if not target then return nil, err end
				local readable, parent = pcall(function() return target.Parent end); if not readable then return nil, "Could not read the source parent" end
				bound.parentId, bound.detachedParent = parent and refs.id(parent), parent == nil
			end
			return bound
		end
	end
	function M.prepare.instance_create(args)
		if args.parent_id and args.parent then return nil, "Choose parent_id or parent path" end
		local parent, why
		if args.parent_id then parent, why = refs.resolve(args.parent_id) else parent, why = H.resolve(args.parent or "Workspace") end
		if not parent then return nil, why end; return { parentId = refs.id(parent) }
	end
	for name, action in pairs({ instance_clone = "duplicate", instance_parent = "reparent", instance_destroy = "delete", instance_create = "create" }) do
		M.run[name] = function(args, ctx, prepared)
			local bound, why = prepared; if not bound then bound, why = M.prepare[name](args) end; if not bound then return N.fail(why) end
			local op = util.copy(bound); op.name, op.class, op.legacyProperties = args.name, args.class, args.properties
			local chosen = name == "instance_parent" and args.parent and args.parent:lower() == "nil" and "detach" or action
			return N.result(edits.hierarchy(chosen, op, ctx))
		end
	end
	function M.extend(tool)
		if not M.run[tool.name] then return end
		tool.run, tool.prepare = M.run[tool.name], M.prepare[tool.name]
		local p = tool.parameters.properties
		if tool.name ~= "instance_create" then p.instance_id = { type = "string", description = "Exact epoch-scoped identity from inspection; use instead of path to survive rename/reparent." } end
		if p.parent then p.parent_id = { type = "string", description = "Exact destination identity; use instead of parent path." } end
		if tool.name == "instance_set" or tool.name == "instance_attribute" then
			p.typed_value = { type = "object", description = "Typed value node from inspection, e.g. {kind='number', value=10}; use instead of legacy value." }
			p.expected_value = { type = "object", description = "Typed prior value to require before writing. A conflict makes no change." }
		end
		if tool.name == "instance_get" then
			p.only_properties = { type = "boolean", description = "Read only the named properties; skip class defaults. Default false." }
			p.attributes = { type = "boolean", description = "Include up to 100 attributes, default true." }
			p.tags = { type = "boolean", description = "Include up to 100 tags, default true." }
		end
		if tool.name == "instance_attribute" then p.remove = { type = "boolean" } end
		local required = {}; for _, key in ipairs(tool.parameters.required) do if key ~= "path" and key ~= "value" and key ~= "parent" then required[#required + 1] = key end end; tool.parameters.required = required
		if tool.name == "instance_create" then tool.description = "Create an instance detached, validate/apply properties, then parent it. Legacy property maps use sorted property names. Failed setup destroys only the new owned instance." end
	end
	return M
end
