{{flutter_js}}
{{flutter_build_config}}

// Per-build URLs for the app code. Flutter's main.dart.* names never change,
// and older deploys told browsers to cache them for a year, so without a
// version query returning phones keep running stale code. This bootstrap is
// inlined into index.html (served no-cache) so the query is always current.
(function () {
  var v = "__BUILD_ID__"; // replaced by deploy_web.bat
  if (v.indexOf("__") === 0) return; // local/dev build: plain names
  _flutter.buildConfig.builds.forEach(function (b) {
    ["mainJsPath", "mainWasmPath", "jsSupportRuntimePath"].forEach(function (k) {
      if (b[k]) b[k] += "?v=" + v;
    });
  });
})();

_flutter.loader.load();
