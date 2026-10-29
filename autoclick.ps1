# ==============================================================
# Antigravity IDE Auto-Clicker (Optimized for Auto-Submit)
# ==============================================================
# Automatically detects and clicks interactive agent prompts,
# confirmation dialogs, and questions (e.g. "Submit ↵", "Allow",
# "Yes, allow this time", "Proceed", etc.) in Antigravity IDE.
# ==============================================================

# ==== SETTINGS ====
$port         = 9333          # Remote debugging port (must match start.bat)
$intervalSecs = 1.5           # Polling interval in seconds
# Priority action labels to match on buttons:
$labels       = @(
  'submit',
  'proceed',
  'always allow',
  'yes, allow this time',
  'allow this time',
  'allow',
  'accept',
  'continue',
  'retry',
  'confirm',
  'run'
)
# Optional custom CSS selector (if set, overrides label matching)
$cssSelector  = ''
# ==================

$log = Join-Path $PSScriptRoot 'autoclick.log'
function Log($m) {
  $line = "$(Get-Date -Format 'HH:mm:ss')  $m"
  Write-Host $line
  $line | Add-Content -Path $log -Encoding UTF8
}

$labelsJson = ($labels | ConvertTo-Json -Compress)
if ($labels.Count -eq 1) { $labelsJson = "[$labelsJson]" }

