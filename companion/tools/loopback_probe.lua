-- Phase 0 gate probe for the mobile companion.
--
-- Run this on its own in the mobile executor (not through UAI). It answers the two
-- questions that decide whether the companion can help at all:
--   1. Can this executor's request() reach another app on 127.0.0.1?
--   2. Does the companion answer, and does pairing succeed?
--
-- Expected with the companion running: hello -> 200 with "uai-relay", then pair ->
-- 200 with a 64-hex token. If hello errors or times out, the executor cannot reach
-- loopback and no client change will fix it.
local PORT = 8790
local fn = request or http_request
	or (type(syn) == "table" and syn.request)
	or (type(http) == "table" and http.request)
	or (type(fluxus) == "table" and fluxus.request)
if not fn then print("[probe] no executor request function is exposed") return end

local function identify()
	if identifyexecutor then local ok, name = pcall(identifyexecutor) if ok and name then return name end end
	if getexecutorname then local ok, name = pcall(getexecutorname) if ok and name then return name end end
	return "unknown"
end

local function call(url, method, headers, body, timeout)
	local options = { Url = url, Method = method or "GET" }
	if headers then options.Headers = headers end
	if body then options.Body = body end
	if timeout then options.Timeout = timeout end
	local started = tick()
	local ok, res = pcall(fn, options)
	return ok and res or nil, ok and nil or tostring(res), tick() - started
end

local function report(label, res, err, elapsed)
	local status = res and (res.StatusCode or res.Status) or "-"
	print(("[probe] %-6s ok=%-5s %.2fs status=%s"):format(label, tostring(err == nil), elapsed, tostring(status)))
	local text = res and (res.Body or res.ResponseData)
	if text then print("[probe] " .. label .. " body: " .. tostring(text)) else print("[probe] " .. label .. " error: " .. tostring(err)) end
end

print("[probe] executor: " .. identify())
print("[probe] transport: " .. tostring(rawget(getfenv(), "request") ~= nil and "named request()" or "fallback"))

local hello, herr, ht = call(("http://127.0.0.1:%d/api/hello"):format(PORT), "GET", nil, nil, 5)
report("hello", hello, herr, ht)

local body = '{"client":"ProjectUAI-Probe","version":"1.0.0","protocol":2,"placeId":0,"gameId":0}'
local pair, perr, pt = call(("http://127.0.0.1:%d/api/pair"):format(PORT), "POST",
	{ ["Content-Type"] = "application/json" }, body, 5)
report("pair", pair, perr, pt)

if hello and pair then
	print("[probe] loopback reachable and pairing works -- the companion can carry inference")
elseif hello then
	print("[probe] loopback reachable but pairing failed -- check the companion's Diagnostics log")
else
	print("[probe] loopback NOT reachable -- the companion cannot help this executor")
end
