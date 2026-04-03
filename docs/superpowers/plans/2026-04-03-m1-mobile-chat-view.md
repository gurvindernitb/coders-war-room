# M1: Mobile Chat View — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform the mobile chat view into an iMessage-style hybrid layout with user bubbles on the right, agent cards on the left, pill-shaped input bar, 20-second grouping, and dynamic scroll fix.

**Architecture:** Single-file changes to `static/index.html`. Mobile CSS overrides inside the existing `@media (max-width: 767px)` block. JavaScript changes to `renderMsg()` for bubble detection and grouping, plus new ResizeObserver for scroll padding. Desktop layout completely untouched.

**Tech Stack:** Vanilla CSS + JavaScript. No dependencies.

---

## File Map

| File | Action | What changes |
|------|--------|-------------|
| `static/index.html` lines 1125-1360 | Modify | Mobile CSS: replace message styles, input bar pill, new CSS variables |
| `static/index.html` lines 1396-1404 | Modify | Input bar HTML: restructure for pill layout with attachment chip |
| `static/index.html` line 1605-1657 | Modify | `renderMsg()`: user detection, bubble classes, timestamp grouping |
| `static/index.html` line 1990 | Modify | `scrollEnd()`: smart scroll with ResizeObserver |

All changes are in one file: `static/index.html`.

---

### Task 1: CSS Variables + Message Bubble Styles

**Files:**
- Modify: `static/index.html` — mobile CSS block (lines 1125-1360)

This task replaces the current flat message cards with iMessage-style bubbles on mobile.

- [ ] **Step 1: Add mobile CSS variables**

Inside `@media (max-width: 767px) {`, at the very top (after the opening brace, before the tab bar rules), add:

```css
    /* ═══ Mobile CSS Variables ═══ */
    :root {
      --bubble-radius-sent: 16px 16px 4px 16px;
      --bubble-radius-received: 4px 12px 12px 12px;
      --bubble-max-sent: 80%;
      --bubble-max-received: 85%;
      --green-bubble-bg: rgba(0, 230, 118, 0.12);
      --input-pill-radius: 20px;
      --input-pill-height: 40px;
      --send-btn-size: 28px;
    }
```

- [ ] **Step 2: Replace mobile message styles**

Find the existing mobile message overrides (lines ~1269-1273):
```css
    /* ═══ Messages ═══ */
    .messages { padding: 12px 12px; }
    .msg { padding: 8px 10px; }
    .msg-body { font-size: 15px; }
    .msg-sender { font-size: 12px; }
```

Replace with the full bubble system:

