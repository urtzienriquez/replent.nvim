local M = {}

function M.setup(opts)
  require("replent.config").setup(opts)
end

-- Re-exports that resolve the backend strategy at runtime
M.send_block = function()
  require("replent.actions").send_block()
end
M.send_selection = function()
  require("replent.actions").send_selection()
end
M.send_buffer = function()
  require("replent.actions").send_buffer()
end

M.start_repl = function(ft)
  require("replent.backend").get().start_repl(ft)
end

M.close_repl = function(ft)
  require("replent.backend").get().close_repl(ft)
end

M.sync_cwd = function()
  require("replent.backend").get().sync_cwd()
end

return M
