# ==============================================================
# Antigravity IDE Auto-Click Diagnostic Tool
# ==============================================================
# Inspects CDP targets, detects candidate buttons, and simulates
# matching logic to verify autosubmit and action button behavior.
# ==============================================================

$port = 9333
$out  = Join-Path $PSScriptRoot 'diagnose-output.txt'
$ct   = [Threading.CancellationToken]::None

function Invoke-Cdp($wsUrl, $expr) {
  $ws = New-Object System.Net.WebSockets.ClientWebSocket
  try {
    $connTask = $ws.ConnectAsync([Uri]$wsUrl, $ct)
    if (-not $connTask.Wait(3000)) { throw "Connection timed out" }
    $msg = @{ id = 1; method = 'Runtime.evaluate'; params = @{ expression = $expr; returnByValue = $true } } |
      ConvertTo-Json -Depth 5 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($msg)
    $sendTask = $ws.SendAsync([ArraySegment[byte]]$bytes, 'Text', $true, $ct)
    if (-not $sendTask.Wait(3000)) { throw "Send timed out" }
    $ms  = New-Object IO.MemoryStream
    $buf = New-Object byte[] 65536
    do {
      $recvTask = $ws.ReceiveAsync([ArraySegment[byte]]$buf, $ct)
      if (-not $recvTask.Wait(4000)) { throw "Receive timed out" }
      $r = $recvTask.Result
      $ms.Write($buf, 0, $r.Count)
    } while (-not $r.EndOfMessage)
    $j = [Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json
    return $j.result.result.value
  } finally {
    $ws.Dispose()
  }
}

$js = @'
(() => {
  const clean = str => {
    if (!str) return '';
    return str
      .replace(/[\u21B5\u23CE\r\n\t]+/g, ' ')
      .replace(/\([^\)]+\)/g, '')
      .replace(/\s+/g, ' ')
      .trim()
      .toLowerCase();
  };

  const getElementText = el => {
    return clean(el.innerText || el.textContent || el.getAttribute('aria-label') || el.title || '');
  };

  const isVisible = el => {
    try {
      const r = el.getBoundingClientRect();
      if (r.width <= 0 || r.height <= 0) return false;
      if (el.disabled || el.getAttribute('aria-disabled') === 'true') return false;
      const style = window.getComputedStyle(el);
      if (style.display === 'none' || style.visibility === 'hidden' || style.opacity === '0') return false;
      return true;
    } catch (e) { return false; }
  };

  const isSafe = el => {
    try {
      if (el.closest('.menubar, .menubar-menu-button, [role="menubar"], [role="menuitem"]')) return false;
      if (el.closest('.activitybar, .sidebar, .pane-header, [role="tablist"]')) return false;
      if (el.closest('.tabs-container, .tab, .editor-container, .monaco-editor, .monaco-tree-row')) return false;
      if (el.closest('.statusbar, [role="status"]')) return false;
      return true;
    } catch (e) { return true; }
  };

  const roots = [];
  const visit = r => {
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

  const allElements = [];
  roots.forEach(r => {
    try {
      r.querySelectorAll('button, [role="button"], input[type="button"], input[type="submit"], div, span, a').forEach(e => {
        if (!isVisible(e) || !isSafe(e)) return;
        const raw = (e.innerText || e.getAttribute('aria-label') || e.title || '').replace(/\s+/g, ' ').trim();
        const cleaned = clean(raw);
        if (!cleaned || cleaned.length > 50) return;
        if (/^(submit|allow|accept|proceed|continue|retry|confirm|run|yes)/i.test(cleaned)) {
          const rc = e.getBoundingClientRect();
          allElements.push({
            tag: e.tagName,
            rawText: raw,
            cleanedText: cleaned,
            role: e.getAttribute('role'),
            isButton: e.tagName === 'BUTTON' || e.getAttribute('role') === 'button',
            inDialog: !!e.closest('[role="dialog"], [role="alertdialog"], .modal, div[class*="dialog"]'),
            cls: (e.className && e.className.toString ? e.className.toString() : '').slice(0, 80)
          });
        }
      });
    } catch (x) {}
  });

  return JSON.stringify({
    title: document.title,
    candidateCount: allElements.length,
    candidates: allElements.slice(0, 30)
  });
})()
'@

$lines = @()
$lines += "=============================================================="
$lines += "Antigravity IDE Auto-Click Diagnostic Report"
$lines += "Generated at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$lines += "=============================================================="

$targets = @()
$endpoints = @("http://127.0.0.1:$port/json/list", "http://127.0.0.1:$port/json")
foreach ($ep in $endpoints) {
  try {
    $raw = Invoke-RestMethod -Uri $ep -TimeoutSec 4 -ErrorAction Stop
    if ($raw) {
      $targets = @($raw)
      break
    }
  } catch {}
}

if ($targets.Count -eq 0) {
  $ideProc = Get-Process -Name "*Antigravity*" -ErrorAction SilentlyContinue
  if ($ideProc) {
    $lines += "[ERROR] Could not connect to http://127.0.0.1:$port"
    $lines += "Antigravity IDE is running, but remote debugging port $port is NOT open."
    $lines += "Reason: Antigravity IDE was launched without '--remote-debugging-port=$port'."
    $lines += "Fix: Close Antigravity IDE and run start.bat."
  } else {
    $lines += "[ERROR] Could not connect to http://127.0.0.1:$port"
    $lines += "Antigravity IDE is not running. Please start it using start.bat."
  }
  $lines | Out-File -FilePath $out -Encoding UTF8
  $lines | ForEach-Object { Write-Host $_ }
  exit
}

$lines += "Targets found: $($targets.Count)"
foreach ($t in $targets) {
  $lines += ""
  $lines += "--------------------------------------------------------------"
  $lines += "TARGET: type=$($t.type) | title=$($t.title)"
  $lines += "  url=$($t.url)"
  if ($t.webSocketDebuggerUrl -and ($t.type -notin @('worker', 'service_worker'))) {
    try {
      $resJson = Invoke-Cdp $t.webSocketDebuggerUrl $js
      $parsed = $resJson | ConvertFrom-Json
      $lines += "  Candidates found: $($parsed.candidateCount)"
      foreach ($c in $parsed.candidates) {
        $btnLabel = if ($c.isButton) { "[BUTTON]" } else { "[ELEMENT]" }
        $dlgLabel = if ($c.inDialog) { "(in-dialog)" } else { "(ui)" }
        $lines += "    $btnLabel $dlgLabel <$($c.tag)> raw='$($c.rawText)' clean='$($c.cleanedText)' class='$($c.cls)'"
      }
    } catch {
      $lines += "  CDP Error: $($_.Exception.Message)"
    }
  } else {
    $lines += "  (Worker/internal target skipped)"
  }
}

$lines | Out-File -FilePath $out -Encoding UTF8
$lines | ForEach-Object { Write-Host $_ }
Write-Host "`nReport saved to: $out"