```css
    /* ═══ Messages — iMessage Hybrid ═══ */
    .messages {
      padding: 12px 12px;
      display: flex;
      flex-direction: column;
    }

    /* Base message — agent card (left-aligned) */
    .msg {
      padding: 10px 12px;
      border-radius: 4px 12px 12px 12px;
      background: var(--bg-card);
      border-left: 4px solid var(--border);
      max-width: 85%;
      align-self: flex-start;
      margin-bottom: 2px;
    }

    .msg-body {
      font-family: 'Source Sans 3', -apple-system, sans-serif;
      font-size: 16px;
      line-height: 1.5;
    }

    .msg-sender { font-size: 12px; font-weight: 700; }
    .msg-time { font-size: 11px; }

    /* User message — right-aligned green bubble */
    .msg.msg-user {
      align-self: flex-end;
      background: var(--green-bubble-bg);
      border-left: none;
      border-radius: 16px 16px 4px 16px;
      max-width: 80%;
      text-align: left;
    }

    .msg.msg-user .msg-head { display: none; }

    .msg.msg-user .msg-time-below {
      display: block;
      text-align: right;
      font-family: 'JetBrains Mono', monospace;
      font-size: 11px;
      color: var(--text-dim);
      margin-top: 4px;
    }

    /* Direct messages — orange tint on border */
    .msg.direct {
      border-left-color: var(--orange);
      background: var(--bg-card);
    }

    .msg.msg-user.direct {
      border-left: none;
      background: rgba(255, 145, 0, 0.10);
    }

    /* System messages — centered, no bubble */
    .msg.system {
      align-self: center;
      max-width: 90%;
      background: transparent;
      border-left: none;
      text-align: center;
      font-size: 12px;
      font-style: italic;
      color: var(--text-dim);
      padding: 4px 12px;
      margin: 4px 0;
    }

    /* Grouping: same sender within 20s */
    .msg.grouped {
      margin-top: 4px;
      border-radius: 4px 12px 12px 12px;
    }

    .msg.msg-user.grouped {
      border-radius: 16px 16px 4px 16px;
    }

    .msg.grouped .msg-head { display: none; }
    .msg.msg-user.grouped .msg-time-below { display: none; }

    .msg.group-start {
      margin-top: 12px;
    }

    .msg.standalone {
      margin-top: 12px;
      margin-bottom: 2px;
    }

    /* Time divider */
    .time-divider {
      align-self: center;
      font-family: 'JetBrains Mono', monospace;
      font-size: 10px;
      color: var(--text-dim);
      padding: 4px 12px;
      margin: 16px 0;
      display: flex;
      align-items: center;
      gap: 8px;
    }

    .time-divider::before, .time-divider::after {
      content: '';
      flex: 1;
      height: 1px;
      background: var(--border);
    }
```

- [ ] **Step 3: Verify desktop styles are unchanged**

Open the file and confirm that the desktop `.msg` styles (lines 343-379) are NOT modified. The mobile overrides only exist inside `@media (max-width: 767px)`.

Run: `grep -c '@media (max-width: 767px)' static/index.html`
Expected: `1` (single media query block)

- [ ] **Step 4: Commit**

```bash
git add static/index.html
git commit -m "feat(m1): step 1 — mobile bubble CSS variables and message styles"
```

---

### Task 2: Update renderMsg() for User Detection + Timestamp Grouping

**Files:**
- Modify: `static/index.html` — `renderMsg()` function (lines 1605-1657)

This task changes the JavaScript to detect user vs agent messages, apply the right CSS classes, and implement 20-second timestamp grouping with time dividers.

- [ ] **Step 1: Replace `lastSender` tracking with richer grouping state**

Find lines 1605-1606:
```javascript
let lastSender = null;
```

Replace with:
```javascript
let lastSender = null;
let lastTimestamp = null;
```

- [ ] **Step 2: Add time divider and formatting helpers**

Insert BEFORE the `renderMsg` function:

```javascript
function formatTimeDivider(dateStr) {
  const d = new Date(dateStr);
  const now = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const msgDay = new Date(d.getFullYear(), d.getMonth(), d.getDate());
  const diffDays = Math.floor((today - msgDay) / 86400000);

  if (diffDays === 0) return 'Today';
  if (diffDays === 1) return 'Yesterday';
  const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return `${days[d.getDay()]}, ${d.getDate()} ${months[d.getMonth()]}`;
}

function formatTimeShort(dateStr) {
  const d = new Date(dateStr);
  let h = d.getHours();
  const m = String(d.getMinutes()).padStart(2, '0');
  const ampm = h >= 12 ? 'PM' : 'AM';
  h = h % 12 || 12;
  return `${h}:${m} ${ampm}`;
}

function shouldShowTimeDivider(prevTs, currTs) {
  if (!prevTs || !currTs) return false;
  const prev = new Date(prevTs);
  const curr = new Date(currTs);
  // Different day — always show divider
  if (prev.toDateString() !== curr.toDateString()) return true;
  // Same day, 5+ minute gap
  return (curr - prev) > 300000;
}

function isSameGroup(prevSender, prevTs, currSender, currTs) {
  if (prevSender !== currSender) return false;
  if (!prevTs || !currTs) return false;
  return (new Date(currTs) - new Date(prevTs)) < 20000; // 20 seconds
}
```

