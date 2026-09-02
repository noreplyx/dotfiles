require("full-border"):setup {
	type = ui.Border.ROUNDED,
}

require("git"):setup {
	order = 1500,
}

require("githead"):setup {
	branch_prefix = "on",
	branch_symbol = " ",
	branch_borders = "()",
}

require("starship"):setup {}
