// Safari stand-ins for the Chrome-only APIs the :\ARCHITECT\ extension uses. Loaded first in every
// extension page and in the background. Chrome is unaffected: this file only ships in the Safari build.
//
//  - sidePanel: Safari has none; the toolbar button opens src/panel.html as a popup instead.
//  - contextMenus: missing on iOS; becomes a no-op there.
//  - storage.session: falls back to storage.local where missing.
//  - identity.launchWebAuthFlow: Safari has none. Cumulus ID returns to https://rchtch.app/cid-return
//    (an origin Cumulus ID already accepts) in a tab the background watches; the one-time code is
//    read from that tab's address and the tab is closed. The PKCE verifier never leaves cid.js.
//    A popup closes as soon as a tab opens, so a popup hands the whole sign-in to the background.

const RETURN = "https://rchtch.app/cid-return";
export const SIGN_IN_MESSAGE = "architect-safari-signin";
const isBackground = (() => {
  if (typeof document === "undefined") return true; // service worker
  try {
    return Boolean(chrome.extension && chrome.extension.getBackgroundPage && chrome.extension.getBackgroundPage() === globalThis);
  } catch {
    return false;
  }
})();

/** Calls a chrome.* function and ignores its promise rejection, whether or not it returns one. */
const quiet = (fn) => {
  try {
    const r = fn();
    if (r && typeof r.catch === "function") r.catch(() => {});
  } catch {
    // ignored
  }
};

if (!chrome.sidePanel) {
  chrome.sidePanel = {
    setPanelBehavior: async () => {},
    open: async () => {},
  };
}

if (!chrome.contextMenus) {
  chrome.contextMenus = {
    removeAll: (cb) => cb && cb(),
    create: () => {},
    onClicked: { addListener: () => {} },
  };
}

if (chrome.storage && !chrome.storage.session) {
  chrome.storage.session = chrome.storage.local;
}

/** Opens Cumulus ID in a tab and resolves with the return address once the code arrives. */
function authInTab(url) {
  return new Promise((resolve, reject) => {
    chrome.tabs.create({ url }, (tab) => {
      if (!tab) return reject(new Error("Sign-in could not open a tab."));
      const done = (fn, value) => {
        chrome.tabs.onUpdated.removeListener(onUpdated);
        chrome.tabs.onRemoved.removeListener(onRemoved);
        fn(value);
      };
      const onUpdated = (id, info, t) => {
        if (id !== tab.id) return;
        const at = info.url || (t && t.url) || "";
        if (at.startsWith(RETURN) && /[?&](code|error)=/.test(at)) {
          quiet(() => chrome.tabs.remove(id));
          done(resolve, at);
        }
      };
      const onRemoved = (id) => {
        if (id === tab.id) done(reject, new Error("Sign-in was cancelled."));
      };
      chrome.tabs.onUpdated.addListener(onUpdated);
      chrome.tabs.onRemoved.addListener(onRemoved);
    });
  });
}

if (!chrome.identity || !chrome.identity.launchWebAuthFlow) {
  chrome.identity = {
    getRedirectURL: () => RETURN,
    launchWebAuthFlow: ({ url }) => {
      if (isBackground) return authInTab(url);
      // A popup: let the background finish; the popup shows the session next time it opens.
      const create = new URL(url).searchParams.get("prompt") === "create";
      quiet(() => chrome.runtime.sendMessage({ type: SIGN_IN_MESSAGE, create }));
      return new Promise(() => {});
    },
  };
}
