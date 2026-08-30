local compiler = {}

local function Compiler(tokens)
    local self = { tokens = tokens, pos = 1, out = {}, indent = 0, scopes = {{}} }
    function self:peek(offset) return self.tokens[self.pos + (offset or 0)] end
    function self:is(value) local t = self:peek(); return t and t.value == value end
    function self:skip_newlines() while self:peek().type == "newline" do self.pos = self.pos + 1 end end
    function self:take(value)
        local t = self:peek()
        if value and t.value ~= value then error("expected '" .. value .. "' at line " .. t.line) end
        self.pos = self.pos + 1; return t
    end
    function self:emit(text) self.out[#self.out + 1] = string.rep("    ", self.indent) .. text end
    function self:declare(name, mutable, token)
        self.scopes[#self.scopes][name] = { mutable = mutable, token = token }
    end
    function self:lookup(name)
        for i = #self.scopes, 1, -1 do
            local binding = self.scopes[i][name]
            if binding then return binding end
        end
    end
    local precedence = { ["="] = 1, ["<"] = 2, [">"] = 2, ["<="] = 2, [">="] = 2, ["=="] = 2, ["~="] = 2, ["+"] = 3, ["-"] = 3, ["*"] = 4, ["/"] = 4 }
    local function starts_expression(t)
        return t and (t.type == "number" or t.type == "string" or t.type == "identifier" or t.value == "(" or t.value == "fn" or t.value == "true" or t.value == "false" or t.value == "nil")
    end
    function self:expression(min_prec)
        local left = self:primary()
        while true do
            local op = self:peek(); local p = op and precedence[op.value]
            if not p or p < min_prec then break end
            self:take(); local right = self:expression(p + 1); left = "(" .. left .. " " .. op.value .. " " .. right .. ")"
        end
        return left
    end
    function self:primary()
        local t = self:take(); local value
        if t.type == "number" or t.type == "string" then value = t.value
        elseif t.type == "rawlua" then value = t.value
        elseif t.value == "true" or t.value == "false" or t.value == "nil" then value = t.value
        elseif t.type == "identifier" then value = t.value
        elseif t.value == "(" then value = self:expression(1); self:take(")"); value = "(" .. value .. ")"
        elseif t.value == "fn" then
            self:take("("); local args = {}
            while not self:is(")") do args[#args + 1] = self:take().value end
            self:take(")"); self:take("{")
            local output = self.out; self.out = {}; self.indent = self.indent + 1
            self.scopes[#self.scopes + 1] = {}
            for _, name in ipairs(args) do self:declare(name, true, t) end
            self:block(true); self.indent = self.indent - 1
            self.scopes[#self.scopes] = nil
            local body = self.out; self.out = output
            value = "function(" .. table.concat(args, ", ") .. ")\n" .. table.concat(body, "\n") .. "\n" .. string.rep("    ", self.indent) .. "end"
        else error("unexpected token '" .. t.value .. "' at line " .. t.line) end
        -- Charon permits both f(x) and f x, with comma-separated implicit arguments.
        if self:is("(") then
            self:take(); local args = {}
            while not self:is(")") do args[#args + 1] = self:expression(1); if self:is(",") then self:take() else break end end
            self:take(")"); value = value .. "(" .. table.concat(args, ", ") .. ")"
        elseif (t.type == "identifier" or t.value == "fn") and starts_expression(self:peek()) then
            local args = { self:expression(1) }
            while self:is(",") do self:take(); args[#args + 1] = self:expression(1) end
            value = value .. "(" .. table.concat(args, ", ") .. ")"
        end
        return value
    end
    function self:block(in_function)
        local lines = {}; self:skip_newlines()
        while not self:is("}") and self:peek().type ~= "eof" do
            local before = #self.out; self:statement(in_function)
            for i = before + 1, #self.out do lines[#lines + 1] = self.out[i] end
            self:skip_newlines()
        end
        self:take("}"); return lines
    end
    function self:statement(in_function)
        local t = self:peek()
        if t.value == "let" or t.value == "var" then
            local mutable = self:take().value == "var"; local names = {}
            while not self:is("=") do names[#names + 1] = self:take().value end; self:take("=")
            local values = {}
            for i = 1, #names do
                values[i] = self:expression(1)
                if self:is(",") then self:take() end
            end
            for i, name in ipairs(names) do
                local name_token = { line = t.line }
                self:declare(name, mutable, name_token)
                self:emit("local " .. name .. " = " .. (values[i] or "nil"))
            end
        elseif t.value == "set" then
            self:take(); local name_token = self:take(); local name = name_token.value
            local binding = self:lookup(name)
            if not binding then error("cannot set undeclared variable '" .. name .. "' at line " .. name_token.line) end
            if not binding.mutable then
                error("cannot set immutable variable '" .. name .. "'\ndeclared with let at line " .. binding.token.line .. " (set at line " .. name_token.line .. ")")
            end
            self:take("="); self:emit(name .. " = " .. self:expression(1))
        elseif t.value == "for" then self:take(); local name_token = self:take(); local name = name_token.value; self:declare(name, true, name_token); self:take("="); local first = self:expression(1); self:take(","); local last = self:expression(1); self:take("{"); self:emit("for " .. name .. " = " .. first .. ", " .. last .. " do"); self.indent = self.indent + 1; self:block(false); self.indent = self.indent - 1; self:emit("end")
        elseif t.value == "while" then self:take(); local condition = self:expression(1); self:take("{"); self:emit("while " .. condition .. " do"); self.indent = self.indent + 1; self:block(false); self.indent = self.indent - 1; self:emit("end")
        elseif t.value == "{" then self:take(); self:emit("do"); self.indent = self.indent + 1; self:block(false); self.indent = self.indent - 1; self:emit("end")
        else local expression = self:expression(1); if in_function then self:emit("return " .. expression) else self:emit(expression) end end
    end
    function self:compile()
        self:skip_newlines(); while self:peek().type ~= "eof" do self:statement(false); self:skip_newlines() end; return table.concat(self.out, "\n") .. "\n" end
    return self
end

function compiler.compile(tokens) return Compiler(tokens):compile() end
return compiler
