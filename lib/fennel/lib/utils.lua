local obj = {dbg = {}}
local mri = require("lib/MemoryReferenceInfo")
obj.dbg.dumpMemory = function()
    mri.m_cMethods.DumpMemorySnapshot("/tmp/", "memory_dump", -1)
    return "ok"
end
obj.dbg.compareMemoryDump = function(a, b)
    mri.m_cMethods.DumpMemorySnapshotComparedFile("/tmp/", "compared", -1, a, b)
    return "ok"
end
return obj
