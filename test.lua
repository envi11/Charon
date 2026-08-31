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

output = compile([[var x: number = 5
set x = 6
set x = "forced" :: string
]])
assert_contains(output, "local x = 5")
assert_contains(output, 'x = "forced"')

output = compile([[var y: string? = "hi"
set y = nil
var foo: number\string = 52
set foo = "hi"
]])
assert_contains(output, "local y = \"hi\"")
assert_contains(output, "foo = \"hi\"")

local ok, err = pcall(function() compile("var x: number = 5\nset x = \"6\"") end)
assert(not ok and err and err:find("cannot assign string to number variable", 1, true), err)

ok, err = pcall(function() compile("var y: string? = \"hi\"\nset y = 5") end)
assert(not ok and err and err:find("cannot assign number to nil\\string variable", 1, true), err)

ok, err = pcall(function() compile("set missing = 1") end)
assert(not ok and err and err:find("cannot set undeclared variable", 1, true), err)

output = compile([[struct Point { x y: number, }
let p: Point = Point(1, 2)
let arr = [1, 6, 3]
print p.x
print arr[2]
let t = { h = 2, :p }
for i, v in pairs(t) { print i, v }
]])
assert_contains(output, "function Point(x, y)")
assert_contains(output, "print(p.x)")
assert_contains(output, "print(arr[2])")
assert_contains(output, "for i, v in pairs(t) do")

ok, err = pcall(function() compile([[struct Point { x: number }
let p: Point = Point(1)
print p.z]]) end)
assert(not ok and err and err:find("no field z in struct", 1, true), err)

output = compile([[export a b
set a b = 55 21
print a, b
]])
assert_contains(output, "a, b = 55, 21")
assert_contains(output, "print(a, b)")

print("all tests passed")

