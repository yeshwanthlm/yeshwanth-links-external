/* Runs first, in <head>: applies the saved theme before paint (no flash).
   Same storage key as yeshwanthlm.in, so the choice carries over on the same domain. */
(function () {
  try {
    var t = localStorage.getItem("ylm-theme");
    if (t) document.documentElement.dataset.theme = t;
  } catch (e) { /* storage blocked: dark default */ }
})();