- [ ] **Step 3: Replace the renderMsg() function body**

Replace the entire `function renderMsg(m)` (lines 1607-1657) with:

```javascript
function renderMsg(m) {
  const isSystem = m.type === 'system';
  const isDirect = !isSystem && m.target !== 'all';
  const isUser = !isSystem && m.sender === 'gurvinder';
  const isMobile = window.innerWidth < 768;

  // Time divider check (mobile only)
  if (isMobile && !isSystem && m.timestamp && shouldShowTimeDivider(lastTimestamp, m.timestamp)) {
    const divider = document.createElement('div');
    divider.className = 'time-divider';
    const dividerText = formatTimeDivider(m.timestamp);
    const timeText = formatTimeShort(m.timestamp);
    divider.textContent = dividerText === 'Today' ? timeText : `${dividerText} ${timeText}`;
    $msgs.appendChild(divider);
  }

  const el = document.createElement('div');

  if (isSystem) {
    el.className = 'msg system';
    el.textContent = m.content;
    lastSender = null;
    lastTimestamp = m.timestamp || null;
    $msgs.appendChild(el);
    return;
  }

  // Grouping logic
  const grouped = isSameGroup(lastSender, lastTimestamp, m.sender, m.timestamp);

  // Build class list
  let cls = 'msg';
  if (isUser && isMobile) cls += ' msg-user';
  if (isDirect) cls += ' direct';
  if (grouped) {
    cls += ' grouped';
    // Mark previous message as group-start
    const prev = $msgs.lastElementChild;
    if (prev && prev.classList.contains('standalone')) {
      prev.classList.remove('standalone');
      prev.classList.add('group-start');
    }
  } else {
    cls += ' standalone';
  }
  el.className = cls;

  // Border color for agent messages
  if (!isUser || !isMobile) {
    el.style.borderLeftColor = color(m.sender);
  }

  // Timestamp
  const ts = m.timestamp ? m.timestamp.slice(11, 19) : '';
  const tag = isDirect ? `<span class="msg-tag">@${esc(m.target)}</span>` : '';

  // Build inner HTML
  let html = '';
  html += `<div class="msg-head">`;
  html += `<span class="msg-sender" style="color:${color(m.sender)}">${esc(m.sender)}</span>`;
  html += tag;
  html += `<span class="msg-time">${ts}</span>`;
  html += `</div>`;
  html += `<div class="msg-body">${esc(m.content)}</div>`;

  // User messages on mobile get timestamp below the bubble
  if (isUser && isMobile) {
    const shortTime = m.timestamp ? formatTimeShort(m.timestamp) : ts;
    html += `<span class="msg-time-below">${shortTime}</span>`;
  }

  el.innerHTML = html;

  lastSender = m.sender;
  lastTimestamp = m.timestamp || null;

  $msgs.appendChild(el);

  // Image preview for uploaded files
  if (m.content && m.content.includes('[uploaded:')) {
    const match = m.content.match(/\[uploaded:\s*([^\]]+)\]/);
    if (match) {
      const filePath = match[1].trim();
      const ext = filePath.split('.').pop().toLowerCase();
      if (['png', 'jpg', 'jpeg', 'gif', 'webp'].includes(ext)) {
        const img = document.createElement('img');
        img.src = `/uploads/${filePath.replace('docs/warroom-uploads/', '')}`;
        img.style.cssText = 'max-width:100%;max-height:300px;border-radius:8px;margin-top:8px;cursor:pointer;display:block';
        img.onclick = () => window.open(img.src, '_blank');
        const body = el.querySelector('.msg-body');
        if (body) body.appendChild(img);
      }
    }
  }
}
```

- [ ] **Step 4: Also reset `lastTimestamp` on history load**

