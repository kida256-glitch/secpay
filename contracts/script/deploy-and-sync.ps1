# Requires BASE_SEPOLIA_RPC_URL and PRIVATE_KEY in the repository .env file.
# It broadcasts the deployment, then writes the deployed addresses used by Next.js.
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$envFile = Join-Path $repoRoot '..\.env'
if (Test-Path $envFile) {
  Get-Content $envFile | ForEach-Object {
    if ($_ -match '^([^#=]+)=(.*)$') { [Environment]::SetEnvironmentVariable($matches[1].Trim(), $matches[2].Trim(), 'Process') }
  }
}
if (-not $env:BASE_SEPOLIA_RPC_URL -or -not $env:PRIVATE_KEY) { throw 'Set BASE_SEPOLIA_RPC_URL and PRIVATE_KEY in .env first.' }

forge script script/Deploy.s.sol:Deploy --rpc-url $env:BASE_SEPOLIA_RPC_URL --broadcast
if ($LASTEXITCODE -ne 0) { throw 'Deployment failed. No contract addresses were created.' }
$deploymentPath = Join-Path $repoRoot 'deployments\base-sepolia.json'
if (-not (Test-Path $deploymentPath)) { throw 'Deployment completed but no deployment-address file was written.' }
$deployment = Get-Content $deploymentPath -Raw | ConvertFrom-Json
$usdc = $deployment.mockUSDC
$pool = $deployment.secPayPool
$env:SECPAY_POOL_ADDRESS = $pool; $env:MOCK_USDC_ADDRESS = $usdc
forge script script/SyncFrontend.s.sol:SyncFrontend
Write-Host "MockUSDC: $usdc`nSecPayPool: $pool"
