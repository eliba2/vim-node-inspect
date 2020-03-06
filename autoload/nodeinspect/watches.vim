let s:inspect_win = -1
let s:watches = {}


function! OnTextModification()
	call s:RecalcWatchesKeys()
	"call s:Draw()
	call s:updateWatches()
endfunction


function s:Draw()
	let cur_win = win_getid()
	let gotoResult = win_gotoid(s:inspect_win)
	if gotoResult == 1
		" execute "set modifiable"
		execute "%d"
		" execute "set nomodifiable"
		" loop here over all watches and update their values
		for watch in keys(s:watches)
			call append(getline('$'), watch."      ".s:watches[watch])
		endfor
		" endofupdate
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
			if len(line) != 0
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
	if len(keys(s:watches)) > 0
		let watchesJson = json_encode(s:watches)
		call nodeinspect#utils#SendEvent('{"m": "nd_updatewatches", "watches":' . watchesJson . '}')
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

function! nodeinspect#watches#CreateWatchWindow(startWin)
	execute "rightb ".winwidth(a:startWin)/3."vnew | setlocal nobuflisted buftype=nofile bufhidden=wipe noswapfile statusline=Watches"
	let s:inspect_win = win_getid()
	set nonu
	autocmd InsertLeave <buffer> noautocmd call OnTextModification()
	autocmd BufLeave <buffer> noautocmd call OnTextModification()
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


