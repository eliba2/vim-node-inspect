let s:repl_win = -1
let s:repl_buf = -1
let s:term_id = -1
let s:ex_job = -1 " id for nvim, job object for vim



function! IsExJobRunning()
    if has("nvim")
       if s:ex_job != -1
           return 1
        endif
    else
        if type(s:ex_job) == v:t_job && job_status(s:ex_job) == 'run'
            return 1
        endif
    endif
    return 0
endfunction


" called when the external command emits to stdout
function! OnExternalJobStdout(...)
    if IsExJobRunning()
        " nvim receives a list while vim receives text
        if type(a:2) == 3 
            let data = join(a:2, '\n')
        else
            let data = a:2
        endif
        call nodeinspect#utils#SendEvent('{"m": "nd_print", "txt":"'.data.'\n"}')
    endif
endfunction



function! OnExternalJobStderr(...)
    " nvim receives a list while vim receives text
    if type(a:2) == 3 
        let data = join(a:2)
    else
        let data = a:2
    endif
    let pos = match(data, "Waiting for the debugger to disconnect")
    if pos != -1 && IsExJobRunning()
        if has("nvim")
            call jobstop(s:ex_job)
        else
            call job_stop(s:ex_job)
        endif
        let s:ex_job = -1
        call nodeinspect#onDebuggerEnded()
    endif
endfunction


function! OnExternalJobExit(...)
    if IsExJobRunning()
        let s:ex_job = -1
        call nodeinspect#onDebuggerEnded()
    endif
endfunction

" returns -1 on failure or 0 on success
" though the job id can be used for commmunication (nvim), I won't use it
" but send a message to the bridge to update the console. It prevents side
" effects such as it simulates user interaction 
function! s:getRuntimeExecutableCommand(runtimeExecutable, runTimeArgs, cwd)
    let ext_cmd = a:runtimeExecutable . " " . join(a:runTimeArgs)
	if has("nvim")
		let ex_job_id = jobstart(ext_cmd, {'cwd': a:cwd, 'on_stdout': 'OnExternalJobStdout', 'on_stderr': 'OnExternalJobStderr', 'on_exit': 'OnExternalJobExit'})
		" -1 will be returned only if the window opening fails
		if ex_job_id == -1
			return -1
		endif
        return ex_job_id
	else
		let ex_job = job_start(ext_cmd, {'exit_cb': 'OnExternalJobExit', 'cwd': a:cwd, 'out_cb': 'OnExternalJobStdout','err_cb': 'OnExternalJobStderr'})
		" 0 will be returned only if the window opening fails
		if job_status(ex_job) != 'run'
            echom "can't start job!"
			return -1
		endif
        return ex_job
	endif
endfunction


function! s:startExternalJobs(session)
    " execute external command, if any
    if a:session["runtimeExecutable"] != ""
        let s:ex_job = s:getRuntimeExecutableCommand(a:session["runtimeExecutable"], a:session["runtimeArgs"],a:session["cwd"])
        if !IsExJobRunning()
            echom "failed to execute external command"
            return
        endif
        let a:session["exJob"] = s:ex_job
    endif
endfunction


" called when restarting node-inspect, external jobs and other non-repl
" windows related job need to restart
function nodeinspect#repl#StartExternalJobs(session)
    call s:startExternalJobs(a:session)
endfunction


" runs node-inspect according to session parameters
function nodeinspect#repl#StartNodeInspect(session, plugin_path)
	if s:repl_win == -1 || win_gotoid(s:repl_win) != 1
		echom "nodeinspect - can't start repl"
		return
	endif
    " find an open port
	let cmd_line = []
	call add(cmd_line, 'node')
	call add(cmd_line, a:plugin_path . "/node-inspect/find_port.js")
    let a:session['bridge_port'] = system(cmd_line)
    if v:shell_error == -1
        return 1
    endif
	" prepare call command line
	let cmd_line = []
	call add(cmd_line, 'node')
	call add(cmd_line, a:plugin_path . "/node-inspect/cli.js")
	call add(cmd_line, a:session['bridge_port'])
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
		let s:term_id = termopen(cmd_line, {'on_exit': 'OnNodeInspectExit', 'cwd': a:session["cwd"]})
		if s:term_id == -1
			return 1
		endif
	else
		let s:term_id = term_start(cmd_line, {'curwin': 1, 'exit_cb': 'OnNodeInspectExit', 'term_finish': 'close', 'term_kill': 'kill', 'cwd': a:session["cwd"]})
		" 0 will be returned only if the window opening fails
		if s:term_id == 0
            " to keep similar with nvim
            let s:term_id = -1
			return 1
		endif
	endif
	sleep 200m
    " set the cursor at the bottom to enable scrolling
    execute "norm G"
    " execute any external jobs
    call s:startExternalJobs(a:session)
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
        let s:term_id = -1
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

