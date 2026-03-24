local M = {}

local state = require("essential-term.state")
local config = require("essential-term.config")
local ui = require("essential-term.ui")

local function apply_colors()
  local c = config.options.colors
  if c.bg or c.fg then
    vim.api.nvim_set_hl(0, "EssentialTermNormal", { bg = c.bg, fg = c.fg })
  end
end

-- Open a window according to display_mode and return the window number
local function open_window()
  local mode = config.options.display_mode or "horizontal"
  local pct  = (config.options.size or 70) / 100

  local win
  if mode == "float" then
    local cols   = vim.o.columns
    local lines  = vim.o.lines
    local width  = math.floor(cols  * pct)
    local height = math.floor(lines * pct)
    local row    = math.floor((lines - height) / 2)
    local col    = math.floor((cols  - width)  / 2)
    local tmp = vim.api.nvim_create_buf(false, true)
    local win_cfg = {
      relative = "editor",
      width = width, height = height,
      row = row, col = col,
      style = "minimal",
      border = config.options.border or "rounded",
      zindex = 50,
    }
    if vim.fn.has("nvim-0.9") == 1 then
      win_cfg.title     = " essential-term "
      win_cfg.title_pos = "center"
    end
    win = vim.api.nvim_open_win(tmp, true, win_cfg)
  elseif mode == "vertical" then
    local width = math.floor(vim.o.columns * pct)
    vim.cmd("botright vsplit")
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_width(win, width)
  else  -- "horizontal" (default)
    local height = math.floor(vim.o.lines * pct)
    vim.cmd("botright " .. height .. " split")
    win = vim.api.nvim_get_current_win()
  end

  local c = config.options.colors
  if c.bg or c.fg then
    vim.wo[win].winhighlight = "Normal:EssentialTermNormal,NormalFloat:EssentialTermNormal,NormalNC:EssentialTermNormal"
  end
  vim.wo[win].cursorline = false

  apply_colors()

  return win
end