Find line 1567:
```javascript
if (d.type === 'history') { $msgs.innerHTML = ''; lastSender = null; d.messages.forEach(renderMsg); scrollEnd(); }
```

Replace with:
```javascript
if (d.type === 'history') { $msgs.innerHTML = ''; lastSender = null; lastTimestamp = null; d.messages.forEach(renderMsg); scrollEnd(); }
```

- [ ] **Step 5: Verify the rendering logic**

Restart the server and load the page:
```bash
pkill -f "python3.*server.py" 2>/dev/null; sleep 1
cd ~/coders-war-room && nohup python3 server.py > /tmp/warroom-server.log 2>&1 &
sleep 2
curl -s http://localhost:5680/api/server/health | python3 -c "import sys,json; print(json.load(sys.stdin)['uptime_human'])"
```
Expected: `0m` (freshly started)

- [ ] **Step 6: Commit**

```bash
git add static/index.html
git commit -m "feat(m1): step 2 — renderMsg user detection, 20s grouping, time dividers"
```

---

### Task 3: Pill-Shaped Input Bar

**Files:**
- Modify: `static/index.html` — HTML (lines 1396-1404) and mobile CSS (lines 1216-1267)

This task transforms the flat rectangular input bar into an iMessage-style pill with inline attachment and circular send button.

- [ ] **Step 1: Update the input bar HTML**

Find lines 1396-1404:
```html
    <div class="input-bar">
      <div class="input-target" id="inputTarget" style="display:none">@all ▼</div>
      <select id="targetSel" class="target-sel"><option value="all">@all</option></select>
      <div class="input-row">
        <button class="input-attach" id="attachBtn" style="display:none" title="Attach">📎</button>
        <textarea id="msgInput" class="msg-input" placeholder="Message the war room..." rows="1"></textarea>
        <button id="sendBtn" class="send-btn" disabled>Send</button>
      </div>
    </div>
```

Replace with:
```html
    <div class="input-bar">
      <div class="input-target" id="inputTarget" style="display:none">@all ▼</div>
      <select id="targetSel" class="target-sel"><option value="all">@all</option></select>
      <div id="attachChip" class="attach-chip" style="display:none">
        <span id="attachName"></span>
        <span id="attachRemove" class="attach-remove">✕</span>
      </div>
      <div class="input-row">
        <div class="input-pill">
          <button class="pill-attach" id="attachBtn" title="Attach">📎</button>
          <textarea id="msgInput" class="msg-input" placeholder="Message the war room..." rows="1"></textarea>
          <button id="sendBtn" class="send-btn" disabled>
            <span class="send-arrow">▲</span>
          </button>
        </div>
      </div>
    </div>
```

- [ ] **Step 2: Replace the mobile input CSS**

Find the existing mobile input styles (lines ~1216-1267) and replace everything from `/* ═══ Input area` to `.msg-input { font-size: 16px; }` with:

