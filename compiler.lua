local compiler = {}

local function types(text)
    local result = {}
    for name in text:gmatch("[^\\]+") do result[name] = true end
    return result
end
local function typename(set)
    if not set then return "unknown" end
    local result = {}
    for name in pairs(set) do result[#result + 1] = name end
    table.sort(result)
    return table.concat(result, "\\")
end
local function compatible(expected, actual)
    if not expected or not actual then return true end
    for name in pairs(actual) do if expected[name] then return true end end
    return false
end

local function Compiler(tokens)
    local self = { tokens = tokens, pos = 1, out = {}, indent = 0, scopes = {{}}, structs = {}, struct_defs = {}, struct_order = {} }
    function self:peek(n) return self.tokens[self.pos + (n or 0)] end
    function self:is(value) local t = self:peek(); return t and t.value == value end
    function self:skip_newlines() while self:peek() and self:peek().type == "newline" do self.pos = self.pos + 1 end end
    function self:take(value)
        local t = self:peek()
        if not t then error("unexpected end of input") end
        if value and t.value ~= value then error("expected '" .. value .. "' at line " .. t.line) end
        self.pos = self.pos + 1
        return t
    end
    function self:emit(value) self.out[#self.out + 1] = string.rep("    ", self.indent) .. value end
    function self:declare(name, mutable, token, type_info) self.scopes[#self.scopes][name] = { mutable = mutable, token = token, type_info = type_info } end
    function self:compile_function(consumed)
        if not consumed then self:take("fn") end
        self:take("("); local args = {}
        while not self:is(")") do args[#args + 1] = self:take().value; if self:is(",") then self:take() end end
        self:take(")"); self:take("{")
        local output, old = self.out, self.indent
        self.out, self.indent = {}, old + 1; self.scopes[#self.scopes + 1] = {}
        for _, name in ipairs(args) do self:declare(name, true, { line = self:peek().line }) end
        self:block(true); self.scopes[#self.scopes] = nil
        local body = self.out; self.out, self.indent = output, old
        return "function(" .. table.concat(args, ", ") .. ")\n" .. table.concat(body, "\n") .. "\n" .. string.rep("    ", old) .. "end"
    end
    function self:lookup(name)
        for i = #self.scopes, 1, -1 do if self.scopes[i][name] then return self.scopes[i][name] end end
    end
    local precedence = { ["="] = 1, ["<"] = 2, [">"] = 2, ["<="] = 2, [">="] = 2, ["=="] = 2, ["~="] = 2, [".."] = 3, ["+"] = 4, ["-"] = 4, ["*"] = 5, ["/"] = 5 }
    local function starts(t)
        return t and (t.type == "number" or t.type == "string" or t.type == "identifier" or t.type == "rawlua" or t.value == "(" or t.value == "[" or t.value == "fn" or t.value == "true" or t.value == "false" or t.value == "nil")
    end
    function self:parse_type()
        local result = {}
        repeat
            local t = self:take()
            if t.type ~= "identifier" and t.type ~= "keyword" then error("expected type at line " .. t.line) end
            result[t.value] = true
            if self:is("\\") then self:take() else break end
        until false
        if self:is("?") then self:take(); result["nil"] = true end
        return result
    end
    function self:expression(min)
        local left, left_info, forced = self:primary()
        local left_type = left_info and left_info.types
        while true do
            local op = self:peek(); local p = op and precedence[op.value]
            if not p or p < min then break end
            self:take(); local right, right_info = self:expression(p + 1); local right_type = right_info and right_info.types
            if (op.value == "+" or op.value == "-" or op.value == "*" or op.value == "/") and left_type and right_type and (not left_type.number or not right_type.number) then error("operator '" .. op.value .. "' requires number operands at line " .. op.line) end
            left = "(" .. left .. " " .. op.value .. " " .. right .. ")"
            left_type = (op.value == "<" or op.value == ">" or op.value == "<=" or op.value == ">=" or op.value == "==" or op.value == "~=") and types("boolean") or left_type
            left_info = left_type and { types = left_type } or nil
        end
        if self:is("::") then
            self:take(); left_info = { types = self:parse_type() }; forced = true
        end
        return left, left_info, forced
    end
    function self:primary()
        local t = self:take(); local value, info
        if t.type == "number" then value, info = t.value, { types = types("number") }
        elseif t.type == "string" then value, info = t.value, { types = types("string") }
        elseif t.type == "rawlua" then value = t.value
        elseif t.value == "true" or t.value == "false" then value, info = t.value, { types = types("boolean") }
        elseif t.value == "nil" then value, info = t.value, { types = types("nil") }
        elseif t.type == "identifier" then
            value = t.value; local binding = self:lookup(value); info = binding and binding.type_info
            if not info and self.structs[value] then info = { types = types(value), fields = self.structs[value].fields } end
        elseif t.value == "(" then value, info = self:expression(1); self:take(")"); value = "(" .. value .. ")"
        elseif t.value == "[" then
            local items = {}; self:skip_newlines()
            while not self:is("]") do local item = self:expression(1); items[#items + 1] = item; if self:is(",") then self:take() else break end; self:skip_newlines() end
            self:take("]"); value = "{" .. table.concat(items, ", ") .. "}"; info = { types = types("array") }
        elseif t.value == "{" then
            local fields = {}; local entries = {}; self:skip_newlines()
            while not self:is("}") do
                local key, item, rendered_key
                if self:is(":") then self:take(); local name = self:take().value; key, item, rendered_key = name, name, name
                elseif self:peek().type == "identifier" and self:peek(1).value == "=" then key = self:take().value; self:take("="); item = self:expression(1); rendered_key = key
                elseif self:is("[") then self:take(); key = self:expression(1); self:take("]"); self:take("="); item = self:expression(1); rendered_key = "[" .. key .. "]"
                elseif self:peek().type == "identifier" then key = self:take().value; item = "nil"; rendered_key = key
                else error("expected table field at line " .. self:peek().line) end
                if type(key) == "string" then
                    entries[#entries + 1] = (rendered_key:sub(1, 1) == "[" and rendered_key or "[\"" .. key .. "\"]") .. " = " .. item
                    fields[key] = true
                else entries[#entries + 1] = rendered_key .. " = " .. item end
                if self:is(",") then self:take() end
                self:skip_newlines()
            end
            self:take("}"); value = "{" .. table.concat(entries, ", ") .. "}"; info = { types = types("table"), fields = fields }
        elseif t.value == "fn" then
            self.pos = self.pos - 1
            value = self:compile_function()
        else error("unexpected token '" .. t.value .. "' at line " .. t.line) end
        while true do
            if self:is("(") then
                self:take(); local args = {}
                while not self:is(")") do local arg = self:expression(1); args[#args + 1] = arg; if self:is(",") then self:take() else break end end
                self:take(")"); value = value .. "(" .. table.concat(args, ", ") .. ")"
                if info and info.fields then info = { types = info.types, fields = info.fields } else info = nil end
            elseif self:is(".") or self:is(":") then
                local separator = self:take().value; local field = self:take(); if info and info.fields and not info.fields[field.value] then error("no field " .. field.value .. " in struct at line " .. field.line) end
                if separator == ":" then value = value .. ":" .. field.value else value = value .. "." .. field.value end; info = nil
            elseif self:is("[") then self:take(); local index = self:expression(1); self:take("]"); value = value .. "[" .. index .. "]"; info = nil
            elseif (t.type == "identifier" or t.value == "fn") and starts(self:peek()) then
                local first_arg = self:expression(1)
                local args = { first_arg }
                while self:is(",") do self:take(); local arg = self:expression(1); args[#args + 1] = arg end
                value = value .. "(" .. table.concat(args, ", ") .. ")"; info = nil
            else break end
        end
        return value, info, false
    end
    function self:block(in_function)
        local kind, name; self:skip_newlines()
        while not self:is("}") and self:peek().type ~= "eof" do kind, name = self:statement(in_function); self:skip_newlines() end
        self:take("}")
        if in_function then if kind == "expression" then self.out[#self.out] = self.out[#self.out]:gsub("^(%s*)", "%1return ") elseif kind == "declaration" then self:emit("return " .. name) end end
    end
    function self:scoped_block() self.scopes[#self.scopes + 1] = {}; self.indent = self.indent + 1; self:block(false); self.indent = self.indent - 1; self.scopes[#self.scopes] = nil end
    function self:statement(in_function)
        local t = self:peek()
        if t.value == "impl" or t.value == "meta" then
            local kind = self:take().value; local name = self:take().value; self:take("{"); local entries = {}
            while not self:is("}") do
                self:skip_newlines()
                if self:is("}") then break end
                local method = self:take().value; self:take("="); entries[#entries + 1] = "[\"" .. method .. "\"] = " .. self:compile_function()
                if self:is(",") then self:take() end; self:skip_newlines()
            end
            self:take("}")
            local suffix = kind == "impl" and "_impl" or "_mt"
            self.struct_defs[name] = self.struct_defs[name] or {}
            if not self.struct_defs[name].seen then self.struct_defs[name].seen = true; self.struct_order[#self.struct_order + 1] = name end
            self.struct_defs[name][kind] = { entries = entries }
            if kind == "impl" and self.structs[name] then self.structs[name].impl = true end
            return "control"
        elseif t.value == "struct" then
            self:take(); local name = self:take(); self:take("{"); local fields = {}; local field_order = {}
            while not self:is("}") do
                self:skip_newlines()
                local field = self:take(); fields[field.value] = true; field_order[#field_order + 1] = field.value
                if self:is(":") then
                    self:take(); local field_type = self:parse_type()
                    for i = #field_order, 1, -1 do if fields[field_order[i]] == true then fields[field_order[i]] = field_type else break end end
                end
                if self:is(",") then self:take() end; self:skip_newlines()
                if self:is("}") then break end
                if self:peek().type ~= "identifier" then error("expected struct field at line " .. self:peek().line) end
            end
            self:take("}"); self.structs[name.value] = { fields = fields, order = field_order }; self.struct_defs[name.value] = self.struct_defs[name.value] or {}; if not self.struct_defs[name.value].seen then self.struct_defs[name.value].seen = true; self.struct_order[#self.struct_order + 1] = name.value end; self.struct_defs[name.value].struct = { order = field_order }; return "control"
        elseif t.value == "let" or t.value == "var" then
            local mutable = self:take().value == "var"; local names, declared = {}, {}
            while not self:is("=") do
                local n = self:take(); names[#names + 1] = n.value
                if self:is(":") then
                    self:take(); local type_info = self:parse_type()
                    for i = 1, #names do if not declared[i] then declared[i] = type_info end end
                end
            end
            self:take("="); local values, inferred = {}, {}; for i = 1, #names do local value, info = self:expression(1); values[i], inferred[i] = value, info and info.types; if self:is(",") then self:take() end end
            for i, name in ipairs(names) do if declared[i] and not compatible(declared[i], inferred[i]) then error("value for '" .. name .. "' is not compatible with type " .. typename(declared[i]) .. " at line " .. t.line) end; self:declare(name, mutable, t, { types = declared[i], fields = declared[i] and self.structs[typename(declared[i])] and self.structs[typename(declared[i])].fields }); self:emit("local " .. name .. " = " .. values[i]) end
            return "declaration", names[#names]
        elseif t.value == "set" then
            self:take(); local name = self:take(); local binding = self:lookup(name.value)
            if not binding then error("cannot set undeclared variable '" .. name.value .. "' at line " .. name.line) end
            if not self:is(".") and not self:is("[") and not binding.mutable then error("cannot set immutable variable '" .. name.value .. "' at line " .. name.line) end
            local target = name.value
            while self:is(".") or self:is("[") do
                if self:is(".") then self:take(); target = target .. "." .. self:take().value else self:take(); local index = self:expression(1); self:take("]"); target = target .. "[" .. index .. "]" end
            end
            self:take("="); local value, info, forced = self:expression(1); local value_type = info and info.types
            if binding.type_info and binding.type_info.types and not forced and not compatible(binding.type_info.types, value_type) then error("cannot assign " .. typename(value_type) .. " to " .. typename(binding.type_info.types) .. " variable '" .. name.value .. "'") end
            if forced then binding.type_info.types = value_type end
            self:emit(target .. " = " .. value); return "assignment"
        elseif t.value == "if" then self:take(); local condition = self:expression(1); self:take("{"); self:emit("if " .. condition .. " then"); self:scoped_block(); if self:is("else") then self:take(); self:take("{"); self:emit("else"); self:scoped_block() end; self:emit("end"); return "control"
        elseif t.value == "for" then
            self:take(); local first = self:take().value; local second
            if self:is(",") then self:take(); second = self:take().value end
            if self:is("in") then
                self:take(); local iterator = self:expression(1); self:take("{"); self:emit("for " .. first .. (second and ", " .. second or "") .. " in " .. iterator .. " do")
            else
                self:take("="); local start = self:expression(1); self:take(","); local finish = self:expression(1); self:take("{"); self:emit("for " .. first .. " = " .. start .. ", " .. finish .. " do")
            end
            self:scoped_block(); self:emit("end"); return "control"
        elseif t.value == "while" then self:take(); local condition = self:expression(1); self:take("{"); self:emit("while " .. condition .. " do"); self:scoped_block(); self:emit("end"); return "control"
        elseif t.value == "{" then self:take(); self:emit("do"); self:scoped_block(); self:emit("end"); return "control"
        elseif t.type == "identifier" and (self:peek(1).value == "." or self:peek(1).value == "[") then
            local look = 1
            while self:peek(look) and (self:peek(look).value == "." or self:peek(look).value == "[") do
                if self:peek(look).value == "." then look = look + 2 else
                    look = look + 1
                    while self:peek(look) and self:peek(look).value ~= "]" do look = look + 1 end
                    look = look + 1
                end
            end
            if self:peek(look).value ~= "=" then self:emit(self:expression(1)); return "expression" end
            local target = self:take().value
            while self:is(".") or self:is("[") do
                if self:is(".") then self:take(); target = target .. "." .. self:take().value else self:take(); local index = self:expression(1); self:take("]"); target = target .. "[" .. index .. "]" end
            end
            if self:is("=") then self:take(); self:emit(target .. " = " .. self:expression(1)); return "assignment" end
            error("expected '=' after assignment target at line " .. t.line)
        else self:emit(self:expression(1)); return "expression" end
    end
    function self:compile()
        self:skip_newlines()
        while self:peek().type ~= "eof" do self:statement(false); self:skip_newlines() end
        local definitions = {}
        for _, name in ipairs(self.struct_order) do
            local def = self.struct_defs[name]
            if def.meta or def.impl then
                local locals = {}
                if def.meta then locals[#locals + 1] = name .. "_mt" end
                if def.impl then locals[#locals + 1] = name .. "_impl" end
                definitions[#definitions + 1] = "local " .. table.concat(locals, ", ")
            end
        end
        for _, name in ipairs(self.struct_order) do
            local def = self.struct_defs[name]
            if def.struct then
                local body = {}
                for _, field in ipairs(def.struct.order) do body[#body + 1] = "[\"" .. field .. "\"] = " .. field end
                definitions[#definitions + 1] = "local function " .. name .. "(" .. table.concat(def.struct.order, ", ") .. ") return setmetatable({" .. table.concat(body, ", ") .. "}, " .. name .. "_mt) end"
            end
        end
        for _, name in ipairs(self.struct_order) do
            local def = self.struct_defs[name]
            if def.meta then definitions[#definitions + 1] = name .. "_mt = {" .. table.concat(def.meta.entries, ", ") .. "}" end
            if def.impl then definitions[#definitions + 1] = name .. "_impl = {" .. table.concat(def.impl.entries, ", ") .. "}" end
            if def.meta and def.impl then definitions[#definitions + 1] = name .. "_mt.__index = " .. name .. "_impl" end
        end
        local output = {}
        for _, line in ipairs(definitions) do output[#output + 1] = line end
        for _, line in ipairs(self.out) do output[#output + 1] = line end
        return table.concat(output, "\n") .. "\n"
    end
    return self
end
function compiler.compile(tokens) return Compiler(tokens):compile() end
return compiler
