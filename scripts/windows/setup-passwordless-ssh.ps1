$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$DefaultRemoteUser = 'root'

function Write-Info($msg) { Write-Host "🔹 $msg" }
function Write-Ok($msg) { Write-Host "✅ $msg" }
function Write-WarnMsg($msg) { Write-Host "⚠️  $msg" }
function Write-Err($msg) { Write-Host "❌ $msg" -ForegroundColor Red }

function Pause-AndExit([int]$code = 0) {
  Write-Host ''
  Read-Host '按回车键关闭窗口' | Out-Null
  exit $code
}

function Need-Command([string]$name) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
    throw "缺少系统命令：$name"
  }
}

function Ensure-SshDir {
  if (-not (Test-Path $script:SshDir)) {
    New-Item -ItemType Directory -Path $script:SshDir | Out-Null
  }
}

function Trim-Value([string]$value) {
  return $value.Trim()
}

function Sanitize-Alias([string]$value) {
  $normalized = $value.ToLowerInvariant()
  $normalized = [regex]::Replace($normalized, '[^a-z0-9._-]+', '-')
  $normalized = [regex]::Replace($normalized, '^-+', '')
  $normalized = [regex]::Replace($normalized, '-+$', '')
  $normalized = [regex]::Replace($normalized, '-{2,}', '-')
  return $normalized
}

function Prompt-Inputs {
  $hostInput = Read-Host '请输入服务器 IP 或域名'
  $script:SshHost = Trim-Value $hostInput
  if ([string]::IsNullOrWhiteSpace($script:SshHost)) {
    throw '服务器 IP 或域名不能为空。'
  }

  $userInput = Read-Host "请输入 SSH 用户名（默认 $DefaultRemoteUser）"
  if ([string]::IsNullOrWhiteSpace($userInput)) {
    $script:SshUser = $DefaultRemoteUser
  } else {
    $script:SshUser = Trim-Value $userInput
  }

  if ([string]::IsNullOrWhiteSpace($script:SshUser)) {
    throw 'SSH 用户名不能为空。'
  }

  $aliasInput = Read-Host '请输入本地备注名（例如 vultr-root）'
  $aliasInput = Trim-Value $aliasInput
  if ([string]::IsNullOrWhiteSpace($aliasInput)) {
    throw '备注名不能为空。'
  }

  $script:HostAlias = Sanitize-Alias $aliasInput
  if ([string]::IsNullOrWhiteSpace($script:HostAlias)) {
    throw '备注名清洗后为空，请换一个。'
  }

  if ($script:HostAlias -ne $aliasInput) {
    Write-WarnMsg "备注名已自动规范化为：$($script:HostAlias)"
  }

  $script:KeyFile = Join-Path $script:SshDir ("id_ed25519_" + $script:HostAlias)
  $script:ConfigFile = Join-Path $script:SshDir 'config'
  $script:MarkBegin = "# >>> $($script:HostAlias) managed block >>>"
  $script:MarkEnd = "# <<< $($script:HostAlias) managed block <<<"
}

function Ensure-Keypair {
  $pubFile = "$($script:KeyFile).pub"
  if ((Test-Path $script:KeyFile) -and (Test-Path $pubFile)) {
    Write-Ok "检测到已有密钥，将复用：$($script:KeyFile)"
    return
  }

  Write-Info "正在生成新的 SSH 密钥：$($script:KeyFile)"
  & ssh-keygen -t ed25519 -f $script:KeyFile -C "$($env:USERNAME)@$($env:COMPUTERNAME)-$($script:HostAlias)" -N ''
  if ($LASTEXITCODE -ne 0) {
    throw 'ssh-keygen 执行失败。'
  }
  Write-Ok '密钥生成完成'
}

