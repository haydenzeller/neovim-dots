return {
	{
		"neovim/nvim-lspconfig",
		autostart = true,
		config = function()
			require("lspconfig").tsserver.setup{}
			require("lspconfig").rust_analyzer.setup{}
			require("lspconfig").vimls.setup{}
			require("lspconfig").bashls.setup{}
			require("lspconfig").jsonls.setup{}
			require("lspconfig").yamlls.setup{}
			require("lspconfig").html.setup{}
			require("lspconfig").cssls.setup{}
			require("lspconfig").vuels.setup{}
			require("lspconfig").jdtls.setup{}
		end,
	},
	{
		"hrsh7th/nvim-cmp",
		config = function()
			require("cmp").setup({
				sources = {
					{ name = "nvim_lsp" },
					{ name = "buffer" },
					{ name = "path" },
					{ name = "nvim_lua" },
				},
			})
		end,
	},
	{
		"hrsh7th/cmp-nvim-lsp",
	},
	{
		"hrsh7th/cmp_luasnip",
	},
	{
		'saadparwaiz1/cmp_luasnip',
	},
	{
		'L3MON4D3/LuaSnip',
	},
}