```css
    /* ═══ Input area — fixed above tab bar ═══ */
    .input-bar {
      position: fixed;
      bottom: calc(50px + env(safe-area-inset-bottom, 8px));
      left: 0;
      right: 0;
      flex-direction: column;
      gap: 4px;
      padding: 8px 12px;
      background: var(--bg-panel);
      border-top: 1px solid var(--border);
      z-index: 100;
    }

    .input-target {
      display: block !important;
      font-family: 'JetBrains Mono', monospace;
      font-size: 11px;
      color: var(--green);
      padding: 2px 0;
      cursor: pointer;
      -webkit-tap-highlight-color: transparent;
    }

    .target-sel { display: none; }

    /* Attachment chip */
    .attach-chip {
      display: flex !important;
      align-items: center;
      gap: 6px;
      background: var(--bg-card);
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 6px 10px;
      font-family: 'JetBrains Mono', monospace;
      font-size: 11px;
      color: var(--text-secondary);
      width: fit-content;
    }

    .attach-remove {
      color: var(--text-dim);
      cursor: pointer;
      font-size: 14px;
      padding: 0 2px;
    }

    .attach-remove:active { color: var(--red); }

    /* Pill container */
    .input-pill {
      display: flex;
      align-items: flex-end;
      gap: 0;
      background: var(--bg-deep);
      border: 1px solid var(--border);
      border-radius: 20px;
      padding: 4px 4px 4px 8px;
      width: 100%;
      transition: border-color 0.15s;
    }

    .input-pill:focus-within { border-color: var(--blue); }

    /* Attach button inside pill */
    .pill-attach {
      display: flex;
      align-items: center;
      justify-content: center;
      background: none;
      border: none;
      font-size: 18px;
      padding: 4px;
      cursor: pointer;
      -webkit-tap-highlight-color: transparent;
      flex-shrink: 0;
    }

    /* Textarea inside pill */
    .input-pill .msg-input {
      flex: 1;
      font-family: 'Source Sans 3', -apple-system, sans-serif;
      font-size: 16px;
      background: transparent;
      border: none;
      color: var(--text-primary);
      padding: 6px 8px;
      resize: none;
      min-height: 32px;
      max-height: 88px;
      line-height: 1.4;
      outline: none;
    }

    .input-pill .msg-input::placeholder { color: var(--text-dim); }

    /* Circular send button */
    .send-btn {
      width: 28px;
      height: 28px;
      border-radius: 50%;
      background: var(--green);
      border: none;
      color: var(--bg-void);
      font-size: 12px;
      display: none;
      align-items: center;
      justify-content: center;
      cursor: pointer;
      flex-shrink: 0;
      padding: 0;
      transition: opacity 0.15s;
    }

    .send-btn.visible { display: flex; }
    .send-btn:disabled { display: none; }

    .send-arrow { font-size: 14px; font-weight: 700; line-height: 1; }

    .input-row {
      display: flex;
      gap: 0;
      align-items: flex-end;
      width: 100%;
    }

    /* Hide the old separate attach button */
    .input-attach { display: none !important; }
```

- [ ] **Step 3: Add desktop styles for the new HTML elements**

The new `.input-pill`, `.attach-chip`, `.pill-attach` elements need to work on desktop too without breaking the layout. Add these in the DESKTOP section (outside the mobile media query, near line 448 where `.input-row` is defined):

```css
  /* Desktop: hide mobile-only input elements */
  .input-pill { display: contents; } /* On desktop, pill is transparent — children flow normally */
  .pill-attach { display: none; } /* Desktop uses the separate attach button, not pill-inline */
  .attach-chip { display: none; } /* Desktop doesn't show attachment chip */
  .send-arrow { display: none; } /* Desktop shows "Send" text, not arrow */
```

- [ ] **Step 4: Commit**

```bash
git add static/index.html
git commit -m "feat(m1): step 3 — pill-shaped input bar with inline attach and circular send"
```

---

### Task 4: Send Button Visibility + Attachment Chip Logic

**Files:**
- Modify: `static/index.html` — JavaScript section

This task wires up the send button show/hide logic and the attachment chip display.

- [ ] **Step 1: Update send button visibility logic**

Find the existing input event listener (line ~1993):
```javascript
$input.addEventListener('input', () => { $input.style.height = 'auto'; $input.style.height = Math.min($input.scrollHeight, 120) + 'px'; });
```

Replace with:
```javascript
function updateSendVisibility() {
  const hasText = $input.value.trim().length > 0;
  const hasAttachment = $('attachChip') && $('attachChip').style.display !== 'none';
  if (hasText || hasAttachment) {
    $send.classList.add('visible');
    $send.disabled = false;
  } else {
    $send.classList.remove('visible');
    $send.disabled = true;
  }
}

$input.addEventListener('input', () => {
  $input.style.height = 'auto';
  $input.style.height = Math.min($input.scrollHeight, 88) + 'px';
  updateSendVisibility();
});
```

