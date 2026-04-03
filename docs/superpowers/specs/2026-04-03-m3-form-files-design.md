# M3: New Agent Form + Files View — Mobile Polish Design Spec

**Date:** 2026-04-03
**Package:** M3 (third of 4 mobile polish packages)
**Scope:** New Agent creation form mobile redesign + Files tab mobile polish
**Files:** `static/index.html` (CSS only — no HTML or JS changes)

---

## Context

The New Agent form (drawer) and Files tab work on mobile but inherit desktop-sized typography and spacing. Labels are 9-10px uppercase monospace, inputs are cramped, directory browser items are tiny, color/icon pickers are cut off. The Files tab has small text and insufficient touch targets.

All changes are CSS overrides inside `@media (max-width: 767px)`.

---

## 1. New Agent Form (Drawer)

### Typography

| Element | Current | New (mobile) |
|---------|---------|-------------|
| `.drawer-label` | 9px uppercase monospace letterspaced | 14px Source Sans 3, normal case, regular weight |
| `.drawer-input` | 13px, ~38px height | 17px, 48px height, 14px padding |
| `.drawer-textarea` | 13px, auto height | 17px, 100px min-height |
| `.drawer-select` | 13px, auto height | 17px, 48px height |
| `.drawer-body` | 12px padding | 16px padding, 20px gap between fields |
| `.drawer-title` | 12px | 16px |
| `.drawer-close` | 24px | 32px tap target |

### Color Picker

- `.color-swatch`: 32px circles (up from 28px), gap 8px
- Wraps to 2 rows naturally — 8 per row at 375px width
- No scroll needed

### Icon Picker

- `.icon-picker`: 4 columns (down from 5) via `grid-template-columns: repeat(4, 1fr)`
- `.icon-cell`: 48px cells (up from 40px)
- `.icon-cell svg`: 26px (up from 22px)

### Directory Browser

- `.dir-browser-list` items: 48px min-height, 15px font
- Folder SVG icons: 20px
- `.dir-browser-up`: 40px tap target
- `.dir-browser-current`: 13px monospace
- `.dir-browser-select`: 48px height, 16px font, border-radius 10px

### Toggle Switch

- `.toggle-row`: 48px min-height, aligned vertically centered

### Launch Button

- `.btn-launch`: 52px height, 17px font, border-radius 12px

### Drawer Body

- `.drawer-body`: padding 16px, gap 20px between `.drawer-field` elements
- Scroll: natural `overflow-y: auto` (already exists)

---

## 2. Files View

### File Tree Items

- `.fp-item`: 48px min-height, 15px font (Source Sans 3)
- Indent: 20px per level with subtle vertical indent line (1px `var(--border)`, left position based on depth)
- Folder/file icons: SVG from existing `SVG_ICONS.folder` and `SVG_ICONS.file` (20px)
- Full-width tap target

### File Tree Header

- `.fp-title`: same "FILES" label styling
- `.fp-path`: 12px monospace for current path breadcrumb
- No structural changes

### File Actions

- Already redesigned in Package F with SVG icons and bottom sheets
- No changes needed

---

## 3. What Does NOT Change

- Desktop drawer layout and styling
- Desktop file tree
- HTML structure of the drawer form
- HTML structure of the file tree
- JavaScript — no functional changes
- Agent creation API
- File browsing API
- Existing bottom sheet file actions (Package F)

---

## 4. Success Criteria

1. Form labels are 14px, legible without squinting
2. All inputs are 48px height with 17px text
3. Color swatches are 32px, icon cells are 48px — easy to tap
4. Directory browser folders are 48px rows with 15px text
5. Launch button is 52px tall, prominent
6. File tree items are 48px min-height with 15px text
7. File tree has SVG folder/file icons
8. Desktop layout completely unchanged
9. All existing functionality preserved
