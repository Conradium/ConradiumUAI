return function(env)
	local explorer = env.require("runtime/explorer")
	local edits = env.require("runtime/instance_edits")
	local changes = env.require("runtime/changes")
	local sources = env.require("tools/source_documents")
	local exports = env.require("runtime/native_exports")
	local store = env.require("runtime/code_store")
	local N = env.require("tools/native_helpers").forGroup("instance")
	local H = env.require("tools/helpers")
	local util = env.require("runtime/util")
	local values = env.require("runtime/values")
	local clock = env.require("runtime/clock")
	local tools, pages = {}, {}
	local str, num, boolean = { type = "string" }, { type = "integer", minimum = 1 }, { type = "boolean" }
	local pageLimit = { type = "integer", minimum = 1, maximum = 100, description = "Items per page, default 25; large results use retained details." }
	local ids = { type = "array", items = str, maxItems = 20 }
	local function focus(destination) store.workspace.destination = destination; env.require("ui/app").show("code") end
	N.add(tools, "explorer_state", "read", "Read native Explorer selection, root handles, metadata coverage and capabilities. Does not scan or change selection.", {}, {}, function() return N.result(explorer.state(), "Shared Explorer state") end)
	N.add(tools, "explorer_children", "read", "Read a bounded child page by exact parent handle or logical root (nil/bookmarks). Cursors reject changed branches.",
		{ parent_id = str, root = { type = "string", enum = { "nil", "bookmarks" } }, cursor = str, limit = pageLimit }, {}, function(args)
		if args.parent_id and args.root then return N.fail("Choose a parent_id or logical root") end
		local page, why = explorer.children(args.parent_id, args.cursor, args.limit or 25, args.root); return N.result(N.page(page), why or "Child page")
	end)
	N.add(tools, "explorer_search", "read", "Search by literal name, class, tag and subtree with bounded cooperative traversal and snapshot pages.",
		{ name = str, class = str, tag = str, root_id = str, cursor = str, pattern = boolean, limit = pageLimit }, {}, function(args, ctx)
		local page, why = explorer.query({ name = args.name, class = args.class, tag = args.tag, rootId = args.root_id, cursor = args.cursor, pattern = args.pattern, limit = args.limit or 25 }, ctx)
		return N.result(N.page(page), why or "Search page; inspect complete/reason for traversal limits")
	end)
	N.add(tools, "explorer_select", "write", "Explicitly change shared Explorer selection (maximum 20). Existing selection requires expected_revision. focus optionally opens the native workspace.",
		{ instance_ids = ids, mode = { type = "string", enum = { "replace", "add", "remove", "clear" } }, expected_revision = { type = "integer", minimum = 0 }, focus = boolean }, {}, function(args)
		if explorer.selectionRevision > 0 and args.expected_revision == nil then return N.fail("expected_revision is required") end
		local state, why = explorer.select(args.instance_ids or {}, args.mode, args.expected_revision)
		if state and args.focus then focus("Explorer") end; return N.result(state, why or "Selection updated")
	end)
	N.add(tools, "explorer_properties", "read", "Read supported properties, attributes or tags for exact handles or shared selection. Returns a bounded page and an expiring snapshot_id for guarded edits; large values are labelled previews.",
		{ instance_ids = ids, section = { type = "string", enum = { "properties", "attributes", "tags" } }, fields = { type = "array", items = str, maxItems = 100 }, cursor = str, limit = pageLimit }, {}, function(args)
		local data, at = nil, 1
		if args.cursor then
			local key, index = args.cursor:match("^(.-):page:(%d+)$"); data, at = pages[key], tonumber(index)
			if not data or not at or at < 1 or at > #data.items or clock.ms() > data.expiresAt then return N.fail("stale_cursor: inspect these fields again") end
			if (args.instance_ids and util.encode(args.instance_ids) ~= util.encode(data.selectorIds))
				or (args.section and args.section ~= data.selectorSection)
				or (args.fields and util.encode(args.fields) ~= util.encode(data.selectorFields)) then return N.fail("stale_cursor: selectors changed; inspect these fields again") end
		else
			local why; data, why = explorer.properties(args.instance_ids, args.section, args.fields); if not data then return N.fail(why) end
			data.selectorIds, data.selectorSection, data.selectorFields = util.copy(args.instance_ids or explorer.selectedIds), args.section or "properties", args.fields and util.copy(args.fields)
			if util.count(pages) >= 20 then local oldest; for key, page in pairs(pages) do if not oldest or page.expiresAt < pages[oldest].expiresAt then oldest = key end end; pages[oldest] = nil end
			pages[data.snapshotId] = data
		end
		local items, bytes = {}, 0
		for index = at, math.min(#data.items, at + (args.limit or 25) - 1) do
			local row = util.deepCopy(data.items[index])
			for _, observation in ipairs(row.observations) do
				if #util.encode(observation.value) > 200 then observation.value = { kind = "preview", text = util.ellipsis(values.format(observation.value), 120), complete = false } end
			end
			local size = #util.encode(row)
			if #items > 0 and bytes + size > H.resultBudget() - 800 then break end
			items[#items + 1] = row; bytes = bytes + size
		end
		return N.result({ snapshotId = data.snapshotId, expiresAt = data.expiresAt, items = items, total = #data.items, coverage = data.coverage,
			nextCursor = at + #items <= #data.items and data.snapshotId .. ":page:" .. (at + #items) or nil, partial = data.partial }, "Observed field page")
	end)
	local function prepareEdits(args)
		if type(args.operations) ~= "table" or #args.operations < 1 or #args.operations > 100 then return nil, "Use 1–100 field operations" end
		local operations = util.deepCopy(args.operations)
		for _, op in ipairs(operations) do
			op.instanceId, op.key, op.kind = op.instance_id, op.field, op.kind or "property"
			if op.snapshot_id or args.snapshot_id then
				if op.expected then return nil, "Choose expected value or snapshot_id, not both" end
				local expected, why = explorer.expected(op.snapshot_id or args.snapshot_id, op.instanceId, op.kind, op.key); if not expected then return nil, why end; op.expected = expected
			end
		end
		return operations
	end
	N.add(tools, "instance_edit_many", "write", "Apply ordered typed property/attribute/tag operations with expected values or an observed snapshot. Preflight conflicts produce zero writes. Property/attribute changes share Game changes Undo.",
		{ operations = { type = "array", minItems = 1, maxItems = 100, items = { type = "object", properties = {
			instance_id = str, field = str, kind = { type = "string", enum = { "property", "attribute", "tag" } },
			expected = { type = "object", description = "Typed prior value from inspection, or use snapshot_id." },
			value = { type = "object", description = "Typed node, e.g. {kind='number', value=10}." }, remove = boolean, snapshot_id = str,
		}, required = { "instance_id", "field" } } }, snapshot_id = str }, { "operations" }, function(args, ctx, prepared)
		local operations, why = prepared; if not operations then operations, why = prepareEdits(args) end; if not operations then return N.fail(why) end
		ctx.origin = "tool"; local result = edits.apply(operations, ctx)
		-- Full field histories stay available by batch; avoid an oversized result.
		return N.result(result)
	end, prepareEdits)
	N.add(tools, "code_open_source", "write", "Open a script/file/capture as a source snapshot in the shared Code workspace. Large source stays in a bounded reader. Never overwrites a modified document or executes source.",
		{ instance_id = str, source_id = str, path = str, record_id = str, record_revision = num, name = str, focus = boolean, decompile = boolean, refresh = boolean }, {}, function(args, ctx)
		local result, why, detail = sources.open({ instanceId = args.instance_id, sourceId = args.source_id, path = args.path, recordId = args.record_id, recordRevision = args.record_revision, name = args.name, focus = args.focus, decompile = args.decompile, refresh = args.refresh }, ctx)
		if not result and detail then return { ok = false, text = why, data = detail } end
		if result and args.focus then focus("Editor") end; return N.result(result, why or "Opened source snapshot")
	end)
	local export = N.add(tools, "explorer_export", "write", "Export explicitly selected object metadata to a verified user file. Model export and full-place saving are not provided.",
		{ instance_ids = ids, format = { type = "string", enum = { "metadata" } }, fields = { type = "array", items = str, maxItems = 20 }, descendants = boolean, depth = { type = "integer", minimum = 0, maximum = 8 }, destination = str }, { "instance_ids" }, function(args, ctx)
		local result, why = exports.explorer(args.instance_ids, args, ctx); return N.result(result, why or "Verified metadata export")
	end); export.needs = { "fs" }
	N.add(tools, "changes_list", "read", "List recorded UAI property/attribute changes and Undo status. Other game effects are outside this history.", { offset = num }, {}, function(args)
		local batches, items = changes.list(), {}; local at = math.max(1, args.offset or 1)
		for i = at, math.min(#batches, at + 9) do local batch = batches[i]; items[#items + 1] = { id = batch.id, at = batch.at, origin = batch.origin, status = batch.status, fields = #batch.records } end
		return N.result({ items = items, nextOffset = at + #items <= #batches and at + #items or nil }, "Supported game-change history")
	end)
	N.add(tools, "changes_undo", "write", "Undo one recorded property/attribute batch. Rechecks every target/value and never overwrites a conflicting newer edit.", { batch_id = str }, { "batch_id" }, function(args, ctx) return N.result(changes.undo(args.batch_id, ctx)) end)
	N.add(tools, "changes_read", "read", "Inspect recorded before/after values for one supported game-change batch.", { batch_id = str, offset = num }, { "batch_id" }, function(args)
		for _, batch in ipairs(changes.list()) do if batch.id == args.batch_id then
			local at, items = math.max(1, args.offset or 1), {}; for i = at, math.min(#batch.records, at + 2) do items[#items + 1] = batch.records[i] end
			return N.result({ batchId = batch.id, status = batch.status, items = items, nextOffset = at + #items <= #batch.records and at + #items or nil }, "Recorded field changes")
		end end
		return N.fail("expired: game-change batch is no longer retained")
	end)
	N.add(tools, "code_extract_source", "write", "Extract a UTF-8 byte range from an immutable source snapshot into a separate editable document. Opening or extracting never runs source.",
		{ source_id = str, document_id = str, first = num, after = num, name = str }, {}, function(args)
		if (args.source_id and args.document_id) or (not args.source_id and not args.document_id) then return N.fail("Choose exactly one source_id or document_id") end
		local doc, why = sources.extract({ sourceId = args.source_id, documentId = args.document_id, first = args.first, after = args.after, name = args.name })
		return N.result(doc and { documentId = doc.id, revision = doc.revision, bytes = #doc.source, readOnly = false }, why or "Editable source extraction created")
	end)
	env.require("runtime/dispose").add(function() pages = {} end, "Explorer tool field pages")
	return tools
end
