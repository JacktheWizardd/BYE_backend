import { useEffect, useLayoutEffect, useRef, useState, type RefObject } from 'react'
import tokens from '../tokens/tokens.json'

// Timings and curves come from the shared design tokens, so the web, Windows and Mac apps move the same way.
export const MOTION = {
  slide: tokens.motion.durationMs.slide,
  spring: `cubic-bezier(${tokens.motion.easing.spring.join(', ')})`,
  expo: `cubic-bezier(${tokens.motion.easing.expo.join(', ')})`,
}

// Small motion helpers shared by the web app (demo and live) and the Windows app. Everything is off for reduced motion.
export const reducedMotion = () => typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches

// Counts a number up from zero once when it first appears (or changes), like the home page.
export function useCountUp(value: number | undefined, ms = 900) {
  const [shown, setShown] = useState(value)
  useEffect(() => {
    if (value === undefined || reducedMotion()) { setShown(value); return }
    let raf = 0
    const start = performance.now()
    const step = (now: number) => {
      const t = Math.min(1, (now - start) / ms), eased = 1 - Math.pow(1 - t, 3)
      setShown(value * eased)
      if (t < 1) raf = requestAnimationFrame(step)
    }
    raf = requestAnimationFrame(step)
    return () => cancelAnimationFrame(raf)
  }, [value, ms])
  return shown
}

// Types and erases example searches as a placeholder while the field is empty and idle.
// Returns null when inactive (use the normal placeholder) and a string, possibly empty, while animating:
// an empty string must stay blank, not fall back to the full placeholder between examples.
export function useTypedHint(examples: string[], active: boolean): string | null {
  const [hint, setHint] = useState<string | null>(null)
  useEffect(() => {
    if (!active || reducedMotion()) { setHint(null); return }
    // A "|" caret follows the text like a real cursor: steady while typing, blinking while it pauses.
    // Typing goes one letter per tick; erasing goes two, so long titles don't drag.
    let i = 0, n = 0, dir = 1, wait = 0, tick = 0
    const show = (text: string, caret: boolean) => setHint(text + (caret ? '|' : ''))
    show('', true)
    const id = setInterval(() => {
      tick += 1
      const word = examples[i % examples.length]
      if (wait > 0) { wait -= 1; show(word.slice(0, n), Math.floor(tick / 4) % 2 === 0); return }
      n = Math.max(0, Math.min(word.length, n + (dir > 0 ? 1 : -2)))
      if (n >= word.length) { dir = -1; wait = 16 }
      if (n <= 0) { dir = 1; i += 1; wait = 5 }
      show(word.slice(0, n), true)
    }, 110)
    return () => clearInterval(id)
  }, [active, examples.join('|')])
  return hint
}

// Items marked `data-flip="<id>"` inside `container` glide from their old place to their new one when `order` changes
// (re-sorting, filtering). New items fade in through CSS instead. Skipped for reduced motion.
export function useFlip(container: RefObject<HTMLElement | null>, order: string) {
  const last = useRef(new Map<string, number>())
  useLayoutEffect(() => {
    const el = container.current
    if (!el) return
    const items = Array.from(el.querySelectorAll<HTMLElement>('[data-flip]'))
    const next = new Map(items.map(item => [item.dataset.flip!, item.offsetTop]))
    if (!reducedMotion() && last.current.size) {
      for (const item of items) {
        const before = last.current.get(item.dataset.flip!)
        const dy = before === undefined ? 0 : before - next.get(item.dataset.flip!)!
        if (dy && typeof item.animate === 'function') item.animate([{ transform: `translateY(${dy}px)` }, { transform: 'none' }], { duration: MOTION.slide, easing: MOTION.spring })
      }
    }
    last.current = next
  }, [order])
}
