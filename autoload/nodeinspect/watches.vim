let s:inspect_win = -1
let s:inspect_buf = -1
let s:watches = {}
let s:auto_watches = {}
let s:auto_sign = "A "

function! OnTextModification()
	call s:RecalcWatchesKeys()
	"call s:Draw()
	"call s:updateWatches()
endfunction


function! s:GetValue(value)
	if a:value is v:null
		let dispValue = 'null'
	elseif a:value is v:true || a:value is v:false
		if a:value
			let dispValue = 'true'
		else
			let dispValue = 'false'
		endif
	else
		let dispValue = string(a:value)
	endif
	return dispValue
endfunction




" Recursive function to format the data
function! s:FormatData(data, prefix)
		let lines = []
		for key in keys(a:data)
				let value = a:data[key]
				if value['type'] == 'object' || value['type'] == 'array'
						" Object or array, use '+'/'-' sign and recursive call
						if (has_key(value, 'value'))
							let prefixSign = a:prefix . '- '
							if type(value['value']) == v:t_dict
								if value['type'] == 'object'
									let postfixSign = ' {}'
								else
									let postfixSign = ' []'
								endif
								call add(lines, prefixSign . key . postfixSign)
								let childLines = s:FormatData(value['value'], a:prefix . '  ')
								call extend(lines, childLines)
							else
								call add(lines, a:prefix . key . '  '  . s:GetValue(value['value']))
							endif
						else
							call add(lines, a:prefix . '+ ' . key )
						endif
				else
						" Primitive value, display as is
						if has_key(value, 'value')
							call add(lines, a:prefix . key . '  ' . s:GetValue(value['value']))
						endif
				endif
		endfor
		return lines
endfunction



function s:Draw()
	let cur_win = win_getid()
	let gotoResult = win_gotoid(s:inspect_win)
	if gotoResult == 1
    call setbufvar(s:inspect_buf, '&modifiable', 1)
		" execute "set modifiable"
		execute "%d"
		" execute "set nomodifiable"
		" loop here over all watches and update their values
		"for watch in keys(s:watches)
			"call append(getline('$'), watch."      ".s:watches[watch])
		"endfor
		"for watch in keys(s:auto_watches)
			"call append(getline('$'), s:auto_sign . watch."      ".s:auto_watches[watch])
		"endfor
		" endofupdate


		"let data = json_decode(s:auto_watches)
		let data = s:auto_watches
    let bufferContent = s:FormatData(data, '')
  	call setbufline(s:inspect_buf, 1, bufferContent)
    call setbufvar(s:inspect_buf, '&modifiable', 0)

    " Prepare the content for the buffer

		call win_gotoid(cur_win)
		" execute "set modifiable"
	endif
endfunction



function s:RecalcWatchesKeys()
	let cur_win = win_getid()
	let gotoResult = win_gotoid(s:inspect_win)
	if gotoResult == 1
		let s:watches = {}
		" execute "set modifiable"
		execute 'normal! 1G'
		let currentLine = 1
		let totalLines = line('$')
		while currentLine <= totalLines
			let line = trim(getline(currentLine))
			" don't recalc autos
			if len(line) != 0 && line[:(len(s:auto_sign)-1)] != s:auto_sign
				let firstWord = split(line)[0]	
				let s:watches[firstWord] = "n/a"
			endif
			let currentLine += 1
		endwhile
		" execute "set nomodifiable"
		call win_gotoid(cur_win)
		" execute "set modifiable"
	endif
endfunction


function! s:updateWatches()
	" should be called only when available
	if nodeinspect#GetStatus() == 1
		if len(keys(s:watches)) > 0
			let watchesJson = json_encode(s:watches)
			call nodeinspect#utils#SendEvent('{"m": "nd_updatewatches", "watches":' . watchesJson . '}')
		endif
	endif
endfunction


function! s:addToWatchWin(watch)
	if len(a:watch) > 0
		let cur_win = win_getid()
		let gotoResult = win_gotoid(s:inspect_win)
		if gotoResult == 1
			call append(getline('$'), a:watch)
			call s:RecalcWatchesKeys()
			call s:updateWatches()
			call win_gotoid(cur_win)
		endif
	endif
endfunction


function! nodeinspect#watches#HideWatchWindow()
	if s:inspect_win != -1 && win_gotoid(s:inspect_win) == 1
		execute "hide"
	endif
endfunction


function! nodeinspect#watches#KillWatchWindow()
	if s:inspect_win != -1 && win_gotoid(s:inspect_win) == 1
		execute "bd!"
		let s:inspect_buf = -1
	endif
endfunction


function! nodeinspect#watches#OnWatchesResolved(watches)
	if len(keys(a:watches)) > 0
		for watch in keys(a:watches)
			if has_key(s:watches, watch) == 1
				let s:watches[watch] = a:watches[watch]
			endif
		endfor
		noautocmd call s:Draw()
	endif
endfunction

" will return the watches object, key - value
function! nodeinspect#watches#GetWatches()
	return s:watches
endfunction


" will return the watches object, key : 1
" used to save watches session
function! nodeinspect#watches#GetWatchesKeys()
	let watchKeys = {}
	if len(keys(s:watches)) > 0
		for watch in keys(s:watches)
			let watchKeys[watch] = 1
		endfor
	endif
	return watchKeys
endfunction


function! nodeinspect#watches#GetWinId()
	return s:inspect_win
endfunction


function! nodeinspect#watches#Draw()
	call s:Draw()
endfunction


function! nodeinspect#watches#UpdateWatches()
	call s:updateWatches()
endfunction

" creates or re-creates the watch window
function! nodeinspect#watches#ShowWatchWindow(startWin)
	if s:inspect_buf == -1 || bufwinnr(s:inspect_buf) == -1
		if s:inspect_buf == -1
			if g:nodeinspect_window_pos == 'right' || g:nodeinspect_window_pos == 'left'
				execute winheight(a:startWin)/5*2."new | setlocal nobuflisted buftype=nofile noswapfile statusline=Watches"
			else
				" bottom/ dk
				execute "rightb ".winwidth(a:startWin)/5*2."vnew | setlocal nobuflisted buftype=nofile noswapfile statusline=Watches"
			endif
			let s:inspect_buf = bufnr('%')
			set nonu
			autocmd InsertLeave <buffer> noautocmd call OnTextModification()
			autocmd BufLeave <buffer> noautocmd call OnTextModification()
		else
			if g:nodeinspect_window_pos == 'right' || g:nodeinspect_window_pos == 'left'
				execute winheight(a:startWin)/5*2."new | buffer ". s:inspect_buf
			else
				execute "rightb ".winwidth(a:startWin)/5*2."vnew | buffer ". s:inspect_buf
			endif
		endif
		let s:inspect_win = win_getid()
	endif
endfunction


" add watches, in a bulk
function! nodeinspect#watches#AddBulk(watches)
	if len(keys(a:watches)) > 0
		for watch in keys(a:watches)
			"echom "restoring watch ".watch
			let s:watches[watch] = 'n/a'
		endfor
	endif
endfunction


" add the word under the cursor to the watch window
function! nodeinspect#watches#AddCurrentWordAsWatch()
	let wordUnderCursor = expand("<cword>")
	call s:addToWatchWin(wordUnderCursor)
endfunction


" return 1 if the watch window is visible
function nodeinspect#watches#IsWindowVisible()
	if s:inspect_buf == -1 || bufwinnr(s:inspect_buf) == -1
		return 0
	else
		return 1
	endif
endfunction


function nodeinspect#watches#ShowTokens(tokens)
	let s:auto_watches = a:tokens
	call s:Draw()
endfunction


