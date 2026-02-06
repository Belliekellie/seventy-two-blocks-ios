# 72 Blocks - App Logic Reference

This document describes how the 72 Blocks app works across iOS and Web versions, for AI assistant context.

## Core Concept

72 Blocks divides each day into 72 twenty-minute blocks. Users track what they work on during each block using a timer system that records segments of work and breaks.

---

# iOS App (`seventy-two-blocks-ios`)

## Block Structure

- **72 blocks per day**, each 20 minutes (1200 seconds)
- **Block indices 0-71** map to times throughout the day (index 0 = midnight, index 3 = 1:00 AM, etc.)
- **Day start hour** is configurable (default 6 AM) - affects "logical today" calculation
- **Display numbers** differ from indices:
  - Morning (indices 24-47) → Display 1-24
  - Afternoon (indices 48-71) → Display 25-48
  - Night (indices 0-23) → Display 49-72

## Block Status

| Status | Meaning |
|--------|---------|
| `.idle` | Not touched, no data |
| `.planned` | Has category/label set but timer never ran |
| `.done` | User worked on it (can be partial OR full - see below) |
| `.skipped` | Explicitly skipped by user or auto-skip |

**CRITICAL**: `.done` does NOT mean 100% filled. It means "user worked on this block". A block can be `.done` with 10%, 50%, or 100% fill. The fill is determined by segments, not status.

## Status vs Fill (Critical Distinction)

These are **INDEPENDENT** concepts:

| Concept | Determined By | Controls |
|---------|--------------|----------|
| **Status** (`.done`) | Whether user worked on block | Time breakdown UI, completed styling, "finished" state |
| **Fill** (color) | `segments` array | Visual fill percentage in grid |
| **Progress** | `usedSeconds / 1200` | Percentage display |

A block marked `.done` shows the time breakdown view, minutes worked, etc. But its fill can be partial (e.g., 50%) if the user only worked 10 minutes.

## Timer Logic

### Starting a Timer
- Timer always runs to **block boundary**, not for a fixed duration
- Starting mid-block means less than 20 minutes remaining
- Cannot start timer on past or future blocks - only current time block

### Timer Completion
- When timer reaches block boundary → `handleTimerComplete()`
- Shows `TimerCompleteDialog` with options:
  - Continue Working (starts timer on next/current block)
  - Take a Break
  - New Block (opens block sheet)
  - Skip Next Block
  - Stop (ends session)

### Auto-Continue
- 25-second countdown for work completion
- 30-second countdown for break notification
- Countdown is epoch-based (survives app backgrounding)
- After N blocks without user interaction → check-in mode (no auto-continue)

## Segments System

Each block has a `segments` array tracking work/break periods:

```swift
struct BlockSegment {
    let type: SegmentType  // .work or .break
    let seconds: Int       // duration
    let category: String?  // only for work segments
    let label: String?     // only for work segments
    let startElapsed: Int  // when this segment started
}
```

### Segment Rendering
- **Fill proportion** = `segment.seconds / 1200`
- Work segments use category color
- Break segments are always **red**
- Multiple segments = multi-color fill bar

### Live vs Previous Segments
- `previousSegments`: From earlier timer sessions on this block (already saved)
- `liveSegments`: Created during current timer session
- `sessionScaleFactor`: Maps real seconds to visual proportion for current session

## Scale Factor System

When a block has multiple timer sessions (stop/restart), each session occupies real time but must fit within remaining visual space.

**Formula**: `sessionScaleFactor = remainingVisualProportion / remainingRealTime`

This ensures:
- First session: full visual space available
- Subsequent sessions: scale factor adjusted so fill reaches 100% at block end
- All math done in proportion space (0..1), converted to pixels only for rendering

## Pause System (iOS-specific)

### Pause Behavior
- `isPaused` is explicit `@Published` state (not computed)
- Pause stops the timer but **block time continues** (real time passes)
- Fill stays at paused position (stored in `secondsUsedAtPause`)
- FloatingTimerBar stays visible when paused (shows Resume button)

### Resume Behavior
- Recalculates `timeLeft` based on remaining block time
- Recalculates `sessionScaleFactor` so fill reaches 100% at block end
- If block time already elapsed → shows `PausedExpiryDialog`

### Paused Expiry Dialog
- Shown when block time ends while timer was paused
- **NO auto-continue** (user was away)
- Options: Continue Working, Take Break, New Block, Stop
- Saves partial block data before any action

## Break System

