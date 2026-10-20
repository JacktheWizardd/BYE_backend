import { reducedMotion } from '../../../../vendor/bye-shared/ui'
import tokens from '../../../../vendor/bye-shared/tokens/tokens.json'

// A short burst of ink and yellow paper when first-run setup finishes (a playful accent). Nothing runs for reduced motion.
export function confetti() {
  if (reducedMotion() || typeof document.body.animate !== 'function') return
  const layer = document.createElement('div')
  layer.className = 'confetti'
  layer.setAttribute('aria-hidden', 'true')
  document.body.appendChild(layer)
  const colors = [tokens.color.accent.value, tokens.color.ink.value], duration = tokens.motion.durationMs.confetti
  for (let i = 0; i < 46; i++) {
    const piece = document.createElement('i'), wide = i % 3 === 0
    piece.style.cssText = `width:${wide ? 8 : 6}px;height:${wide ? 12 : 8}px;background:${colors[i % 2]}`
    layer.appendChild(piece)
    const angle = Math.random() * Math.PI * 2, speed = 120 + Math.random() * 220
    piece.animate([
      { transform: 'translate(-50%, -50%) rotate(0deg)', opacity: 1 },
      { transform: `translate(calc(-50% + ${Math.cos(angle) * speed}px), calc(-50% + ${Math.sin(angle) * speed * 0.7 + 180}px)) rotate(${Math.random() * 720}deg)`, opacity: 0 },
    ], { duration: duration * (0.8 + Math.random() * 0.4), easing: 'cubic-bezier(.2,.7,.4,1)', fill: 'forwards' })
  }
  setTimeout(() => layer.remove(), duration * 1.3)
}
