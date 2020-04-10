let s:backtrace_win = -1


" populates the backtrace window according to the array in a:backtrace
function! nodeinspect#backtrace#DisplayBacktraceWindow(backtrace)
	let gotoResult = win_gotoid(s:backtrace_win)
	if gotoResult == 1
		" execute "set modifiable"
		execute "%d"
		for traceEntry in a:backtrace
			" props are name & frameLocation
			call append(getline('$'), traceEntry["name"].'['.traceEntry["frameLocation"].']')
		endfor
		execute 'normal! 1G'
		" execute "set nomodifiable"
	endif
endfunction


" kill the backtrace window, if exists.
function! nodeinspect#backtrace#KillBacktraceWindow()
	if s:backtrace_win != -1 && win_gotoid(s:backtrace_win) == 1
		execute "bd!"
	endif
endfunction


" empty the backtrace window, adds a 'debugger not stopped' window by default
" or a user message
function! nodeinspect#backtrace#ClearBacktraceWindow(...)
	if a:0 == 0
		let message = 'Running'
	else
		let message = a:1
	endif
	let cur_win = win_getid()
	let gotoResult = win_gotoid(s:backtrace_win)
	if gotoResult == 1
		" execute "set modifiable"
		execute "%d"
		call setline('.', message)
		" execute "set nomodifiable"
		call win_gotoid(cur_win)
		" execute "set modifiable"
	endif
endfunction

" create the backtrace window
function! nodeinspect#backtrace#CreateBacktraceWindow(startWin)
		" open split for call stack
		execute "rightb ".winwidth(a:startWin)/3."vnew | setlocal nobuflisted buftype=nofile bufhidden=wipe noswapfile statusline=Callstack"
		let s:backtrace_win = win_getid()
		set nonu
endfunction



