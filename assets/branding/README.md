# Mac app icon

`AppIcon.png` is the source image for the temporary profile-picture icon.
To replace it, save a square PNG at that path, then run:

```sh
sh scripts/generate-app-icon.sh
./scripts/build-test-app.sh
```

The generated `Sources/Classwise/Resources/AppIcon.icns` is tracked so normal
builds do not need to regenerate it. Both test and release app bundles use it.

The generator uses `scripts/render-app-icon.swift` to add rounded corners and
transparent margins before creating the icon sizes. The source artwork remains
unchanged. Adjust its `tile` rectangle and corner sizes to change the silhouette.
