print "hi"

for i = 1, 10 {
    print i
}

let x = 6.9 -- let variables are constant
var y z = 420 7 -- difining multiple variables; var variables are mutable
set y = 21 -- explisitly use set to change values

print x, y, z; print(x, y, z) -- the two ways to call functions
-- print x y -- compiles to: print(x(y))

let f = fn(a b) { -- defining a function
    a + b -- implicit returns
}
let ab = f y, z -- ab == 28

--[[
    multiline comment
]]

-- ; is treated like newline unless it is in a comment
set y = 0;;;;;;;; -- doesnt cause an error
-- set x = 6 -- causes error because defined with let