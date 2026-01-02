vim.api.nvim_create_user_command("Run", function(opts)
	local cmd = opts.args
	local buf = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_buf_set_name(buf, "Run Output")
	vim.cmd("botright split")
	vim.api.nvim_win_set_buf(0, buf)

	vim.fn.jobstart(cmd, {
		stdout_buffered = false,
		stderr_buffered = false,
		on_stdout = function(_, data)
			if data then
				vim.api.nvim_buf_set_lines(buf, -1, -1, false, data)
			end
		end,
		on_stderr = function(_, data)
			if data then
				vim.api.nvim_buf_set_lines(buf, -1, -1, false, data)
			end
		end,
	})
end, { nargs = "+", complete = "shellcmd" })
