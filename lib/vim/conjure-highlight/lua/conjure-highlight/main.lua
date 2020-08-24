local a = require("conjure.aniseed.core")
local client = require("conjure.client")
local eval = require("conjure.eval")
local nrepl_state = require("conjure.client.clojure.nrepl.state")

local function is_connected()
    return a.get(nrepl_state.get("conn"), "session")
end

local function connect(cb)
    local connected = is_connected()
    if connected then cb() else
        local timer = vim.loop.new_timer()
        timer:start(250, 250, vim.schedule_wrap(function()
            local connected = is_connected()
            if connected then
                timer:close()
                cb()
            end
        end))
    end
end

local function eval_str(code, cb)
    client["with-filetype"]("clojure", eval["eval-str"], {
        origin = "conjure-highlight",
        code = "(do {:conjure-highlight/silent true} "..code..")",
        ["passive?"] = true,
        ["on-result"] = cb
    })
end

local function read_all(file)
    local f = assert(io.open(file, "rb"))
    local content = f:read("*all")
    f:close()
    return content
end

local function execute_syntax_command()
    eval_str("(ns-name *ns*)", function(ns)
        eval_str("(conjure-highlight/syntax-command (quote "..ns.."))", function(r)
            vim.api.nvim_command("ExecuteSyntaxCommand "..r)
        end)
    end)
end

local function main()
    connect(function()
        eval_str("(find-ns 'conjure-highlight)", function (r)
            if r == 'nil' then
                local clj_file = vim.api.nvim_call_function("conjure_highlight#clojure_highlight_filepath", {})
                local clj_code = read_all(clj_file)
                eval_str('(do '..clj_code..')', function(r)
                    execute_syntax_command()
                end)
            else
                execute_syntax_command()
            end
        end)
    end)
end

return {
    main = main
}
