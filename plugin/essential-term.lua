-- Auto-sourced by Neovim when the plugin is on the runtimepath.
-- Registers user commands and autocmds.

if vim.g.loaded_essential_term then
  return
end
vim.g.loaded_essential_term = true

local function cmd(name, fn, opts)
  vim.api.nvim_create_user_command(name, fn, opts or {})
end

cmd("EssentialTermToggle", function() require("essential-term").toggle() end, { desc = "Toggle terminal panel" })
cmd("EssentialTermNew",    function() require("essential-term").new() end,    { desc = "Create new terminal session" })
cmd("EssentialTermClose",  function() require("essential-term").close() end,  { desc = "Close active terminal session" })
cmd("EssentialTermNext",   function() require("essential-term").next() end,   { desc = "Go to next terminal session" })
cmd("EssentialTermPrev",   function() require("essential-term").prev() end,   { desc = "Go to previous terminal session" })
cmd("EssentialTermRename", function(args)
  require("essential-term").rename(args.args ~= "" and args.args or nil)
end, { nargs = "?", desc = "Rename active terminal session" })

-- Keep active_id in sync when entering a terminal buffer
vim.api.nvim_create_autocmd("BufEnter", {
  group = vim.api.nvim_create_augroup("EssentialTermBufEnter", { clear = true }),
  callback = function()
    local bufnr = vim.api.nvim_get_current_buf()
    local state = require("essential-term.state")
    local term = state.get_by_bufnr(bufnr)
    if term then
      state.active_id = term.id
      -- Update winnr in case the window was changed externally
      term.winnr = vim.api.nvim_get_current_win()
      require("essential-term.ui").refresh()
    end
  end,
})

-- Handle shell exit (when close_on_exit = false, clean up closed buffers manually)
vim.api.nvim_create_autocmd("TermClose", {
  group = vim.api.nvim_create_augroup("EssentialTermClose", { clear = true }),
  callback = function()
    local bufnr = vim.api.nvim_get_current_buf()
    local state = require("essential-term.state")
    local term = state.get_by_bufnr(bufnr)
    if term then
      -- The terminal module's on_exit already handles close_on_exit=true.
      -- If the window closed but the term is still in state (close_on_exit=false),
      -- mark the window as nil so state stays consistent.
      if term.winnr and not vim.api.nvim_win_is_valid(term.winnr) then
        term.winnr = nil
      end
    end
  end,
})
