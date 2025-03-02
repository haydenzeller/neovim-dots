return {
    {
        dir = "/home/hayden/.config/nvim/lua/plugins/wingman",
        dependencies = { "nvim-lua/plenary.nvim" },
        config = function()
            local M = {}
            local curl = require("plenary.curl")
            
            -- Configure the Ollama model and endpoint
            M.config = {
                model = "qwen2.5-coder:7b", 
                url = "http://localhost:11434",
                show_prompt = false,
                max_tokens = 250,
                temperature = 0.2,
                idle_timeout = 5000,
                debounce_ms = 300,
                context_window = 2048,
            }

            -- Setup completion sources
            M.completions = {
                active = false,
                timer = nil,
                idle_timer = nil,
                waiting_for_response = false,
                typing_since_request = false,
                cache = {},
            }

            -- Function to get code context from current buffer
            function M.get_context()
                local line = vim.api.nvim_win_get_cursor(0)[1]
                local buf = vim.api.nvim_get_current_buf()
                local context_start = math.max(1, line - 50)
                local context = vim.api.nvim_buf_get_lines(buf, context_start - 1, line, false)
                return table.concat(context, '\n')
            end

            -- Function to generate completion using direct API call
            function M.generate_completion(callback)
                if not M.completions.active then
                    return
                end
                
                local context = M.get_context()
                local prompt = "Complete the following code:\n\n" .. context
                
                -- Set the waiting flag and reset typing flag
                M.completions.waiting_for_response = true
                M.completions.typing_since_request = false
                
                curl.post({
                    url = M.config.url .. "/api/generate",
                    body = vim.fn.json_encode({
                        model = M.config.model,
                        prompt = prompt,
                        options = {
                            temperature = M.config.temperature,
                            num_predict = M.config.max_tokens,
                        }
                    }),
                    headers = {
                        content_type = "application/json",
                    },
                    callback = function(response)
                        M.completions.waiting_for_response = false
                        
                        -- Discard the response if user has typed since the request was sent
                        if M.completions.typing_since_request then
                            return
                        end
                        
                        if response and response.body then
                            local data = vim.fn.json_decode(response.body)
                            if data and data.response then
                                callback(data.response)
                            end
                        end
                    end,
                })
            end

            -- Function to show completion after idle timeout
            function M.show_completion()
                -- Reset any existing timers
                if M.completions.timer then
                    M.completions.timer:stop()
                end
                
                if M.completions.idle_timer then
                    M.completions.idle_timer:stop()
                end
                
                -- If already waiting for a response, mark that typing occurred
                if M.completions.waiting_for_response then
                    M.completions.typing_since_request = true
                end
                
                -- Set up idle timer (5 seconds)
                M.completions.idle_timer = vim.loop.new_timer()
                M.completions.idle_timer:start(M.config.idle_timeout, 0, vim.schedule_wrap(function()
                    -- Only proceed if we're not already waiting for a response
                    if not M.completions.waiting_for_response then
                        M.generate_completion(function(completion)
                            if completion and #completion > 0 then
                                local line = vim.api.nvim_win_get_cursor(0)[1]
                                local col = vim.api.nvim_win_get_cursor(0)[2]
                                local lines = vim.split(completion, "\n")
                                local display_text = lines[1] or ""
                                
                                -- Create namespace if not exists
                                M.ns_id = M.ns_id or vim.api.nvim_create_namespace("wingman")
                                
                                -- Show the completion as virtual text
                                vim.api.nvim_buf_set_virtual_text(0, M.ns_id, line - 1, {{display_text, "Comment"}}, {})
                                M.completions.cache = {
                                    text = completion,
                                    line = line,
                                    col = col,
                                }
                            end
                        end)
                    end
                end))
            end

            -- Function to accept completion
            function M.accept_completion()
                if M.completions.cache and M.completions.cache.text then
                    local text = M.completions.cache.text
                    local lines = vim.split(text, "\n")
                    
                    -- Create namespace if not exists
                    M.ns_id = M.ns_id or vim.api.nvim_create_namespace("wingman")
                    vim.api.nvim_buf_clear_namespace(0, M.ns_id, 0, -1)
                    
                    -- Insert the completion text
                    if #lines == 1 then
                        local line = vim.api.nvim_win_get_cursor(0)[1]
                        local col = vim.api.nvim_win_get_cursor(0)[2]
                        vim.api.nvim_buf_set_text(0, line-1, col, line-1, col, {lines[1]})
                    else
                        -- Handle multi-line completions
                        local line = vim.api.nvim_win_get_cursor(0)[1]
                        local col = vim.api.nvim_win_get_cursor(0)[2]
                        vim.api.nvim_buf_set_text(0, line-1, col, line-1, col, lines)
                    end
                    
                    M.completions.cache = {}
                end
            end

            -- Toggle wingman completion
            function M.toggle()
                M.completions.active = not M.completions.active
                if M.completions.active then
                    vim.api.nvim_echo({{"Wingman activated", "None"}}, false, {})
                    -- Set up autocommands to trigger completions while typing
                    vim.api.nvim_create_autocmd({"InsertCharPre"}, {
                        callback = function()
                            M.show_completion()
                        end,
                    })
                else
                    vim.api.nvim_echo({{"Wingman deactivated", "None"}}, false, {})
                    -- Create namespace if not exists
                    M.ns_id = M.ns_id or vim.api.nvim_create_namespace("wingman")
                    vim.api.nvim_buf_clear_namespace(0, M.ns_id, 0, -1)
                    if M.completions.timer then
                        M.completions.timer:stop()
                    end
                    if M.completions.idle_timer then
                        M.completions.idle_timer:stop()
                    end
                end
            end

            -- Set up key mappings
            vim.api.nvim_set_keymap('n', '<leader>wt', '<cmd>lua _G.wingman_toggle()<CR>', {noremap = true, silent = true})
            vim.api.nvim_set_keymap('i', '<C-]>', '<cmd>lua _G.wingman_accept()<CR>', {noremap = true, silent = true})
            
            -- Create global functions for keymaps
            _G.wingman_toggle = M.toggle
            _G.wingman_accept = M.accept_completion
            
            -- Add a namespace ID for virtual text
            M.ns_id = vim.api.nvim_create_namespace("wingman")
        end,
    }
}