---Create a new terminal session: allocate a buffer, open a window (reusing the
---active terminal's window when one is visible), start the shell process, and
---register the session in state.
---@param name? string Display name shown in the sidebar/tabline. Defaults to `"term <n>"`.
---@return {id:integer, bufnr:integer, job_id:integer, name:string, winnr:integer}
function M.create(name)
  local bufnr = vim.api.nvim_create_buf(false, false)

  -- Reuse the active terminal's window if one is visible, to avoid stacking splits
  local winnr = nil
  local prev_active = state.get_active()
  if prev_active and prev_active.winnr and vim.api.nvim_win_is_valid(prev_active.winnr) then
    winnr = prev_active.winnr
    prev_active.winnr = nil
    vim.api.nvim_set_current_win(winnr)
  else
    winnr = open_window()
  end
  vim.api.nvim_win_set_buf(winnr, bufnr)

  local term = state.add({
    bufnr = bufnr,
    job_id = nil,
    name = name or ("term " .. state._next_id - 1),
    winnr = winnr,
  })

  local job_id = vim.fn.termopen(config.options.shell, {
    on_exit = function(_, _, _)
      if config.options.close_on_exit then
        -- Schedule so we're not inside the job callback
        vim.schedule(function()
          M.destroy(term.id)
        end)
      end
    end,
  })

  term.job_id = job_id
  state.active_id = term.id

  local esc = config.options.escape_key
  if esc and esc ~= "" then
    vim.keymap.set("t", esc, function()
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-\\><C-n>", true, false, true), "n", false)
      vim.schedule(function()
        M.hide(term.id)
        ui.hide_sidebar()
        ui.hide_tabline()
      end)
    end, { buffer = bufnr, silent = true, desc = "Exit terminal mode and hide" })
  end

  if config.options.start_in_insert then
    vim.cmd("startinsert")
  end

  return term
end

---Show the terminal session identified by `id`.
---If its window is already visible, focus it. Otherwise open a new window
---according to `display_mode` and switch it to the session's buffer.
---@param id integer
function M.show(id)
  local term = state.get(id)
  if not term then
    return
  end

  if term.winnr and vim.api.nvim_win_is_valid(term.winnr) then
    -- Already visible — just focus it
    vim.api.nvim_set_current_win(term.winnr)
    state.active_id = id
    return
  end

  local winnr = open_window()
  vim.api.nvim_win_set_buf(winnr, term.bufnr)
  term.winnr = winnr
  state.active_id = id

  if config.options.start_in_insert then
    vim.cmd("startinsert")
  end
end

---Close the window for terminal `id` without stopping the shell process.
---The session remains in state and can be re-shown with `M.show`.
---@param id integer
function M.hide(id)
  local term = state.get(id)
  if not term then
    return
  end

  if term.winnr and vim.api.nvim_win_is_valid(term.winnr) then
    vim.api.nvim_win_close(term.winnr, false)
  end
  term.winnr = nil
end

---Replace the buffer shown in the active terminal window with the session
---identified by `id`, without opening a new split.
---Falls back to `M.show` when no terminal window is currently visible.
---@param id integer
function M.swap_to(id)
  local term = state.get(id)
  if not term then
    return
  end

  -- Find the currently visible terminal window to reuse it
  local active = state.get_active()
  local winnr = nil
  if active and active.winnr and vim.api.nvim_win_is_valid(active.winnr) then
    winnr = active.winnr
    active.winnr = nil
  end

  if not winnr then
    -- No visible terminal window; just show normally
    M.show(id)
    return
  end

  vim.api.nvim_win_set_buf(winnr, term.bufnr)
  term.winnr = winnr
  state.active_id = id

  if config.options.start_in_insert then
    vim.api.nvim_set_current_win(winnr)
    vim.cmd("startinsert")
  end
end

---Destroy the terminal session identified by `id`: close its window, stop the
---shell process, wipe the buffer, and remove it from state. Automatically
---refreshes the sidebar/tabline for any remaining sessions.
---@param id integer
function M.destroy(id)
  local term = state.get(id)
  if not term then
    return
  end

  -- Close the window first
  if term.winnr and vim.api.nvim_win_is_valid(term.winnr) then
    vim.api.nvim_win_close(term.winnr, false)
  end

  -- Kill the shell process
  if term.job_id then
    pcall(vim.fn.jobstop, term.job_id)
  end

  -- Wipe the buffer
  if vim.api.nvim_buf_is_valid(term.bufnr) then
    vim.api.nvim_buf_delete(term.bufnr, { force = true })
  end

  state.remove(id)

  -- Always tear down the sidebar/tabline first; the auto-close path below
  -- is responsible for re-creating it when appropriate.
  ui.hide_sidebar()
  ui.hide_tabline()

  -- Auto-close path (on_exit): if a terminal window is still visible,
  -- re-show the appropriate UI without requiring user interaction.
  if config.options.display_mode == "float" or config.options.display_mode == "vertical" then
    for _, t in ipairs(state._terms) do
      if t.winnr and vim.api.nvim_win_is_valid(t.winnr) then
        ui.show_tabline(t.winnr)
        break
      end
    end
  elseif state.count() >= 2 then
    for _, t in ipairs(state._terms) do
      if t.winnr and vim.api.nvim_win_is_valid(t.winnr) then
        ui.show_sidebar(t.winnr)
        break
      end
    end
  end
end

---Resize all currently visible terminal windows to match the current editor
---dimensions while preserving the configured size percentage.
---No-op for sessions whose window is not currently open.
function M.resize()
  local mode = config.options.display_mode or "horizontal"
  local pct  = (config.options.size or 70) / 100

  for _, term in ipairs(state._terms) do
    if term.winnr and vim.api.nvim_win_is_valid(term.winnr) then
      if mode == "float" then
        local cols   = vim.o.columns
        local lines  = vim.o.lines
        local width  = math.floor(cols  * pct)
        local height = math.floor(lines * pct)
        local row    = math.floor((lines - height) / 2)
        local col    = math.floor((cols  - width)  / 2)
        vim.api.nvim_win_set_config(term.winnr, {
          relative = "editor",
          width = width, height = height,
          row = row, col = col,
        })
      elseif mode == "vertical" then
        local width = math.floor(vim.o.columns * pct)
        vim.api.nvim_win_set_width(term.winnr, width)
      else -- horizontal
        local height = math.floor(vim.o.lines * pct)
        vim.api.nvim_win_set_height(term.winnr, height)
      end
    end
  end
end

return M
