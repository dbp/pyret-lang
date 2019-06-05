const setup = require("./setup.ts");
const runner = require("./runner.ts");
const pyretApi = require("./pyret-api.ts");

const fs = setup.BrowserFS.BFSRequire("fs");
const worker = setup.worker;

const input = <HTMLInputElement>document.getElementById("program");
const compile = document.getElementById("compile");

compile.onclick = function() {
  fs.writeFileSync("./projects/program.arr", input.value);
  let message = {
    _parley: true,
    options: {
      program: "program.arr",
      "base-dir": "/projects",
      "builtin-js-dir": "/prewritten/",
      checks: "none",
    }
  };
  worker.postMessage(message);
  console.log('Message posted to worker');
};

worker.onmessage = function(e) {
  try {
    var msgObject = JSON.parse(e.data);

    var tag = msgObject["tag"];
    if (tag !== undefined) {
      if (tag === "log") {
        setup.workerLog(msgObject.data);
      } else if (tag === "error") {
        setup.workerError(msgObject.data);
      } else {
        setup.workerLog(msgObject.data);
      }
    } else {
      setup.workerLog(e.data);
    }
  } catch(error) {
    setup.workerLog(e.data);
  }
};