local tokenizer = require "tokenizer"
local compiler = require "compiler"

local function compile(source)
    return compiler.compile(tokenizer.tokenize(source))
end

local function assert_contains(value, expected)
    assert(value:find(expected, 1, true), "expected output to contain: " .. expected .. "\n" .. value)
end

local output = compile([[if true {
    print "yes"
} else {
    print "no"
}]])
assert_contains(output, "if true then")
assert_contains(output, "else")
assert_contains(output, "print(\"yes\")")

output = compile([[let f = fn() {
    print "side effect"
    "result"
}
let g = fn() {
    let value = 42
}]])
assert_contains(output, "print(\"side effect\")\n    return \"result\"")
assert_contains(output, "local value = 42\n    return value")

output = compile([[let x = 1
if true {
    let x = 2
    print x
}
print x]])
assert_contains(output, "    local x = 2")
assert(output:match("end\nprint%(x%)"), output)

local ok, err = pcall(function() compile("set missing = 1") end)
assert(not ok and err:find("cannot set undeclared variable", 1, true), err)

print("all tests passed")
