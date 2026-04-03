# M3: New Agent Form + Files View — Mobile Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the New Agent creation form and Files tab feel native on iPhone with proper font sizes, touch targets, and spacing — CSS-only changes inside the mobile media query.

**Architecture:** All changes are CSS overrides added inside the existing `@media (max-width: 767px)` block in `static/index.html`. No HTML or JavaScript changes. Desktop layout completely untouched.

**Tech Stack:** Vanilla CSS only.

---

## File Map

| File | Action | What changes |
|------|--------|-------------|
| `static/index.html` | Modify | Add mobile CSS overrides for drawer form + file tree inside `@media (max-width: 767px)` |

---

### Task 1: Drawer Form — Typography + Spacing

**Files:**
- Modify: `static/index.html` — mobile CSS block

This task upgrades all form field typography and spacing for mobile.

- [ ] **Step 1: Add drawer form mobile CSS**

Inside the `@media (max-width: 767px)` block, find the existing drawer overrides:
```css
    .drawer { width: 100%; right: -100%; }
    .drawer.open { right: 0; }
```

Add AFTER those two lines:

```css
    /* ═══ Drawer form — mobile typography ═══ */
    .drawer-title {
      font-size: 16px;
    }

    .drawer-close {
      width: 32px;
      height: 32px;
      font-size: 24px;
      display: flex;
      align-items: center;
      justify-content: center;
    }

    .drawer-body {
      padding: 16px;
    }

    .drawer-field {
      margin-bottom: 20px;
    }

    .drawer-label {
      font-family: 'Source Sans 3', -apple-system, sans-serif;
      font-size: 14px;
      font-weight: 500;
      text-transform: none;
      letter-spacing: 0;
      margin-bottom: 8px;
    }

    .drawer-input {
      font-size: 17px;
      min-height: 48px;
      padding: 12px 14px;
      border-radius: 10px;
    }

    .drawer-textarea {
      font-size: 17px;
      min-height: 100px;
      padding: 12px 14px;
      border-radius: 10px;
      line-height: 1.5;
    }

    .drawer-select {
      font-size: 17px;
      min-height: 48px;
      padding: 12px 14px;
      border-radius: 10px;
      -webkit-appearance: none;
      appearance: none;
      background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='12' viewBox='0 0 24 24' fill='none' stroke='%237a8a9e' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpolyline points='6 9 12 15 18 9'%3E%3C/polyline%3E%3C/svg%3E");
      background-repeat: no-repeat;
      background-position: right 14px center;
      padding-right: 36px;
    }

    .toggle-row {
      min-height: 48px;
      display: flex;
      align-items: center;
    }

    .toggle-row .drawer-label {
      font-size: 14px;
    }

    .btn-launch {
      min-height: 52px;
      font-size: 17px;
      border-radius: 12px;
    }
```

- [ ] **Step 2: Verify desktop drawer CSS is untouched**

Run:
```bash
grep -A 3 '  .drawer-label {' static/index.html | head -5
```
Expected: the desktop styles (9px, uppercase, letterspaced) should still be there at their original line numbers.

- [ ] **Step 3: Commit**

```bash
git add static/index.html
git commit -m "feat(m3): step 1 — drawer form mobile typography and spacing"
```

---

### Task 2: Color + Icon Pickers — Bigger Touch Targets

**Files:**
- Modify: `static/index.html` — mobile CSS block

This task makes the color swatches and icon grid cells bigger for mobile.

- [ ] **Step 1: Add picker mobile CSS**

Inside the `@media (max-width: 767px)` block, add AFTER the drawer form styles from Task 1:

```css
    /* ═══ Color + Icon Pickers — mobile ═══ */
    .color-picker {
      gap: 8px;
      padding: 8px 0;
    }

    .color-swatch {
      width: 32px;
      height: 32px;
    }

    .icon-picker {
      grid-template-columns: repeat(4, 1fr);
      gap: 6px;
      padding: 8px 0;
    }

    .icon-cell {
      width: auto;
      height: 48px;
      border-radius: 10px;
    }

    .icon-cell svg {
      width: 26px;
      height: 26px;
    }
```

- [ ] **Step 2: Commit**

```bash
git add static/index.html
git commit -m "feat(m3): step 2 — color and icon pickers mobile touch targets"
```

---

### Task 3: Directory Browser — Bigger Rows

