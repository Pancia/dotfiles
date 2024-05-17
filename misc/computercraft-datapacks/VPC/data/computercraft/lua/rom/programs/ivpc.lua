function vpc(space)
    print("switching to space "..space)
    http.post("http://localhost:31415/vpc/"..space, '').readAll()
end

function awaitInput(space)
    while true do
        print("press enter to switch space")
        read()
        vpc(space)
    end
end

args = {...}
if args[1] then
    space = args[1]
else
    print("input a space number from 1 to 9")
    space = read()
end
print("running ivpc on space "..space)
awaitInput(space)
