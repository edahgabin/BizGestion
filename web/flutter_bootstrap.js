{{flutter_js}}
{{flutter_build_config}}
_flutter.loader.load({
  config: {
    // Keep Flutter's renderer on the same origin so the offline worker can cache it.
    canvasKitBaseUrl: "canvaskit/",
  },
});