### Break Mode
- Same timer, runs to block boundary
- Break segments rendered in **red**
- `lastWorkCategory`/`lastWorkLabel` preserved for "Back to Work"

### 5-Minute Break Notification
- `showBreakComplete` triggers mid-block popup
- Timer **keeps running** during this popup
- "Keep Resting" dismisses popup, break continues
- "Back to Work" switches to work mode

### Break Leak Behavior
- If break completes as block time expires, break can extend into NEXT block
- Preserves work context for when user returns to work

## FloatingTimerBar

- Shows when timer is active OR paused (`shouldShow = isActive || isPaused`)
- Three buttons: Break/Work toggle, Pause/Resume, Stop
- Break button disabled when paused
- Multi-segment progress bar shows work/break segments in colors

## Block Grid Rendering (BlockGridView)

### Active Block Detection
```swift
isTimerActiveOnThisBlock = isViewingToday && (timerManager.isActive || timerManager.isPaused) && timerManager.currentBlockIndex == blockIndex
```

### Fill Rendering
- For active blocks: Uses `timerManager.previousSegments` + `timerManager.liveSegmentsIncludingCurrent`
- For past blocks: Uses saved `block.segments`
- Minimum fill (sliver) applied when `totalSeconds < 60`

### Styling
- Bold labels on blocks
- Thick border on active block (including when paused)
- Category color from segments

## Background Handling

### Entering Background
- `saveStateForBackground()` saves current snapshot

### Returning to Foreground
1. `restoreFromBackground()` - recovers timer state
2. If timer expired while backgrounded → `handleTimerComplete()`
3. If paused and block time elapsed → `resumeTimer()` → shows paused expiry dialog
4. Check-in grace period (20 min) for auto-stop after long absence
5. Date switch if day changed and user not actively working

## Haptic Feedback

- Haptic generators pre-created at init for instant response
- `prepare()` called after each use for next response
- Avoids 2-3 second delay on first button press

## Key iOS Files

| File | Purpose |
|------|---------|
| `TimerManager.swift` | Timer state, segments, pause/resume, completion |
| `MainView.swift` | Dialog handling, callbacks, foreground recovery |
| `FloatingTimerBar.swift` | Timer UI with pause/resume/stop buttons |
| `BlockGridView.swift` | Grid rendering, fill from segments |
| `BlockSheetView.swift` | Block detail sheet with time breakdown |
| `AudioManager.swift` | Sounds and haptic feedback |

---

# Web App (`seventy-two-blocks`)

## Tech Stack

- **Framework**: React 18.3 with TypeScript
- **Styling**: Tailwind CSS + Shadcn/UI components
- **State Management**: React Context (BlockTimerProvider) + TanStack React Query v5
- **Database**: Supabase PostgreSQL
- **Build Tool**: Vite with React SWC

## Data Model

### BlockSegment (same as iOS)
```typescript
{
  type: 'work' | 'break',
  seconds: number,
  category?: string | null,
  label?: string | null,
  startElapsed?: number
}
```

### Run (Web-specific - groups segments by timer session)
```typescript
{
  id: string,                    // UUID for this run
  startedAt: number,             // epoch ms
  endedAt: number | null,        // null if active
  initialRealTime: number,       // real seconds when run started
  scaleFactor: number,           // LOCKED for run lifetime
  segments: BlockSegment[],      // finalized segments within this run
  // Transient fields (not persisted):
  currentSegmentStart, currentType, currentCategory, lastWorkCategory
}
```

### Block (database row)
```typescript
{
  id: string,
  user_id: string,
  date: string,                  // YYYY-MM-DD (CRITICAL format)
  block_index: number,           // 0-71
  is_muted: boolean,             // sleep blocks
  is_activated: boolean,
  category: string | null,
  label: string | null,
  status: 'idle' | 'planned' | 'done' | 'skipped',
  progress: number,              // 0-100
  break_progress: number,        // 0-100
  runs: Run[],                   // completed runs
  activeRunSnapshot: Run | null, // in-progress run for crash recovery
  segments: BlockSegment[],      // DEPRECATED legacy format
  used_seconds: number           // if > 0, block can NEVER be skipped
}
```

## Timer Architecture (useBlockTimer.tsx)

### TimerState
```typescript
{
  blockIndex, timeLeft, initialTime, isActive,
  isBreak: boolean,
  date: string,
  blockData: { category, label, note, status },
  activeRunId: string,           // UUID, LOCKED for run lifetime
  sessionScaleFactor: number,    // LOCKED visual conversion
  liveSegments: BlockSegment[],  // MEMORY ONLY
  currentSegmentStartElapsed: number,
  currentType: 'work' | 'break',
  currentCategory, currentLabel,
  lastWorkCategory, lastWorkLabel,
  breakElapsed: number,
  breakReminderShown: boolean
}
```

