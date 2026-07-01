---
title: "feat: Finder carousel navigation"
date: 2026-07-01
status: draft
type: feature
author: opencode
origin: user request
---

# Finder Carousel Navigation

## Problem Frame

The current Finder flow uses linear step-by-step navigation where users answer questions one at a time. Going back requires tapping a back button, and skipping a question requires an explicit "Skip" button. This creates friction when users want to:
- Review previous answers
- Change earlier responses
- Skip questions without thinking about it

A carousel interface would make navigation more intuitive: swipe left to advance (with or without answering), swipe right to go back and change answers. This matches common iOS patterns and reduces cognitive load.

## Scope Boundaries

### In Scope
- Convert Finder from step-by-step to carousel (TabView-based paging)
- Support free navigation between all questions
- Allow changing previous answers (subsequent questions update automatically)
- Visual feedback for answered vs. unanswered questions
- Results page as final carousel page
- Remove explicit "Skip" button (swipe without selecting = skip)

### Out of Scope
- Changes to question logic or scoring
- Changes to result ranking algorithm
- Changes to question order or content
- Changes to result view layout or features
- Changes to Finder start screen

### Deferred for Later
- Page indicator dots (can add if needed)
- Haptic feedback on page changes
- Animation customization
- Accessibility improvements beyond current state

## Requirements

**R1.** Users can swipe left to advance to the next question (with or without selecting an option).

**R2.** Users can swipe right to go back to previous questions.

**R3.** Users can change their answer on any question, and subsequent questions update to reflect the new filter state.

**R4.** The results page appears as the final carousel page after all questions.

**R5.** Visual feedback indicates which questions have been answered vs. unanswered.

**R6.** The carousel supports the existing 5 questions (vibe, complexity, players, duration, category) plus results.

## Key Technical Decisions

### 1. TabView vs. Custom Swipe Implementation

**Decision:** Use SwiftUI `TabView` with `.page` style.

**Rationale:**
- Native iOS paging behavior (momentum, bounce, accessibility)
- Built-in gesture handling (no conflict with existing swipe-back gesture)
- Automatic page indicator support (if needed later)
- Less code to maintain

**Trade-off:** TabView loads all pages upfront, but FinderStepView is lightweight so this is acceptable.

### 2. Auto-Advance After Selection

**Decision:** Do NOT auto-advance after selection.

**Rationale:**
- Users may want to review their selection before advancing
- Manual swipe is more explicit and less surprising
- Matches the "skip by swiping" mental model

**Trade-off:** Requires one extra swipe per question, but reduces accidental advances.

### 3. State Management for Picks

**Decision:** Change `FinderFlow.picks` from `[FinderOption]` to `[FinderOption?]` (optional array).

**Rationale:**
- `nil` = unanswered (skip state)
- Non-nil = answered with specific option
- Supports random access (change answer at any index)
- Simplifies `survivors` computation (skip nil picks)

**Trade-off:** Requires updating all code that reads/writes picks, but makes the model more accurate.

### 4. Page Tracking

**Decision:** Add `visiblePage: Int` to `FinderFlow` to track current carousel page.

**Rationale:**
- Single source of truth for current page
- Enables programmatic navigation (e.g., jump to results)
- Survives view recreation

**Trade-off:** Adds state to manage, but centralizes navigation logic.

### 5. Results Page Integration

**Decision:** Results page is a separate view in the carousel (not a conditional in FinderView).

**Rationale:**
- Cleaner separation of concerns
- Results page can have its own layout (scrollable, different from question layout)
- Easier to test independently

**Trade-off:** Requires passing `FinderFlow` to results page (already done).

## Implementation Units

### U1. Update FinderFlow Model for Carousel

**Goal:** Refactor `FinderFlow` to support random access to picks and page tracking.

**Requirements:** R1, R2, R3, R4

**Dependencies:** None

**Files:**
- `ios/MBGC/Models/FinderFlow.swift`

**Approach:**
1. Change `picks: [FinderOption]` to `picks: [FinderOption?]` (optional array, one per question)
2. Add `visiblePage: Int` property (default 0)
3. Add `select(at index: Int, option: FinderOption)` method to set pick at specific index
4. Add `clearPick(at index: Int)` method to unset pick (skip)
5. Update `survivors` to skip nil picks (treat as "no filter")
6. Update `stepIndex` to return `visiblePage` instead of `picks.count`
7. Add `isPageAnswered(at index: Int) -> Bool` helper
8. Remove `back()` method (carousel handles navigation)
9. Remove `skipEmptySteps()` (no longer needed, users can skip manually)