function Install-PublicKey {
  Write-Host ''
  Write-Info '接下来会要求你输入服务器密码，用于安装公钥。'
  Write-Info '密码只会由 ssh 读取，不会写入脚本或配置文件。'
  Write-Host ''

  $target = "$($script:SshUser)@$($script:SshHost)"
  $sshCopyId = Get-Command ssh-copy-id -ErrorAction SilentlyContinue
  if ($sshCopyId) {
    & $sshCopyId.Source -i "$($script:KeyFile).pub" -o StrictHostKeyChecking=accept-new $target
    if ($LASTEXITCODE -ne 0) {
      throw 'ssh-copy-id 执行失败。'
    }
    return
  }

  $pubKey = Get-Content "$($script:KeyFile).pub" -Raw
  $remoteScript = @'
set -eu
umask 077
mkdir -p "$HOME/.ssh"
touch "$HOME/.ssh/authorized_keys"
chmod 700 "$HOME/.ssh"
chmod 600 "$HOME/.ssh/authorized_keys"
tmp="$(mktemp)"
cat > "$tmp"
grep -qxFf "$tmp" "$HOME/.ssh/authorized_keys" || cat "$tmp" >> "$HOME/.ssh/authorized_keys"
rm -f "$tmp"
'@

  $pubKey | & ssh -o StrictHostKeyChecking=accept-new $target $remoteScript
  if ($LASTEXITCODE -ne 0) {
    throw '通过 ssh 安装公钥失败。'
  }
}

function Write-Config {
  if (-not (Test-Path $script:ConfigFile)) {
    New-Item -ItemType File -Path $script:ConfigFile | Out-Null
  }

  $existing = @()
  if (Test-Path $script:ConfigFile) {
    $existing = Get-Content $script:ConfigFile
  }

  $filtered = New-Object System.Collections.Generic.List[string]
  $skip = $false
  foreach ($line in $existing) {
    if ($line -eq $script:MarkBegin) {
      $skip = $true
      continue
    }
    if ($line -eq $script:MarkEnd) {
      $skip = $false
      continue
    }
    if (-not $skip) {
      $filtered.Add($line)
    }
  }

  if ($filtered.Count -gt 0 -and $filtered[$filtered.Count - 1] -ne '') {
    $filtered.Add('')
  }

  $filtered.Add($script:MarkBegin)
  $filtered.Add("Host $($script:HostAlias)")
  $filtered.Add("  HostName $($script:SshHost)")
  $filtered.Add("  User $($script:SshUser)")
  $filtered.Add("  IdentityFile $($script:KeyFile.Replace('\','/'))")
  $filtered.Add('  IdentitiesOnly yes')
  $filtered.Add('  PreferredAuthentications publickey')
  $filtered.Add($script:MarkEnd)

  [System.IO.File]::WriteAllLines($script:ConfigFile, $filtered)
  Write-Ok "已写入 ~/.ssh/config 别名：$($script:HostAlias)"
}

function Verify-PasswordlessLogin {
  Write-Info '正在验证新免密 SSH...'

  & ssh `
    -i $script:KeyFile `
    -o IdentitiesOnly=yes `
    -o BatchMode=yes `
    -o ConnectTimeout=8 `
    -o StrictHostKeyChecking=accept-new `
    -o ControlMaster=no `
    -o ControlPath=none `
    "$($script:SshUser)@$($script:SshHost)" `
    'echo __SSH_OK__'
  if ($LASTEXITCODE -ne 0) {
    throw '使用新密钥直连验证失败。'
  }

  & ssh `
    -o BatchMode=yes `
    -o ConnectTimeout=8 `
    -o ControlMaster=no `
    -o ControlPath=none `
    $script:HostAlias `
    'echo __SSH_ALIAS_OK__'
  if ($LASTEXITCODE -ne 0) {
    throw '使用备注名验证失败。'
  }

  Write-Ok '免密 SSH 验证通过'
}

try {
  Clear-Host
  Write-Host '========================================'
  Write-Host '  SSH 免密配置器（Windows）'
  Write-Host '========================================'
  Write-Host ''
  Write-Info '这个工具会自动完成：生成新密钥、上传公钥、写入 SSH 别名、验证免密登录。'
  Write-Info '适合第一次在新机器上配置 SSH。'

  Need-Command ssh
  Need-Command ssh-keygen
  Need-Command Get-Content

  $script:SshDir = Join-Path $HOME '.ssh'
  Ensure-SshDir
  Prompt-Inputs
  Ensure-Keypair
  Install-PublicKey
  Write-Config
  Verify-PasswordlessLogin

  Write-Host ''
  Write-Ok '配置完成。以后可以直接使用：'
  Write-Host "   ssh $($script:HostAlias)"
  Write-Host ''
  Write-Ok "私钥位置：$($script:KeyFile)"
  Pause-AndExit 0
} catch {
  Write-Err $_.Exception.Message
  Pause-AndExit 1
}
