// Only installed in Mica's explicitly marked, bundled DevTools frontend.
(() => {
  const send = (kind, value) => __slSend(JSON.stringify({kind, value}));
  const preferences = () => {
    try { return JSON.parse(localStorage.getItem('searchlight-devtools') || '{}'); }
    catch { return {}; }
  };
  const store = data => { try { localStorage.setItem('searchlight-devtools', JSON.stringify(data)); } catch {} };
  const dockStates = new Set(['bottom', 'right', 'left', 'undocked']);
  const initialDockSide = dockStates.has(globalThis.__slInitialDockSide) ? globalThis.__slInitialDockSide : 'bottom';
  let syncingDockSide = false;
  const installFrontendLayout = async () => {
    const UI = await import('devtools://devtools/bundled/ui/legacy/legacy.js');
    const fit = () => {
      // Chrome normally places the inspected page inside this root split.
      // Mica already owns that page surface outside the DevTools renderer.
      let parent = UI.InspectorView.InspectorView.instance().parentWidget();
      while (parent && !(parent instanceof UI.SplitWidget.SplitWidget)) parent = parent.parentWidget();
      if (parent) parent.hideMain();
    };
    const controller = UI.DockController.DockController.instance();
    controller.addEventListener(UI.DockController.Events.DOCK_SIDE_CHANGED, fit);
    controller.addEventListener(UI.DockController.Events.AFTER_DOCK_SIDE_CHANGED, fit);
    fit();
  };
  // Mica's saved placement wins over a stale frontend preference on creation.
  store({...preferences(), currentDockState: JSON.stringify(initialDockSide)});
  const host = {
    isHostedMode: () => false,
    platform: () => 'mac',
    sendMessageToBackend: value => send('protocol', value),
    getPreferences: callback => callback(preferences()),
    getHostConfig: callback => {
      // Bind Chromium's web-host fallbacks to a real instance: some use private
      // fields and cannot be copied as unbound prototype methods.
      import('devtools://devtools/bundled/core/host/host.js').then(Host => {
        const fallback = new Host.InspectorFrontendHost.InspectorFrontendHostStub();
        fallback.events = host.events;
        for (const name of Object.getOwnPropertyNames(Object.getPrototypeOf(fallback))) {
          if (name !== 'constructor' && !provided.has(name) && typeof fallback[name] === 'function') host[name] = fallback[name].bind(fallback);
        }
        callback({});
      }).catch(error => { console.error('DevTools host initialization', error); callback({}); });
    },
    setPreference: (name, value) => store({...preferences(), [name]: value}),
    removePreference: name => { const data = preferences(); delete data[name]; store(data); },
    clearPreferences: () => store({}),
    loadCompleted: async () => {
      InspectorFrontendAPI.setUseSoftMenu(true);
      await installFrontendLayout();
      send('ready');
    },
    closeWindow: () => send('close'),
    bringToFront() {},
    setIsDocked: (docked, callback) => {
      const side = docked ? [...dockStates].find(side => side !== 'undocked' && document.body.classList.contains(side)) : 'undocked';
      if (side && !syncingDockSide) send('dock', side);
      callback();
    },
    setInspectedPageBounds() {},
    inspectedURLChanged() {},
    getSyncInformation: callback => callback({isSyncActive: false, arePreferencesSynced: false}),
    copyText: value => send('copy', value),
    openInNewTab: value => send('open', value),
    recordEnumeratedHistogram() {}, recordPerformanceHistogram() {}, recordCountHistogram() {},
    recordUserMetricsAction() {}, registerPreference() {},
    setWhitelistedShortcuts() {}, setEyeDropperActive() {},
    isUnderTest: () => false,
    zoomFactor: () => 1,
    zoomIn() {}, zoomOut() {}, resetZoom() {},
    setDevicesDiscoveryConfig() {}, setDevicesUpdatesEnabled() {},
    setConnectionReady() {}, readyForTest() {},
    dispatchProtocolMessage: value => send('protocol', value),
  };
  const provided = new Set(Object.keys(host));
  Object.defineProperty(globalThis, 'InspectorFrontendHost', {get: () => host, set() {}, configurable: false});
  globalThis.__slSetDockSide = async side => {
    if (!dockStates.has(side)) return;
    const UI = await import('devtools://devtools/bundled/ui/legacy/legacy.js');
    const controller = UI.DockController.DockController.instance();
    syncingDockSide = true;
    try { if (controller.dockSide() !== side) controller.setDockSide(side); }
    finally { syncingDockSide = false; }
  };
  globalThis.__slInspect = async (x, y) => {
    const SDK = await import('devtools://devtools/bundled/core/sdk/sdk.js');
    for (let attempt = 0; attempt < 40; attempt++) {
      const target = SDK.TargetManager.TargetManager.instance().primaryPageTarget();
      if (target) {
        await target.runtimeAgent().invoke_evaluate({expression: `inspect(document.elementFromPoint(${x},${y}))`, includeCommandLineAPI: true});
        return;
      }
      await new Promise(resolve => setTimeout(resolve, 50));
    }
  };
})();
