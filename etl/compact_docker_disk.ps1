# compact_docker_disk.ps1 - Docker data disk (docker_data.vhdx) compaction (2026-10-26)
#   Must run as administrator (diskpart). Stops Docker for 10-30 min, then restarts it and re-queues the loaders.
#   ASCII only on purpose (Windows PowerShell 5 reads .ps1 as ANSI).
$ErrorActionPreference = "Continue"
$root = "C:\Project\Teomoony"
$log  = Join-Path $root ("logs\compact_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".log")
function L($m) { $s = (Get-Date -Format "HH:mm:ss") + " " + $m; $s | Tee-Object -FilePath $log -Append }
$v = Join-Path $env:LOCALAPPDATA "Docker\wsl\disk\docker_data.vhdx"
if (-not (Test-Path $v)) { $v = "C:\Users\" + (Split-Path $env:USERPROFILE -Leaf) + "\AppData\Local\Docker\wsl\disk\docker_data.vhdx" }
L ("admin: " + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
L ("vhdx: " + $v + "  size GB: " + [math]::Round((Get-Item $v).Length/1GB,1) + "  C free GB: " + [math]::Round((Get-PSDrive C).Free/1GB,1))
L "trim inside the VM"
wsl -d docker-desktop -u root -e sh -c 'fstrim -av 2>&1' 2>&1 | ForEach-Object { L $_ }
L "stop heavy loaders"
$p = Get-CimInstance Win32_Process -Filter "Name='python.exe'" | Where-Object { $_.CommandLine -match 'hub_swap|load_cadastral|nation_lawd|rtms_nation|load_rtms|kapt_cost|nation_sgg|load_kapt|svc_publish' }
L ("kill " + @($p).Count); $p | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep 5
L "stop Docker and WSL"
Get-Process 'Docker Desktop','com.docker.backend','com.docker.build','docker' -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 10
wsl --shutdown
Start-Sleep 15
wsl -l -v 2>&1 | ForEach-Object { L $_ }
L "diskpart compact (takes a while)"
$dp = Join-Path $env:TEMP "teomoony_compact.txt"
@("select vdisk file=""$v""", "attach vdisk readonly", "compact vdisk", "detach vdisk", "exit") | Set-Content -Path $dp -Encoding ASCII
diskpart /s $dp 2>&1 | ForEach-Object { L $_ }
L ("after: size GB: " + [math]::Round((Get-Item $v).Length/1GB,1) + "  C free GB: " + [math]::Round((Get-PSDrive C).Free/1GB,1))
L "start Docker"
Start-Process (Join-Path $env:LOCALAPPDATA "Programs\DockerDesktop\Docker Desktop.exe")
for ($i = 0; $i -lt 40; $i++) { Start-Sleep 10; $o = docker ps --format '{{.Names}} {{.Status}}' 2>$null; if ($LASTEXITCODE -eq 0 -and $o) { $o | ForEach-Object { L $_ }; break } }
Start-Sleep 30
L "re-queue loaders"
foreach ($j in @('hs-hub-index-hsprc-par','nc-cadastral-nation-par','rn-rtms-nation-par','nk-kapt-nation-par','ci-kaptcost-1y-par','sp-full-rest-par')) { New-Item -ItemType File -Force -Path (Join-Path $root "etl\_queue\$j.job") | Out-Null; L ("queued " + $j) }
L "done"
