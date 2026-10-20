import React, { createContext, useContext } from 'react'

// Where the shared screens are running. `demo` is the sample-data web demo: every "Sample" label must show there,
// because testers mistook the demo for real data. The live web app and the Windows app use real sources.
export interface Surface { demo: boolean }
const SurfaceContext = createContext<Surface>({ demo: false })
export function SurfaceProvider({ demo, children }: Surface & { children: React.ReactNode }) {
  return <SurfaceContext.Provider value={{ demo }}>{children}</SurfaceContext.Provider>
}
export const useSurface = () => useContext(SurfaceContext)

export function SampleTag({ children }: { children: React.ReactNode }) { return useSurface().demo ? <span className="sample-tag">{children}</span> : null }
