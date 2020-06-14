let s:repl_win = -1
let s:repl_buf = -1


" runs node-inspect according to session parameters
function nodeinspect#repl#StartNodeInspect(session, plugin_path)
	if s:repl_win == -1 || win_gotoid(s:repl_win) != 1
		echom "nodeinspect - can't start repl"
		return
	endif
	" prepare call command line
	let cmd_line = []
	call add(cmd_line, 'node')
	call add(cmd_line, a:plugin_path . "/node-inspect/cli.js")
	" start according to settings
	if a:session["request"] == "launch"
		" add the relevant launch params
		call add(cmd_line, a:session["script"])
		let cmd_line += a:session["args"]
	else
		" add the relevant connect params
		call add(cmd_line, a:session["address"].":".a:session["port"])
	endif
	" open terminal
	if has("nvim")
		let term_id = termopen(cmd_line, {'on_exit': 'OnNodeInspectExit'})
		if term_id == -1
			return 1
		endif
	else
		let term_id = term_start(cmd_line, {'curwin': 1, 'exit_cb': 'OnNodeInspectExit', 'term_finish': 'close', 'term_kill': 'kill'})
		" 0 will be returned only if the window opening fails
		if term_id == 0
			return 1
		endif
	endif
	sleep 200m
	return 0
endfunction

" hide the repl window
function! nodeinspect#repl#HideReplWindow()
	if s:repl_win != -1 && win_gotoid(s:repl_win) == 1
		execute "hide"
	endif
endfunction

" create the repl win
function nodeinspect#repl#ShowReplWindow(startWin)
	if s:repl_buf == -1 || bufwinnr(s:repl_buf) == -1
			" create according to g:nodeinspect_window_pos
			if g:nodeinspect_window_pos == 'right' || g:nodeinspect_window_pos == 'left'
				let rightSplitVal = &splitright
				if g:nodeinspect_window_pos == 'right'
					execute "set splitright"
				elseif g:nodeinspect_window_pos == 'left'
					execute "set nosplitright"
				endif

				if s:repl_buf == -1
					execute "vert ".winwidth(a:startWin)/3."new"
					let s:repl_buf = bufnr('%')
					set nonu
				else
					execute "vert ".winwidth(a:startWin)/3."new | buffer" .s:repl_buf
				endif

				if rightSplitVal == 0
					execute "set nosplitright"
				else
					execute "set splitright"
				endif
			else
				" bottom/ dk
				if s:repl_buf == -1
					execute "bo ".winheight(a:startWin)/3."new"
					let s:repl_buf = bufnr('%')
					set nonu
				else
					execute "bo ".winheight(a:startWin)/3."new | buffer " . s:repl_buf
				endif
			endif
		let s:repl_win = win_getid()
	endif
endfunction


" kill the repl window
function nodeinspect#repl#KillReplWindow()
	if s:repl_win != -1 && win_gotoid(s:repl_win) == 1
		execute "bd!"
		let s:repl_buf = -1
	endif
endfunction


" return 1 if the repl window is visible
function nodeinspect#repl#IsWindowVisible()
	if s:repl_buf == -1 || bufwinnr(s:repl_buf) == -1
		return 0
	else
		return 1
	endif
endfunction