**Patterns to follow:**
- Existing `FinderFlow` structure (Observable, MainActor)
- Keep `funnel` as source of truth for question count

**Test scenarios:**
- Initialize with empty picks array (all nil)
- Select option at index 0 → picks[0] is set, others remain nil
- Clear pick at index 0 → picks[0] becomes nil
- Survivors with nil picks → no filtering applied for those questions
- Survivors with mixed nil/non-nil picks → only non-nil picks filter
- isPageAnswered returns false for nil pick, true for non-nil pick

**Verification:**
- `FinderFlow` compiles with new signature
- Existing tests (if any) updated to use new API
- Manual test: can set/clear picks at arbitrary indices

---

### U2. Update FinderView to Use TabView Carousel

**Goal:** Replace conditional step rendering with TabView-based carousel.

**Requirements:** R1, R2, R4

**Dependencies:** U1

**Files:**
- `ios/MBGC/Views/FinderView.swift`

**Approach:**
1. Remove conditional rendering (`if flow.isDone`, `else if let axis = flow.currentAxis`)
2. Add `TabView(selection: $flow.visiblePage)` with pages:
   - `ForEach(0..<flow.funnel.count)` → `FinderStepView` for each question
   - Final page (tag = funnel.count) → `FinderResultView`
3. Remove `goingBack` state (carousel handles animation)
4. Remove manual navigation logic (back button, swipe gestures)
5. Keep `sync()` method to update `flow.ownedGames` and `flow.allCollections`
6. Keep start screen and empty state logic (unchanged)

**Patterns to follow:**
- Existing `FinderView` structure (NavigationStack, ZStack)
- Use `.tabViewStyle(.page)` for native paging

**Test scenarios:**
- Carousel shows all 5 questions as separate pages
- Swipe left advances to next page
- Swipe right goes to previous page
- Can swipe from last question to results page
- Can swipe back from results to last question
- Start screen and empty state still work (not in carousel)

**Verification:**
- Carousel navigates smoothly between all pages
- No crashes when swiping rapidly
- Results page appears after last question

---

### U3. Update FinderStepView for Carousel Integration

**Goal:** Refactor `FinderStepView` to work within carousel and show selection state.

**Requirements:** R3, R5

**Dependencies:** U1, U2

**Files:**
- `ios/MBGC/Views/FinderStepView.swift`

**Approach:**
1. Add `axis: FinderAxis` parameter (already present)
2. Add `pageIndex: Int` parameter (to identify which question this is)
3. Add `selectedOption: FinderOption?` parameter (current selection, nil if unanswered)
4. Add `onSelect: (FinderOption) -> Void` callback (already present)
5. Remove header with back/skip buttons (carousel handles navigation)
6. Remove swipe gestures (TabView provides native paging)
7. Highlight selected option if `selectedOption` is non-nil
8. Allow re-selection to change answer (call `onSelect` with new option)

**Patterns to follow:**
- Existing `FinderStepView` layout (question block, option grid/list)
- Use existing `SelectableCard` or similar for selection highlight

**Test scenarios:**
- Step shows question and options
- Selected option is highlighted (if answered)
- Tapping different option updates selection
- No back/skip buttons visible
- Swipe gestures work (provided by TabView, not step view)

**Verification:**
- Step view displays correctly in carousel
- Selection state updates visually
- Can change selection by tapping different option

---

### U4. Update FinderResultView for Carousel Integration

**Goal:** Remove back navigation from results view (carousel handles it).

**Requirements:** R4

**Dependencies:** U2

**Files:**
- `ios/MBGC/Views/FinderResultView.swift`

**Approach:**
1. Remove `onBack` parameter (carousel handles back navigation)
2. Remove `.swipeBack` gesture (TabView provides native paging)
3. Keep results display, pull-to-restart, and menu
4. Keep recommendation details sheet

**Patterns to follow:**
- Existing `FinderResultView` layout (hero card, runners, all games)

**Test scenarios:**
- Results page shows top picks and full list
- Can swipe back to last question
- Pull-to-restart still works
- Menu (share, start over) still works