**Files:**
- Modify: `static/index.html` — mobile CSS block

This task makes the directory browser inside the creation form touch-friendly.

- [ ] **Step 1: Add directory browser mobile CSS**

Inside the `@media (max-width: 767px)` block, add AFTER the picker styles from Task 2:

```css
    /* ═══ Directory Browser — mobile ═══ */
    .dir-browser {
      border-radius: 10px;
    }

    .dir-browser-path {
      padding: 10px 12px;
    }

    .dir-browser-up {
      width: 40px;
      height: 40px;
      min-width: 40px;
      font-size: 16px;
    }

    .dir-browser-current {
      font-size: 13px;
    }

    .dir-browser-item {
      min-height: 48px;
      padding: 12px 14px;
      font-size: 15px;
      display: flex;
      align-items: center;
      gap: 10px;
    }

    .dir-browser-select {
      min-height: 48px;
      font-size: 16px;
      border-radius: 10px;
      margin: 10px;
    }
```

- [ ] **Step 2: Commit**

```bash
git add static/index.html
git commit -m "feat(m3): step 3 — directory browser mobile touch targets"
```

---

### Task 4: Files Tab — Tree Polish

**Files:**
- Modify: `static/index.html` — mobile CSS block

This task upgrades the Files tab tree view for mobile.

- [ ] **Step 1: Replace existing fp-item mobile override**

Find the existing mobile override:
```css
    .fp-item { padding: 10px 12px; font-size: 13px; min-height: 44px; }
```

Replace with:

```css
    /* ═══ File tree — mobile ═══ */
    .fp-item {
      padding: 12px 14px;
      font-size: 15px;
      min-height: 48px;
      display: flex;
      align-items: center;
      gap: 10px;
      -webkit-tap-highlight-color: transparent;
    }

    .fp-head {
      padding: 10px 14px;
    }

    .fp-title {
      font-size: 12px;
    }

    .fp-path {
      font-size: 12px;
    }

    .fp-tree {
      padding: 0 4px;
    }
```

- [ ] **Step 2: Verify the old override is gone**

Run:
```bash
grep 'fp-item.*13px' static/index.html
```
Expected: no output (the 13px override was replaced)

- [ ] **Step 3: Commit**

```bash
git add static/index.html
git commit -m "feat(m3): step 4 — file tree mobile polish"
```

---

### Task 5: Final Verification + Push

**Files:**
- No modifications — verification only

- [ ] **Step 1: Restart server**

```bash
cd ~/coders-war-room
lsof -ti :5680 2>/dev/null | xargs kill -9 2>/dev/null; sleep 2
nohup python3 server.py > /tmp/warroom-server.log 2>&1 &
sleep 3
curl -s http://localhost:5680/api/server/health | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'{d[\"status\"]} — {d[\"agent_count\"]} agents')"
```

- [ ] **Step 2: Verify desktop is unchanged**

Check that desktop drawer label is still 9px uppercase:
```bash
grep -A 4 '  .drawer-label {' static/index.html | head -6
```
Expected: first match shows desktop styles (9px, uppercase), second match shows mobile override (14px, normal case)

- [ ] **Step 3: Check file size**

```bash
wc -l static/index.html
```
Expected: ~3560-3580 lines (was ~3500, adding ~60-80 lines of CSS)

- [ ] **Step 4: Verify in Chrome**

Open http://localhost:5680 in Chrome. Use DevTools to toggle mobile viewport (375px width). Check:
- Open the "+ new" drawer — labels should be 14px, inputs 48px tall
- Directory browser items should be 48px tall
- Switch to Files tab — items should be 48px tall with 15px font

- [ ] **Step 5: Push**

```bash
git push origin main
```

- [ ] **Step 6: Screenshot request**

Ask Gurvinder to screenshot the New Agent form and Files tab on iPhone.

---

## Success Criteria Checklist

| # | Criterion | Task |
|---|-----------|------|
| 1 | Form labels 14px, legible | Task 1 |
| 2 | All inputs 48px height, 17px text | Task 1 |
| 3 | Color swatches 32px, icon cells 48px | Task 2 |
| 4 | Directory browser 48px rows, 15px text | Task 3 |
| 5 | Launch button 52px, prominent | Task 1 |
| 6 | File tree items 48px, 15px text | Task 4 |
| 7 | Desktop unchanged | Task 5 |
| 8 | All functionality preserved | Task 5 |
