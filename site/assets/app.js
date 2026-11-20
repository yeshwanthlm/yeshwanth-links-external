(() => {
  const $ = (s) => document.querySelector(s);
  const root = document.documentElement;

  /* ── theme (same key as yeshwanthlm.in) ── */
  $("#themeBtn").addEventListener("click", () => {
    const t = root.dataset.theme === "dark" ? "light" : "dark";
    root.dataset.theme = t;
    try { localStorage.setItem("ylm-theme", t); } catch {}
  });
  $("#yr").textContent = new Date().getFullYear();

  /* ── device ── */
  const ua = navigator.userAgent;
  const isAndroid = /Android/i.test(ua);
  const isIOS = /iPhone|iPad|iPod/i.test(ua) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
  const device = isIOS ? "ios" : isAndroid ? "android" : "desktop";
  root.dataset.device = device;

  // Android: intent:// opens the app. No browser fallback on purpose:
  // if the app is missing, Android opens its Play Store page instead.
  const intentUrl = (web, pkg) => {
    const u = new URL(web);
    return `intent://${u.host}${u.pathname}${u.search}#Intent;scheme=https;package=${pkg};end`;
  };

  // iOS: open the app. If the page is still visible after a moment, the app is missing,
  // so go to the App Store (never the website, where nobody is logged in).
  let fallbackTimer = null;
  const cancelFallback = () => { clearTimeout(fallbackTimer); fallbackTimer = null; };
  document.addEventListener("visibilitychange", () => { if (document.hidden) cancelFallback(); });
  window.addEventListener("pagehide", cancelFallback);

  const openIOS = (appUrl, store) => {
    cancelFallback();
    if (store) fallbackTimer = setTimeout(() => { if (!document.hidden) location.href = store; }, 1500);
    location.href = appUrl;
  };

  /* ── render ── */
  const list = $("#links");
  const cmd = $("#cmd");
  const appFor = (l) => device === "android" ? l.android : device === "ios" ? (l.ios || l.universal) : null;
  const verb = (l) => appFor(l) ? "open --app" : "open";

  window.LINKS.forEach((l, i) => {
    const li = document.createElement("li");
    li.style.setProperty("--d", `${i * 45}ms`);
    const a = document.createElement("a");
    a.className = "lk";
    a.href = l.web;
    a.style.setProperty("--brand", l.brand);
    a.target = "_blank"; a.rel = "noopener";
    const hasApp = !!appFor(l);
    a.innerHTML = `
      <span class="lk__ic" aria-hidden="true"><svg viewBox="0 0 24 24">${l.icon}</svg></span>
      <span class="lk__txt"><b>${l.name}</b><span class="mono">${l.handle}</span></span>
      ${hasApp ? '<span class="lk__app mono">app</span>' : ""}
      <span class="lk__go" aria-hidden="true">↗</span>`;

    const show = () => { cmd.textContent = `${verb(l)} ${l.id}`; };
    a.addEventListener("mouseenter", show);
    a.addEventListener("focus", show);

    a.addEventListener("click", (e) => {
      show();
      if (device === "android" && l.android) {
        e.preventDefault();
        location.href = intentUrl(l.web, l.android);
      } else if (device === "ios" && l.ios) {
        e.preventDefault();
        openIOS(l.ios, l.appStore);
      } else if (device === "ios" && l.universal) {
        // same-tab https link: iOS gives it to the installed app (a new tab would stay in Safari)
        e.preventDefault();
        location.href = l.web;
      }
      // computers (and Topmate): the normal web link
    });

    li.appendChild(a);
    list.appendChild(li);
  });
})();
