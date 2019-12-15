import sys
import json
import vim
import socket
import os
import os.path
# from threading import Thread, active_count
import threading 
try:
   import queue
except ImportError:
   import Queue as queue



# var fs = require('fs');
# const net = require('net');
_plugin = None
_started = False
sign_id = 2
brkpt_sign_id = 3
sign_group = 'visgroup'
sign_cur_exec = 'vis'
sign_brkpt = 'visbkpt'
start_win = None
repl_win = None
repl_buf = None
term_id = None
ipcServer = None
socket_path = '/tmp/node-inspect.sock'
breakpoints = []
initialted = False
connection = None
callback_queue = queue.Queue()
pythonExecTimer = None


def NodeInspectExecLoop():
    while True:
        try:
            callback = callback_queue.get(False)
        except queue.Empty:
            break
        if callback != None:
            callback()


def _addBrkptSign(file, line):
    id = brkpt_sign_id + 1
    vim.command('sign place %d line=%s name=%s group=%s file=%s' % (id, line, sign_brkpt, sign_group, file))
    return id

def _removeBrkptSign(id, file):
    vim.command('sign unplace %d group=%s file=%s' % (id, sign_group, file))

def _addSign(file, line):
    vim.command('sign place %d line=%d name=%s group=%s file=%s' % (sign_id, line, sign_cur_exec, sign_group, file))

def _removeSign():
    # print 'sign unplace %i group=%s' % (sign_id, sign_group)
    # vim.command('sign unplace %i group=%s' % (sign_id, sign_group))
    # vim doesn't have the group... should check w nvim.
    vim.command('sign unplace %d group=%s' % (sign_id, sign_group))


def _sendEvent(msg):
    s = json.dumps(msg)
    # ipcServer.send(s.encode())
    connection.sendall(s.encode())
    # print ("sending msg")
    # global.socket_client.write(JSON.stringify(msg))


def _onDebuggerStopped(m):
    # print ("==> stopped on "+m["file"])
    # check if file exists
    if os.path.isfile(m['file']) == False:
    # probably an inline module, anyway, can't do anything with it
        sys.stderr.write("can't open " + m['file'] + "\n")
        return
    vim.command('edit %s' % m['file'])
    vim.command('%d' % m['line'])
    _addSign(m['file'], m['line'])




def _startServer(start_running):
    global connection
    global ipcServer
    global queue
    initial_stop = True
    # This server listens on a Unix socket at /var/run/mysocket
    ipcServer = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    ipcServer.bind(socket_path)

    while True:
        # wait 4 connection
        ipcServer.listen(1)
        try:
            connection, client_address = ipcServer.accept()
        except Exception:
            break
        try:
            while True:
                try:
                    data = connection.recv(2048)
                except Exception:
                    break
                # print >>sys.stderr, 'received "%s"' % data
                if data:
                    msg = json.loads(data)
                    if msg['m'] == 'nd_stopped':
                        # in case the user starts the debugger running
                        if initial_stop == True:
                            callback_queue.put(
                                _sendEvent({
                                    'm': 'nd_setbreakpoints',
                                    'breakpoints': breakpoints
                                })
                            )
                            if start_running == True:
                                callback_queue.put(_sendEvent({ 'm': 'nd_continue' }))
                            else:
                                callback_queue.put(lambda: _onDebuggerStopped(msg))
                                initial_stop = False
                        else:
                            callback_queue.put(lambda: _onDebuggerStopped(msg))
                    else:
                        sys.stderr.write('received unknown msg from inspect: '+msg);
                # else:
                #     sys.stderr.write("no more data from \n" + client_address + "\n")
            # break
        finally:
            # Clean up the connection
            connection.close()







