local M           = {}

local NuiSplit    = require("nui.split")
local NuiPopup    = require("nui.popup")
local NuiLine     = require("nui.line")
local NuiText     = require("nui.text")

local ns          = vim.api.nvim_create_namespace("essential_term_ui")

M._sidebar        = nil -- NuiSplit instance
M._tabline        = nil -- NuiPopup instance
M._tab_col_ranges = {}

-- ── Highlight groups ─────────────────────────────────────────────────────────

local hl_ready    = false

local function ensure_hl()
  if hl_ready then return end
  hl_ready = true
  vim.api.nvim_set_hl(0, "EssentialTermActive", { link = "PmenuSel", default = true })
  vim.api.nvim_set_hl(0, "EssentialTermActiveName", { link = "PmenuSel", default = true })
  vim.api.nvim_set_hl(0, "EssentialTermName", { link = "Pmenu", default = true })
  vim.api.nvim_set_hl(0, "EssentialTermTabActive", { link = "PmenuSel", default = true })
  vim.api.nvim_set_hl(0, "EssentialTermTabInactive", { link = "Pmenu", default = true })
  vim.api.nvim_set_hl(0, "EssentialTermTabSep", { link = "VertSplit", default = true })
end

-- ── Sidebar ───────────────────────────────────────────────────────────────────

local function setup_sidebar_keymaps(bufnr)
  local function select()
    if not (M._sidebar and vim.api.nvim_win_is_valid(M._sidebar.winid)) then return end
    local row = vim.api.nvim_win_get_cursor(M._sidebar.winid)[1]
    require("essential-term").goto_index(row)
  end
  vim.keymap.set("n", "<CR>", select, { noremap = true, silent = true, buffer = bufnr })
  vim.keymap.set("n", "<LeftRelease>", select, { noremap = true, silent = true, buffer = bufnr })
end

---Open the session-picker sidebar to the left of `term_winnr`.
---If the sidebar is already visible, refreshes its content instead.
---Entries are mouse- and `<CR>`-clickable to switch sessions.
---@param term_winnr integer Window id of the active terminal window
function M.show_sidebar(term_winnr)
  if M._sidebar and vim.api.nvim_win_is_valid(M._sidebar.winid) then
    M.refresh_sidebar()
    return
  end

  ensure_hl()
  local config     = require("essential-term.config")
  local width      = (config.options and config.options.sidebar_width) or 25

  -- Mount the split relative to the terminal window
  local caller_win = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(term_winnr)

  M._sidebar = NuiSplit({
    relative    = "win",
    position    = "left",
    size        = width,
    enter       = false,
    win_options = {
      number         = false,
      relativenumber = false,
      signcolumn     = "no",
      wrap           = false,
      cursorline     = true,
      winfixwidth    = true,
    },
    buf_options = {
      buftype   = "nofile",
      bufhidden = "hide",
      swapfile  = false,
    },
  })
  M._sidebar:mount()

  setup_sidebar_keymaps(M._sidebar.bufnr)

  local target = vim.api.nvim_win_is_valid(caller_win) and caller_win or term_winnr
  vim.api.nvim_set_current_win(target)

  M.refresh_sidebar()
end

---Close the sidebar window. No-op if the sidebar is not currently visible.
function M.hide_sidebar()
  if M._sidebar then
    if vim.api.nvim_win_is_valid(M._sidebar.winid) then
      M._sidebar:unmount()
    end
    M._sidebar = nil
  end
end

