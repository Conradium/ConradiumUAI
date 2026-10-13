-- Model-facing structured results. UI receipts keep their original text/data.
return function(env)
	local util = env.require("runtime/util")
	local details = env.require("tools/native_helpers")
	local M = {}
	local MARK = "\n\nResult data:\n"
	local MAX_BYTES, MAX_NODES = 4 * 1024 * 1024, 10000
	local IMPORTANT = { "ok", "status", "error", "id", "sourceId", "documentId", "instanceId", "revision", "sourceRevision", "snapshotId", "batchId", "patchId", "sessionId", "runId", "offset", "nextOffset", "cursor", "nextCursor", "totalBytes", "bytes", "eof", "complete", "truncated", "omitted", "count", "total" }
	-- Normalize bounded JSON-like evidence before encoding. Host callbacks, cycles
	-- or enormous graphs cannot make model-result formatting crash a tool batch.
	local function snapshot(data)
		local seen, nodes, bytes = {}, 0, 0
		local function visit(value, depth)
			nodes = nodes + 1
			if nodes > MAX_NODES or depth > 24 then error("structured result exceeds traversal limit", 0) end
			local kind = type(value)
			if kind == "string" then
				bytes = bytes + #value
				if bytes > MAX_BYTES then error("structured result exceeds retention limit", 0) end
				return (util.sanitise(value))
			elseif kind == "number" then return value == value and value ~= math.huge and value ~= -math.huge and value or 0
			elseif kind == "boolean" or kind == "nil" then return value
			elseif kind ~= "table" then return "<" .. kind .. ">" end
			if seen[value] then error("structured result contains a cycle", 0) end
			if util.isEmptyObject(value) then return util.emptyObject() end
			seen[value] = true
			local out = {}
			for key, item in pairs(value) do
				if type(key) == "string" or type(key) == "number" then out[visit(key, depth + 1)] = visit(item, depth + 1) end
			end
			seen[value] = nil
			return out
		end
		local ok, value = pcall(visit, data, 0)
		if not ok then return nil end
		local encoded, json = pcall(util.encode, value)
		if not encoded or #json > MAX_BYTES then return nil end
		return value, json
	end
	local function inlineData(data, text)
		if type(data) ~= "table" then return data end
		if util.isEmptyObject(data) then return util.emptyObject() end
		local out = {}
		for key, value in pairs(data) do
			if type(value) == "string" and #value >= 256 and text:find(value, 1, true) then out[key] = "<included verbatim in result text>"
			elseif type(value) == "table" then out[key] = inlineData(value, text)
			else out[key] = value end
		end
		return out
	end
	local function summary(data, room)
		local out = { structuredDetailsOmitted = true }
		if type(data) == "table" then
			for _, key in ipairs(IMPORTANT) do
				local value = data[key]
				if (type(value) == "string" and #value <= room) or type(value) == "number" or type(value) == "boolean" then
					out[key] = value
					local ok, json = pcall(util.encode, out)
					if not ok or #json > room then out[key] = nil end
				end
			end
		end
		return util.encode(out)
	end
	function M.signature(data) local _, json = snapshot(data); return json end
	function M.render(text, data, budget, group, available, referenceAllowed)
		if data == nil then return nil end
		budget = tonumber(budget) or 4000
		if budget ~= budget or budget < 256 then
			local note = "Structured result needs a tool result budget of at least 256 bytes. Narrow the query or increase the budget."
			return note:sub(1, budget == budget and math.max(0, math.floor(budget)) or #note)
		end
		budget = math.min(128000, math.floor(budget))
		text = tostring(text or "")
		local copied = snapshot(data)
		local reference = details.reference(data)
		if reference and referenceAllowed == false then
			-- A hook amended this receipt after a native helper retained its first
			-- version. Never direct the model back to the superseded pre-hook data.
			if copied then
				copied.resultId, copied.readTool, copied.expiresInSeconds = nil, nil, nil
				copied.detailsUnavailable = "Original retained details omitted after postTool changes."
			end
			reference = nil
		end
		local json = copied ~= nil and util.encode(inlineData(copied, text)) or nil
		-- A native receipt can already contain a bounded useful summary and its
		-- own detail pointer. Deliver both immediately when they fit; forcing an
		-- extra reader call here spent a model round trip to recover the same text.
		if json and #text + #MARK + #json <= budget and (not reference or available(reference.readTool)) then return text .. MARK .. json end
		local reader = reference and reference.readTool or details.reader(group)
		if reader and available(reader) then
			local key = reference and reference.resultId
			if not key and copied ~= nil then key = details.retain(copied, text, group) end
			if key then
				-- Never clip a page while advertising its original nextOffset. Both
				-- source bytes and original continuation remain in this exact receipt.
				local hint = "Result retained. Read section=text before continuing; omit section to inspect its fields."
				local pointer = { readTool = reader, result_id = key, section = "text", offset = 1 }
				return hint .. MARK .. util.encode(pointer)
			end
		end
		-- Existing prose/source pages remain useful without a detail reader. Do not
		-- discard their exact bytes just to make room for newly exposed metadata.
		if #text <= budget then
			local room = budget - #text - #MARK
			if room >= 33 then return text .. MARK .. summary(copied or data, room) end
			return text
		end
		local note = "Structured details omitted: no available detail reader or retention limit reached. Narrow the original query."
		local fields = summary(copied or data, math.max(64, budget - #note - #MARK))
		if #text + #note + #MARK + #fields + 1 <= budget then return text .. "\n" .. note .. MARK .. fields end
		return note .. " Original result text omitted; its page was not consumed." .. MARK .. summary(copied or data, math.max(64, budget - #note - #MARK - 61))
	end
	return M
end
