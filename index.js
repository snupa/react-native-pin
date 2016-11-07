'use strict';

import {NativeModules} from 'react-native';

var RNPinch = {
  fetch: function (url, obj) {
    return new Promise((resolve, reject) => {
      NativeModules.RNPinch.fetch(url, obj, (err, res) => {
        if(err) return reject(err);
        resolve(res);
      });
    });
  }
};


module.exports = RNPinch;
