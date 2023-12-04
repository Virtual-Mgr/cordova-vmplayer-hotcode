var exec = require('cordova/exec');

let VMPlayerHotCodeModule = 'vmplayerHotCode';

let plugin = {
    startServer: function (options, success, error) {
        window.setTimeout(() => {
            success('http://localhost');
        })
    },
    stopServer: function (success, error) {
        window.setTimeout(success, 0);
    },
    getURL: function (success, error) {
        window.setTimeout(() => {
            success('http://localhost');
        })
    },
    getLocalPath: function (success, error) {
        window.setTimeout(() => {
            success('/www');
        })
    },
    setSpaConfig: function (config, success, error) {
        exec(success, error, VMPlayerHotCodeModule, 'setSpaConfig', [config])
    }
}

module.exports = plugin;