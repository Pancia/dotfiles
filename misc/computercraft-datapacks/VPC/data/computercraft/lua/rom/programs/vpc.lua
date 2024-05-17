function vpc(space)
    print("switching to space "..space)
    http.post("http://localhost:31415/vpc/"..space, '').readAll()
end

function awaitRedstone(space)
    while true do
        print("awaiting any redstone input")
        os.pullEvent("redstone")
        sides = redstone.getSides()
        for _, side in ipairs(sides) do
            if redstone.getInput(side) then
                vpc(space)
            end
        end
    end
end

args = {...}
if args[1] then
    space = args[1]
else
    print("input a space number from 1 to 9")
    space = read()
end
print("running vpc on space "..space)
awaitRedstone(space)
