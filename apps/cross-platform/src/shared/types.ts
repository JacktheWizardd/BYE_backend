// Shared domain types, with desktop-only commands kept on this boundary.
export * from '../../vendor/bye-shared/core/types'
import type { Command as SharedCommand, Snapshot } from '../../vendor/bye-shared/core/types'
export type Command = SharedCommand
  | { kind: 'byeReviews'; professorId: string; filter?: string; sort?: string; more?: boolean }
  | { kind: 'scheduleView'; crns: string[]; active: boolean }
export interface Bridge { command(command: Command): Promise<unknown>; subscribe(listener: (state: Snapshot) => void): () => void }
