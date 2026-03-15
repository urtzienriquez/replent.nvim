local M = {}

---@class ReplentConfig
M.defaults = {
  strategy = "tmux",
  filetypes = { "python", "julia", "matlab", "quarto" },
  keymaps = {
    send_line = "<CR>",
    send_selection = "<CR>",
    send_buffer = "<leader>sb",
    start_python = "<leader>op",
    start_julia = "<leader>oj",
    start_matlab = "<leader>om",
    close_python = "<leader>qp",
    close_julia = "<leader>qj",
    close_matlab = "<leader>qm",
    sync_cwd = "<leader>cd",
    julia_instantiate = "<leader>ji",
    debug_block = "<leader>bc",
  },
  repl_commands = {
    python = "ipython --no-confirm-exit --no-banner --quiet",
    julia = "julia",
    matlab = "matlab -nodesktop -nosplash",
  },
  auto_cd = false,
}

M.options = vim.deepcopy(M.defaults)

function M.setup(user_opts)
  M.options = vim.tbl_deep_extend("force", M.options, user_opts or {})

  if M.options.strategy == "neovim" then
    vim.g.slime_target = "neovim"
    vim.g.slime_bracketed_paste = 0
  else
    vim.g.slime_target = "tmux"
    vim.g.slime_bracketed_paste = 1
  end
end

return M
