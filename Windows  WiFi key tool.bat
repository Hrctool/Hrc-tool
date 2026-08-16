@echo off
fltmc >nul 2>&1 || (powershell Start -File "%~f0" -Verb RunAs >nul 2>&1 && exit /b)
chcp 65001 >nul 2>&1
title HRC?tool｜WiFi密码查看工具

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
$bootLogo.Text = \"HRC WiFi密码查看\"
$bootLogo.Font = New-Object System.Drawing.Font(\"Segoe UI\", 64, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Point)
$bootLogo.ForeColor = [System.Drawing.Color]::White
$bootLogo.Location = [System.Drawing.Point]::new(($bootWin.Width/2)-240, ($bootWin.Height/2)-120)
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
        @{p=25;name=\"初始化网络模块\";action={Start-Sleep -Milliseconds 150}},
        @{p=60;name=\"读取本机WiFi配置\";action={Start-Sleep -Milliseconds 150}},
        @{p=100;name=\"启动主窗口\";action={Start-Sleep -Milliseconds 80}}
    )
    foreach($step in $totalSteps){
        $bootBar.Value = $step.p
        [System.Windows.Forms.Application]::DoEvents()
        & $step.action
    }
    $bootWin.Close()
})
[void]$bootWin.ShowDialog()

$agree=New-Object System.Windows.Forms.Form
$agree.Size=\"720,600\"
$agree.StartPosition=\"CenterScreen\"
$agree.FormBorderStyle=\"FixedDialog\"
$agree.BackColor=\"White\"
$agree.Text=\"HRC?tool WiFi密码查看工具 声明\"
$agree.Font = $globalFont
$agree.MaximizeBox = $false
$agree.MinimizeBox = $false

$txt=New-Object System.Windows.Forms.Label
$txt.Location=\"25,25\"
$txt.Size=\"660,500\"
$txt.Font = $globalFont
$txt.Text=\"WiFi密码查看工具`n`n??法律提醒：仅查看**本机已经保存过**的WiFi密码。`n禁止在不属于你的设备上读取WiFi密码，违者自行承担法律责任。`n`n本工具不会破解未知WiFi，只能读取本机曾经连接成功过的网络。`n全部运行在本地，密码不会上传任何服务器。`n`n同意声明后进入工具。\"
$agree.Controls.Add($txt)

$btnYes=New-Object System.Windows.Forms.Button
$btnYes.Text=\"我已阅读并同意\"
$btnYes.Location=\"520,540\"
$btnYes.Size=\"140,32\"
$btnYes.DialogResult=\"OK\"
$agree.Controls.Add($btnYes)

$btnNo=New-Object System.Windows.Forms.Button
$btnNo.Text=\"取消退出\"
$btnNo.Location=\"410,540\"
$btnNo.Size=\"95,32\"
$btnNo.DialogResult=\"Cancel\"
$agree.Controls.Add($btnNo)

if($agree.ShowDialog() -ne \"OK\"){
    Remove-Item $HRC_ROOT -Recurse -Force -ErrorAction SilentlyContinue
    exit
}

$mainWin=New-Object System.Windows.Forms.Form
$mainWin.Size=\"660,420\"
$mainWin.StartPosition=\"CenterScreen\"
$mainWin.FormBorderStyle=\"FixedDialog\"
$mainWin.BackColor=\"White\"
$mainWin.Text=\"HRC?tool｜WiFi密码查看工具\"
$mainWin.Font = $globalFont
$mainWin.MaximizeBox = $false
$mainWin.MinimizeBox = $false

$labList=New-Object System.Windows.Forms.Label
$labList.Text=\"本机已保存WiFi列表：\"
$labList.Location=\"30,20\"
$labList.Font=$titleFont
$mainWin.Controls.Add($labList)

$textWifiList=New-Object System.Windows.Forms.TextBox
$textWifiList.Location=\"30,50\"
$textWifiList.Size=\"590,140\"
$textWifiList.Multiline=$true
$textWifiList.ReadOnly=$true
$textWifiList.ScrollBars=\"Vertical\"
$mainWin.Controls.Add($textWifiList)

$labInput=New-Object System.Windows.Forms.Label
$labInput.Text=\"输入要查询的WiFi名称：\"
$labInput.Location=\"30,205\"
$mainWin.Controls.Add($labInput)

$inputSSID=New-Object System.Windows.Forms.TextBox
$inputSSID.Location=\"210,202\"
$inputSSID.Size=\"280,22\"
$mainWin.Controls.Add($inputSSID)

$btnQuery=New-Object System.Windows.Forms.Button
$btnQuery.Text=\"查询密码\"
$btnQuery.Location=\"510,200\"
$btnQuery.Size=\"100,26\"
$mainWin.Controls.Add($btnQuery)

$labResult=New-Object System.Windows.Forms.Label
$labResult.Text=\"查询结果：\"
$labResult.Location=\"30,245\"
$labResult.Font=$titleFont
$mainWin.Controls.Add($labResult)

$textResult=New-Object System.Windows.Forms.TextBox
$textResult.Location=\"30,275\"
$textResult.Size=\"590,95\"
$textResult.Multiline=$true
$textResult.ReadOnly=$true
$textResult.ScrollBars=\"Vertical\"
$mainWin.Controls.Add($textResult)

$mainWin.Add_Shown({
    $rawList = netsh wlan show profiles
    $textWifiList.AppendText($rawList+\"`r`n\")
})

$btnQuery.Add_Click({
    $ssid = $inputSSID.Text.Trim()
    if([string]::IsNullOrWhiteSpace($ssid)){
        [System.Windows.Forms.MessageBox]::Show(\"请输入WiFi名称\",\"提示\",\"OK\",\"Exclamation\")
        return
    }
    $out = netsh wlan show profile name=\"$ssid\" key=clear
    $textResult.Text = $out
})

[void]$mainWin.ShowDialog()
Remove-Item $HRC_ROOT -Recurse -Force -ErrorAction SilentlyContinue
'@; Invoke-Expression $code
