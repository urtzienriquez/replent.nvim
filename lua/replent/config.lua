local M = {}

---@class ReplentConfig
M.defaults = {
  strategy = "tmux",
  filetypes = { "python", "julia", "matlab", "quarto", "jnoweb" },
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
  -- Options used only by the "neovim" strategy
  neovim = {
    -- Split width in columns (0 = equal 50/50 split)
    width = 80,
    -- Split height in rows (0 = equal split; used only if width doesn't fit)
    height = 0,
    -- Position of the REPL split: "right", "left", "below", or "above"
    position = "right",
    -- Local options applied to the REPL window. The default keeps the REPL
    -- at its fixed width/height, so external window resizes hit the editor
    -- (a plain text buffer) instead of the terminal, and the REPL text is
    -- never narrow-baked into the terminal scrollback.
    -- Set buflisted -> nobuflisted here to hide the REPL from :ls.
    buffer_opts = "winfixwidth winfixheight buflisted",
    -- Map <Esc> to exit terminal-insert mode (<C-\\><C-n>)
    esc_term = true,
  },
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
