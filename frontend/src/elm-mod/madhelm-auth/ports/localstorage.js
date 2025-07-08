export function allState() {
  let obj = {};
  for (var n=0; n <localStorage.length; n++) {
    let key = localStorage.key(n);
    let val = localStorage.getItem(key);
    obj[key] = val;
  }
  return obj
}

export function addLocalStoragePorts(app) {
  app.ports.storeCache.subscribe(function([key, val]) {
    if (val === null) {
      localStorage.removeItem(key);
    } else {
      localStorage.setItem(key, JSON.stringify(val));
    }

    // Report that the new session was stored successfully.
    setTimeout(function() { app.ports.onStoreChange.send([key, val]); }, 0);
  });

  // Whenever localStorage changes in another tab, report it if necessary.
  window.addEventListener("storage", function(event) {
    if (event.storageArea === localStorage) {
      app.ports.onStoreChange.send([event.key, event.newValue]);
    }
  }, false);
}
