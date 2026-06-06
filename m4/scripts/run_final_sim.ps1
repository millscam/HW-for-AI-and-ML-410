# M4 final end-to-end co-simulation (Icarus Verilog)
# Run from repository root:  .\project\m4\scripts\run_final_sim.ps1

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$M4   = Join-Path $Root "project\m4"
$Sim  = Join-Path $M4 "sim"
$Rtl  = Join-Path $M4 "rtl"
$Tb   = Join-Path $M4 "tb\tb_top.sv"

$Out  = Join-Path $Sim "sim_top.out"
$Log  = Join-Path $Sim "final_run.log"

Push-Location $Root
try {
    & iverilog -g2012 -DDUMP_VCD -o $Out `
        $Tb `
        (Join-Path $Rtl "top.sv") `
        (Join-Path $Rtl "interface.sv") `
        (Join-Path $Rtl "compute_core.sv")
    if ($LASTEXITCODE -ne 0) { throw "iverilog failed" }

    Push-Location $Sim
    try {
        & vvp (Split-Path -Leaf $Out) 2>&1 | Tee-Object -FilePath $Log
        if ($LASTEXITCODE -ne 0) { throw "vvp failed" }
    } finally {
        Pop-Location
    }

    $pass = Select-String -Path $Log -Pattern "PASS -- all end-to-end checks passed" -Quiet
    if (-not $pass) {
        Write-Error "Simulation did not report PASS. See $Log"
    }
    Write-Host "OK: $Log"
} finally {
    Pop-Location
}
