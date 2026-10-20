/** Shared form/API types. No auth tokens or Supabase client code belong here. */
export interface ReviewDimension { name: string; low_label: string; high_label: string; sort_order: number }
export interface ReviewCourse { id: string; code: string; title: string }
export interface ReviewProfessor { id: string; first_name: string; last_name: string }
export interface ReviewInput {
  professorId: string; courseId: string; quality: number; difficulty: number;
  body: string; answers: Record<string, -1 | 0 | 1>;
}
export interface ReviewSession { signedIn: boolean; email?: string }
export const TEST_REVIEW_PREFIX = 'BYE website test, please ignore.\n'
export const REVIEW_COMMENT_LIMIT = 2000 - TEST_REVIEW_PREFIX.length
export const questionLabel = (name: string) => ({
  grading: 'Grading', workload: 'Workload', attendance: 'Attendance', clarity: 'Clarity',
  feedback_speed: 'Feedback speed', test_alignment: 'Tests compared with class', textbook: 'Textbook',
}[name] ?? name.replaceAll('_', ' '))

export interface ByeResolution {
  professor: ReviewProfessor | null
  course: ReviewCourse | null
  match: 'matched' | 'missing' | 'ambiguous'
}
export interface ByeRatingProfile {
  professorId: string
  count: number
  quality: number | null
  difficulty: number | null
  courses: (ReviewCourse & { count: number })[]
  retrievedAt: string
}
export interface ByeWrittenReview {
  id: string; quality: number; difficulty: number; body: string | null; date: string; courseId: string; course: string
}
export interface ByeReviewPage { reviews: ByeWrittenReview[]; nextOffset: number | null }
