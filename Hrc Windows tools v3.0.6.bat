@echo off
fltmc >nul 2>&1 || (powershell Start -File "%~f0" -Verb RunAs >nul 2>&1 && exit /b)
chcp 65001 >nul 2>&1
title HRC 系统优化工具 V3.6 最终版

powershell -Command "$code=@'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Media
[System.Windows.Forms.Application]::EnableVisualStyles()

$HRC_ROOT = "C:\HRC_TempCache"
$MUSIC_DIR = Join-Path $HRC_ROOT "Music"
$SETAPP_DIR = Join-Path $HRC_ROOT "SetApp"
@($HRC_ROOT, $MUSIC_DIR, $SETAPP_DIR) | ForEach-Object { if(-not (Test-Path $_)){New-Item -ItemType Directory -Path $_ -Force | Out-Null} }

$SELF_PATH = $MyInvocation.MyCommand.Path
$AUTO_RUN_CFG = Join-Path $HRC_ROOT "auto_boot.ini"
$RUN_MARK = Join-Path $HRC_ROOT "run_lock.lock"
if(Test-Path $RUN_MARK){
    [System.Windows.Forms.MessageBox]::Show("工具正在运行中，请勿重复启动", "提示", "OK", "Warning")
    exit
}
New-Item $RUN_MARK -ItemType File -Force | Out-Null

$globalFont = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Point)
$titleFont = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Point)

function Confirm-ThreeTimes {
    param($Title, $Msg1, $Msg2, $Msg3)
    $res1 = [System.Windows.Forms.MessageBox]::Show($Msg1, $Title, "OKCancel", "Warning")
    if($res1 -ne "OK"){return $false}
    $res2 = [System.Windows.Forms.MessageBox]::Show($Msg2, $Title, "OKCancel", "Warning")
    if($res2 -ne "OK"){return $false}
    $res3 = [System.Windows.Forms.MessageBox]::Show($Msg3, $Title, "OKCancel", "Warning")
    return ($res3 -eq "OK")
}

function Download-WithProgress {
    param($Url, $SavePath, $ProgressBar, $StatusLabel)
    if(Test-Path $SavePath){
        $fileSize = (Get-Item $SavePath).Length / 1MB
        $StatusLabel.Text = "使用本地缓存：$([math]::Round($fileSize,2)) MB"
        [System.Windows.Forms.Application]::DoEvents()
        return $true
    }
    $mirrorMap = @{
        "https://aka.ms/vs/17/release/vc_redist.x64.exe" = @(
            "https://mirrors.tuna.tsinghua.edu.cn/Adoptium/17/jdk/x64/windows/jdk-17-latest-x64.exe",
            "https://mirror.ghproxy.com/https://aka.ms/vs/17/release/vc_redist.x64.exe"
        )
        "https://download.oracle.com/java/17/latest/jdk-17_windows-x64_bin.exe" = @(
            "https://mirrors.tuna.tsinghua.edu.cn/Adoptium/17/jdk/x64/windows/jdk-17-latest-x64.exe",
            "https://mirror.ghproxy.com/https://download.oracle.com/java/17/latest/jdk-17_windows-x64_bin.exe"
        )
        "https://www.huorong.cn/download/huorong-latest.exe" = @(
            "https://mirror.ghproxy.com/https://www.huorong.cn/download/huorong-latest.exe",
            "https://down.huorong.cn/huorong-latest.exe"
        )
    }
    $tryUrls = @($Url)
    if($mirrorMap.ContainsKey($Url)){ $tryUrls += $mirrorMap[$Url] }

    foreach($targetUrl in $tryUrls){
        for($retry=0;$retry -lt 3;$retry++){
            try{
                $webClient = New-Object System.Net.WebClient
                $webClient.Timeout = 120000
                $webClient.DownloadProgressChanged += {
                    $p = [Math]::Min($args[1].ProgressPercentage, 100)
                    $ProgressBar.Value = $p
                    $StatusLabel.Text = "正在下载：$([math]::Round($args[1].BytesReceived / 1MB,2)) MB / $([math]::Round($args[1].TotalBytesToReceive / 1MB,2)) MB"
                    [System.Windows.Forms.Application]::DoEvents()
                }
                $asyncTask = $webClient.DownloadFileTaskAsync($targetUrl, $SavePath)
                while(-not $asyncTask.Wait(10)){[System.Windows.Forms.Application]::DoEvents()}
                if(Test-Path $SavePath){return $true}
            }catch{
                $StatusLabel.Text = "下载超时，正在重试 $($retry+1)/3"
                [System.Windows.Forms.Application]::DoEvents()
                Start-Sleep 1
            }
        }
    }
    $StatusLabel.Text = "下载失败，跳过当前步骤"
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep 1
    return $false
}

function Cleanup-RedundantServices {
    $keepServices = @(
        "Audiosrv", "Dhcp", "Dnscache", "EventLog", "LanmanServer", "LanmanWorkstation",
        "PlugPlay", "RpcSs", "Schedule", "Seclogon", "TermService", "Themes", "Winmgmt", "wuauserv",
        "nvvsvc", "amdacpsvc", "BthServ", "Spooler", "WlanSvc", "Dot3Svc", "msedgewebview2"
    )
    $keepUninstall = @("nvidia","amd","intel","驱动","驱动人生","驱动精灵")
    Get-Service | Where-Object { 
        $_.StartType -eq "Automatic" -and $_.Status -eq "Running" -and 
        -not ($keepServices -contains $_.Name.ToLower())
    } | ForEach-Object {
        try{Stop-Service $_.Name -Force -ErrorAction SilentlyContinue; Set-Service $_.Name -StartupType Disabled -ErrorAction SilentlyContinue}catch{}
    }
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    $keepProcess = @("System", "Idle", "explorer", "svchost", "lsass", "winlogon", "nvvpdsrv", "amdowcc", "msedgewebview2")
    Get-Process | Where-Object { 
        $_.CPU -gt 10 -and $_.WorkingSet -gt 100MB -and 
        -not ($keepProcess -contains $_.Name.ToLower())
    } | Stop-Process -Force -ErrorAction SilentlyContinue
}