$jsTemplate = @'
(() => {
  const customSel = __SEL__;
  const targetLabels = __LABELS__;

  // 1. Text normalization: cleans whitespace and Unicode return symbols (↵, ⏎, etc.)
  const clean = (str) => {
    if (!str) return '';
    return str
      .replace(/[\u21B5\u23CE\r\n\t]+/g, ' ') // Strip return arrows (↵, ⏎)
      .replace(/\([^\)]+\)/g, '')             // Strip parenthetical shortcuts like (Enter) or (Ctrl+Enter)
      .replace(/\s+/g, ' ')
      .trim()
      .toLowerCase();
  };

  const getElementText = (el) => {
    const raw = (el.innerText || el.textContent || el.getAttribute('aria-label') || el.title || '');
    return clean(raw);
  };

  // 2. Visibility check
  const isVisible = (el) => {
    try {
      const r = el.getBoundingClientRect();
      if (r.width <= 0 || r.height <= 0) return false;
      if (el.disabled || el.getAttribute('aria-disabled') === 'true') return false;
      const style = window.getComputedStyle(el);
      if (style.display === 'none' || style.visibility === 'hidden' || style.opacity === '0') return false;
      return true;
    } catch (e) {
      return false;
    }
  };

  // 3. Safety check: DO NOT touch menubars, editor tabs, monaco editor, or statusbars!
  const isSafe = (el) => {
    try {
      if (el.closest('.menubar, .menubar-menu-button, [role="menubar"], [role="menuitem"]')) return false;
      if (el.closest('.activitybar, .sidebar, .pane-header, [role="tablist"]')) return false;
      if (el.closest('.tabs-container, .tab, .editor-container, .monaco-editor, .monaco-tree-row')) return false;
      if (el.closest('.statusbar, [role="status"]')) return false;
      return true;
    } catch (e) {
      return true;
    }
  };

  // 4. Realistic click simulation: dispatches full pointer + mouse event chain for React/Radix UI
  const simulateClick = (el) => {
    if (!el) return false;
    try { if (typeof el.focus === 'function') el.focus(); } catch (x) {}
    const rect = el.getBoundingClientRect();
    const clientX = rect.left + rect.width / 2;
    const clientY = rect.top + rect.height / 2;
    const opts = {
      bubbles: true,
      cancelable: true,
      view: window,
      clientX,
      clientY,
      buttons: 1
    };
    try { el.dispatchEvent(new PointerEvent('pointerdown', opts)); } catch (x) {}
    try { el.dispatchEvent(new MouseEvent('mousedown', opts)); } catch (x) {}
    try { el.dispatchEvent(new PointerEvent('pointerup', opts)); } catch (x) {}
    try { el.dispatchEvent(new MouseEvent('mouseup', opts)); } catch (x) {}
    try { el.click(); } catch (x) {}
    return true;
  };

  // 5. DOM crawler: collects all roots (main document + shadow roots + iframes)
  const roots = [];
  const visit = (r) => {
    roots.push(r);
    try {
      r.querySelectorAll('*').forEach(e => {
        if (e.shadowRoot) visit(e.shadowRoot);
        if (e.tagName === 'IFRAME') {
          try { if (e.contentDocument) visit(e.contentDocument); } catch (x) {}
        }
      });
    } catch (x) {}
  };
  visit(document);

  const gather = (sel) => {
    const res = [];
    roots.forEach(r => {
      try {
        res.push(...r.querySelectorAll(sel));
      } catch (x) {}
    });
    return res.filter(isVisible).filter(isSafe);
  };

  // 6. Custom selector override (if configured)
  if (customSel && customSel.trim().length > 0) {
    const customElements = gather(customSel);
    if (customElements.length > 0) {
      simulateClick(customElements[0]);
      return 'clicked custom selector: ' + customSel;
    }
  }

  // 7. Find all real buttons and button-like elements
  const allButtons = gather('button, [role="button"], input[type="button"], input[type="submit"]');

  // Label matching helper
  const matchesLabel = (text, label) => {
    if (!text) return false;
    if (text === label) return true;
    if (label === 'continue') {
      // For 'continue', only match exact "continue" or shortcut hints, NEVER third-party OAuth logins ("Continue with Google")
      return text === 'continue' || text.startsWith('continue:') || text.startsWith('continue-');
    }
    if (text.startsWith(label + ' ') || text.startsWith(label + ':') || text.startsWith(label + '-')) return true;
    if (label === 'allow' && (text.includes('allow this time') || text.includes('always allow') || text.startsWith('allow'))) return true;
    if (label === 'accept' && (text.startsWith('accept') || text.includes('accept all'))) return true;
    if (label === 'proceed' && (text === 'proceed' || text.startsWith('proceed '))) return true;
    return false;
  };

  // ==============================================================
  // PRIORITY 1: ANTIGRAVITY IDE INTERACTIVE PROMPTS & SUBMIT
  // Specifically optimized for Antigravity IDE ask_question and
  // ask_permission widgets (CZ / PWb React components).
  // Ensures the first / recommended option remains selected and
  // NEVER switches to the write-in / "No" option.
  // ==============================================================
  let questionBtn = null;
  let questionRoot = null;
  for (const r of roots) {
    try {
      const btn = r.querySelector('[data-testid="interaction-continue-button"]');
      if (btn && isSafe(btn)) {
        questionBtn = btn;
        questionRoot = r;
        break;
      }
    } catch (e) {}
  }

  if (questionBtn && questionRoot) {
    const qContainer = questionBtn.closest('.no-focus-agent-input') ||
                       questionBtn.closest('[role="radiogroup"]') ||
                       questionBtn.closest('.relative') ||
                       questionRoot;

    // 1. Gather all legitimate options (excluding the "No" / "Other" write-in container)
    let optionLabels = Array.from(qContainer.querySelectorAll('[data-testid="ask-question-option"]'));

    if (optionLabels.length === 0) {
      optionLabels = Array.from(qContainer.querySelectorAll('label, div[role="radio"]'))
        .filter(el => {
          const input = el.querySelector('input') || el;
          if (input.value === '__write_in__') return false;
          if (el.querySelector('[data-testid="ask-question-writein"]')) return false;
          const t = getElementText(el);
          if (t === 'no' || t.startsWith('no ') || t.startsWith('other')) return false;
          return !!(el.querySelector('input[type="radio"], input[type="checkbox"]') || el.getAttribute('role') === 'radio');
        });
    }

    // 2. Check if the "No" / write-in option is currently active
    const writeInRadio = qContainer.querySelector('input[value="__write_in__"]');
    const writeInActive = !!(writeInRadio && writeInRadio.checked) ||
                          !!qContainer.querySelector('textarea[data-testid="ask-question-writein"]:focus');

    // 3. Check if any legitimate option is currently selected
    let selectedOption = null;
    for (const opt of optionLabels) {
      const input = opt.querySelector('input') || (opt.tagName === 'INPUT' ? opt : null);
      const isChecked = (input && (input.checked || input.getAttribute('aria-checked') === 'true')) ||
                        opt.classList.contains('bg-secondary') ||
                        opt.getAttribute('data-state') === 'checked' ||
                        opt.getAttribute('aria-checked') === 'true';
      if (isChecked) {
        selectedOption = opt;
        break;
      }
    }

    // 4. Identify the first option (prioritizing '(Recommended)' if present)
    const targetFirstOption = optionLabels.find(o => getElementText(o).includes('recommended')) ||
                              optionLabels[0];

    // 5. If "No" / write-in was activated, OR no valid option is selected:
    // Select the first option and NEVER touch the "No" option!
    if (writeInActive || !selectedOption) {
      if (targetFirstOption) {
        simulateClick(targetFirstOption);
        const optInput = targetFirstOption.querySelector('input');
        if (optInput) {
          try {
            optInput.checked = true;
            optInput.dispatchEvent(new Event('change', { bubbles: true }));
          } catch (x) {}
        }
        return 'selected first option: ' + (getElementText(targetFirstOption) || 'Option 1');
      }
    }

    // 6. Legitimate option is selected: STAY on first option and submit!
    if (!questionBtn.disabled && questionBtn.getAttribute('aria-disabled') !== 'true') {
      simulateClick(questionBtn);
      return 'clicked submit button: ' + (questionBtn.innerText || 'Submit').trim();
    }

    // Button is waiting for React state update
    return 'none';
  }

  // 1B. Fallback: General Submit button in standard dialogs/modals
  const submitBtn = allButtons.find(b => {
    const txt = getElementText(b);
    return txt === 'submit' || txt.startsWith('submit ') || txt.startsWith('submit:');
  });

  if (submitBtn) {
    const modalContainer = submitBtn.closest('[role="dialog"], [role="alertdialog"], .modal, div[class*="dialog"], div[class*="modal"]');
    if (modalContainer) {
      const radios = Array.from(modalContainer.querySelectorAll('[role="radio"], input[type="radio"], [role="checkbox"]'))
        .filter(r => r.value !== '__write_in__' && !getElementText(r.parentElement).toLowerCase().startsWith('no'));
      const hasSelectedRadio = radios.some(r => r.getAttribute('aria-checked') === 'true' || r.checked);

      if (radios.length > 0 && !hasSelectedRadio) {
        simulateClick(radios[0]);
      }
    }

    simulateClick(submitBtn);
    return 'clicked submit button: ' + (submitBtn.innerText || 'Submit').trim();
  }

  // ==============================================================
  // PRIORITY 2: ACTION BUTTONS (Allow, Proceed, Accept, Continue, etc.)
  // ==============================================================
  for (const label of targetLabels) {
    if (label === 'submit') continue; // already handled
    const btn = allButtons.find(b => matchesLabel(getElementText(b), label));
    if (btn) {
      // Extra safety for 'run': must be inside chat, notification, or dialog, never bare
      if (label === 'run') {
        const inActionArea = btn.closest('.notification-toast, [role="dialog"], [role="alertdialog"], div[class*="action"], div[class*="terminal"], div[class*="chat"]');
        if (!inActionArea) continue;
      }
      simulateClick(btn);
      return 'clicked button [' + label + ']: ' + (btn.innerText || label).trim();
    }
  }

  // ==============================================================
  // PRIORITY 3: MODAL-SCOPED NON-BUTTON CLICKABLE ELEMENTS
  // Only checked inside dialogs, notifications, and alert modals!
  // ==============================================================
  const modalClickables = gather('[role="dialog"] *, [role="alertdialog"] *, .notification-toast *, div[class*="dialog"] *, div[class*="modal"] *')
    .filter(e => window.getComputedStyle(e).cursor === 'pointer');

  for (const label of targetLabels) {
    if (label === 'run') continue; // never click raw spans for 'run'
    const el = modalClickables.find(e => matchesLabel(getElementText(e), label));
    if (el) {
      simulateClick(el);
      return 'clicked modal element [' + label + ']: ' + getElementText(el);
    }
  }

  return 'none';
})()
'@

