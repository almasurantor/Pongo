const startupRecoveryScript = String.raw`
(function () {
  var KEY = 'pongo-startup-recovery-v1';
  var READY_EVENT = 'pongo:boot-ready';
  var OVERLAY_ID = 'pongo-startup-recovery';
  var BOOT_TIMEOUT_MS = 15000;
  var RECOVERY_WINDOW_MS = 60000;
  var recovering = false;
  var ready = false;
  var bootTimer;

  function messageOf(value) {
    if (!value) return '';
    return String(value.message || value.reason || value);
  }

  function isBuildFailure(value) {
    return /ChunkLoadError|Loading chunk [\w-]+ failed|Failed to fetch dynamically imported module|Importing a module script failed|Unable to preload CSS/i.test(messageOf(value));
  }

  function isBuildAsset(target) {
    if (!target || !target.tagName) return false;
    var tag = String(target.tagName).toUpperCase();
    if (tag !== 'SCRIPT' && tag !== 'LINK') return false;
    var address = target.src || target.href || '';
    try { return new URL(address, location.href).pathname.indexOf('/_next/static/') === 0; }
    catch (_) { return false; }
  }

  function recoveryUrl() {
    var url = new URL(location.href);
    url.searchParams.set('_pwa_recovery', '1');
    return url.href;
  }

  function showRecovery(detail) {
    function render() {
      if (ready || document.getElementById(OVERLAY_ID) || !document.body) return;
      var root = document.createElement('div');
      root.id = OVERLAY_ID;
      root.setAttribute('role', 'alert');
      root.style.cssText = 'position:fixed;inset:0;z-index:2147483647;display:grid;place-items:center;padding:24px;background:#2563eb;color:#0f172a;font-family:system-ui,-apple-system,sans-serif';
      root.innerHTML = '<main style="width:min(100%,420px);border-radius:28px;background:#fff;padding:32px;text-align:center;box-shadow:0 24px 70px rgba(30,58,138,.5)"><div style="font-size:12px;font-weight:900;letter-spacing:.08em;text-transform:uppercase;color:#2563eb">Pongo</div><h1 style="margin:8px 0 0;font-size:30px">Pongo could not finish opening</h1><p style="margin:12px 0 24px;color:#475569;line-height:1.55">' + detail + '</p><button id="pongo-retry" type="button" style="min-height:48px;width:100%;border:0;border-radius:14px;background:#f97316;padding:0 24px;color:#fff;font:inherit;font-weight:800">Repair and retry</button><a href="/" style="display:block;margin-top:16px;color:#1d4ed8;font-weight:800">Open the start page</a></main>';
      document.body.appendChild(root);
      document.getElementById('pongo-retry').addEventListener('click', function () {
        try { sessionStorage.removeItem(KEY); } catch (_) {}
        recover(true);
      });
    }
    if (document.body) render();
    else document.addEventListener('DOMContentLoaded', render, { once: true });
  }

  function clearOldBundleCaches() {
    if (!('caches' in window)) return Promise.resolve();
    return caches.keys().then(function (keys) {
      return Promise.all(keys.filter(function (key) {
        return key.indexOf('pongo-assets-') === 0;
      }).map(function (key) { return caches.delete(key); }));
    });
  }

  function updateWorker() {
    if (!('serviceWorker' in navigator)) return Promise.resolve();
    return navigator.serviceWorker.getRegistration('/').then(function (registration) {
      if (!registration) return;
      if (registration.waiting) registration.waiting.postMessage({ type: 'SKIP_WAITING' });
      return registration.update().catch(function () {});
    }).catch(function () {});
  }

  function recover(manual) {
    if (recovering) return;
    var previous = 0;
    try { previous = Number(sessionStorage.getItem(KEY) || 0); } catch (_) {}
    if (!manual && previous && Date.now() - previous < RECOVERY_WINDOW_MS) {
      showRecovery('A startup file is still unavailable. Check your connection, then retry. Your account and saved session are safe.');
      return;
    }
    recovering = true;
    try { sessionStorage.setItem(KEY, String(Date.now())); } catch (_) {}
    Promise.allSettled([clearOldBundleCaches(), updateWorker()]).then(function () {
      location.replace(recoveryUrl());
    }).catch(function () {
      location.reload();
    });
  }

  window.addEventListener('error', function (event) {
    if (isBuildAsset(event.target) || isBuildFailure(event.error || event.message)) recover(false);
  }, true);
  window.addEventListener('unhandledrejection', function (event) {
    if (isBuildFailure(event.reason)) recover(false);
  });
  window.addEventListener(READY_EVENT, function () {
    ready = true;
    clearTimeout(bootTimer);
    var overlay = document.getElementById(OVERLAY_ID);
    if (overlay) overlay.remove();
    window.setTimeout(function () {
      try { sessionStorage.removeItem(KEY); } catch (_) {}
    }, 10000);
  }, { once: true });
  bootTimer = window.setTimeout(function () {
    if (!ready) showRecovery('The app took too long to start. This can happen after an update or an interrupted connection.');
  }, BOOT_TIMEOUT_MS);
})();
`;

export default function StartupRecoveryScript() {
  // Keep this as a literal inline script: unlike next/script, it does not need
  // Next's bootstrap runtime in order to install the failure listeners.
  return <script id="pongo-startup-recovery-script" dangerouslySetInnerHTML={{ __html: startupRecoveryScript }} />;
}
