" Global tree variable
let s:tree = []
let s:buf_to_tree = {}
let s:buffer_width = 0
let s:initialLine = v:true
let s:buffer = -1
let s:callback = v:null

" Function to create (initialize) the tree
" Receives a
" buffer - buffer id to create the tree in
" callback - function to call when an item is clicked
" width - width of the buffer to display the values (buffer width will
" set the values at rightmost)
" Callback description:
" 	Receives the clicked node as a paramter. The function should return
" 	a boolean indicating wherever to supress the default action.
function! nodeinspect#treectl#Create(buffer, callback = v:null, width = 20)
	let s:tree = []
	let s:buffer = a:buffer
	let s:callback = a:callback
	let s:bufferWidth = a:width
endfunction

" Function to insert an item into the tree
" Receives an object with
" text - item's text. Required
" value - item's value, if case of a leaf node. omitting the value indicating
" a parent node
" description - item's description. will be shown beside the name
" user - user data. will be passed back with the onClick callback
" open - in case of a parent node, wherever to open the children. v:false by default
" parent - parent node. pass parent to insert the item as a child
function! nodeinspect#treectl#InsertItem(parent, item)
	let itemValue = ''
	let isParent = v:true
	if has_key(a:item, 'value')
		let itemValue = a:item['value']
		let isParent = v:false
	endif
	let userValue = ''
	if has_key(a:item, 'user')
		let userValue = a:item['user']
	endif
	let openValue = v:false
	if has_key(a:item, 'open')
		let openValue = a:item['open']
	endif
	let description = ''
	if has_key(a:item, 'description')
		let description = a:item['description']
	endif
  let node = {'text': a:item['text'], 'value': itemValue, 'user': userValue, 'open': openValue, 'isParent': isParent, 'description': description}
	" add children in case of a parent
	if (isParent)
		let node['children'] = []
	else
		let node['children'] = v:null
	endif
  if a:parent is v:null
    call add(s:tree, node)
  else
		if !has_key(a:parent, 'children')
			echoerr 'Attempt to insert a child to a leaf node'
			return
		endif
    call add(a:parent['children'], node)
  endif
	return node
endfunction


function! DisplayLeftRight(leftWord, rightWord)
    let l:width = s:buffer_width
    let l:spacing = l:width - len(a:leftWord) - len(a:rightWord)
    if l:spacing < 1
        let l:spacing = 2
    endif
    let l:line = a:leftWord . repeat(' ', l:spacing) . a:rightWord
    return l:line
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
	elseif type(a:value) != v:t_number && type(a:value) != v:t_float && type(a:value) != v:t_string
			let dispValue = string(a:value)
	else
		let dispValue = a:value
	endif
	return dispValue
endfunction



" Recursive function to render tree nodes
function! s:RenderTree(nodes, prefix)
	if a:nodes is v:null
		return
	endif
  for node in a:nodes

		let parentPrefix = ''
		if node['isParent']
			if has_key(node, 'open') && node['open']
				let parentPrefix = '- '
			else
				let parentPrefix = '+ '
			endif
		endif

		if !node['isParent']
			let dispValue = s:GetValue(node['value'])
			let dispText = DisplayLeftRight(a:prefix . parentPrefix . node['text'] . ' ' . node['description'], dispValue)
		else
			let dispText = a:prefix . parentPrefix . node['text'] . ' ' . node['description']
		endif
		" replace the initial line, otherwise append
		if s:initialLine == v:true
			call setbufline(s:buffer, 1 , dispText)
			let s:initialLine = v:false
		else
			call appendbufline(s:buffer, '$', dispText)
		endif
		" add mapping so a node can be easily be found
		let curLine = string(line('$', bufwinid(s:buffer)))
		let s:buf_to_tree[curLine] = node
    if node['open']
      call s:RenderTree(node['children'], a:prefix . ' ')
    endif
  endfor
endfunction

" Function to render the tree to a buffer. width is the buffer width, if
" available.
function! nodeinspect#treectl#Render()
	let currentLineNumber = line('.')
  call setbufvar(s:buffer, '&modifiable', 1)
	" clear all
	if has('nvim')
		call nvim_buf_set_lines(s:buffer, 0, -1, v:false, [])
	else
		call delbufline(s:buffer, 1, '$')
	endif
	let s:initialLine = v:true
	let s:buf_to_tree = {}
  call s:RenderTree(s:tree, '')
	execute "nnoremap <buffer> <CR> :call OnWatchRequest()<CR>"
  call setbufvar(s:buffer, '&modifiable', 0)
	call cursor(currentLineNumber, 1)
endfunction


function! OnWatchRequest(...)
	let lineNum = string(line('.'))
	let node = s:buf_to_tree[lineNum]
	if s:callback != v:null
		let callbackVal = call(s:callback, [node])
		" in case the callback returns true, supress the default behaviour
		if callbackVal is v:true
			return
		endif
	endif
	if node['isParent'] 
		let node['open'] = !node['open']
		call nodeinspect#treectl#Render()
	endif
endfunction
