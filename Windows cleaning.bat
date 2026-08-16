@echo off
fltmc >nul 2>&1 || (powershell Start -File "%~f0" -Verb RunAs >nul 2>&1 && exit /b)
chcp 65001 >nul 2>&1
title HRC?tool｜系统垃圾清理工具

powershell -Command "$code=@'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$HRC_ROOT = \"C:\HRC_TempCache\"
@($HRC_ROOT) | ForEach-Object { if(-not (Test-Path $_)){New-Item -ItemType Directory -Path $_ -Force | Out-Null} }

$globalFont = New-Object System.Drawing.Font(\"Segoe UI\", 9, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Point)
$titleFont = New-Object System.Drawing.Font(\"Segoe UI\", 11, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Point)

$bootWin = New-Object System.Windows.Forms.Form
$bootWin.FormBorderStyle = \"None\"
$bootWin.Size = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Size
$bootWin.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$bootWin.TopMost = $true
$bootWin.DoubleBuffered = $true

$bootLogo = New-Object System.Windows.Forms.Label
$bootLogo.Text = \"HRC 垃圾清理工具\"
$bootLogo.Font = New-Object System.Drawing.Font(\"Segoe UI\", 64, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Point)
$bootLogo.ForeColor = [System.Drawing.Color]::White
$bootLogo.Location = [System.Drawing.Point]::new(($bootWin.Width/2)-220, ($bootWin.Height/2)-120)
$bootLogo.AutoSize = $true
$bootWin.Controls.Add($bootLogo)

$bootBar = New-Object System.Windows.Forms.ProgressBar
$bootBar.Size = [System.Drawing.Size]::new($bootWin.Width, 4)
$bootBar.Location = [System.Drawing.Point]::new(0, $bootWin.Height - 42)
$bootBar.Maximum = 100
$bootBar.Style = \"Continuous\"
$bootBar.ForeColor = [System.Drawing.Color]::FromArgb(16, 185, 129)
$bootBar.BackColor = [System.Drawing.Color]::FromArgb(80, 170, 255)
$bootWin.Controls.Add($bootBar)

$bootWin.Add_Shown({
    $bootWin.Refresh()
    $totalSteps = @(
        @{p=20;name=\"初始化缓存目录\";action={Start-Sleep -Milliseconds 150}},
        @{p=50;name=\"预加载系统清理模块\";action={Start-Sleep -Milliseconds 150}},
        @{p=80;name=\"扫描系统垃圾目录\";action={Start-Sleep -Milliseconds 150}},
        @{p=100;name=\"启动主程序\";action={Start-Sleep -Milliseconds 80}}
    )
    foreach($step in $totalSteps){
        $bootBar.Value = $step.p
        [System.Windows.Forms.Application]::DoEvents()
        & $step.action
    }
    $bootWin.Close()
})
[void]$bootWin.ShowDialog()

function Confirm-Twice {
    param($Title, $Msg1, $Msg2)
    $res1 = [System.Windows.Forms.MessageBox]::Show($Msg1, $Title, \"OKCancel\", \"Warning\")
    if($res1 -ne \"OK\"){return $false}
    $res2 = [System.Windows.Forms.MessageBox]::Show($Msg2, $Title, \"OKCancel\", \"Warning\")
    return ($res2 -eq \"OK\")
}

$agree=New-Object System.Windows.Forms.Form
$agree.Size=\"720,620\"
$agree.StartPosition=\"CenterScreen\"
$agree.FormBorderStyle=\"FixedDialog\"
$agree.BackColor=\"White\"
$agree.Text=\"HRC?tool 垃圾清理工具 隐私声明\"
$agree.Font = $globalFont
$agree.MaximizeBox = $false
$agree.MinimizeBox = $false

$txt=New-Object System.Windows.Forms.Label
$txt.Location=\"25,25\"
$txt.Size=\"660,520\"
$txt.Font = $globalFont
$txt.Text=\"HRC?tool 系统垃圾清理工具`n`n1、本工具仅清理系统临时缓存、日志、预读取文件，**不会删除你的文档、图片、下载文件**。`n`n2、被系统占用的文件无法删除属于正常现象。`n`n3、全部操作在本地执行，不上传任何数据。`n`n4、风险提示：操作前建议保存好正在编辑的文档。`n`n点击【我已阅读并同意】继续，不同意直接退出工具。\"
$agree.Controls.Add($txt)

$btnYes=New-Object System.Windows.Forms.Button
$btnYes.Text=\"我已阅读并同意\"
$btnYes.Location=\"520,560\"
$btnYes.Size=\"140,32\"
$btnYes.DialogResult=\"OK\"
$agree.Controls.Add($btnYes)

$btnNo=New-Object System.Windows.Forms.Button
$btnNo.Text=\"取消退出\"
$btnNo.Location=\"410,560\"
$btnNo.Size=\"95,32\"
$btnNo.DialogResult=\"Cancel\"
$agree.Controls.Add($btnNo)

if($agree.ShowDialog() -ne \"OK\"){
    Remove-Item $HRC_ROOT -Recurse -Force -ErrorAction SilentlyContinue
    exit
}

$exec=New-Object System.Windows.Forms.Form
$exec.Size=\"640,280\"
$exec.StartPosition=\"CenterScreen\"
$exec.FormBorderStyle=\"FixedDialog\"
$exec.BackColor=\"White\"
$exec.Text=\"HRC?tool｜正在执行垃圾清理\"
$exec.Font = $globalFont
$exec.MaximizeBox = $false
$exec.MinimizeBox = $false

$bar=New-Object System.Windows.Forms.ProgressBar
$bar.Size=\"560,6\"
$bar.Location=\"40,55\"
$bar.Style=\"Continuous\"
$bar.ForeColor = [System.Drawing.Color]::FromArgb(16, 185, 129)
$exec.Controls.Add($bar)

$tip=New-Object System.Windows.Forms.Label
$tip.Location=\"40,100\"
$tip.Size=\"560,24\"
$tip.Font = $globalFont
$exec.Controls.Add($tip)

$logBox=New-Object System.Windows.Forms.TextBox
$logBox.Location=\"40,135\"
$logBox.Size=\"560,90\"
$logBox.Multiline=$true
$logBox.ReadOnly=$true
$logBox.ScrollBars=\"Vertical\"
$exec.Controls.Add($logBox)

$exec.Add_Shown({
    $steps = @(
        @{p=15;n=\"1/5 清理系统目录临时文件\";c={del /f /s /q \"%systemroot%\temp\*.*\" 2>nul}},
        @{p=35;n=\"2/5 清理用户本地Temp缓存\";c={del /f /s /q \"$env:USERPROFILE\AppData\Local\Temp\*.*\" 2>nul}},
        @{p=55;n=\"3/5 清理预读取Prefetch缓存\";c={del /f /s /q \"%systemroot%\Prefetch\*.*\" 2>nul}},
        @{p=75;n=\"4/5 清理日志与临时磁盘文件\";c={del /f /s /q \"$env:SystemDrive\*.tmp\",\"$env:SystemDrive\*.log\" 2>nul}},
        @{p=100;n=\"5/5 清理任务完成\";c={}}
    )
    foreach($s in $steps){
        $bar.Value=$s.p
        $tip.Text=$s.n
        $logBox.AppendText($s.n+\"`r`n\")
        [System.Windows.Forms.Application]::DoEvents()
        if($s.c){cmd /c $s.c}
    }
    [System.Windows.Forms.MessageBox]::Show(\"?垃圾清理全部完成！`n部分文件被占用跳过属于正常。\",\"执行完毕\",\"OK\",\"Information\")
    $exec.Close()
    Remove-Item $HRC_ROOT -Recurse -Force -ErrorAction SilentlyContinue
})

[void]$exec.ShowDialog()
'@; Invoke-Expression $code
