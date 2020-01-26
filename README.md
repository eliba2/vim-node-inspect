# vim-node-inspect
Interactive node debugger for (n)vim.

## Description
This plugin adds node debugging capabilities to vim with interactive CLI. Under the hood it wraps node-inspect *(https://github.com/nodejs/node-inspect)*.


[![asciicast](https://asciinema.org/a/292793.svg)](https://asciinema.org/a/292793)

## Requirements
Vim8.1/Neovim.

## Installation
Install with your favorite package manager. For vim-plug its
```
Plug 'eliba2/vim-node-inspect'
```

## How to use
Either start debugging a local js file (via NodeInspectStart or NodeInspectRun) or connect to a running instance using NodeInspectConnect. In the later case the target must start with --inspect (e.g. node --inspect server.js).
To run arbitrary js code in the debugger use "exec".


The following commands are available:

NodeInspectStart - Starts debugger, paused

NodeInspectRun - Continue / Start and run immediatly

NodeInspectConnect host:port - Connect to a running instance

NodeInspectStepOver - Step over

NodeInspectStepInto - Step into

NodeInspectStepOut - Step out

NodeInspectStop - Stop debugging (and kill the node instance)

NodeInspectToggleBreakpoint - Toggle breakpoint

NodeInspectRemoveAllBreakpoints - Removes all breakpoints


There are no default bindings; the following is added for convinience:
```
nnoremap <silent><F4> :NodeInspectStart<cr>
nnoremap <silent><F5> :NodeInspectRun<cr>
nnoremap <silent><F6> :NodeInspectConnect("127.0.0.1:9229")<cr>
nnoremap <silent><F7> :NodeInspectStepInto<cr>
nnoremap <silent><F8> :NodeInspectStepOver<cr>
nnoremap <silent><F9> :NodeInspectToggleBreakpoint<cr>
nnoremap <silent><F10> :NodeInspectStop<cr>
```

## Connecting to a running container

You'll need to configure the local and remote directories when connecting to a remote host or the local instance will set the wrong breakpoints locations. This can be set by creating a configuration file "vim-node-config.json" in the relevant project' directory, as follows:
```
{
  "localRoot": "/Users/eli/projects/my-test-project",
  "remoteRoot": "/app"
}
```
Make sure to use full paths.

## Remarks
In beta. Means its useful; things may change or fail.
**NOT** tested on Windows.

## License
Whatever node-inspect is.

