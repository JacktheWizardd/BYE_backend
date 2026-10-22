/** Hosted transport staging only. Private, fictional, no real outbound calls or credentials. */
import { handleReviewRequest } from './reviews'
import { handleSourceRequest } from './source-api'
import { reviewFixture } from '../tests/review-fixtures'
const fixture = reviewFixture()
export default { fetch(request: Request) {
  const path = new URL(request.url).pathname
  if (path.startsWith('/api/reviews/')) return handleReviewRequest(request, fixture.env, fixture.outbound)
  if (path.startsWith('/api/v1/')) return handleSourceRequest(request, { LIVE_APP_ENABLED: 'false' })
  return new Response('Not found', { status: 404 })
} }
