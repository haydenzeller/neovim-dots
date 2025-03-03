return {
  "custom/wingman",
  dir = vim.fn.stdpath("config") .. "/lua/custom/plugins", -- Points to the plugin directory
  lazy = false,
  dependencies = { "nvim-lua/plenary.nvim" },
  config = function()
    local api = vim.api
    local curl = require("plenary.curl")
    local ns_id = api.nvim_create_namespace("wingman")

    -- Configuration table
    local config = {
      ollama_url = "http://192.168.2.33:11435/api/generate",
      model = "qwen2.5-coder:0.5b",
      show_suggestions = true,
      auto_trigger = true,
      trigger_threshold = 3,
      max_tokens = 100,
      keymaps = {
        accept = "<Tab>",
        reject = "<C-]>",
        next = "<C-n>",
        prev = "<C-p>",
      },
    }

    -- State management
    local state = {
      suggestion_text = nil,
      suggestion_line = nil,
      suggestion_col = nil,
      suggestion_virt_text_id = nil,
      timer = nil,
      prompt_in_progress = false,
      latest_request_id = 0, -- Track the latest request ID
    }

    -- Clear existing suggestion
    local function clear_suggestion()
      if state.suggestion_virt_text_id then
        pcall(api.nvim_buf_del_extmark, 0, ns_id, state.suggestion_virt_text_id)
        state.suggestion_virt_text_id = nil
      end
      state.suggestion_text = nil
      state.suggestion_line = nil
      state.suggestion_col = nil
    end

    -- Show suggestion as virtual text
    local function show_suggestion(text, line, col, request_id)
      -- Only show suggestion if it matches the latest request
      if request_id ~= state.latest_request_id then
        return -- Discard outdated suggestion
      end
      clear_suggestion()
      if not text or text == "" then
        return
      end

      vim.schedule(function()
        local current_cursor = api.nvim_win_get_cursor(0)
        if current_cursor[1] ~= line then
          return -- Discard if cursor has moved to a different line
        end

        local current_line = api.nvim_buf_get_lines(0, line - 1, line, false)[1] or ""
        local clamped_col = math.min(col, #current_line)

        state.suggestion_text = text
        state.suggestion_line = line
        state.suggestion_col = clamped_col

        local suggestion_lines = vim.split(text, "\n", { trimempty = true })
        if #suggestion_lines == 0 then
          return
        end

        local target_line = line - 1 -- 0-based indexing
        local virt_text = { { suggestion_lines[1], "Comment" } }
        local virt_lines = {}
        for i = 2, #suggestion_lines do
          table.insert(virt_lines, { { suggestion_lines[i], "Comment" } })
        end

        state.suggestion_virt_text_id = api.nvim_buf_set_extmark(0, ns_id, target_line, 0, {
          virt_text = virt_text,
          virt_text_pos = "overlay",
          virt_lines = virt_lines,
          invalidate = true,
        })
      end)
    end

    -- Gather context for completion
    local function get_context()
      local bufnr = api.nvim_get_current_buf()
      local cursor_pos = api.nvim_win_get_cursor(0)
      local line = cursor_pos[1]
      local col = cursor_pos[2]
      local current_line = api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1] or ""
      col = math.min(col, #current_line)
      local prefix = string.sub(current_line, 1, col)
      local start_line = math.max(1, line - 10)
      local prev_lines = api.nvim_buf_get_lines(bufnr, start_line - 1, line - 1, false)
      local context = table.concat(prev_lines, "\n")
      if #context > 0 then
        context = context .. "\n"
      end
      context = context .. prefix
      return context, prefix, line, col
    end

    -- Request completion from Ollama API
    local function request_completion()
      if state.prompt_in_progress then
        return -- Avoid overlapping requests
      end

      -- Increment the request ID for this new request
      state.latest_request_id = state.latest_request_id + 1
      local request_id = state.latest_request_id

      local context, prefix, line, col = get_context()
      if #context < config.trigger_threshold then
        return
      end

      local filetype = vim.bo.filetype
      local cursor_marker = "<|cursor|>"
      local full_context = context .. cursor_marker
      local prompt = "You are completing code in a " .. filetype .. " file.\n" ..
                    "Context:\n```" .. filetype .. "\n" .. full_context .. "```\n" ..
                    "Provide only the completion starting from the <|cursor|> marker. Do not repeat the existing code."

      state.prompt_in_progress = true

      curl.post({
        url = config.ollama_url,
        body = vim.json.encode({
          model = config.model,
          prompt = prompt,
          stream = false,
          max_tokens = config.max_tokens,
        }),
        headers = { content_type = "application/json" },
        callback = function(response)
          state.prompt_in_progress = false
          if response.status ~= 200 then
            vim.notify("Wingman: Error getting completion", vim.log.levels.ERROR)
            return
          end

          local result = vim.json.decode(response.body)
          if not result or not result.response then
            vim.notify("Wingman: Error decoding response", vim.log.levels.ERROR)
            return
          end

          local suggestion = result.response:gsub("^```[%w]*\n", ""):gsub("\n```$", ""):gsub(cursor_marker, "")
          show_suggestion(suggestion, line, col, request_id)
        end,
      })
    end

    -- Accept and insert the suggestion at the current cursor position
    local function accept_suggestion()
      if not state.suggestion_text then
        return
      end

      local cursor_pos = api.nvim_win_get_cursor(0)
      local line = cursor_pos[1]
      local col = cursor_pos[2] -- Use current cursor column

      local lines = vim.split(state.suggestion_text, "\n", { plain = true })
      api.nvim_buf_set_text(0, line - 1, col, line - 1, col, lines)

      if #lines == 1 then
        api.nvim_win_set_cursor(0, { line, col + #lines[1] })
      else
        local last_line = line + #lines - 1
        local last_col = #lines[#lines]
        api.nvim_win_set_cursor(0, { last_line, last_col })
      end

      clear_suggestion()
    end

    -- Setup autocommands and keybindings
    local function setup()
      local group = api.nvim_create_augroup("Wingman", { clear = true })

      if config.auto_trigger then
        api.nvim_create_autocmd({ "TextChangedI", "TextChangedP" }, {
          group = group,
          callback = function()
            clear_suggestion()
            if state.timer then
              vim.loop.timer_stop(state.timer)
              state.timer:close()
              state.timer = nil
            end
            state.timer = vim.loop.new_timer()
            state.timer:start(2000, 0, vim.schedule_wrap(function()
              if vim.fn.mode() == "i" then
                request_completion()
              end
            end))
          end,
        })
        api.nvim_create_autocmd("CursorMovedI", {
          group = group,
          callback = clear_suggestion,
        })
        api.nvim_create_autocmd("InsertLeave", {
          group = group,
          callback = clear_suggestion,
        })
      end

      vim.keymap.set("i", "<Tab>", function()
        if state.suggestion_text then
          vim.schedule(accept_suggestion)
          return ""
        else
          return "<Tab>"
        end
      end, { expr = true })

      vim.keymap.set("i", "<CR>", function()
        local cr = api.nvim_replace_termcodes("<CR>", true, false, true)
        api.nvim_feedkeys(cr, "n", false)
        vim.schedule(request_completion)
        return ""
      end, { noremap = true, silent = true })

      local keymaps = config.keymaps
      vim.keymap.set("i", keymaps.reject, function()
        if state.suggestion_text then
          clear_suggestion()
          return ""
        else
          return keymaps.reject
        end
      end, { expr = true })
    end

    -- Initialize the plugin
    setup()

    -- User commands
    vim.api.nvim_create_user_command("WingmanToggle", function()
      config.show_suggestions = not config.show_suggestions
      print("Wingman suggestions " .. (config.show_suggestions and "enabled" or "disabled"))
    end, {})

    vim.api.nvim_create_user_command("WingmanComplete", request_completion, {})
  end,
}