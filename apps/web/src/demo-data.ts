import type { Profile, Review, Row, Term } from '@shared/types'

// Everything here is invented for the demo. Rows follow the shape of PCC's class schedule feed
// (see Tests/ClasswiseCoreTests/Fixtures) so the shared domain code parses them unchanged,
// but every instructor, profile and review is fictional.

export interface DemoData { terms: Term[]; schedules: Record<string, Row[]>; profiles: Profile[] }

export const FALL: Term = { termCode: '202670', termName: 'Fall 2026', termDisplayControl: 'Y' }
const START = '2026-08-24 00:00:00', END = '2026-12-12 00:00:00'
const DAYS: Record<string, string> = { M: 'monDay', T: 'tueDay', W: 'wedDay', R: 'thuDay', F: 'friDay', S: 'satDay' }

interface Meeting { days?: string; begin?: string; end?: string; building: string; room: string }
interface SectionPlan { crn: string; instructor: string; format: 'L' | 'HY' | 'OD' | 'OL'; status: 'O' | 'C'; meetings: Meeting[] }

const online: Meeting = { building: 'Online ASYNCH', room: 'Needs Assignment' }

function rows(subject: string, number: string, title: string, sections: SectionPlan[]): Row[] {
  return sections.flatMap(s => s.meetings.map(m => {
    const row: Row = {
      subjCode: subject, courseNumbDisplay: number, crn: s.crn, courseTitle: title, pfaName: s.instructor, schdCode: s.format,
      ptrmStartDate: START, ptrmEndDate: END, fwSectOpenInd: s.status, beginTime: m.begin ?? null, endTime: m.end ?? null, bldgDesc: m.building, roomCode: m.room
    }
    for (const [letter, field] of Object.entries(DAYS)) row[field] = m.days?.includes(letter) ? letter : null
    return row
  }))
}

const schedule: Row[] = [
  ...rows('ETH', '014', 'INTRODUCTION TO ETHNIC STUDIES', [
    { crn: '61204', instructor: 'Marisol Quintero-Hale', format: 'L', status: 'O', meetings: [{ days: 'MW', begin: '0800', end: '0925', building: 'C', room: '323' }] },
    { crn: '61207', instructor: 'Marisol Quintero-Hale', format: 'OD', status: 'C', meetings: [online] },
    { crn: '61215', instructor: 'Theo Vandermeer', format: 'HY', status: 'O', meetings: [{ days: 'W', begin: '1030', end: '1320', building: 'R', room: '516' }, online] },
    { crn: '61222', instructor: 'Imani Okafor-Price', format: 'OD', status: 'O', meetings: [online] },
    { crn: '61223', instructor: 'Imani Okafor-Price', format: 'OD', status: 'O', meetings: [online] },
    { crn: '61231', instructor: 'Daniel Reyes', format: 'L', status: 'O', meetings: [{ days: 'TR', begin: '1200', end: '1325', building: 'C', room: '208' }] },
    { crn: '61238', instructor: '', format: 'L', status: 'O', meetings: [{ days: 'F', begin: '0900', end: '1150', building: 'C', room: '115' }] }
  ]),
  ...rows('MATH', '5A', 'SINGLE VARIABLE CALCULUS I', [
    { crn: '62110', instructor: 'Desmond Achterberg', format: 'L', status: 'C', meetings: [{ days: 'MTWR', begin: '0700', end: '0805', building: 'D', room: '201' }] },
    { crn: '62112', instructor: 'Desmond Achterberg', format: 'L', status: 'O', meetings: [{ days: 'MTWR', begin: '0815', end: '0920', building: 'D', room: '201' }] },
    { crn: '62118', instructor: 'Lena Whitcombe', format: 'L', status: 'O', meetings: [{ days: 'MW', begin: '1700', end: '1925', building: 'D', room: '304' }] },
    { crn: '62125', instructor: 'Noor Haddadin', format: 'OL', status: 'O', meetings: [{ days: 'TR', begin: '1830', end: '2055', building: 'Online SYNCH', room: 'Zoom' }] },
    { crn: '62131', instructor: 'Calvin Ostrowski', format: 'L', status: 'O', meetings: [{ days: 'TR', begin: '1030', end: '1255', building: 'D', room: '110' }] }
  ]),
  ...rows('ENGL', '1A', 'READING AND COMPOSITION', [
    { crn: '63302', instructor: 'Yuki Hartwell', format: 'L', status: 'O', meetings: [{ days: 'MW', begin: '0930', end: '1055', building: 'W', room: '107' }] },
    { crn: '63305', instructor: 'Yuki Hartwell', format: 'HY', status: 'O', meetings: [{ days: 'T', begin: '1300', end: '1425', building: 'W', room: '110' }, online] },
    { crn: '63311', instructor: 'Rafael Ibarra-Lund', format: 'OD', status: 'C', meetings: [online] },
    { crn: '63318', instructor: 'Simone Delacroix-Byrd', format: 'L', status: 'O', meetings: [{ days: 'TR', begin: '0800', end: '0925', building: 'W', room: '203' }] },
    { crn: '63319', instructor: 'Simone Delacroix-Byrd', format: 'L', status: 'O', meetings: [{ days: 'F', begin: '0900', end: '1150', building: 'W', room: '203' }] }
  ])
]

