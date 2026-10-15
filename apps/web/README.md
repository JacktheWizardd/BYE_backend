# BYE web demo

A browser version of BYE that runs entirely on **bundled sample data**. Every instructor, rating and review is fictional. It makes no PCC or Rate My Professors requests and needs no server: the build is static files.

## Run

Use Node 24 LTS (or Node 22.16+).

```sh
cd apps/web
npm install
npm run dev        # http://localhost:5173
npm run typecheck
npm test
npm run build      # static output in dist/, relative paths, so it can be served from any folder such as /demo/
```

## How it fits together

- `src/demo-bridge.ts` implements the same `Bridge` contract (`command` + `subscribe`) as the Electron app's preload bridge. It follows the Electron `Engine` flow: schedule → professors → profile preview → full reviews, including the ambiguous-profile chooser and the stop behavior. A live implementation can replace it later without changing the UI.
- Course parsing, suggestions, section grouping, identity matching, delivery labels and sorting/filtering are imported unchanged from `apps/cross-platform/src/shared` via the `@shared` alias. There is no second copy.
- `src/demo-data.ts` holds rows shaped like PCC's schedule feed, plus fictional profiles. A test checks that no instructor name from the saved real PCC fixture is reused.
- `src/styles.css` uses the current redesign tokens (light only). Libre Baskerville comes from `Sources/Classwise/Resources`, and Schibsted Grotesk and JetBrains Mono come from bundled `@fontsource` packages, so no font CDN is needed.
- AI summaries are not part of the demo.
