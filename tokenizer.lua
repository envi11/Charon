local tokentypes = require "tokens"

local tokenizer = {}

local keyword = {}
for _, value in ipairs(tokentypes.keywords) do keyword[value] = true end

---@param code string
---@return table
function tokenizer.tokenize(code)
    local tokens = {}
    local i = 1
    local line, column = 1, 1
    local function add(type, value, at_line, at_column)
        tokens[#tokens + 1] = { type = type, value = value, line = at_line, column = at_column }
    end
    local function advance(text)
        for c in text:gmatch(".") do
            if c == "\n" then line, column = line + 1, 1 else column = column + 1 end
        end
        i = i + #text
    end
    while i <= #code do
        local rest = code:sub(i)
        local at_line, at_column = line, column
        local text
        if rest:match("^%-%-%[%[") then
            text = rest:match("^%-%-%[%[.-%]%]")
            if not text then error("unterminated multiline comment at line " .. line) end
            advance(text)
        elseif rest:match("^%-%-") then
            text = rest:match("^%-%-[^\n]*")
            advance(text)
        elseif rest:match("^<<") then
            text = rest:match("^(<<.->>)")
            if not text then error("unterminated raw Lua block at line " .. line) end
            add("rawlua", text:sub(3, -3), at_line, at_column); advance(text)
        elseif rest:match("^[ \t\r]+") then
            advance(rest:match("^[ \t\r]+"))
        elseif rest:sub(1, 1) == "\n" or rest:sub(1, 1) == ";" then
            text = rest:sub(1, 1)
            if #tokens == 0 or tokens[#tokens].type ~= "newline" then add("newline", text, at_line, at_column) end
            advance(text)
        elseif rest:match("^%d+%.?%d*") then
            text = rest:match("^%d+%.?%d*"); add("number", text, at_line, at_column); advance(text)
        elseif rest:match("^[%a_][%w_]*") then
            text = rest:match("^[%a_][%w_]*"); add(keyword[text] and "keyword" or "identifier", text, at_line, at_column); advance(text)
        elseif rest:match('^"') or rest:match("^'") then
            local quote = rest:sub(1, 1); local j = 2
            while j <= #rest and rest:sub(j, j) ~= quote do
                if rest:sub(j, j) == "\\" then j = j + 1 end
                j = j + 1
            end
            if j > #rest then error("unterminated string at line " .. line) end
            text = rest:sub(1, j); add("string", text, at_line, at_column); advance(text)
        elseif rest:match("^==") or rest:match("^~=") or rest:match("^<=") or rest:match("^>=") or rest:match("^=>") or rest:match("^[+%-%*/%=<>]") then
            text = rest:match("^==") or rest:match("^~=") or rest:match("^<=") or rest:match("^>=") or rest:match("^=>") or rest:match("^[+%-%*/%=<>]")
            add("operator", text, at_line, at_column); advance(text)
        elseif string.find("(){}[],:", rest:sub(1, 1), 1, true) then
            text = rest:sub(1, 1); add("symbol", text, at_line, at_column); advance(text)
        else
            error("lexical error: unexpected character '" .. rest:sub(1, 1) .. "' at line " .. line .. ", column " .. column)
        end
    end
    add("eof", "", line, column)

    return tokens
end

return tokenizer
