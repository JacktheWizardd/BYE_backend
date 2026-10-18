export interface Course { subject: string; number: string; key: string; display: string; matchingKey: string }
export interface Term { termCode: string; termName: string; termDisplayControl: string }
export type Row = Record<string, string | number | null>
export interface Suggestion { course: Course; title: string }
/** Enrollment and term facts PCC publishes for a section. Every field is optional because rows can omit them. */
export interface SectionDetails { seatsOpen?: number; capacity?: number; waitlistCount?: number; waitlistCapacity?: number; termPart: string; campus: string; units: string }
export type Weekday = 'Mon' | 'Tue' | 'Wed' | 'Thu' | 'Fri' | 'Sat' | 'Sun'
export interface Section {
  crn: string; title: string; start: string; end: string; formats: string[]; meetings: string[]; status: string
  /** Days with a scheduled meeting, and whether any scheduled meeting has no announced day. */
  days?: Weekday[]; unannouncedMeetings?: boolean; details?: SectionDetails
}
export interface Review { id: string; course: string; text: string; date: string; rating?: number; difficulty?: number; online?: boolean }
export interface Coverage { reviewIDs: string[]; nextCursor?: string; hasNextPage: boolean; updatedAt: number }
export interface Profile {
  id: string; firstName: string; lastName: string; school: string; schoolID: number; department: string;
  rating?: number; difficulty?: number; ratingCount?: number; wouldTakeAgain?: number;
  reviews: Review[]; courseCounts: { label: string; count?: number }[]; coverage: Record<string, Coverage>
}
export interface Point { text: string; reviewIDs: string[] }
export interface Summary { overview: string; positives: Point[]; concerns: Point[]; analyzedCount: number; exactCourseCount: number; generatedAt: number; providerIdentity: string; evidence: Review[] }
export interface Professor {
  id: string; name: string; sections: Section[]; subject: string; subjectDescription?: string;
  state: 'pending' | 'loading' | 'ready' | 'choose' | 'unavailable'; profile?: Profile; candidates: Profile[];
  issue?: string; reviewIssue?: string; summaryIssue?: string; summary?: Summary; detailLoading?: boolean; summaryLoading?: boolean; choosing?: boolean
}
export interface Snapshot { operationId: string; course?: Course; term?: Term; professors: Professor[]; loading: boolean; previewPending: number; issue?: string }
export type Command =
  | { kind: 'terms' }
  | { kind: 'suggest'; term: string; query: string }
  | { kind: 'search'; term: Term; query: string; refresh?: boolean }
  | { kind: 'stop' }
  | { kind: 'retry' | 'discover' | 'dismiss' | 'summary'; professorId: string }
  | { kind: 'select'; professorId: string; profileId: string }
  | { kind: 'details'; professorId: string; filter?: string }
  | { kind: 'source'; target: 'pcc' | 'rmp' | 'review'; professorId?: string; candidateId?: string }
export interface Bridge { command(command: Command): Promise<unknown>; subscribe(listener: (state: Snapshot) => void): () => void }