- [ ] **Step 2: Add attachment chip wiring**

Find the existing `$attachBtn.onclick` handler (the one that calls `showBottomSheet('Attach', ...)`). Inside the upload success callback, after the line `$input.value += \`[uploaded: ${data.path}] \`;`, add chip display logic.

Find:
```javascript
          if (data.path) {
              $input.value += `[uploaded: ${data.path}] `;
              $input.focus();
            }
```

Replace with:
```javascript
          if (data.path) {
              // Show attachment chip instead of inline text
              const chipEl = $('attachChip');
              const nameEl = $('attachName');
              if (chipEl && nameEl) {
                const fname = data.filename || data.path.split('/').pop();
                nameEl.textContent = '📄 ' + (fname.length > 25 ? fname.slice(0, 22) + '...' : fname);
                chipEl.style.display = 'flex';
                chipEl.dataset.path = data.path;
                updateSendVisibility();
              }
              $input.focus();
            }
```

- [ ] **Step 3: Add attachment chip remove handler**

After the `$attachBtn.onclick` handler block, add:

```javascript
// Attachment chip remove
const $attachRemove = $('attachRemove');
if ($attachRemove) {
  $attachRemove.onclick = () => {
    const chipEl = $('attachChip');
    if (chipEl) {
      chipEl.style.display = 'none';
      chipEl.dataset.path = '';
    }
    updateSendVisibility();
    $input.focus();
  };
}
```

- [ ] **Step 4: Update send handler to include attachment**

Find the message send logic (around line 1975-1985 where the send action builds and sends the message). Locate where `text` is assembled and sent. After the text is captured, add attachment path if chip is active:

Find the line like:
```javascript
  const text = $input.value.trim();
  if (!text) return;
```

Replace with:
```javascript
  let text = $input.value.trim();
  const chipEl = $('attachChip');
  const attachPath = chipEl ? chipEl.dataset.path : '';
  if (attachPath) {
    text = (text ? text + ' ' : '') + `[uploaded: ${attachPath}]`;
  }
  if (!text) return;
```

And after the send completes (after `$input.value = ''`), add:
```javascript
  // Clear attachment chip
  if (chipEl) { chipEl.style.display = 'none'; chipEl.dataset.path = ''; }
  updateSendVisibility();
```

- [ ] **Step 5: Commit**

```bash
git add static/index.html
git commit -m "feat(m1): step 4 — send button visibility, attachment chip logic"
```

---

### Task 5: Dynamic Scroll Padding + ResizeObserver

**Files:**
- Modify: `static/index.html` — JavaScript section

This task fixes the "last message buried under input bar" problem with a ResizeObserver that dynamically adjusts message padding.

- [ ] **Step 1: Replace scrollEnd() with smart scrolling**

Find line 1990:
```javascript
function scrollEnd() { $msgs.scrollTop = $msgs.scrollHeight; }
```

Replace with:
```javascript
function scrollEnd() {
  // Only auto-scroll if user is near the bottom (within 150px)
  const nearBottom = ($msgs.scrollHeight - $msgs.scrollTop - $msgs.clientHeight) < 150;
  if (nearBottom) {
    $msgs.scrollTop = $msgs.scrollHeight;
  }
}

function scrollForce() {
  $msgs.scrollTop = $msgs.scrollHeight;
}
```

- [ ] **Step 2: Update history load to use scrollForce**

Find:
```javascript
if (d.type === 'history') { $msgs.innerHTML = ''; lastSender = null; lastTimestamp = null; d.messages.forEach(renderMsg); scrollEnd(); }
```

Replace `scrollEnd()` with `scrollForce()`:
```javascript
if (d.type === 'history') { $msgs.innerHTML = ''; lastSender = null; lastTimestamp = null; d.messages.forEach(renderMsg); scrollForce(); }
```

