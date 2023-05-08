const { spawn } = require('child_process')

class InspectChild {
  constructor () {
    if (!InspectChild.instance) {
      InspectChild.instance = this
      this.child = null
    }
    return InspectChild.instance
  }

  init (target) {
    process.on('uncaughtException', (e) => {
      console.error('Cant start nodejs-inspect')
      console.error(e.message)
      console.error(e.stack)
    })

    /* starting nodejs in case of launch */
    this.child = spawn('node', ['--inspect-brk=9222', target])

    this.child.stdout.on('data', (data) => {
      console.log(`>> ${data}`)
    })

    this.child.stderr.on('data', (data) => {
      console.error(`!> ${data}`)
    })

    this.child.on('close', (code) => {
      console.log(`!!>${code}`)
    })
  }

  close = () => {
    if (this.child) {
      this.child.kill()
      this.child = null
    }
  }
}

module.exports = new InspectChild()
