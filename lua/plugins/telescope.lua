return {
    'nvim-telescope/telescope.nvim',
    depends = {
        'nvim-lua/plenary.nvim',
    },
    config = function()
        vim.keymap.set('n', '<space>ff', '<cmd>Telescope find_files<cr>')
    end,
}