- [ ] **Step 3: Add ResizeObserver for dynamic padding**

Add this block in the Init section (near the bottom of the script, after the input event listener):

```javascript
// ═══════════ Dynamic scroll padding (mobile) ═══════════
if (window.innerWidth < 768) {
  const inputBar = document.querySelector('.input-bar');
  const tabBar = document.querySelector('.tab-bar');

  function updateScrollPadding() {
    const inputH = inputBar ? inputBar.offsetHeight : 80;
    const tabH = tabBar ? tabBar.offsetHeight : 50;
    $msgs.style.paddingBottom = (inputH + tabH + 16) + 'px';
  }

  // Initial calculation
  updateScrollPadding();

  // Recalculate when input bar resizes (multi-line text, attachment chip)
  if (typeof ResizeObserver !== 'undefined' && inputBar) {
    new ResizeObserver(updateScrollPadding).observe(inputBar);
  }

  // Also recalculate when textarea resizes
  $input.addEventListener('input', () => {
    setTimeout(updateScrollPadding, 50);
  });
}
```

- [ ] **Step 4: Remove the static padding-bottom from CSS**

Find in the mobile CSS block:
```css
    .chat .messages {
      flex: 1;
      overflow-y: auto;
      padding-bottom: 120px; /* Space for fixed input bar + tab bar */
    }
```

Replace with:
```css
    .chat .messages {
      flex: 1;
      overflow-y: auto;
      padding-bottom: 140px; /* Initial estimate — ResizeObserver updates dynamically */
    }
```

(Keep a reasonable initial value so messages aren't hidden before JS runs.)

- [ ] **Step 5: Commit**

```bash
git add static/index.html
git commit -m "feat(m1): step 5 — dynamic scroll padding with ResizeObserver"
```

---

### Task 6: Final Verification + Push

**Files:**
- No modifications — verification only

- [ ] **Step 1: Restart server**

```bash
pkill -f "python3.*server.py" 2>/dev/null; sleep 1
cd ~/coders-war-room && nohup python3 server.py > /tmp/warroom-server.log 2>&1 &
sleep 2
echo "Server running"
```

- [ ] **Step 2: Verify server is healthy**

```bash
curl -s http://localhost:5680/api/server/health | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'OK — {d[\"agents_alive\"]} agents, uptime {d[\"uptime_human\"]}')"
```

- [ ] **Step 3: Verify desktop is unchanged**

Check that desktop CSS rules (lines 343-379) are untouched:
```bash
grep -A 5 '\.msg {' static/index.html | head -8
```
Expected: original desktop styles with `border-left: 3px solid` and `border-radius: 6px`

- [ ] **Step 4: Check file size is reasonable**

```bash
wc -l static/index.html
```
Expected: ~2600-2700 lines (was ~2550, adding ~100-150 lines of CSS/JS)

- [ ] **Step 5: Push to remote**

```bash
git push origin main
```

- [ ] **Step 6: Screenshot request**

Ask Gurvinder to screenshot the mobile chat on iPhone and provide feedback for iteration.

---

## Success Criteria Checklist

| # | Criterion | Task |
|---|-----------|------|
| 1 | User messages render as right-aligned green bubbles | Task 2 |
| 2 | Agent messages render as left-aligned rounded cards with colored left border | Task 1 |
| 3 | Input bar always visible above tab bar, never hidden | Task 3 |
| 4 | Input expands 1-3 lines, padding adjusts dynamically | Task 5 |
| 5 | Paperclip opens attachment sheet, chip appears | Task 4 |
| 6 | Send button only visible when content to send | Task 4 |
| 7 | Last message always scrollable into full view | Task 5 |
| 8 | Same agent within 20s stacks tight, else full header | Task 2 |
| 9 | Time dividers after 5+ minute gaps | Task 2 |
| 10 | Desktop layout completely unchanged | Task 1, 3 |
