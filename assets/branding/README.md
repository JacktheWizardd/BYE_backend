# Mac app icon

`AppIcon.png` is the square source artwork: Libre Baskerville Bold "BYE" in Jet Black
(#161618) over the yellow highlighter swipe (#F2C14E), on ivory (#FAF8F3). It matches the
wordmark in the app and on the website.

To regenerate it and the app icon:

```sh
swift scripts/render-wordmark-icon.swift Sources/Classwise/Resources/LibreBaskerville-Bold.ttf assets/branding/AppIcon.png
sh scripts/generate-app-icon.sh
./scripts/build-test-app.sh
```

The generated `Sources/Classwise/Resources/AppIcon.icns` is tracked so normal
builds do not need to regenerate it. Both test and release app bundles use it.

The generator uses `scripts/render-app-icon.swift` to add rounded corners and
transparent margins before creating the icon sizes. The source artwork remains
unchanged. Adjust its `tile` rectangle and corner sizes to change the silhouette.