### Key Methods
- `startTimer()` - Creates explicit initial segment, maps to database run
- `splitLiveSegment()` - Creates segment boundary without stopping timer
- `startBreakTimer()` - Switches segment type, main timer unchanged
- `stopTimer()` - Returns final run data for persistence

### Completion Flow
1. Timer hits 0s → completion effect
2. Plays bell sound (Web Audio API with harmonics)
3. `onTimerComplete` callback → persists run → shows dialog
4. `stopTimer()` called AFTER dialog shown

## Run Management & Persistence

### Run Lifecycle
1. `startRunForBlock()` - Fetches fresh DB, calculates runParams, starts timer
2. Active in memory - liveSegments growing, activeRunId locked
3. Autosave every 5s to `activeRunSnapshot` field
4. Completion - Finalizes run, appends to `runs[]`, clears snapshot

### Key Rules
- `runs[]` contains ONLY completed runs (endedAt !== null)
- `activeRunSnapshot` stores in-progress run for crash tolerance
- `used_seconds > 0` prevents block from being skipped
- Transient fields never persisted

## Segment Editing

### Label Changes During Work
1. Committed label tracked when entering work mode
2. On blur: if changed → `splitLiveSegment()`
3. Minimum 10s threshold for label-only changes (prevents micro-segments)

### Break Interruptions
1. Current work segment finalized
2. Break segment starts at same elapsed time
3. `lastWorkCategory`/`lastWorkLabel` preserved
4. Restored when switching back to work

## Dialog Flows

### Work Block Completion
```
Timer hits 0s → playDingSound() → handleTimerComplete()
  → Persist run → Show TimerCompleteDialog (25s countdown)
  → [Continue] / [Break] / [Start New] / [Skip Next]
```

### Break Completion
```
5-min break hits 0s → Show BreakCompleteDialog (30s countdown)
  → [Back to Work] / [Continue Break] / [Stop] / [Start New]
```

### Set Celebration
Every 12 completed work blocks triggers celebration screen.

## Key Web Files

| File | Purpose |
|------|---------|
| `useBlockTimer.tsx` | Timer context, state, segment management |
| `Index.tsx` | Main page, dialog handling, run persistence |
| `BlockItem.tsx` | Individual block rendering with segments |
| `BlockSheet.tsx` | Block edit interface |
| `TimerCompleteDialog.tsx` | Work completion dialog |
| `BreakCompleteDialog.tsx` | Break completion dialog |

---

# Cross-Platform Patterns

## Shared Concepts

| Concept | iOS | Web |
|---------|-----|-----|
| Block indices | 0-71 | 0-71 |
| Block duration | 1200 seconds | 1200 seconds |
| Status values | idle/planned/done/skipped | idle/planned/done/skipped |
| Segment structure | type/seconds/category/label | type/seconds/category/label |
| Scale factor | sessionScaleFactor | scaleFactor per run |
| Break color | Red | Red (destructive) |
| Auto-continue | 25s work, 30s break | 25s work, 30s break |

## Key Differences

| Feature | iOS | Web |
|---------|-----|-----|
| Pause | Explicit `isPaused` state | No pause (use break instead) |
| Run model | Flat segments + previousSegments | Structured `runs[]` array |
| Crash recovery | `saveStateForBackground()` | `activeRunSnapshot` autosave |
| Audio | System sounds + haptics | Web Audio API bell |
| Background | Full background support | Tab visibility handling |

## Common Gotchas (Both Platforms)

1. **Status ≠ Fill**: A `.done` block can have partial fill. Always use segments for fill.
2. **Block boundary timing**: Timer runs to block end, not for fixed 20 minutes.
3. **Scale factor locked**: Once a session starts, its scale factor is fixed.
4. **Category during break**: Work category preserved but not written to break segments.
5. **Auto-continue suppression**: Check-in mode after N blocks without interaction.
6. **Segment normalization**: Filter zero/negative, merge consecutive same-type segments.

## Data Consistency Rules

1. **Natural key**: user_id + date + block_index (never rely on UUID for overwrites)
2. **Date format**: YYYY-MM-DD (length 10, no 'T')
3. **used_seconds > 0**: Block can never be auto-skipped
4. **Segments determine fill**: Not status, not progress field
5. **Fresh fetch before write**: Prevents stale data overwrites
