param(
    # Executável do Python (por padrão: "python")
    [string]$Python = "python",

    # Nome do arquivo de log
    [string]$LogFile = "1.log"
)

$ErrorActionPreference = "Stop"

# Início do log (sobrescreve o arquivo anterior)
"==== Execução em $(Get-Date) ====" | Out-File -FilePath $LogFile -Encoding UTF8

Write-Host "Usando executável: $Python"
Add-Content $LogFile "Usando executável: $Python"

Write-Host "Listando pacotes desatualizados..."
Add-Content $LogFile "`nListando pacotes desatualizados..."

# -------------------------------------------------------------------
# 1) Tenta via JSON (pip moderno, mais confiável)
# -------------------------------------------------------------------
$packages = $null
$outdatedJson = & $Python -m pip list --outdated --format=json | Out-String

Add-Content $LogFile "`nSaída bruta do 'pip list --outdated --format=json':"
Add-Content $LogFile $outdatedJson

try {
    if (-not [string]::IsNullOrWhiteSpace($outdatedJson)) {
        $packages = $outdatedJson | ConvertFrom-Json
    }
} catch {
    Add-Content $LogFile "`nFalha ao interpretar JSON, tentando formato freeze..."
}

# -------------------------------------------------------------------
# 2) Se JSON não funcionou ou veio vazio, tenta formato freeze
# -------------------------------------------------------------------
if (-not $packages -or $packages.Count -eq 0) {
    $packages = @()
    $outdatedFreeze = & $Python -m pip list --outdated --format=freeze | ForEach-Object { $_.ToString() }

    Add-Content $LogFile "`nSaída bruta do 'pip list --outdated --format=freeze':"
    $outdatedFreeze | ForEach-Object { Add-Content $LogFile "  $_" }

    foreach ($line in $outdatedFreeze) {
        if ($line -match '==') {
            # Cada linha vem como "nome==versao"
            $name = $line.Split('=')[0].Trim()
            if (-not [string]::IsNullOrWhiteSpace($name)) {
                $obj = [PSCustomObject]@{ name = $name }
                $packages += $obj
            }
        }
    }
}

# -------------------------------------------------------------------
# 3) Se ainda não tem pacote, então não há nada para atualizar
# -------------------------------------------------------------------
if (-not $packages -or $packages.Count -eq 0) {
    Write-Host "`nNenhum pacote desatualizado encontrado."
    Add-Content $LogFile "`nNenhum pacote desatualizado encontrado."
    Add-Content $LogFile "==== Fim em $(Get-Date) ===="
    exit 0
}

Write-Host "Iniciando atualização dos pacotes...`n"
Add-Content $LogFile "`nIniciando atualização dos pacotes...`n"

$successCount = 0
$errorCount   = 0

foreach ($pkg in $packages) {
    $packageName = $pkg.name
    if ([string]::IsNullOrWhiteSpace($packageName)) { continue }

    Write-Host "Atualizando pacote: $packageName ..."
    Add-Content $LogFile "----------------------------------------"
    Add-Content $LogFile "[$(Get-Date)] Atualizando pacote: $packageName"

    # Executa o pip e manda toda a saída (stdout + stderr) para o log
    & $Python -m pip install -U $packageName *>> $LogFile

    if ($LASTEXITCODE -eq 0) {
        $successCount++
        Write-Host "  -> OK"
        Add-Content $LogFile "[$(Get-Date)] SUCESSO ao atualizar $packageName"
    } else {
        $errorCount++
        Write-Warning "  -> ERRO ao atualizar $packageName (exit code $LASTEXITCODE). Veja $LogFile."
        Add-Content $LogFile "[$(Get-Date)] ERRO ao atualizar $packageName (exit code $LASTEXITCODE)"
    }

    Add-Content $LogFile ""  # linha em branco
}

Write-Host "`nAtualização concluída."
Write-Host "Sucessos: $successCount  |  Erros: $errorCount"
Add-Content $LogFile "`nResumo:"
Add-Content $LogFile "  Sucessos: $successCount"
Add-Content $LogFile "  Erros:    $errorCount"
Add-Content $LogFile "==== Fim em $(Get-Date) ===="
