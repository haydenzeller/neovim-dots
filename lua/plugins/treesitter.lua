return {
	{
		'nvim-treesitter/nvim-treesitter',
		build = ":TSUpdate",
		config = function () 
      		local configs = require("nvim-treesitter.configs")
		configs.setup({
          		sync_install = true,
          		highlight = { enable = true },
          		indent = { enable = false },
		})
        vim.opt.smartindent = true
        vim.opt.autoindent = true
		vim.cmd([[set tabstop=4]])
		vim.cmd([[set shiftwidth=4]])
		vim.cmd([[set expandtab]])
		vim.cmd([[set relativenumber]])
		vim.cmd([[set number]])
		vim.cmd([[syntax off]])
    	end,
	},
}