interface ProfilePlan {
  id: string; first: string; last: string; department: string
  rating: number; difficulty: number; silent: number
  courses: string[]; notes: string[]
}

// Each written review pairs one teaching note with one overall impression that fits its rating.
const impressions: Record<'high' | 'mid' | 'low', string[]> = {
  high: [
    'One of the best classes I took at PCC. Go to every lecture and you will be fine.',
    'Really cares whether students understand, and it shows in office hours.',
    'Would take again without thinking twice.',
    'Clear expectations from day one, so there were no surprises at the end.'
  ],
  mid: [
    'Solid class overall, but you have to keep up on your own.',
    'Fair grader. Lectures can drag, but the material is useful.',
    'Not the easiest, not the hardest. Start assignments early.',
    'Some weeks were great and some felt rushed.'
  ],
  low: [
    'Hard to follow at times, and feedback came back late.',
    'The workload felt heavier than the units suggested.',
    'Instructions changed a few times during the semester, which was frustrating.'
  ]
}

const plans: ProfilePlan[] = [
  { id: '7100', first: 'Marisol', last: 'Quintero-Hale', department: 'Ethnic Studies', rating: 4.6, difficulty: 2.4, silent: 9, courses: ['ETH014', 'ETH014', 'ETH020'], notes: [
    'Discussion every class, and the professor actually reads what you post.',
    'Weekly reading quizzes keep you on track, and they are short.',
    'Essay feedback is detailed, but citations are graded strictly.',
    'The community project at the end was the highlight of the course.',
    'Readings are long, but lecture explains what matters in each one.'] },
  { id: '7101', first: 'Theo', last: 'Vandermeer', department: 'Ethnic Studies', rating: 3.7, difficulty: 3.1, silent: 6, courses: ['ETH014', 'ETH014', 'HIST007B'], notes: [
    'The hybrid format works if you finish the online modules before the Wednesday meeting.',
    'Lectures are packed with stories and primary sources.',
    'Exams are mostly short answer and pull straight from lecture.',
    'Grades take a while to show up on Canvas.',
    'Group presentations count for a big part of the grade.'] },
  { id: '7102', first: 'Imani', last: 'Okafor-Price', department: 'Ethnic Studies', rating: 4.2, difficulty: 2.0, silent: 14, courses: ['ETH014', 'ETH014', 'ETH014', 'SOC001'], notes: [
    'Fully online and very organized. Every module has the same layout.',
    'Due dates are flexible if you ask before the deadline.',
    'Video lectures are short and to the point.',
    'Discussion boards are most of the grade, so post on time.',
    'Answers emails quickly, even on weekends.'] },
  { id: '7103', first: 'Daniel', last: 'Reyes', department: 'Ethnic Studies', rating: 4.0, difficulty: 2.8, silent: 4, courses: ['ETH014', 'ETH014', 'ETH030'], notes: [
    'Lectures connect the readings to things happening in LA right now.',
    'The midterm essay is the big grade, so use the outline workshop.',
    'Attendance is taken every class.',
    'Encourages questions and debate without making anyone feel put on the spot.'] },
  { id: '7140', first: 'Daniel', last: 'Reyes', department: 'Kinesiology', rating: 4.4, difficulty: 1.9, silent: 11, courses: ['KIN020', 'KIN020', 'PE014'], notes: [
    'Fitness labs are fun, and you go at your own pace.',
    'Grading is mostly participation and a short final.',
    'Explains the science behind each workout.'] },
  { id: '7200', first: 'Desmond', last: 'Achterberg', department: 'Mathematics', rating: 3.4, difficulty: 4.1, silent: 21, courses: ['MATH5A', 'MATH5A', 'MATH5B', 'MATH3'], notes: [
    'Homework every night, and it is graded for correctness.',
    'Exams are harder than the homework, so do the extra practice sets.',
    'Lectures move fast but follow the textbook closely.',
    'You will learn calculus properly, but it takes real time each week.',
    'Office hours are the best way to get unstuck.'] },
  { id: '7201', first: 'Lena', last: 'Whitcombe', department: 'Mathematics', rating: 4.7, difficulty: 3.3, silent: 8, courses: ['MATH5A', 'MATH5A', 'MATH4'], notes: [
    'Night class that never feels long. Lots of worked examples.',
    'Posts annotated lecture notes after every class.',
    'Quizzes every Monday on the previous week.',
    'Partial credit on exams if your setup is right.',
    'Great if you work during the day.'] },
  { id: '7202', first: 'Noor', last: 'Haddadin', department: 'Mathematics', rating: 3.9, difficulty: 3.6, silent: 5, courses: ['MATH5A', 'MATH5A', 'STAT50'], notes: [
    'Live Zoom lectures with cameras optional. Recordings are posted.',
    'Exams are proctored online, so have a quiet space ready.',
    'Breakout room problem sets help a lot.',
    'Online homework system has many attempts per problem.'] },
  { id: '7300', first: 'Yuki', last: 'Hartwell', department: 'English', rating: 4.5, difficulty: 3.0, silent: 12, courses: ['ENGL1A', 'ENGL1A', 'ENGL1C'], notes: [
    'Four essays, each with a required draft and conference.',
    'Peer review days are actually useful because of the checklist.',
    'The reading list is modern and interesting.',
    'Feedback is kind but honest about what to fix.',
    'Rewrites are allowed on the first essay.'] },
  { id: '7301', first: 'Rafael', last: 'Ibarra-Lund', department: 'English', rating: 2.9, difficulty: 3.4, silent: 7, courses: ['ENGL1A', 'ENGL1A', 'ENGL100'], notes: [
    'Online class with a lot of reading responses each week.',
    'Rubrics are posted, but grading does not always match them.',
    'The research essay is the hardest part, so start it early.',
    'Responds to messages, though it can take a few days.'] },
  { id: '7302', first: 'Simone', last: 'Delacroix-Byrd', department: 'English', rating: 4.1, difficulty: 2.6, silent: 10, courses: ['ENGL1A', 'ENGL1A', 'ENGL5'], notes: [
    'Writing workshops in class mean less homework at home.',
    'Very clear essay prompts with sample papers.',
    'The Friday section is long, but the time is used well.',
    'Grammar mini lessons at the start of each class.'] }
]