**Verification:**
- Results page displays correctly as final carousel page
- Swipe back navigates to last question
- All existing features still work

---

### U5. Wire Up Carousel Navigation

**Goal:** Connect FinderView, FinderStepView, and FinderFlow for seamless navigation.

**Requirements:** R1, R2, R3, R5

**Dependencies:** U1, U2, U3, U4

**Files:**
- `ios/MBGC/Views/FinderView.swift`
- `ios/MBGC/Views/FinderStepView.swift`

**Approach:**
1. In `FinderView`, pass `pageIndex`, `selectedOption`, and `onSelect` to each `FinderStepView`
2. In `FinderStepView`, call `flow.select(at: pageIndex, option: option)` when user selects
3. Update `FinderFlow.select(at:option:)` to set pick and optionally advance page (if desired)
4. Add visual indicator for answered vs. unanswered questions (optional, can defer)

**Patterns to follow:**
- Existing `FinderFlow` API (Observable, MainActor)

**Test scenarios:**
- Selecting option on page 0 updates picks[0]
- Swiping to page 1 shows options filtered by picks[0]
- Changing answer on page 0 updates options on page 1
- Can navigate back and forth without losing selections

**Verification:**
- Carousel navigation works end-to-end
- Selections persist across page changes
- Changing previous answer updates subsequent questions

## Test Strategy

### Unit Tests
- `FinderFlow` model: pick selection, clearing, survivors computation
- No UI tests needed (manual testing sufficient for carousel behavior)

### Manual Testing
- Swipe through all questions without answering → results show all games
- Answer some questions, skip others → results filter correctly
- Change answer on previous question → subsequent questions update
- Swipe back and forth rapidly → no crashes or state corruption
- Pull-to-restart on results → carousel resets to page 0

### Edge Cases
- Empty collection → empty state shown (not in carousel)
- No collections → FinderEmptyView shown (not in carousel)
- All questions skipped → results show all games (no filtering)
- Single game in collection → all questions show that game

## Risks and Mitigations

### Risk 1: TabView Performance with Many Pages

**Impact:** Medium
**Likelihood:** Low (only 6 pages: 5 questions + results)

**Mitigation:** TabView loads all pages upfront, but each page is lightweight (question + options). If performance becomes an issue, can switch to lazy loading or custom implementation.

### Risk 2: State Synchronization Between Pages

**Impact:** High
**Likelihood:** Medium

**Mitigation:** `FinderFlow` is single source of truth. All pages read from and write to the same `picks` array. SwiftUI's `@Observable` ensures pages update when picks change.

### Risk 3: Gesture Conflicts with Existing Swipe-Back

**Impact:** Medium
**Likelihood:** Low

**Mitigation:** TabView's paging gesture takes precedence. Remove custom `.swipeBack` gestures from `FinderStepView` and `FinderResultView` to avoid conflicts.

### Risk 4: Breaking Existing Functionality

**Impact:** High
**Likelihood:** Medium

**Mitigation:** Keep start screen and empty state logic unchanged. Only refactor the question/results flow. Test each page independently before integrating.

## Deferred Work

- **Page indicator dots:** Can add `.tabViewStyle(.page(indexDisplayMode: .always))` if needed
- **Haptic feedback on page changes:** Can add `.sensoryFeedback` modifier
- **Animation customization:** Can adjust spring parameters for page transitions
- **Accessibility improvements:** Can add VoiceOver announcements for page changes
- **Question progress indicator:** Can add "Step X of Y" label or progress bar

## Success Criteria

- Users can swipe left/right to navigate between questions
- Users can change previous answers without losing progress
- Results page appears after last question
- No crashes or state corruption during rapid navigation
- Existing functionality (start screen, empty state, results display) still works
- Code is simpler and more maintainable than before

## References

- Current implementation: `ios/MBGC/Models/FinderFlow.swift`, `ios/MBGC/Views/FinderView.swift`, `ios/MBGC/Views/FinderStepView.swift`, `ios/MBGC/Views/FinderResultView.swift`
- SwiftUI TabView documentation: https://developer.apple.com/documentation/swiftui/tabview
- iOS Human Interface Guidelines: Paging https://developer.apple.com/design/human-interface-guidelines/paging
