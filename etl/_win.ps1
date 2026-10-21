$p = 28236
Get-Process -Id $p -ErrorAction SilentlyContinue | ForEach-Object {
  Write-Output ("killing " + $_.Id + " " + $_.ProcessName); Stop-Process -Id $_.Id -Force }
Start-Sleep -Seconds 3
Get-Process python -ErrorAction SilentlyContinue | ForEach-Object { Write-Output ("남은 python PID " + $_.Id) }