$js = $jsTemplate.Replace('__SEL__', ($cssSelector | ConvertTo-Json -Compress)).Replace('__LABELS__', $labelsJson)
$ct = [Threading.CancellationToken]::None

function Invoke-Cdp($wsUrl, $expr) {
  $ws = New-Object System.Net.WebSockets.ClientWebSocket
  try {
    $connTask = $ws.ConnectAsync([Uri]$wsUrl, $ct)
    if (-not $connTask.Wait(3000)) {
      throw "Timeout connecting to WebSocket $wsUrl"
    }
    $msg = @{ id = 1; method = 'Runtime.evaluate'; params = @{ expression = $expr; returnByValue = $true } } |
      ConvertTo-Json -Depth 5 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($msg)
    $sendTask = $ws.SendAsync([ArraySegment[byte]]$bytes, 'Text', $true, $ct)
    if (-not $sendTask.Wait(3000)) {
      throw "Timeout sending command to WebSocket $wsUrl"
    }
    $ms  = New-Object IO.MemoryStream
    $buf = New-Object byte[] 65536
    do {
      $recvTask = $ws.ReceiveAsync([ArraySegment[byte]]$buf, $ct)
      if (-not $recvTask.Wait(4000)) {
        throw "Timeout receiving response from WebSocket $wsUrl"
      }
      $r = $recvTask.Result
      $ms.Write($buf, 0, $r.Count)
    } while (-not $r.EndOfMessage)
    $j = [Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json
    return $j.result.result.value
  } finally {
    $ws.Dispose()
  }
}

function Get-Targets($port) {
  $endpoints = @("http://127.0.0.1:$port/json/list", "http://127.0.0.1:$port/json")
  foreach ($ep in $endpoints) {
    try {
      $raw = Invoke-RestMethod -Uri $ep -TimeoutSec 3 -ErrorAction Stop
      if ($raw) {
        $arr = @($raw)
        $valid = @($arr | Where-Object {
          $_.webSocketDebuggerUrl -and ($_.type -notin @('worker', 'service_worker'))
        })
        if ($valid.Count -gt 0) {
          return $valid
        }
      }
    } catch {}
  }
  return @()
}

Log "Auto-clicker started for Antigravity IDE (port $port)"
Log "Active labels: $($labels -join ', ')"

$loop = 0
while ($true) {
  $loop++
  try {
    $targets = Get-Targets $port
    if ($targets.Count -eq 0) {
      if ($loop % 20 -eq 1) {
        # Check if port is open
        $portOpen = $false
        try {
          $tcp = New-Object Net.Sockets.TcpClient
          $iar = $tcp.BeginConnect('127.0.0.1', $port, $null, $null)
          if ($iar.AsyncWaitHandle.WaitOne(400, $false)) {
            $tcp.EndConnect($iar)
            $portOpen = $true
          }
          $tcp.Close()
        } catch {}

        if ($portOpen) {
          Log "Port $port is open, waiting for IDE window target..."
        } else {
          $ideProc = Get-Process -Name "*Antigravity*" -ErrorAction SilentlyContinue
          if ($ideProc) {
            Log "Antigravity IDE is running, but remote debugging port $port is not open. Restart it using start.bat!"
          } else {
            Log "Antigravity IDE is not running. Launch it using start.bat."
          }
        }
      }
    } else {
      if ($loop % 20 -eq 1) {
        $firstTitle = if ($targets[0].title) { $targets[0].title } else { "Workbench" }
        Log "Connected to port $port ($($targets.Count) target(s): $firstTitle)"
      }
      foreach ($t in $targets) {
        try {
          $res = Invoke-Cdp $t.webSocketDebuggerUrl $js
          if ($res -and $res -ne 'none') {
            Log "$res  [$($t.title)]"
            Start-Sleep -Milliseconds 600
          }
        } catch {
          # Silently handle transient disconnects during navigation
        }
      }
    }
  } catch {
    if ($loop % 20 -eq 1) { Log "Loop error: $($_.Exception.Message)" }
  }
  Start-Sleep -Seconds $intervalSecs
}
