local M = {}

local state = require("essential-term.state")
local config = require("essential-term.config")
local terminal = require("essential-term.terminal")
local ui = require("essential-term.ui")

---Initialise essential-term with user options. Must be called once before any other API.
---@param opts? {shell?:string, size?:integer, close_on_exit?:boolean, start_in_insert?:boolean, sidebar_width?:integer, display_mode?:"horizontal"|"float", colors?:{bg?:string, fg?:string}}
function M.setup(opts)
  config.setup(opts)
end

-- Returns true if any terminal window is currently visible
local function any_visible()
  for _, term in ipairs(state._terms) do
    if term.winnr and vim.api.nvim_win_is_valid(term.winnr) then
      return true
    end
  end
  return false
end

-- Hide all visible terminal windows
local function hide_all()
  for _, term in ipairs(state._terms) do
    terminal.hide(term.id)
  end
end

local function maybe_show_sidebar(term)
  if not (term and term.winnr and vim.api.nvim_win_is_valid(term.winnr)) then return end
  if config.options.display_mode == "float" then
    if state.count() >= 2 then
      ui.show_tabline(term.winnr)
    else
      ui.hide_tabline()
    end
    return
  end
  if state.count() >= 2 then
    ui.show_sidebar(term.winnr)
  end
end

---Show the terminal panel (creating one if needed), or hide all visible terminals.
---Restores the last active session when re-opening from a hidden state.
function M.toggle()
  if state.count() == 0 then
    M.new()
    return
  end

  if any_visible() then
    hide_all()
    ui.hide_sidebar()
    ui.hide_tabline()
  else
    local id = state.active_id or state._terms[1].id
    terminal.show(id)
    maybe_show_sidebar(state.get(id))
  end
end

---Create a new terminal session and show the sidebar/tabline when applicable.
---@return table The new session entry from state.
function M.new()
  local term = terminal.create()
  maybe_show_sidebar(term)
  return term
end

---Destroy the currently active terminal session. Automatically switches to
---an adjacent session if one exists, or hides the UI entirely if it was last.
function M.close()
  local active = state.get_active()
  if not active then
    return
  end

  local id = active.id
  local idx = state.index_of(id)
  local next_id = nil
  if state.count() > 1 then
    if idx < state.count() then
      next_id = state._terms[idx + 1].id
    else
      next_id = state._terms[idx - 1].id
    end
  end

  terminal.destroy(id)

  if next_id then
    terminal.show(next_id)
    maybe_show_sidebar(state.get(next_id))
  else
    ui.hide_sidebar()
    ui.hide_tabline()
  end
end

---Switch to the next terminal session in the list (wraps around).
---The current window's buffer is swapped in-place; no new split is opened.
function M.next()
  if state.count() == 0 then
    return
  end

  local idx = state.index_of(state.active_id) or 1
  local next_idx = (idx % state.count()) + 1
  local next_id = state._terms[next_idx].id

  if next_id == state.active_id then
    return
  end

  terminal.swap_to(next_id)
  ui.refresh()
end

---Switch to the previous terminal session in the list (wraps around).
---The current window's buffer is swapped in-place; no new split is opened.
function M.prev()
  if state.count() == 0 then
    return
  end

  local idx = state.index_of(state.active_id) or 1
  local prev_idx = ((idx - 2) % state.count()) + 1
  local prev_id = state._terms[prev_idx].id

  if prev_id == state.active_id then
    return
  end

  terminal.swap_to(prev_id)
  ui.refresh()
end

---Jump directly to the session at 1-based position `n` in the session list.
---If `n` is already the active session and its window is hidden, re-opens it.
---@param n integer 1-based index into the session list
function M.goto_index(n)
  if n < 1 or n > state.count() then
    return
  end
  local term = state._terms[n]
  if term.id == state.active_id then
    if not (term.winnr and vim.api.nvim_win_is_valid(term.winnr)) then
      terminal.show(term.id)
      maybe_show_sidebar(term)
    end
    -- Ensure focus goes to the terminal, not the sidebar
    if term.winnr and vim.api.nvim_win_is_valid(term.winnr) then
      vim.api.nvim_set_current_win(term.winnr)
      if config.options.start_in_insert then
        vim.cmd("startinsert")
      end
    end
    return
  end

  if any_visible() then
    terminal.swap_to(term.id)
  else
    terminal.show(term.id)
    maybe_show_sidebar(state.get(term.id))
  end
  ui.refresh()
end

---Rename the active terminal session.
---If `name` is provided it is applied immediately; otherwise `vim.ui.input` is
---used to prompt the user.
---@param name? string New name for the session
function M.rename(name)
  local active = state.get_active()
  if not active then
    return
  end

  if name and name ~= "" then
    active.name = name
    ui.refresh()
  else
    vim.ui.input({ prompt = "Terminal name: ", default = active.name }, function(input)
      if input and input ~= "" then
        active.name = input
        ui.refresh()
      end
    end)
  end
end

return M
