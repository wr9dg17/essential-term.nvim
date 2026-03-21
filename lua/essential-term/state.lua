local M = {}

-- Registry of terminal instances
-- Each entry: { id=number, bufnr=number, job_id=number, name=string, winnr=number|nil }
M._terms = {}
M._next_id = 1
M.active_id = nil

---Assign an id to `entry`, insert it into the registry, and return it.
---`entry` should contain `bufnr`, `job_id`, `name`, and optionally `winnr`.
---The `id` field is assigned here and must not be set by the caller.
---@param entry table
---@return table
function M.add(entry)
  entry.id = M._next_id
  M._next_id = M._next_id + 1
  table.insert(M._terms, entry)
  return entry
end

---Remove the terminal with the given id from the registry.
---Updates `active_id` to the last remaining entry when the active session is removed.
---@param id integer
---@return boolean `true` if an entry was found and removed, `false` otherwise
function M.remove(id)
  for i, term in ipairs(M._terms) do
    if term.id == id then
      table.remove(M._terms, i)
      if M.active_id == id then
        -- set active to the last remaining term, or nil
        if #M._terms > 0 then
          M.active_id = M._terms[#M._terms].id
        else
          M.active_id = nil
        end
      end
      return true
    end
  end
  return false
end

---Return the terminal entry with the given id, or `nil` if not found.
---@param id integer
---@return {id:integer, bufnr:integer, job_id:integer|nil, name:string, winnr:integer|nil}|nil
function M.get(id)
  for _, term in ipairs(M._terms) do
    if term.id == id then
      return term
    end
  end
  return nil
end

---Return the currently active terminal entry, or `nil` if no session is active.
---@return {id:integer, bufnr:integer, job_id:integer|nil, name:string, winnr:integer|nil}|nil
function M.get_active()
  if M.active_id then
    return M.get(M.active_id)
  end
  return nil
end

---Return the terminal entry whose buffer matches `bufnr`, or `nil` if not found.
---@param bufnr integer
---@return {id:integer, bufnr:integer, job_id:integer|nil, name:string, winnr:integer|nil}|nil
function M.get_by_bufnr(bufnr)
  for _, term in ipairs(M._terms) do
    if term.bufnr == bufnr then
      return term
    end
  end
  return nil
end

---Return the total number of registered terminal sessions.
---@return integer
function M.count()
  return #M._terms
end

---Return the 1-based index of the terminal with the given id, or `nil` if not found.
---@param id integer
---@return integer|nil
function M.index_of(id)
  for i, term in ipairs(M._terms) do
    if term.id == id then
      return i
    end
  end
  return nil
end

return M
