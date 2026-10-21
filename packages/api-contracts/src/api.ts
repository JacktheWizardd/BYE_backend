import type { Course, Profile, Professor, SourceMeta, Suggestion, Term } from './types'
export interface Envelope<T> { data: T; meta: SourceMeta; warning?: string }
export interface ApiErrorBody { error: { code: string; message: string; retryable: boolean; retryAfter?: number } }
export interface SectionsResult { course: Course; professors: Professor[] }
export interface ReviewsResult { profile: Profile; ids: string[]; hasNextPage: boolean; nextCursor?: string }
export interface Status { enabled: boolean; rmpConfigured: boolean }
export interface ApiResults { terms: Term[]; courses: Suggestion[]; sections: SectionsResult; candidates: Profile[]; profile: ReviewsResult; reviews: ReviewsResult }