const offsets = [0, 1, -1, 0, 1, -2, 0, 1, -1, 0, 1, 0]
const clamp = (n: number) => Math.min(5, Math.max(1, Math.round(n)))
const tone = (rating: number) => rating >= 4 ? 'high' : rating >= 3 ? 'mid' : 'low'

function reviewsFor(plan: ProfilePlan): Review[] {
  const count = plan.notes.length * 2
  return Array.from({ length: count }, (_, n): Review => {
    const rating = clamp(plan.rating + offsets[n % offsets.length]), difficulty = clamp(plan.difficulty - offsets[(n + 4) % offsets.length])
    const pool = impressions[tone(rating)]
    const month = 9 - (n % 9), year = 2026 - Math.floor(n / 9)
    return {
      id: `demo-${plan.id}-${n + 1}`, course: plan.courses[n % plan.courses.length], rating, difficulty,
      date: `${year}-${String(month).padStart(2, '0')}-${String(28 - (n * 3) % 26).padStart(2, '0')}`,
      text: `${plan.notes[n % plan.notes.length]} ${pool[(n + plan.notes.length) % pool.length]}`
    }
  })
}

function profileFor(plan: ProfilePlan): Profile {
  const reviews = reviewsFor(plan)
  const average = (key: 'rating' | 'difficulty') => Math.round(reviews.reduce((sum, r) => sum + (r[key] ?? 0), 0) / reviews.length * 10) / 10
  const counts = new Map<string, number>()
  for (const r of reviews) counts.set(r.course, (counts.get(r.course) ?? 0) + 1)
  return {
    id: plan.id, firstName: plan.first, lastName: plan.last, school: 'Pasadena City College', schoolID: 2649, department: plan.department,
    rating: average('rating'), difficulty: average('difficulty'), ratingCount: reviews.length + plan.silent,
    wouldTakeAgain: Math.round(reviews.filter(r => (r.rating ?? 0) >= 4).length / reviews.length * 100),
    courseCounts: [...counts].map(([label, count]) => ({ label, count })), reviews, coverage: {}
  }
}

export interface Seats { open: number; capacity: number; waitlist: number; waitCapacity: number }
// Open seats and waitlists by CRN (the Mac app reads these from PCC; here they are invented).
// Closed sections ('C' above) have no open seats.
export const demoSeats: Record<string, Seats> = Object.fromEntries(([
  ['61204', 18, 40, 0], ['61207', 0, 40, 4], ['61215', 9, 35, 0], ['61222', 26, 45, 0], ['61223', 3, 45, 0], ['61231', 12, 40, 0], ['61238', 30, 40, 0],
  ['62110', 0, 35, 6], ['62112', 7, 35, 0], ['62118', 15, 35, 0], ['62125', 2, 35, 0], ['62131', 21, 35, 0],
  ['63302', 5, 25, 0], ['63305', 11, 25, 0], ['63311', 0, 25, 3], ['63318', 14, 25, 0], ['63319', 19, 25, 0]
] as const).map(([crn, open, capacity, waitlist]) => [crn, { open, capacity, waitlist, waitCapacity: 10 }]))

export const demoData: DemoData ={ terms: [FALL], schedules: { [FALL.termCode]: schedule }, profiles: plans.map(profileFor) }
