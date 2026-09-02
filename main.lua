local tokenizer = require("tokenizer")
local compiler = require("compiler")

local function eprint(...)
    local args = {...}
    for i = 1, #args do
        args[i] = tostring(args[i])
    end
    io.stderr:write(table.concat(args, "\t") .. "\n")
end

local function printUsage()
   eprint("Usage: hrc [file]")
end

local args = { ... }

if args[1] == nil then
   eprint("no file provided")
   printUsage()
   return 1
end

if type(args[1]) ~= "string" then
   eprint("wrong argument type provided")
   printUsage()
   return 1
end

local file, file_err = io.open(args[1], "r")

if not file then
   eprint("could not read file:", file_err)
   return 1
end

local code = file:read("*a")
file:close()
local tokens = tokenizer.tokenize(code)
local output = compiler.compile(tokens)

print(output)
