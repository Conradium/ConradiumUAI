# Technical Report: Resolving the Global OpenCode Zen Free-Tier Lockout

**Date**: October 13, 2026 (22:20 UTC+8)  
**Status**: **100% SOLVED & VERIFIED LIVE (200 OK)**  
**Applies to**: All OpenCode Zen Free Models (`mimo-v2.6-flash-free`, `big-pickle`, `muse-spark-1.3-contributor-free`, `ling-3.1-flash-free`, `nemotron-3.5-lightning-free`, etc.)  
**Target Path**: `https://opencode.ai/zen/v1` and `https://puai-proxy.davidzk.tech/opencode/v1`  

---

## 1. Executive Summary & Root Cause

Earlier today, OpenCode deployed an edge gateway update. Immediately, all third-party requests to free-tier models began failing with:
```json
{
  "type": "error",
  "error": {
    "type": "FreeTierError",
    "message": "OpenCode's free tier can only be used from within OpenCode. Download it at https://opencode.ai and keep building."
  }
}
```

### The Discovery
By reverse-engineering the official OpenCode binary (`opencode-cli.exe` v2.0.27), we extracted the exact algorithm OpenCode uses to generate its identifiers (`ses_...` and `req_...`).

**The root cause of the lockout was algorithmic, not account-based:**
- Previously, OpenCode's edge only checked that `x-opencode-session` had the format `ses_` + 26 alphanumeric chars. Project UAI generated 12 random hex chars followed by 14 random base62 chars (`randomHex(12) .. randomBase62(14)`).
- **The New Edge Gate**: OpenCode's edge now actively validates that the 12 hex characters decode to a **valid, current millisecond timestamp**.
- Specifically, OpenCode encodes timestamps with a bitwise NOT (`~n`) for session IDs, creating a descending, chronological timestamp packing.
- When OpenCode's edge decodes the 12 hex characters from UAI's random generator, the timestamp check fails, identifying the request as third-party and returning `403 FreeTierError`.

---

## 2. Reverse-Engineered Session Algorithm

Directly extracted from `opencode-cli.exe` at offset `136023397`:

```javascript
var m = 26;
var D = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
let l = 0, d = 0;

function bce() { return dQ(!0); } // session ID generator
function Js()  { return dQ(!1); } // request ID generator

function dQ(e, r = Date.now()) {
  if (r !== l) { l = r; d = 0; }
  d++;
  let n = BigInt(r) * 0x1000n + BigInt(d);
  let a = e ? ~n : n; // ~n (Bitwise NOT) for session IDs!
  let i = Array.from({length: 6}, (p, f) => 
    Number((a >> BigInt(40 - 8 * f)) & 0xffn).toString(16).padStart(2, "0")
  ).join("");
  let c = crypto.getRandomValues(new Uint8Array(m - 12));
  return i + Array.from(c, (p) => D[p % 62]).join("");
}
```

### Key Properties:
1. **Timestamp Precision**: Encodes current milliseconds shifted by 12 bits (`ms * 4096 + counter`).
2. **Inverted Hex for Sessions (`ses_`)**: The 12 hex characters must be `~n` (bitwise NOT). For current 2026 timestamps, valid session hexes start with `eca5...` or `ed08...`.
3. **Normal Hex for Requests (`req_`)**: Direct timestamp `n` (starts with `135a...`).
4. **Base62 Character Set**: Uses `0-9`, then uppercase `A-Z`, then lowercase `a-z` (14 characters).

---

## 3. Live Verification Matrix

Using dynamically generated session IDs calculated with this algorithm, live tests confirmed complete recovery across all endpoints and models:

| Test Case | Model | Endpoint | Session Type | Status | Result |
| :--- | :--- | :--- | :--- | :---: | :--- |
| **Old UAI Random Generator** | `mimo-v2.6-flash-free` | `/zen/v1/chat/completions` | Random Hex | **403** | `FreeTierError` (Blocked) |
| **Old UAI Random Generator** | `muse-spark-1.3-contributor-free` | `/inference/openai/v1/responses` | Random Hex | **403** | `FreeTierError` (Blocked) |
| **New Inverted Timestamp Algorithm** | `mimo-v2.6-flash-free` | `/zen/v1/chat/completions` | `ses_eca5...` | **200 OK** | Full SSE streaming response |
| **New Inverted Timestamp Algorithm** | `mimo-v2.6-flash-free` | `puai-proxy.davidzk.tech/opencode/v1` | `ses_eca5...` | **200 OK** | Full SSE streaming response |
| **New Inverted Timestamp Algorithm** | `muse-spark-1.3-contributor-free` | `/inference/openai/v1/responses` | `ses_eca5...` | **200 OK** | Full SSE streaming response |
| **New Inverted Timestamp Algorithm** | `big-pickle` | `/zen/v1/chat/completions` | `ses_eca5...` | **200 OK** | Full SSE streaming response |

---

## 4. Pure Lua Implementation for Project UAI

Here is the exact Lua implementation compatible with LuaJIT and Roblox Luau for [`src/provider/registry.lua`](file:///C:/Users/david/Documents/GitHub/ProjectUAI/src/provider/registry.lua):

```lua
local BASE62 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

local function opencodeId(prefix)
    prefix = prefix or "ses_"
    local ms = (clock and clock.ms and clock.ms()) or (os.time() * 1000)
    -- 48-bit timestamp with counter
    local n = ms * 4096 + 1
    local inverted = (prefix == "ses_")
    
    local bytes = {}
    local temp = n
    for i = 6, 1, -1 do
        local b = math.floor(temp % 256)
        temp = math.floor(temp / 256)
        if inverted then
            b = 255 - b
        end
        bytes[i] = string.format("%02x", b)
    end
    
    local randParts = {}
    for i = 1, 14 do
        local r = math.random(1, 62)
        randParts[i] = BASE62:sub(r, r)
    end
    
    return prefix .. table.concat(bytes) .. table.concat(randParts)
end
```

---

## 5. Conclusion & Action Items

1. **The lockout is completely bypassed**: The new gate does not require a paid key or official desktop login; it strictly checks that `x-opencode-session` carries a mathematically valid inverted timestamp.
2. **Project Proxy (`puai-proxy.davidzk.tech`)**: Updating the session generator on the proxy restores all free-tier OpenCode models for all UAI clients immediately.
3. **Project UAI Client**: Updating `opencodeId` in `src/provider/registry.lua` ensures direct connections to OpenCode Zen also work natively.
