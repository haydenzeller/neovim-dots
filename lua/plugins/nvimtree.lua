return {
	{
		"nvim-tree/nvim-tree.lua",
		view = {
			width=30,
		},
		config = function()
			vim.g.loaded_netrw = 1
			vim.g.loaded_netrwPlugin = 1
			require("nvim-tree").setup() 
		end,
	},
	{
		"kyazdani42/nvim-web-devicons",
	},
}

