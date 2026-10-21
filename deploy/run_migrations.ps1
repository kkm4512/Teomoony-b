<#
  Teomoony - 스키마 마이그레이션 실행기 (Windows / PowerShell)

  사용법
    cd C:\Project\Teomoony\deploy
    .\run_migrations.ps1
    .\run_migrations.ps1 -WithSample     # 구조 검증용 합성 샘플까지 적재

  -I (QUOTED_IDENTIFIER ON) 이 반드시 필요하다.
  sqlcmd 기본값이 OFF 라서, PERSISTED computed column 과
  filtered index 가 걸린 테이블 생성이 그냥 실패한다.
#>
param(
    [switch]$WithSample,
    [string]$Container = "teomoony-mssql",
    # ★ 평문을 여기 안 둔다. .env 가 유일한 출처다.
    [string]$SaPassword = (((Get-Content "$PSScriptRoot\..\.env") |
        Where-Object { $_ -like 'DB_PASSWORD=*' }) -replace '^DB_PASSWORD=','')
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($SaPassword)) {
    throw ".env 에 DB_PASSWORD 가 없다. C:\Project\Teomoony\.env 를 확인해라."
}
$sqlcmd = "/opt/mssql-tools18/bin/sqlcmd"

function Invoke-SqlFile {
    param([string]$LocalPath)

    $name = Split-Path $LocalPath -Leaf
    Write-Host "  -> $name" -ForegroundColor Cyan

    docker cp $LocalPath "${Container}:/tmp/$name" | Out-Null
    $out = docker exec $Container $sqlcmd -S localhost -U sa -P $SaPassword -C -No -I -i "/tmp/$name" 2>&1
    $joined = $out -join "`n"

    # sqlcmd 는 SQL 오류가 나도 exit code 0 을 주는 경우가 있어 본문을 직접 검사한다
    if ($joined -match "Msg \d+, Level (1[6-9]|2[0-5])") {
        Write-Host $joined -ForegroundColor Red
        throw "FAILED: $name"
    }
    $joined -split "`n" | Where-Object { $_ -match "done\.|rows affected" } | ForEach-Object {
        Write-Host "     $_" -ForegroundColor DarkGray
    }
}

Write-Host "`n[1/3] 컨테이너 상태 확인" -ForegroundColor Yellow
$state = docker inspect -f '{{.State.Running}}' $Container 2>$null
if ($state -ne "true") {
    Write-Host "  컨테이너가 꺼져 있습니다. docker compose up -d 먼저 실행하세요." -ForegroundColor Red
    exit 1
}

Write-Host "[2/3] SQL Server 접속 대기" -ForegroundColor Yellow
$ready = $false
for ($i = 1; $i -le 60; $i++) {
    docker exec $Container $sqlcmd -S localhost -U sa -P $SaPassword -C -No -Q "SELECT 1" *> $null
    if ($LASTEXITCODE -eq 0) { $ready = $true; Write-Host "  준비됨 ($($i*2)s)" -ForegroundColor Green; break }
    Start-Sleep -Seconds 2
}
if (-not $ready) { Write-Host "  접속 실패. docker logs $Container 확인" -ForegroundColor Red; exit 1 }

Write-Host "[3/3] 마이그레이션 적용" -ForegroundColor Yellow
# ★ 목록을 직접 적지 않는다. 전에는 00~03 네 개만 있었고,
#   그 뒤에 마이그레이션을 24개 더 만들어도 **아무도 목록을 업데이트하지
#   않았다.** 이 스크립트로 DB 를 새로 만들면 스키마가 미완성인데
#   성공으로 끝나는 종류다(2026-10-17).
#
#   NN_ 파일 전부를 번호 순으로 집는다. 9x 는 진단/샘플용이므로 제외한다.
#   모든 파일은 OBJECT_ID 가드가 있어 재실행이 안전하다(확인함).
$scripts = Get-ChildItem (Join-Path $PSScriptRoot "sql") -Filter "*.sql" |
    Where-Object { $_.Name -match '^[0-8][0-9]_' } |
    Sort-Object Name | Select-Object -ExpandProperty Name
if ($WithSample) { $scripts += "90_sample_probe.sql" }
Write-Host "  적용 대상 $($scripts.Count) 개" -ForegroundColor DarkGray

foreach ($s in $scripts) {
    $p = Join-Path $PSScriptRoot "sql\$s"
    if (-not (Test-Path $p)) { throw "스크립트 없음: $p" }
    Invoke-SqlFile -LocalPath $p
}

Write-Host "`n완료." -ForegroundColor Green
# ★ 비밀번호는 찍지 않는다. 터미널이 어디에 남는지 모른다.
Write-Host "접속 정보 : localhost,11433 / sa / (.env 의 DB_PASSWORD) / DB=Teomoony`n"
