import { handleReviewRequest, type ReviewEnv } from './reviews'
import { handleSourceRequest, type SourceEnv } from './source-api'
export type Env = ReviewEnv & SourceEnv
// Private Worker: the service binding preserves the original public URL for origin validation.
export default { async fetch(request: Request, env: Env): Promise<Response> {
  const path = new URL(request.url).pathname
  if (path.startsWith('/api/reviews/')) return handleReviewRequest(request, env)
  if (path.startsWith('/api/v1/')) return handleSourceRequest(request, env)
  return new Response('Not found', { status: 404, headers: { 'Cache-Control': 'no-store', 'X-Robots-Tag': 'noindex, nofollow' } })
} }
