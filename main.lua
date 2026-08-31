local tokenizer = require "tokenizer"
local compiler = require "compiler"

local function printUsage()
   print("Usage: chc [file]")
end

local args = { ... }

if args[1] == nil then
   print("no file provided")
   printUsage()
   return 1
end

if type(args[1]) ~= "string" then
   print("wrong argument type provided")
   printUsage()
   return 1
end

local file, file_err = io.open(args[1], "r")

if not file then
   print("could not read file:", file_err)
   return 1
end

local code = file:read("*a")
file:close()
local tokens = tokenizer.tokenize(code)
local output = compiler.compile(tokens)

print(output)
