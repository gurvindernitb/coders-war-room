# M1: Mobile Chat View — Design Spec

**Date:** 2026-04-03
**Package:** M1 (first of 4 mobile polish packages)
**Scope:** Mobile chat view only (`@media (max-width: 767px)`)
**File:** `static/index.html` (CSS + JS changes only)

---

## Context

The Coder's War Room web UI has a working mobile layout (tab bar, bottom sheets, file browser, agent picker) but the chat view needs polish to feel like a native messaging app. This spec defines the iMessage-inspired hybrid design for mobile chat.

Desktop layout is NOT touched. All changes are scoped inside the mobile media query.

---

## 1. Message Layout — Hybrid iMessage Style

### User messages (gurvinder)

- **Alignment:** right-aligned
- **Background:** `var(--green-bubble-bg)` — defined as `rgba(0, 230, 118, 0.12)`
- **Border-radius:** 16px 16px 4px 16px (flat bottom-right corner, like iMessage sent bubbles)
- **Max-width:** 80% of chat width
- **Sender name:** hidden (it's obviously the user)
- **Timestamp:** 11px, dim, below the bubble on the right
- **Text color:** `var(--text-primary)` (white-ish on dark bg)

### Agent messages

- **Alignment:** left-aligned
- **Background:** `var(--bg-card)` (existing dark card color)
- **Border-left:** 4px solid, agent-specific color (existing colored border)
- **Border-radius:** 4px 12px 12px 12px (flat top-left where the border is)
- **Max-width:** 85% of chat width
- **Sender name:** 12px, JetBrains Mono, bold, agent color
- **Timestamp:** 11px, JetBrains Mono, dim, inline after sender name
- **Text color:** `var(--text-primary)`

### System messages

- **Alignment:** centered
- **Style:** no bubble, dim italic text, 12px
- **No sender name, no timestamp** (system messages are informational)

### Direct messages (@you)

- **Same as agent message** but with a subtle orange-tinted left border or faint orange background tint
- Uses existing `var(--orange-dim)` at reduced opacity

---

## 2. Typography

| Element | Font | Size | Weight | Line-height | Color |
|---------|------|------|--------|-------------|-------|
| Message body | Source Sans 3 | 16px | 400 | 1.5 | `--text-primary` |
| Sender name | JetBrains Mono | 12px | 700 | 1 | agent color |
| Timestamp | JetBrains Mono | 11px | 400 | 1 | `--text-dim` |
| Time divider | JetBrains Mono | 10px | 400 | 1 | `--text-dim` |
| System message | Source Sans 3 | 12px | 400 (italic) | 1.4 | `--text-dim` |

---

## 3. Message Grouping

### Rules

1. **Never group across different agents** — every sender change shows full header
2. **Same agent, consecutive, within 20 seconds** — stack tight (4px gap), header on first message only
3. **Same agent, consecutive, 20+ seconds apart** — show full header again
4. **Time dividers** — after 5+ minute gap between any messages, insert centered divider: `── 12:45 PM ──`
5. **Day dividers** — when messages cross midnight: `── Today ──`, `── Yesterday ──`, or `── Mon, 31 Mar ──`

### Grouping CSS

- Grouped messages (same agent, <20s): `margin-top: 4px`, no header
- Non-grouped messages: `margin-top: 12px`, full header
- Time dividers: `margin: 16px 0`, centered, dim text with horizontal rules

---

## 4. Input Bar

### Layout (bottom to top)

```
  Tab bar (existing, fixed at bottom)
  ─────────────────────────────────────
  Input bar (fixed above tab bar)
  ┌─────────────────────────────────┐
  │ @supervisor ▼                   │   ← target chip (tappable)
  │ [📄 state.py  ✕]               │   ← attachment chip (if attached)
  │ ┌─────────────────────────────┐ │
  │ │ 📎 │ Message...         │🟢│ │   ← pill input
  │ └─────────────────────────────┘ │
  └─────────────────────────────────┘
```

### Input pill

- **Shape:** border-radius 20px, 1px solid `var(--border)`, background `var(--bg-input)`
- **Height:** single line (40px min), expands to max 3 lines (~88px)
- **Left icon:** 📎 paperclip, 20px, always visible, tappable — opens attachment bottom sheet
- **Right icon:** green circular send button (28px diameter), appears only when input has text
- **Font:** 16px Source Sans 3 (prevents iOS zoom)
- **Placeholder:** "Message the war room..." in `var(--text-dim)`

### Target chip

- **Position:** above the pill, left-aligned
- **Style:** `@name ▼` in 11px JetBrains Mono, green text
- **Tap action:** opens agent picker bottom sheet (existing `showBottomSheet`)

### Attachment chip

- **Position:** between target chip and pill
- **Style:** inline-block, rounded pill (border-radius 12px), bg `var(--bg-card)`, border `var(--border)`
- **Content:** file icon + filename (truncated to 25 chars) + ✕ remove button
- **Tap ✕:** removes attachment, hides chip

### Send button behavior

- **Hidden** when input is empty and no attachment
- **Visible** (green circle with white arrow ▲) when input has text OR attachment is present
- **Tap:** sends message with optional attachment reference

---

## 5. Scroll Fix

### Problem

The last message in chat gets buried under the fixed input bar. Hard to pull up.

### Solution

1. **ResizeObserver** on the input bar — when it grows (multi-line text, attachment chip), recalculate bottom padding on `.messages`
2. **Bottom padding formula:** `messages.style.paddingBottom = inputBar.offsetHeight + tabBar.offsetHeight + 16 + 'px'`
3. **Auto-scroll on new message:** after `renderMsg()`, if user was already near the bottom (within 100px), scroll to bottom. If user has scrolled up to read history, don't force-scroll (show a "new message" indicator instead — future enhancement).
4. **On page load:** scroll to bottom immediately

---

## 6. CSS Variables (new, mobile only)

```css
--bubble-radius-sent: 16px 16px 4px 16px;
--bubble-radius-received: 4px 12px 12px 12px;
--bubble-max-width-sent: 80%;
--bubble-max-width-received: 85%;
--green-bubble-bg: rgba(0, 230, 118, 0.12);
--input-pill-radius: 20px;
--input-pill-height: 40px;
--send-btn-size: 28px;
```

---

## 7. What Does NOT Change

- Desktop CSS — untouched, all changes inside `@media (max-width: 767px)`
- Color scheme, font families, header layout
- WebSocket logic, message sending, agent picker, bottom sheets
- File upload endpoint, attachment flow backend
- Message data format (sender, content, timestamp, target)

---

## 8. Detection: User vs Agent Messages

The `renderMsg()` function already receives message data with `sender` field. To determine bubble alignment:

```javascript
const isUser = (m.sender === 'gurvinder');
```

User messages → right-aligned green bubble.
All other senders → left-aligned agent card.

---

## 9. Success Criteria

1. Messages from gurvinder render as right-aligned green bubbles with rounded corners
2. Agent messages render as left-aligned rounded cards with colored left border
3. Input bar is always visible above the tab bar, never hidden
4. Input expands from 1 to 3 lines, padding adjusts dynamically
5. Paperclip opens attachment bottom sheet, attachment chip appears
6. Send button only visible when there's content to send
7. Last message always scrollable into full view above input bar
8. Grouping: same agent within 20s stacks tight, everything else gets full header
9. Time dividers appear after 5+ minute gaps
10. Desktop layout completely unchanged

---

*This spec covers M1 only. M2 (Agents), M3 (Files), M4 (Header + Navigation) are separate packages.*
