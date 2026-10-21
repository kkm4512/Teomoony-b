# Teomoony - kick the stuck cloudflared service and start it with real args.
#   The old argument-less process ignored SCM's stop, leaving the service in
#   StopPending forever, so Start-Service failed. Kill it, then start.
Start-Transcript -Path 'C:\Project\Teomoony\etl\_cf_fix.out.txt' -Force | Out-Null
Write-Output '[kill stuck process]'
Get-Process cloudflared -ErrorAction SilentlyContinue |
  ForEach-Object { Write-Output ("  killing PID " + $_.Id); Stop-Process -Id $_.Id -Force }
Start-Sleep -Seconds 4
Write-Output ("  service status: " + (Get-Service cloudflared).Status)

Write-Output '[start]'
try { Start-Service cloudflared; Write-Output '  started' }
catch { Write-Output ("  FAILED: " + $_.Exception.Message) }
Start-Sleep -Seconds 12
Write-Output ("  status: " + (Get-Service cloudflared).Status)
Get-Process cloudflared -ErrorAction SilentlyContinue |
  ForEach-Object { Write-Output ("  PID " + $_.Id) }

Write-Output '[reach the site from outside]'
foreach ($u in @('https://teomoony.com/', 'https://www.teomoony.com/')) {
  try {
    $r = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 25
    Write-Output ("  " + $u + "  -> " + $r.StatusCode)
  } catch { Write-Output ("  " + $u + "  -> FAILED: " + $_.Exception.Message) }
}
Stop-Transcript | Out-Null
