# vim-node-inspect
Interactive node debugger for (n)vim.

## Description
This plugin adds node debugging capabilities to vim with interactive CLI. Under the hood it wraps a modified version of node-inspect *(https://github.com/nodejs/node-inspect)*.


[![asciicast](https://asciinema.org/a/NOCL8Fc3LcQjVDD0CIR08I698.svg)](https://asciinema.org/a/NOCL8Fc3LcQjVDD0CIR08I698)

## Requirements
Vim**8.1+**/Recent Neovim.
Node in the path.

## Installation
Install with your favorite package manager. For vim-plug its
```
Plug 'eliba2/vim-node-inspect'
```

## How to use
Either start a node script or attach to an already running script. Both can be done manually (NodeIndpectStart/NodeInspectRun) or using the configuration file vim-node-config.json. The later is encouraged.

### Starting Manually ###

Either start debugging a local js file (via NodeInspectStart or NodeInspectRun) or connect to a running instance using NodeInspectConnect. In the later case the target must start with --inspect (e.g. node --inspect server.js). If a configuration file is present, it takes precedence.

### Using the configuration file ###

Use the configuration file to define the starting method. Create a file named "vim-node-config.json" in the current working directory. The format is json, and the available options are:

**"request"** - either "launch" or "attach". The former is for executing a script. The second is for connecting to a running node instance.

**"program"** - in the case of "launch", this is the script's filename and must be present.

A sample configuration for launch would be:
```
{
	"request": "launch",
	"program": "/Users/eli/Tests/test.js"
}
```


**"address"** - in the case of "attach", this is the address to connect to. Can be omitted, in this case it defaults to "127.0.0.1".

**"port"** - in the case of "attach", this is the port to connect to. Must be present.

A sample configuration for attach would be:

```
{
	"request": "attach",
	"port": 9229
}
```

## Available Commands

The following commands are available:

**NodeInspectStart** - Starts debugger, paused

**NodeInspectRun** - Continue / Start and run immediatly

**NodeInspectConnect** host:port - Connect to a running instance

**NodeInspectStepOver** - Step over

**NodeInspectStepInto** - Step into

**NodeInspectStepOut** - Step out

**NodeInspectStop** - Stop debugging (and kill the node instance)

**NodeInspectToggleBreakpoint** - Toggle breakpoint

**NodeInspectRemoveAllBreakpoints** - Removes all breakpoints

**NodeInspectAddWatch** - Add the word under the cursor to the watch window


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

## Breakpoints

The plugin saves your breakpoint's locations between Vim sessions. Once the plugin is started it will try and re-activate the breakpoints for the current location, that's for all the breakpoints which root in the current working directory.

Note breakpoints are triggered through Vim and resolved in node, so resolved locations might differ from the triggered ones. 
The breakpoints signs appear in the resolved locations.


## Watches

There are two ways to add a watch. One is to use the *NodeInspectAddWatch* command which will add the word under the cursor as a watch. The other is by directly editing the watch window: this will resolve the watches, one per line.
Remove a watch by deleting it from the watch window.


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
MIT.