---Redraw the sidebar with the current session list, highlighting the active
---session and repositioning the cursor to its line.
function M.refresh_sidebar()
  if not (M._sidebar and vim.api.nvim_win_is_valid(M._sidebar.winid)) then return end

  local state = require("essential-term.state")
  local bufnr = M._sidebar.bufnr
  if not vim.api.nvim_buf_is_valid(bufnr) then return end

  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  local active_line = nil
  for i, term in ipairs(state._terms) do
    local is_active = term.id == state.active_id
    local line = NuiLine()
    if is_active then
      line:append(NuiText("  " .. term.name, "EssentialTermActive"))
      active_line = i
    else
      line:append(NuiText("   " .. term.name, "EssentialTermName"))
    end
    line:render(bufnr, ns, i)
  end

  -- Trim any extra lines left from a previous larger list
  local lcount = vim.api.nvim_buf_line_count(bufnr)
  if lcount > #state._terms then
    vim.api.nvim_buf_set_lines(bufnr, #state._terms, -1, false, {})
  end

  vim.bo[bufnr].modifiable = false

  if active_line and vim.api.nvim_win_is_valid(M._sidebar.winid) then
    if vim.api.nvim_get_current_win() ~= M._sidebar.winid then
      vim.api.nvim_win_set_cursor(M._sidebar.winid, { active_line, 0 })
    end
  end
end

-- ── Tabline ───────────────────────────────────────────────────────────────────

local function setup_tabline_keymaps(bufnr)
  local function click_tab()
    if not (M._tabline and vim.api.nvim_win_is_valid(M._tabline.winid)) then return end
    local col = vim.api.nvim_win_get_cursor(M._tabline.winid)[2]
    for _, range in ipairs(M._tab_col_ranges) do
      if col >= range.col_start and col <= range.col_end then
        require("essential-term").goto_index(range.index)
        return
      end
    end
  end
  vim.keymap.set("n", "<CR>", click_tab, { noremap = true, silent = true, buffer = bufnr })
  vim.keymap.set("n", "<LeftRelease>", click_tab, { noremap = true, silent = true, buffer = bufnr })
end

---Open a one-line floating tabline positioned at the top of the terminal
---window `term_winnr`. Works for both float and split windows.
---If the tabline is already visible, refreshes it.
---Tabs are mouse- and `<CR>`-clickable to switch sessions.
---@param term_winnr integer Window id of the active terminal window
function M.show_tabline(term_winnr)
  if M._tabline and vim.api.nvim_win_is_valid(M._tabline.winid) then
    M.refresh_tabline()
    return
  end

  ensure_hl()
  local wincfg = vim.api.nvim_win_get_config(term_winnr)

  local row, col, width, zindex
  if wincfg.relative and wincfg.relative ~= "" then
    -- Float window: place tabline one row above the float
    row    = wincfg.row - 1
    col    = wincfg.col
    width  = wincfg.width + 2
    zindex = (wincfg.zindex or 50) + 1
  else
    -- Split window: overlay the tabline at the top-left of the window
    local pos = vim.api.nvim_win_get_position(term_winnr)
    row    = pos[1]
    col    = pos[2]
    width  = vim.api.nvim_win_get_width(term_winnr)
    zindex = 50
  end

  M._tabline = NuiPopup({
    relative    = "editor",
    position    = { row = row, col = col },
    size        = { width = width, height = 1 },
    border      = { style = "none" },
    zindex      = zindex,
    enter       = false,
    focusable   = true,
    buf_options = {
      buftype   = "nofile",
      bufhidden = "hide",
      swapfile  = false,
    },
    win_options = {
      winblend = 0,
    },
  })
  M._tabline:mount()

  setup_tabline_keymaps(M._tabline.bufnr)
  M.refresh_tabline()
end

---Close the floating tabline window. No-op if the tabline is not visible.
function M.hide_tabline()
  if M._tabline then
    if vim.api.nvim_win_is_valid(M._tabline.winid) then
      M._tabline:unmount()
    end
    M._tabline = nil
  end
end

---Redraw the tabline with session labels, highlighting the active tab.
---Tracks column ranges for click handling. No-op if not visible.
function M.refresh_tabline()
  if not (M._tabline and vim.api.nvim_win_is_valid(M._tabline.winid)) then return end

  local state = require("essential-term.state")
  local bufnr = M._tabline.bufnr
  if not vim.api.nvim_buf_is_valid(bufnr) then return end

  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  -- Seed the buffer with a blank line so render() can replace it
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "" })

  local line        = NuiLine()
  local col         = 0
  M._tab_col_ranges = {}

  for i, term in ipairs(state._terms) do
    local is_active = term.id == state.active_id
    local label     = is_active and ("  " .. term.name .. "  ") or ("   " .. term.name .. "  ")
    local sep       = (i < #state._terms) and "│" or ""

    table.insert(M._tab_col_ranges, {
      index     = i,
      col_start = col,
      col_end   = col + #label - 1,
    })
    col = col + #label + #sep

    line:append(NuiText(label, is_active and "EssentialTermTabActive" or "EssentialTermTabInactive"))
    if sep ~= "" then
      line:append(NuiText(sep, "EssentialTermTabSep"))
    end
  end

  line:render(bufnr, ns, 1)
  vim.bo[bufnr].modifiable = false
end

---Update the floating tabline's position and width to match `term_winnr`.
---Call this after the terminal window has been resized or moved so the tabline
---stays anchored to the top of the terminal.
---No-op if the tabline is not currently visible.
---@param term_winnr integer Window id of the active terminal window
function M.reposition_tabline(term_winnr)
  if not (M._tabline and vim.api.nvim_win_is_valid(M._tabline.winid)) then return end
  if not vim.api.nvim_win_is_valid(term_winnr) then return end

  local wincfg = vim.api.nvim_win_get_config(term_winnr)
  local row, col, width, zindex
  if wincfg.relative and wincfg.relative ~= "" then
    row    = wincfg.row - 1
    col    = wincfg.col
    width  = wincfg.width + 2
    zindex = (wincfg.zindex or 50) + 1
  else
    local pos = vim.api.nvim_win_get_position(term_winnr)
    row    = pos[1]
    col    = pos[2]
    width  = vim.api.nvim_win_get_width(term_winnr)
    zindex = 50
  end

  vim.api.nvim_win_set_config(M._tabline.winid, {
    relative = "editor",
    row      = row,
    col      = col,
    width    = width,
    height   = 1,
    zindex   = zindex,
  })
end

---Refresh whichever UI elements are currently visible (sidebar and/or tabline).
function M.refresh()
  M.refresh_sidebar()
  M.refresh_tabline()
end

return M