def _startNodeInspector(start_running = False):
    global _started
    global pythonExecTimer
    try:
        os.unlink(socket_path)
    except OSError:
        if os.path.exists(socket_path):
            raise
    # initial
    _started = True
    # get working win
    # start_win = vim.current.window
    start_win = vim.eval("winnr()")
    # repl_win = vim.command('winnr')
    # repl_buf = vim.command('bufnr %')
    # get filename
    f = vim.eval("expand('%:p')")
    # print ("==>> filename %s" % f)
    # create split for repl
    vim.command('bo 10new')
    # repl_win = vim.current.window
    repl_win = vim.eval("winnr()")
    # repl_buf = vim.current.buffer
    repl_buf = vim.eval("bufnr('%')")

    vim.command('set nonu')
    # create terminal, nvim node
    # vim.command('call termopen("node")')
    termcmd = '''call termopen ("node node-inspect/cli.js %s", {'on_exit': 'OnNodeInspectExit'})'''%f
    # print(termcmd)
    term_id = vim.command(termcmd)
    # term_id = vim.command("call termopen (\"node node-inspect/cli.js %(f) {'on_exit': 'OnNodeDebuggerExit'}\"")
    repl_buf = vim.current.buffer
    # switch back to start buf
    vim.command('%s.wincmd w'%start_win)
    # start the server
    serverThread = threading.Thread(target=_startServer, args=(start_running,))
    serverThread.start()

    # detect changes
    pythonExecTimer = vim.eval("timer_start(500, 'NodeInspectTimerCallback', {'repeat': -1})")


def initNodeInspect():
    # define the dbg 
    vim.command('sign define %s text=>> texthl=Select' % sign_cur_exec);
    #  define brpt sign
    vim.command('sign define %s text=() texthl=SyntasticErrorSign' % sign_brkpt);

def _isRunning():
    global _started
    if _started==False:
        vim.command('echo "debugger not running"')
    return _started

#####################
### API

# start debugger and execute 
def NodeInspectStartRun():
    global _started
    global initialted
    if _started == True:
        vim.command('echo "debugger already running"')
        return
    if initialted == False:
        initNodeInspect()
        initialted = True
    _removeSign()
    _startNodeInspector(False)
# step over (next)
def NodeInspectStepOver():
    # if _isRunning() == False:
        # return
    _removeSign()
    _sendEvent({'m': 'nd_next'})
# continue
def NodeInspectContinue():
    # if _isRunning()==False:
        # return
    _removeSign();
    _sendEvent({'m': 'nd_continue'})
# step into
def NodeInspectStepInto():
    # if _isRunning()==False:
        # return
    _removeSign()
    _sendEvent({'m': 'nd_into'})
# stop debugging
def NodeInspectStop():
    # if _isRunning()==False:
        # return
    _removeSign()
    _sendEvent({'m': 'nd_kill'})
# step out
def NodeInspectStepOut():
    # if _isRunning()==False:
        # return
    _removeSign();
    _sendEvent({'m': 'nd_out'})
# add breakpoint
def NodeInspectToggleBreakpoint():
    global _started
    file = vim.eval("expand('%:.')")
    line = vim.eval("line('.')")
    # check if its already set. if so, remove it
    foundIndex = -1
    for index, item in enumerate(breakpoints):
        if item['file'] == file and item['line'] == line:
            foundIndex = index
            break
    if foundIndex != -1:
        # this breakpoint exists, remove it
        _removeBrkptSign(breakpoints[foundIndex]['id'], breakpoints[foundIndex]['file']);
        del breakpoints[foundIndex]
        if _started == True:
            _sendEvent({
                'm': 'nd_removebrkpt',
                'file': file,
                'line': line
            })
    else:
        # breakpoint doesn't exists, add it
        id = _addBrkptSign(file, line)
        breakpoints.append({
            'file': file,
            'line': line,
            'id': id
        })
        if _started == True:
            _sendEvent({
                'm': 'nd_addbrkpt',
                'file': file,
                'line': line
            })



# on debuggger exit
def NodeInspectCleanup():
    global connection
    global pythonExecTimer
    global _started
    vim.command('sign unplace %d group=%s' % (sign_id, sign_group))
    if pythonExecTimer != None:
        vim.eval("timer_stop(%s)" % pythonExecTimer)
        pythonExecTimer = None
    connection.close()
    ipcServer.close()
    _started = False
    vim.command('echo "NodeInspectExited"')


# start node inspect, paused
def NodeInspectStart():
    global initialted
    global _started
    if initialted == False:
        initNodeInspect()
        initialted = True
    _removeSign()
    if _started == True:
        _sendEvent("{'m': 'nd_restart'}")
        return
    _startNodeInspector(False)



def initPythonModule():
    if sys.version_info[:2] < (2, 4):
        vim.command('let s:has_supported_python = 0')

