// Safari only: runs Cumulus ID sign-in for the popup, which Safari closes when the sign-in tab opens.
import { SIGN_IN_MESSAGE } from "./safari-shim.js";
import { signIn } from "./cid.js";

chrome.runtime.onMessage.addListener((message) => {
  if (!message || message.type !== SIGN_IN_MESSAGE) return false;
  signIn({ create: Boolean(message.create) }).catch(() => {
    // Cancelled or failed: the popup shows "Sign in" again next time it opens.
  });
  return false;
});
