var exec = require('cordova/exec');

let VMPlayerHotCodeModule = 'vmplayerHotCode';

function callAll() {
    let all = Array.prototype.slice.call(arguments);
    return function () {
        let result = Array.prototype.slice.call(arguments);
        for (let i = 0; i < all.length; i++) {
            if (typeof all[i] === 'function') {
                all[i].apply(null, result);
            }
        }
    }
}

var plugin = {
    revertToReleaseCode: function (options, success, error) {
        return new Promise((resolve, reject) => {
            success = callAll(success, resolve);
            error = callAll(error, reject);
            exec(success, error, VMPlayerHotCodeModule, 'revertToReleaseCode', [options]);
        });
    },

    getHotCodeConfig: function (success, error) {
        return new Promise((resolve, reject) => {
            success = callAll(success, resolve);
            error = callAll(error, reject);
            exec(success, error, VMPlayerHotCodeModule, 'getHotCodeConfig', []);
        });
    },

    setHotCodeConfig: function (config, success, error) {
        // To allow override (ie not having to specify all the options) we must retrieve current config first, then merge in the new config
        return new Promise(async (resolve, reject) => {
            success = callAll(success, resolve);
            error = callAll(error, reject);
            let currentConfig = await this.getHotCodeConfig();
            let mergedConfig = Object.assign(currentConfig, config);
            exec(success, error, VMPlayerHotCodeModule, 'setHotCodeConfig', [mergedConfig]);
        });
    }
}

// LUCIFER-968 We request this dummy localhost URL to make sure our HotcodePlugin Auth cookie is refreshed to make sure it never expires
const localHostUrl = window.location.protocol + '//' + window.location.hostname + (window.location.port ? ':' + window.location.port : '') + '/plugins/cordova-vmplayer-hotcode/www/auth_refresh_dummy.txt';
console.log('cordova-vmplayer-hotcode: Auth cookie refresh URL:', localHostUrl);

window.setInterval(() => {
    fetch(localHostUrl)
        .then(() => {
            console.log('cordova-vmplayer-hotcode: Auth cookie refreshed');
        })
        .catch(() => {
            console.log('cordova-vmplayer-hotcode: Auth cookie refresh failed');
        });
}, 1000 * 60 * 5); // 5 minutes

module.exports = plugin;