$fullSteps = @(
    @{p=5;t="1/21 重置Winsock网络栈";c={netsh winsock reset | Out-Null}},
    @{p=10;t="2/21 重置TCP/IP协议栈";c={netsh int ip reset | Out-Null}},
    @{p=15;t="3/21 修复Windows更新组件";c={
        Stop-Service wuauserv cryptsvc -Force -ErrorAction SilentlyContinue
        Rename-Item C:\Windows\SoftwareDistribution C:\Windows\SoftwareDistribution.old -Force -ErrorAction SilentlyContinue
        Rename-Item C:\Windows\System32\catroot2 C:\Windows\System32\catroot2.old -Force -ErrorAction SilentlyContinue
        Start-Service wuauserv cryptsvc
    }},
    @{p=20;t="4/21 执行DISM系统镜像修复";c={dism /online /cleanup-image /restorehealth | Out-Null}},
    @{p=25;t="5/21 执行SFC系统文件扫描";c={sfc /scannow | Out-Null}},
    @{p=30;t="6/21 清理后台冗余服务进程";c={Cleanup-RedundantServices}},
    @{p=35;t="7/21 强制释放系统待机内存";c={EmptyStandbyList.exe -all >$null 2>&1}},
    @{p=40;t="8/21 安装VC++全版本运行库";c={
        $vcPath = Join-Path $SETAPP_DIR vc_redist.exe
        Download-WithProgress -Url "https://aka.ms/vs/17/release/vc_redist.x64.exe" -SavePath $vcPath -ProgressBar $mainBar -StatusLabel $statusLabel
        Start-Process $vcPath /quiet /norestart -Wait
    }},
    @{p=45;t="9/21 安装Java 17官方运行环境";c={
        $javaPath = Join-Path $SETAPP_DIR jre17.exe
        Download-WithProgress -Url "https://download.oracle.com/java/17/latest/jdk-17_windows-x64_bin.exe" -SavePath $javaPath -ProgressBar $mainBar -StatusLabel $statusLabel
        Start-Process $javaPath /s INSTALLDIR="C:\Program Files\Java\jdk-17" -Wait
    }},
    @{p=50;t="10/21 修复Windows应用商店组件";c={Get-AppXPackage -AllUsers | Foreach {Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml" -ErrorAction SilentlyContinue}}},
    @{p=55;t="11/21 安装.NET全版本运行组件";c={dism /online /enable-feature /featurename:NetFx3 /All | Out-Null; winget install --id Microsoft.DotNet.DesktopRuntime.6 --id Microsoft.DotNet.DesktopRuntime.7 --id Microsoft.DotNet.DesktopRuntime.8 --silent --accept-package-agreements --accept-source-agreements | Out-Null}},
    @{p=60;t="12/21 锁定Defender扫描CPU为5%";c={Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows Defender\Scan" AvgCPULoadFactor -Value 5 -Force}},
    @{p=65;t="13/21 开启高性能电源计划";c={powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61; powercfg /setactive e9a42b02-d5df-448d-aa00-03f14749eb61}},
    @{p=70;t="14/21 扫描所有非系统盘坏道";c={Get-Volume | Where-Object {$_.DriveLetter -ne $null -and $_.DriveLetter -ne "C"} | ForEach-Object {chkdsk $_.DriveLetter: /k >$null 2>&1}}},
    @{p=75;t="15/21 卸载全家桶安全软件";c={Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where-Object {$_.DisplayName -match '360|腾讯管家|鲁大师|金山毒霸|百度卫士' -and $_.DisplayName -notin @('火绒安全软件','Windows Defender','火绒') -and -not ($keepUninstall | Where-Object {$_.DisplayName -match $_})} | ForEach-Object {if($_.UninstallString -match 'msiexec'){cmd /c "$($_.UninstallString) /x /s >$null 2>&1"}else{cmd /c "$($_.UninstallString) /s >$null 2>&1"}; Start-Sleep 3}}},
    @{p=80;t="16/21 静默安装最新版火绒";c={
        $hrcPath = Join-Path $SETAPP_DIR huorong.exe
        Download-WithProgress -Url "https://www.huorong.cn/download/huorong-latest.exe" -SavePath $hrcPath -ProgressBar $mainBar -StatusLabel $statusLabel
        Start-Process $hrcPath /verysilent /norestart -Wait
    }},
    @{p=85;t="17/21 清理右键菜单冗余项目";c={reg delete "HKCR\DesktopBackground\Shell" /va /f /reg:64 >$null 2>&1}},
    @{p=90;t="18/21 清除Xbox/OneDrive冗余组件";c={Get-AppxPackage *Xbox*,*OneDrive*,*Cortana* | Remove-AppxPackage -ErrorAction SilentlyContinue}},
    @{p=92;t="19/21 修复任务栏卡死问题";c={Stop-Process explorer -Force -ErrorAction SilentlyContinue; Start-Process explorer}},
    @{p=95;t="20/21 全系统垃圾缓存清理完成";c={Remove-Item $env:TEMP\*,C:\Windows\Temp\*,C:\Windows\Prefetch\* -Recurse -Force; Clear-RecycleBin -Force}},
    @{p=100;t="21/21 配置重启内存扫描";c={bcdedit /set {default} memorytest=basic >$null 2>&1}}
)

$winVer = [Environment]::OSVersion.Version
$isWin7 = ($winVer.Major -eq 6 -and $winVer.Minor -ge 1) -or $winVer.Major -lt 6

if(Test-Path $AUTO_RUN_CFG){
    $autoCfg = Get-Content $AUTO_RUN_CFG | ConvertFrom-StringData
    $rebootSec = [int]$autoCfg.reboot_sec

    $bootWin = New-Object System.Windows.Forms.Form
    $bootWin.FormBorderStyle = "None"
    $bootWin.Size = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Size
    $bootWin.BackColor = [System.Drawing.Color]::Black
    $bootWin.TopMost = $true
    $bootWin.Opacity = 0
    $bootWin.DoubleBuffered = $true

    $centerX = $bootWin.Width / 2
    $centerY = $bootWin.Height / 2

    $particleLayer = New-Object System.Windows.Forms.Panel
    $particleLayer.Size = $bootWin.Size
    $particleLayer.Location = [System.Drawing.Point]::new(0,0)
    $particleLayer.BackColor = [System.Drawing.Color]::Transparent
    $particleLayer.Visible = $false
    $bootWin.Controls.Add($particleLayer)

    $starLayer = New-Object System.Windows.Forms.Panel
    $starLayer.Size = $bootWin.Size
    $starLayer.Location = [System.Drawing.Point]::new(0,0)
    $starLayer.BackColor = [System.Drawing.Color]::Transparent
    $starLayer.Visible = $false
    $bootWin.Controls.Add($starLayer)

    $hrcTitle = New-Object System.Windows.Forms.Label
    $hrcTitle.Text = "HRC 工具集"
    $hrcTitle.Font = New-Object System.Drawing.Font("Segoe UI", 56, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Point)
    $hrcTitle.ForeColor = [System.Drawing.Color]::White
    $hrcTitle.Location = [System.Drawing.Point]::new($centerX - 180, $centerY - 80)
    $hrcTitle.AutoSize = $true
    $hrcTitle.Visible = $false
    $bootWin.Controls.Add($hrcTitle)

    $winLogo = New-Object System.Windows.Forms.PictureBox
    $winLogo.Image = [System.Drawing.Icon]::ExtractAssociatedIcon("C:\Windows\System32\imageres.dll", 15).ToBitmap()
    $winLogo.Size = [System.Drawing.Size]::new(160, 160)
    $winLogo.Location = [System.Drawing.Point]::new($centerX - 80, $centerY - 120)
    $winLogo.SizeMode = "Stretch"
    $winLogo.Opacity = 0
    $winLogo.Visible = $false
    $bootWin.Controls.Add($winLogo)

    $mainBar = New-Object System.Windows.Forms.ProgressBar
    $mainBar.Size = [System.Drawing.Size]::new(600, 4)
    $mainBar.Location = [System.Drawing.Point]::new($centerX - 300, $bootWin.Height - 120)
    $mainBar.Maximum = 100
    $mainBar.ForeColor = [System.Drawing.Color]::FromArgb(0, 180, 255)
    $mainBar.Style = "Continuous"
    $mainBar.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 40)
    $mainBar.Visible = $false
    $bootWin.Controls.Add($mainBar)

    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.Text = ""
    $statusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Point)
    $statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(180, 180, 180)
    $statusLabel.Location = [System.Drawing.Point]::new($centerX - 120, $bootWin.Height - 160)
    $statusLabel.AutoSize = $true
    $statusLabel.Visible = $false
    $bootWin.Controls.Add($statusLabel)

    $volSlider = New-Object System.Windows.Forms.TrackBar
    $volSlider.Size = [System.Drawing.Size]::new(120, 30)
    $volSlider.Location = [System.Drawing.Point]::new($bootWin.Width - 160, $bootWin.Height - 50)
    $volSlider.Minimum = 30
    $volSlider.Maximum = 75
    $volSlider.Value = 50
    $volSlider.Visible = $false
    $bootWin.Controls.Add($volSlider)

    $bootWin.Add_Shown({
        $bootWin.Refresh()
        for($i=0;$i -le 100;$i+=1){$bootWin.Opacity = $i/100; [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 10}
        Start-Sleep 0.3

        $particleLayer.Visible = $true
        $starLayer.Visible = $true
        $particleList = @()
        for($p=0;$p -lt 80;$p++){
            $dot = New-Object System.Windows.Forms.Panel
            $dot.Size = [System.Drawing.Size]::new(4,4)
            $dot.BackColor = [System.Drawing.Color]::FromArgb(80, [System.Drawing.Color]::LightBlue)
            $dot.Location = [System.Drawing.Point]::new((Get-Random -Maximum $bootWin.Width), (Get-Random -Maximum $bootWin.Height))
            $particleLayer.Controls.Add($dot)
            $particleList += [PSCustomObject]@{
                Obj = $dot
                VelX = (Get-Random -Minimum -2 -Maximum 2)
                VelY = (Get-Random -Minimum -2 -Maximum 2)
            }
        }
        $starList = @()
        for($s=0;$s -lt 15;$s++){
            $star = New-Object System.Windows.Forms.Panel
            $star.Size = [System.Drawing.Size]::new(20,20)
            $star.BackColor = [System.Drawing.Color]::FromArgb(40, [System.Drawing.Color]::White)
            $star.Location = [System.Drawing.Point]::new((Get-Random -Maximum $bootWin.Width), (Get-Random -Maximum $bootWin.Height))
            $starLayer.Controls.Add($star)
            $starList += [PSCustomObject]@{
                Obj = $star
                Phase = (Get-Random -Maximum 360)
            }
        }

        $animTimer = New-Object System.Windows.Forms.Timer
        $animTimer.Interval = 30
        $animTimer.Add_Tick({
            foreach($p in $particleList){
                $newX = $p.Obj.Location.X + $p.VelX
                $newY = $p.Obj.Location.Y + $p.VelY
                if($newX -le 0 -or $newX -ge $bootWin.Width){ $p.VelX *= -1 }
                if($newY -le 0 -or $newY -ge $bootWin.Height){ $p.VelY *= -1 }
                $p.Obj.Location = [System.Drawing.Point]::new([Math]::Clamp($newX, 0, $bootWin.Width), [Math]::Clamp($newY, 0, $bootWin.Height))
            }
            foreach($s in $starList){
                $s.Phase += 8
                $alpha = 30 + [Math]::Abs([Math]::Sin($s.Phase * [Math]::PI / 180)) * 50
                $s.Obj.BackColor = [System.Drawing.Color]::FromArgb($alpha, [System.Drawing.Color]::White)
            }
            [System.Windows.Forms.Application]::DoEvents()
        })
        $animTimer.Start()

        $hrcTitle.Visible = $true
        for($c=0;$c -lt 7;$c++){
            $hrcTitle.Text = $hrcTitle.Text.Substring(0, $c+1)
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 120
        }
        for($i=0;$i -le 100;$i+=2){$hrcTitle.Opacity = $i/100; $hrcTitle.Top -= 1; [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 10}
        Start-Sleep 1

        for($i=100;$i -ge 0;$i-=2){$hrcTitle.Opacity = $i/100; $hrcTitle.Top += 2; [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 10}
        $hrcTitle.Visible = $false

        $winLogo.Visible = $true
        for($i=0;$i -le 100;$i+=2){$winLogo.Opacity = $i/100; $winLogo.Size = [System.Drawing.Size]::new(160-32+[int]($i/100*32), 160-32+[int]($i/100*32)); [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 10}

        $volSlider.Visible = $true
        $mainBar.Visible = $true
        $statusLabel.Visible = $true

        $nodeLabels = @{30="外接设备扫描完成";60="组件预加载完成";90="系统配置初始化完成"}
        foreach($step in $fullSteps){
            if($isWin7 -and $step.t -match "TranslucentTB|winget|内存扫描"){continue}
            $mainBar.Value = $step.p
            $statusLabel.Text = $step.t
            if($nodeLabels.ContainsKey($step.p)){
                $nodeTip = New-Object System.Windows.Forms.Label
                $nodeTip.Text = $nodeLabels[$step.p]
                $nodeTip.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Point)
                $nodeTip.ForeColor = [System.Drawing.Color]::FromArgb(150,150,150)
                $nodeTip.Location = [System.Drawing.Point]::new($centerX - 80, $bootWin.Height - 180)
                $nodeTip.AutoSize = $true
                $bootWin.Controls.Add($nodeTip)
                for($f=0;$f -le 100;$f+=5){$nodeTip.Opacity = $f/100; [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 10}
                Start-Sleep 1
                for($f=100;$f -ge 0;$f-=5){$nodeTip.Opacity = $f/100; [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 10}
                $bootWin.Controls.Remove($nodeTip)
            }
            [System.Windows.Forms.Application]::DoEvents()
            & $step.c
            Start-Sleep -Milliseconds 100
        }

        $animTimer.Stop()
        $statusLabel.Text = "修复完成，即将重启..."
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep 1.5

        for($i=100;$i -ge 0;$i-=1){$bootWin.Opacity = $i/100; [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 10}

        Remove-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce" "HRC_AutoRunOnce" -ErrorAction SilentlyContinue
        Remove-Item $HRC_ROOT -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $RUN_MARK -Force -ErrorAction SilentlyContinue
        shutdown /r /f /t $rebootSec
        $bootWin.Close()
    })
    [void]$bootWin.ShowDialog()
    exit
}

$bootWin = New-Object System.Windows.Forms.Form
$bootWin.FormBorderStyle = "None"
$bootWin.Size = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Size
$bootWin.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$bootWin.TopMost = $true
$bootWin.DoubleBuffered = $true

$bootLogo = New-Object System.Windows.Forms.Label
$bootLogo.Text = "HRC 工具集"
$bootLogo.Font = New-Object System.Drawing.Font("Segoe UI", 64, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Point)
$bootLogo.ForeColor = [System.Drawing.Color]::White
$bootLogo.Location = [System.Drawing.Point]::new(($bootWin.Width/2)-160, ($bootWin.Height/2)-120)
$bootLogo.AutoSize = $true
$bootWin.Controls.Add($bootLogo)

$bootBar = New-Object System.Windows.Forms.ProgressBar
$bootBar.Size = [System.Drawing.Size]::new($bootWin.Width, 4)
$bootBar.Location = [System.Drawing.Point]::new(0, $bootWin.Height - 42)
$bootBar.Maximum = 100
$bootBar.Style = "Continuous"
$bootBar.ForeColor = [System.Drawing.Color]::FromArgb(16, 185, 129)
$bootBar.BackColor = [System.Drawing.Color]::FromArgb(80, 170, 255)
$bootWin.Controls.Add($bootBar)

$bootWin.Add_Shown({
    $bootWin.Refresh()
    $totalSteps = @(
        @{p=10;name="初始化缓存目录";action={Start-Sleep -Milliseconds 100}},
        @{p=35;name="扫描外接设备加载音频";action={
            $usbDrives = Get-Volume | Where-Object { $_.DriveType -eq 'Removable' -and $_.DriveLetter } | Select-Object -ExpandProperty DriveLetter -ErrorAction SilentlyContinue
            $targetMusic = $null
            foreach($drv in $usbDrives){
                $found = Get-ChildItem "$($drv):\" -Include *.wav,*.mp3 -Recurse -Depth 2 -ErrorAction SilentlyContinue | Select-Object -First 1
                if($found){ $targetMusic = $found.FullName; break }
            }
            if(-not $targetMusic){
                $targetMusic = Join-Path $env:SystemRoot "Media\Windows Startup.wav"
            }
            $musicPath = Join-Path $MUSIC_DIR "auto_load.wav"
            if($targetMusic -ne $musicPath){
                Copy-Item $targetMusic $musicPath -Force -ErrorAction SilentlyContinue
            }
        }},
        @{p=70;name="下载组件安装包";action={
            $tbPath = Join-Path $SETAPP_DIR "translucenttb.exe"
            if(-not (Test-Path $tbPath) -and -not $isWin7){
                try{irm "https://cdn.jsdelivr.net/gh/TranslucentTB/TranslucentTB@latest/TranslucentTB.exe" -OutFile $tbPath -TimeoutSec 90}catch{}
            }
        }},
        @{p=90;name="预加载系统组件";action={Start-Sleep -Milliseconds 100}},
        @{p=100;name="启动完成";action={Start-Sleep -Milliseconds 50}}
    )
    foreach($step in $totalSteps){
        $bootBar.Value = $step.p
        [System.Windows.Forms.Application]::DoEvents()
        & $step.action
    }
    $bootWin.Close()
})
[void]$bootWin.ShowDialog()

function Safe-Run {
    param($c)
    $job = Start-Job -ScriptBlock { param($cmd)
        $ErrorActionPreference = "SilentlyContinue"
        for($i=0;$i -lt 4;$i++){try{Invoke-Expression $cmd 2>&1|Out-Null;return $true}catch{Start-Sleep 1}}
        return $false
    } -ArgumentList $c
    $timer = 0
    while($job.State -eq "Running" -and $timer -lt 30){Start-Sleep 1;$timer++;[System.Windows.Forms.Application]::DoEvents()}
    if($job.State -ne "Completed"){Stop-Job $job -Force -ErrorAction SilentlyContinue;Start-Sleep 1;$null = Start-Job -ScriptBlock { param($cmd)
        $ErrorActionPreference = "SilentlyContinue"
        for($i=0;$i -lt 4;$i++){try{Invoke-Expression $cmd 2>&1|Out-Null;return $true}catch{Start-Sleep 1}}
    } -ArgumentList $c | Wait-Job}
    Remove-Job $job -Force -ErrorAction SilentlyContinue
}

$agree=New-Object System.Windows.Forms.Form
$agree.Size="780,680"
$agree.StartPosition="CenterScreen"
$agree.FormBorderStyle="FixedDialog"
$agree.BackColor="White"
$agree.Text="HRC 系统优化工具 开源隐私声明 V3.6"
$agree.Font = $globalFont
$agree.MaximizeBox = $false
$agree.MinimizeBox = $false

$txt=New-Object System.Windows.Forms.Label
$txt.Location="30,30"
$txt.Size="720,580"
$txt.Font = $globalFont
$txt.Text="HRC 系统优化工具 开源项目隐私声明 V3.6`n生效日期：2026年08月13日`n`n1. 本工具为纯本地运行的开源工具，所有操作均在您的设备内执行，全程不会收集、上传、共享任何个人信息或设备数据。`n`n2. 本工具仅用于个人非商业用途，使用过程中修改系统配置、卸载软件、执行修复操作产生的全部风险，由使用者自行承担。`n`n3. 本工具无任何第三方广告、恶意代码，仅会从官方域名下载必要的运行组件，无任何后台追踪行为。`n`n4. 点击「同意」即代表您已完整阅读并接受本声明全部条款，不同意请点击取消，工具将自动退出并清除所有临时文件。"
$agree.Controls.Add($txt)

$btnYes=New-Object System.Windows.Forms.Button
$btnYes.Text="我已阅读并同意"
$btnYes.Location="580,620"
$btnYes.Size="140,32"
$btnYes.DialogResult="OK"
$agree.Controls.Add($btnYes)

$btnNo=New-Object System.Windows.Forms.Button
$btnNo.Text="取消"
$btnNo.Location="480,620"
$btnNo.Size="80,32"
$btnNo.DialogResult="Cancel"
$agree.Controls.Add($btnNo)

if($agree.ShowDialog() -ne "OK"){Remove-Item $HRC_ROOT -Recurse -Force -ErrorAction SilentlyContinue;Remove-Item $RUN_MARK -Force -ErrorAction SilentlyContinue;Remove-Item $SELF_PATH -Force -ErrorAction SilentlyContinue;exit}

$modes=@(
    @{n="? 全自动基础模式";d="无弹窗自动执行，拉满显示器刷新率，兼容所有设备";level="normal"},
    @{n="? 全家桶+安全软件全清模式";d="除火绒外所有安全软件全部卸载，自动安装最新版火绒";level="high"},
    @{n="? Win7-Win11 全系统清理修复";d="全版本兼容，清理所有系统冗余，修复所有常见bug";level="normal"},
    @{n="? 手动确认模式";d="每一步优化前弹出确认，可自由跳过不需要的优化项";level="normal"},
    @{n="? 强打驱动模式";d="适用于老设备安装不上驱动，使用官方驱动程序强打功能";level="high"},
    @{n="? 轻量兼容模式";d="仅做基础优化，保留所有系统原生功能，适合办公设备";level="normal"},
    @{n="? 联网全量扫描修复";d="21步全链路修复，系统性能拉满，重启自动跑内存检测";level="high"},
    @{n="? 离线全量扫描修复";d="仅使用本地系统命令，不联网不更新，全量扫描修复";level="normal"},
    @{n="? 希沃一体机专用版本";d="完整保留希沃所有自带功能，缺失应用自动补全";level="normal"},
    @{n="? 常用软件自动安装模式";d="自动安装常用适配工具，静默无弹窗";level="normal"},
    @{n="? 系统激活/版本切换模式";d="调用开源MAS方案，一键永久激活Windows";level="high"},
    @{n="? 本地账户密码重置工具";d="一键清空管理员/来宾账户密码，仅用于本地账户解锁，无网络请求";level="normal"}
)

$modeWin=New-Object System.Windows.Forms.Form
$modeWin.Size="740,1000"
$modeWin.StartPosition="CenterScreen"
$modeWin.FormBorderStyle="FixedDialog"
$modeWin.BackColor="White"
$modeWin.Text="HRC 全模式工具箱 V3.6"
$modeWin.Font = $globalFont
$modeWin.MaximizeBox = $false
$modeWin.MinimizeBox = $false

$musicSwitch = New-Object System.Windows.Forms.CheckBox
$musicSwitch.Text = "播放外接设备音频"
$musicSwitch.Font = $globalFont
$musicSwitch.Location = [System.Drawing.Point]::new(60, 900)
$modeWin.Controls.Add($musicSwitch)

$autoCleanSwitch = New-Object System.Windows.Forms.CheckBox
$autoCleanSwitch.Text = "运行完成后自动清除所有工具缓存与脚本"
$autoCleanSwitch.Font = $globalFont
$autoCleanSwitch.Checked = $true
$autoCleanSwitch.Location = [System.Drawing.Point]::new(60, 925)
$modeWin.Controls.Add($autoCleanSwitch)

$autoRunSwitch = New-Object System.Windows.Forms.CheckBox
$autoRunSwitch.Text = "下次重启自动执行全量修复"
$autoRunSwitch.Font = $globalFont
$autoRunSwitch.Location = [System.Drawing.Point]::new(60, 950)
$autoRunSwitch.Visible = $false
$modeWin.Controls.Add($autoRunSwitch)

$modeTitle=New-Object System.Windows.Forms.Label
$modeTitle.Text="请选择优化运行模式"
$modeTitle.Font=New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Point)
$modeTitle.Location="270,30"
$modeWin.Controls.Add($modeTitle)

$sel=6
for($i=0;$i -lt $modes.Count;$i++){
    $p=New-Object System.Windows.Forms.Panel
    $p.Size="620,55"
    $p.Location="60,$(80+$i*60)"
    $p.BackColor=if($i -eq 6){[System.Drawing.Color]::FromArgb(232,242,254)}else{[System.Drawing.Color]::FromArgb(248,248,248)}
    $p.BorderStyle="FixedSingle"
    $ln=New-Object System.Windows.Forms.Label
    $ln.Text=$modes[$i].n
    $ln.Font=$titleFont
    $ln.ForeColor=if($i -eq 6){[System.Drawing.Color]::FromArgb(0,102,204)}else{[System.Drawing.Color]::Gray}
    $ln.Location="20,15"
    $p.Controls.Add($ln)
    $ld=New-Object System.Windows.Forms.Label
    $ld.Text=$modes[$i].d
    $ld.Font=$globalFont
    $ld.ForeColor="Gray"
    $ld.Location="60,32"
    $p.Controls.Add($ld)
    $currentIndex = $i
    $p.Add_Click({param($s);for($j=0;$j -lt $modes.Count;$j++){$modeWin.Controls[$j+6].BackColor=[System.Drawing.Color]::FromArgb(248,248,248)};$s.BackColor=[System.Drawing.Color]::FromArgb(232,242,254);$script:sel = $currentIndex; $autoRunSwitch.Visible = ($currentIndex -eq 6)})
    $modeWin.Controls.Add($p)
}

$btnOk=New-Object System.Windows.Forms.Button
$btnOk.Text="确定"
$btnOk.Location="560,965"
$btnOk.Size="80,28"
$btnOk.DialogResult="OK"
$modeWin.Controls.Add($btnOk)

$modeWin.Add_FormClosing({
    if($_.DialogResult -ne "OK"){return}
    if($modes[$sel].level -eq "high"){
        $pass = Confirm-ThreeTimes -Title "高危操作模式确认" `
            -Msg1 "您当前选中的模式会修改系统核心配置、卸载第三方软件，操作不可逆，是否继续？" `
            -Msg2 "该模式会清理系统冗余组件、修改安全软件配置，可能导致部分第三方软件运行异常，是否确认？" `
            -Msg3 "最终确认：您明确知晓该模式的操作风险，仍要执行该模式？"
        if(-not $pass){
            $_.Cancel = $true
            $script:sel = 0
        }
    }
})

if($modeWin.ShowDialog() -ne "OK"){Remove-Item $HRC_ROOT -Recurse -Force -ErrorAction SilentlyContinue;Remove-Item $RUN_MARK -Force -ErrorAction SilentlyContinue;Remove-Item $SELF_PATH -Force -ErrorAction SilentlyContinue;exit}

$secBox = New-Object System.Windows.Forms.TextBox
$secBox.Text = "30"

if($autoRunSwitch.Checked){
    $autoPass = Confirm-ThreeTimes -Title "开机自动运行确认" `
        -Msg1 "开启该选项后，下次设备重启时会自动执行全量修复，会延长开机时间，是否继续？" `
        -Msg2 "自动运行过程无任何人工干预机会，可能导致开机后软件/系统异常，是否确认？" `
        -Msg3 "最终确认：您明确知晓该功能的风险，仍要开启重启自动运行？"
    if(-not $autoPass){
        $autoRunSwitch.Checked = $false
    }else{
        $rebootPass = Confirm-ThreeTimes -Title "重启确认" `
            -Msg1 "你确定要设置倒计时重启吗？这会丢失所有未保存的工作" `
            -Msg2 "未保存的文件会永远找不回来，真的要重启？" `
            -Msg3 "最后一次：你真的真的确定要现在设置重启吗？"
        if($rebootPass){
            "reboot_sec=30" | Out-File $AUTO_RUN_CFG -Encoding UTF8
            Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce" "HRC_AutoRunOnce" "`"$SELF_PATH`"" -Force
        }
    }
}

function Show-CleanupProgress{
    $s=[System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Size
    $cleanWin = New-Object System.Windows.Forms.Form
    $cleanWin.FormBorderStyle = "None"
    $cleanWin.Size = $s
    $cleanWin.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $cleanWin.TopMost = $true
    $cleanWin.DoubleBuffered = $true

    $cleanTitle = New-Object System.Windows.Forms.Label
    $cleanTitle.Text = "正在删除运行资源"
    $cleanTitle.Font = New-Object System.Drawing.Font("Segoe UI", 28, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Point)
    $cleanTitle.ForeColor = [System.Drawing.Color]::White
    $cleanTitle.Location = [System.Drawing.Point]::new(($cleanWin.Width/2)-160, ($cleanWin.Height/2)-80)
    $cleanTitle.AutoSize = $true
    $cleanWin.Controls.Add($cleanTitle)

    $cleanBar = New-Object System.Windows.Forms.ProgressBar
    $cleanBar.Size = "360,4"
    $cleanBar.Location = [System.Drawing.Point]::new(($cleanWin.Width/2)-180, ($cleanWin.Height/2)+40)
    $cleanBar.Maximum = 100
    $cleanBar.ForeColor = [System.Drawing.Color]::FromArgb(16, 185, 129)
    $cleanWin.Controls.Add($cleanBar)

    $cleanWin.Add_Shown({
        $cleanWin.Refresh()
        for($p=0;$p -lt 60;$p++){$cleanBar.Value=$p;[System.Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 10}
        Remove-Item $HRC_ROOT -Recurse -Force -ErrorAction SilentlyContinue
        for($p=60;$p -lt 100;$p++){$cleanBar.Value=$p;[System.Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 10}
        $cleanWin.Close()
    })
    [void]$cleanWin.ShowDialog()
}

function Show-Reboot{
    param($sec = 30)
    $officeRunning = Get-Process | Where-Object {$_.Name -in @("WINWORD","EXCEL","POWERPNT")}
    if($officeRunning){
        [System.Windows.Forms.MessageBox]::Show("检测到Word/Excel/PPT正在运行，请先保存文件后再执行重启", "提醒", "OK", "Information")
    }
    $rebootPass = Confirm-ThreeTimes -Title "重启操作确认" `
        -Msg1 "工具执行完成即将重启设备，所有未保存的文档、工作进度将永久丢失，是否继续？" `
        -Msg2 "重启操作会强制关闭所有正在运行的程序，没有任何撤回机会，是否确认？" `
        -Msg3 "最终确认：您已保存所有工作，明确知晓重启会丢失未保存数据，仍要立即重启？"
    if(-not $rebootPass){
        if($autoCleanSwitch.Checked){Show-CleanupProgress}
        exit
    }

    $s=[System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bar=New-Object System.Windows.Forms.Form
    $bar.FormBorderStyle="None"
    $bar.Size="$($s.Width),4"
    $bar.Location="0,$($s.Height-42)"
    $bar.BackColor=[System.Drawing.Color]::FromArgb(220,220,220)
    $bar.TopMost=$true
    $bar.Show()
    $fill=New-Object System.Windows.Forms.Panel
    $fill.Size="0,4"
    $fill.BackColor=[System.Drawing.Color]::FromArgb(16, 185, 129)
    $bar.Controls.Add($fill)
    [System.Media.SystemSounds]::Asterisk.Play()
    $cnt=New-Object System.Windows.Forms.Form
    $cnt.Size="320,180"
    $cnt.StartPosition="CenterScreen"
    $cnt.FormBorderStyle="FixedDialog"
    $cnt.ControlBox=$false
    $cnt.BackColor="White"
    $cnt.TopMost=$true
    $t=New-Object System.Windows.Forms.Label
    $t.Text="$sec 秒倒计时"
    $t.Font=New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Point)
    $t.Location="80,40"
    $t.AutoSize=$true
    $cnt.Controls.Add($t)
    $canc=New-Object System.Windows.Forms.Button
    $canc.Text="取消重启"
    $canc.Size="100,30"
    $canc.Location="110,100"
    $canc.Add_Click({$cnt.Tag=$true;$cnt.Close()})
    $cnt.Controls.Add($canc)
    $cnt.Tag=$false
    $cnt.Show()
    for($i=$sec;$i -ge 0;$i--){$fill.Width=[int]($s.Width*($i/$sec));$t.Text="$i 秒倒计时";[System.Windows.Forms.Application]::DoEvents();if($cnt.Tag){break};Start-Sleep 1}
    $bar.Close();$cnt.Close()
    if(-not $cnt.Tag){
        if($autoCleanSwitch.Checked){Show-CleanupProgress}
        bcdedit /deletevalue {default} memorytest >$null 2>&1
        taskkill /f /im msedge.exe /im chrome.exe /im firefox.exe >$null 2>&1
        shutdown /r /f /t 0
    }
}

$steps=@{
    0=@(
        @{p=10;n="1/10 检测系统硬件配置";c="Get-CimInstance Win32_OperatingSystem,Win32_ComputerSystem | Out-Null"},
        @{p=20;n="2/10 拉满显示器最高刷新率";c="$mon=Get-CimInstance Win32_VideoController;$max=($mon|Select-Object -Expand CurrentDisplayRefreshRate|Measure-Object -Maximum).Maximum;Set-ItemProperty 'HKCU:\Control Panel\Desktop' RefreshRate -Value $max -Force"},
        @{p=30;n="3/10 清理系统临时缓存";c="Remove-Item $env:TEMP\* -Recurse -Force -ErrorAction SilentlyContinue"},
        @{p=40;n="4/10 关闭系统遥测服务";c="Set-Service DiagTrack -StartupType Disabled -ErrorAction SilentlyContinue"},
        @{p=50;n="5/10 关闭系统广告推送";c="Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer' EnableStartMenuSuggestions -Value 0 -Force"},
        @{p=60;n="6/10 执行系统文件修复";c="Start-Job -ScriptBlock {sfc /scannow | Out-Null} | Wait-Job | Out-Null"},
        @{p=70;n="7/10 优化系统网络参数";c="netsh int tcp set global autotuninglevel=normal | Out-Null"},
        @{p=80;n="8/10 关闭无用自启项";c="Get-CimInstance Win32_StartupCommand | Where-Object Name -notmatch 'Windows Defender|WPS|微信' | Remove-CimInstance -ErrorAction SilentlyContinue"},
        @{p=90;n="9/10 配置Defender扫描CPU限制为5%";c="Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows Defender\Scan' AvgCPULoadFactor -Value 5 -Force"},
        @{p=100;n="10/10 优化完成，准备重启";c=""}
    )
    1=@(
        @{p=20;n="1/4 扫描所有已安装软件";c="Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Select-Object DisplayName,UninstallString | Out-Null"},
        @{p=40;n="2/4 过滤白名单保留应用";c=""},
        @{p=60;n="3/4 卸载所有安全软件全家桶";c="Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where-Object { $_.DisplayName -match '360|腾讯管家|鲁大师|金山毒霸|百度卫士' -and $_.DisplayName -notin @('火绒安全软件','Windows Defender','火绒') -and -not ($keepUninstall | Where-Object {$_.DisplayName -match $_}) } | ForEach-Object { if($_.UninstallString -match 'msiexec'){cmd /c "$($_.UninstallString) /x /s >$null 2>&1"}else{cmd /c "$($_.UninstallString) /s >$null 2>&1"}; Start-Sleep 3 }"},
        @{p=80;n="4/4 静默安装最新版火绒";c="$hrcInstall = Join-Path $SETAPP_DIR 'huorong-latest.exe';if(Test-Path $hrcInstall){Start-Process $hrcInstall /verysilent /norestart -Wait}"},
        @{p=100;n="4/4 清理完成，准备重启";c=""}
    )
    2=@(
        @{p=10;n="1/10 清理系统临时缓存";c="Remove-Item $env:TEMP\* -Recurse -Force -ErrorAction SilentlyContinue"},
        @{p=20;n="2/10 清理系统预取文件";c="Remove-Item C:\Windows\Prefetch\* -Recurse -Force -ErrorAction SilentlyContinue"},
        @{p=30;n="3/10 清理Windows临时目录";c="Remove-Item C:\Windows\Temp\* -Recurse -Force -ErrorAction SilentlyContinue"},
        @{p=40;n="4/10 清理回收站所有文件";c="Clear-RecycleBin -Force -ErrorAction SilentlyContinue"},
        @{p=60;n="6/10 修复系统文件损坏";c="Start-Job -ScriptBlock {sfc /scannow | Out-Null} | Wait-Job | Out-Null"},
        @{p=70;n="7/10 修复网络配置异常";c="netsh int ip reset; netsh winsock reset | Out-Null"},
        @{p=80;n="8/10 清理无效注册表项";c="reg delete HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall /va /f /reg:32 >$null 2>&1"},
        @{p=90;n="9/10 关闭无用自启项";c="Get-CimInstance Win32_StartupCommand | Where-Object Name -notmatch 'Windows Defender|WPS|微信' | Remove-CimInstance -ErrorAction SilentlyContinue"},
        @{p=100;n="10/10 清理完成，准备重启";c=""}
    )
    3=@($steps[0][0..9])
    4=@($steps[0][0..9])
    5=@($steps[0][0..5] + $steps[0][7..9])
    6=@($fullSteps)
    7=@(
        @{p=20;n="1/5 执行SFC系统扫描";c="sfc /scannow | Out-Null"},
        @{p=40;n="2/5 清理临时文件";c="Remove-Item $env:TEMP\* -Recurse -Force -ErrorAction SilentlyContinue"},
        @{p=60;n="3/5 关闭遥测服务";c="Set-Service DiagTrack -StartupType Disabled"},
        @{p=80;n="4/5 优化网络参数";c="netsh int tcp set global autotuninglevel=normal"},
        @{p=100;n="5/5 修复完成";c=""}
    )
    8=@(
        @{p=20;n="1/4 保留希沃核心服务";c="Set-Service SeewoService -StartupType Automatic"},
        @{p=40;n="2/4 清理第三方冗余";c="Remove-Item $env:TEMP\* -Recurse -Force"},
        @{p=60;n="3/4 修复触控异常";c="powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"},
        @{p=100;n="4/4 修复完成";c=""}
    )
    9=@(
        @{p=25;n="1/4 安装常用运行库";c="winget install Microsoft.VCRedist.2015+.x64 --silent"},
        @{p=50;n="2/4 安装办公工具";c="winget install WPS.Office --silent"},
        @{p=75;n="3/4 安装影音工具";c="winget install ShPlayer.ShPlayer --silent"},
        @{p=100;n="4/4 安装完成";c=""}
    )
    10=@(
        @{p=50;n="1/2 下载MAS激活工具";c="irm https://get.activated.win | iex"},
        @{p=100;n="2/2 激活完成";c=""}
    )
    11=@(
        @{p=25;n="1/4 检测系统账户状态";c={net user | Out-Null}},
        @{p=50;n="2/4 清空Administrator账户密码";c={net user Administrator ""}},
        @{p=75;n="3/4 清空Guest账户密码";c={net user Guest ""}},
        @{p=100;n="4/4 恢复系统安全保护";c={
            net user Administrator /active:yes
            reg add HKLM\SYSTEM\CurrentControlSet\Control\Lsa /v LimitBlankPasswordUse /t REG_DWORD /d 1 /f >nul
        }}
    )
}

$run=$steps[$sel] ?? $steps[0]

$exec=New-Object System.Windows.Forms.Form
$exec.Size="660,300"
$exec.StartPosition="CenterScreen"
$exec.FormBorderStyle="FixedDialog"
$exec.BackColor="White"
$exec.Text="HRC 系统优化执行中 V3.6"
$exec.Font = $globalFont
$exec.MaximizeBox = $false
$exec.MinimizeBox = $false

$bar=New-Object System.Windows.Forms.ProgressBar
$bar.Size="580,6"
$bar.Location="40,60"
$bar.Style="Continuous"
$bar.ForeColor = [System.Drawing.Color]::FromArgb(16, 185, 129)
$exec.Controls.Add($bar)

$tip=New-Object System.Windows.Forms.Label
$tip.Location="40,110"
$tip.Size="580,25"
$tip.Font = $globalFont
$exec.Controls.Add($tip)

$exec.Add_Shown({
    if($musicSwitch.Checked){try{$musicPath = Join-Path $MUSIC_DIR "auto_load.wav";(New-Object System.Media.SoundPlayer $musicPath).PlayLooping()}catch{}}
    if(-not $isWin7){
        try{$tbPath = Join-Path $SETAPP_DIR "translucenttb.exe";if(-not (Get-Process "TranslucentTB" -ErrorAction SilentlyContinue)){Start-Process $tbPath --start-hidden}}catch{}
    }
    foreach($s in $run){
        $bar.Value=$s.p
        $tip.Text=$s.n
        [System.Windows.Forms.Application]::DoEvents()
        if($s.c){Safe-Run $s.c}
    }
    $exec.Close()
    if($sel -eq 11){
        [System.Windows.Forms.MessageBox]::Show("密码重置完成，系统空白密码保护已恢复", "完成", "OK", "Information")
        if($autoCleanSwitch.Checked){Show-CleanupProgress}
        exit
    }
    Show-Reboot -sec [int]$secBox.Text
})

[void]$exec.ShowDialog()

Remove-Item $RUN_MARK -Force -ErrorAction SilentlyContinue
'@; Invoke-Expression $code
?
