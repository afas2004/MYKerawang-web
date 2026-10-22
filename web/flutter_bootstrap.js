{{flutter_js}}
{{flutter_build_config}}

// Per-build URLs for the app code. Flutter's main.dart.* names never change,
// so without a version query a phone can keep running stale code. This
// bootstrap is inlined into index.html (served no-cache) so the query is
// always current. (firebase.json also serves main.dart.* no-cache now, with
// ETag revalidation, so even an unversioned request can't be stale.)
(function () {
  var v = "__BUILD_ID__"; // replaced by deploy_web.bat
  if (v.indexOf("__") === 0) return; // local/dev build: plain names
  _flutter.buildConfig.builds.forEach(function (b) {
    ["mainJsPath", "mainWasmPath", "jsSupportRuntimePath"].forEach(function (k) {
      if (b[k]) b[k] += "?v=" + v;
    });
  });
})();

// Renderer. Android Chrome drops a backgrounded tab's GPU (WebGL) context —
// most often while the camera or file picker is open. The CanvasKit
// renderer listens for that and rebuilds its surface when the context comes
// back; the skwasm renderer (the --wasm build's default) does not, and the
// page stays white. So Android uses the CanvasKit build; other platforms
// keep the default (skwasm where supported). index.html reloads as a last
// resort if a lost context never comes back.
(function () {
  var android = /Android/i.test(navigator.userAgent);
  var config = android ? { renderer: "canvaskit" } : {};
  window.__mkRenderer = android ? "canvaskit" : "auto";
  _flutter.loader.load({ config: config });
})();
