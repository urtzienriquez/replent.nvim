local M = {}
function M.get()
  local strategy = require("replent.config").options.strategy
  if strategy == "neovim" then
    return require("replent.neovim")
  end
  return require("replent.tmux")
end
return M
