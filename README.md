# replent.nvim

> Lightweight, language-aware REPL integration for Neovim, built on [vim-slime](https://github.com/jpalardy/vim-slime).

## Features

- **Smart block detection** for Python and Julia – sends the whole function, class, or loop the cursor lives in, not just one line
- **Julia channel picker** via `juliaup` (uses fzf-lua when available)
- **Working-directory sync** between Neovim and the REPL
- **Buffer-local keymaps** that activate only for configured filetypes and never override your existing maps
- **Zero-config** – works out of the box; `setup()` is entirely optional

The `plugin/` entrypoint does nothing on startup beyond registering a FileType autocommand. Every module is `require`d lazily inside that callback, so the plugin has zero startup cost for unrelated filetypes.

## Requirements

| Requirement | Notes |
|-------------|-------|
| Neovim ≥ 0.10 | |
| [vim-slime](https://github.com/jpalardy/vim-slime) | Must be listed as a dependency |
| tmux | Only supported transport |
| [juliaup](https://github.com/JuliaLang/juliaup) | Optional – for Julia channel picker |
| [fzf-lua](https://github.com/ibhagwan/fzf-lua) | Optional – for Julia channel picker UI |

## Installation

### lazy.nvim (recommended)

```lua
{
  "yourname/replent.nvim",
  ft = { "python", "julia", "matlab" },   -- lazy-load on these filetypes
  dependencies = { "jpalardy/vim-slime" },
  -- opts = {}  ← entirely optional, see Configuration below
}
```

No `setup()` call is needed. Drop the spec in, open a Python or Julia file, and the keymaps are there.

### Customising

Pass an `opts` table (lazy.nvim calls `setup()` for you):

```lua
{
  "yourname/replent.nvim",
  ft = { "python", "julia", "matlab" },
  dependencies = { "jpalardy/vim-slime" },
  opts = {
    filetypes = { "python", "julia" },   -- remove matlab

    keymaps = {
      start_python = "<leader>rp",       -- remap
      debug_block  = false,              -- disable
    },

    repl_commands = {
      python = "ipython",                -- change launch command
    },
  },
}
```

Or without lazy.nvim:

```lua
require("replent").setup({
  keymaps = { send_buffer = false },
})
```

## Default Keymaps

All keymaps are **buffer-local** and only appear for configured filetypes. A mapping is silently skipped when you already have a buffer-local map on that key.

| Config key | Default | Mode | Action |
|---|---|---|---|
| `send_line` | `<CR>` | n | Send block / line at cursor |
| `send_selection` | `<CR>` | v | Send visual selection |
| `send_buffer` | `<leader>sb` | n | Send entire buffer |
| `start_python` | `<leader>op` | n | Open Python REPL |
| `start_julia` | `<leader>oj` | n | Open Julia REPL (channel picker) |
| `start_matlab` | `<leader>om` | n | Open MATLAB REPL |
| `close_python` | `<leader>qp` | n | Close Python REPL |
| `close_julia` | `<leader>qj` | n | Close Julia REPL |
| `close_matlab` | `<leader>qm` | n | Close MATLAB REPL |
| `sync_cwd` | `<leader>cd` | n | Sync Neovim cwd → REPL |
| `julia_instantiate` | `<leader>ji` | n | `Pkg.activate` + `Pkg.instantiate` |
| `debug_block` | `<leader>bc` | n | Debug block detection |

## Public API

```lua
local replent = require("replent")

replent.setup(opts)          -- optional configuration
replent.send_block()         -- send block/line at cursor
replent.send_selection()     -- send visual selection
replent.send_buffer()        -- send entire buffer
replent.start_repl("python") -- open a REPL
replent.close_repl("julia")  -- close a REPL
replent.sync_cwd()           -- sync working directory
replent.has_active_repl()    -- → boolean
```

## License

GNU General Public License v3.0 — see [LICENSE](LICENSE).
