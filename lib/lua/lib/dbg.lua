local dbg = {}
local mri = require("lib/MemoryReferenceInfo")
dbg.dumpMemory = function()
    mri.m_cMethods.DumpMemorySnapshot("/tmp/", "memory_dump", -1)
    return "ok"
end
dbg.compareMemoryDump = function(a, b)
    mri.m_cMethods.DumpMemorySnapshotComparedFile("/tmp/", "compared", -1, a, b)
    return "ok"
end
return dbg
