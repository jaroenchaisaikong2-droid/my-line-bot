# ========================================================================
# โปรแกรมย่อย: send.ps1 (เวอร์ชันรวมร่างข้อความ: ต่อบรรทัดด้วยโค้ดเนทีฟ)
# ========================================================================

$token = $env:LINE_TOKEN
$groupIds = $env:LINE_GROUP_ID -split ","
$sheetUrl = $env:GOOGLE_SHEET_API_URL 

$taiTime = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([System.DateTime]::Now, "SE Asia Standard Time")
$currentDateStr = $taiTime.ToString("dd/MM/yyyy", [System.Globalization.CultureInfo]::InvariantCulture)

$csvRaw = Invoke-RestMethod -Uri $sheetUrl -Method Get -TimeoutSec 15
$tasks = ConvertFrom-Csv -InputObject $csvRaw

# สร้างตัวแปรเก็บข้อความที่จะ "รวมร่าง" (TextBuilder)
$allTextMessages = @{}

foreach ($task in $tasks) {
    $rawSendAt = if ($task.sendAt) { $task.sendAt } else { $task.'วันที่และเวลา' }
    if ([string]::IsNullOrEmpty($rawSendAt)) { continue }

    $timeParts = $rawSendAt -split "@"
    $taskTime = [DateTime]::ParseExact($timeParts[1].Trim().Replace(".", ":"), "HH:mm", $null)
    $currentHourMin = [DateTime]::ParseExact($taiTime.ToString("HH:mm"), "HH:mm", $null)
    
    # ถ้าเวลาตรงกัน (ผ่อนผัน 5 นาที)
    if ([Math]::Abs(($currentHourMin - $taskTime).TotalMinutes) -le 5) {
        
        $type = if ($task.type) { $task.type } else { $task.'ประเภทข้อความ' }
        $param1 = if ($task.param1) { $task.param1 } else { $task.'ข้อความ / ลิงก์รูปภาพ' }

        if ($type -eq "text") {
            # รวมร่างข้อความเข้าด้วยกันโดยใช้ `n (Backtick-n คือการขึ้นบรรทัดใหม่ใน PowerShell)
            if ($allTextMessages.ContainsKey($rawSendAt)) {
                $allTextMessages[$rawSendAt] += "`n" + $param1
            } else {
                $allTextMessages[$rawSendAt] = $param1
            }
        }
    }
}

# ส่งข้อความแบบก้อนเดียว
$finalMessages = @()
foreach ($key in $allTextMessages.Keys) {
    $finalMessages += @{ type = "text"; text = $allTextMessages[$key] }
}

if ($finalMessages.Count -gt 0) {
    foreach ($id in $groupIds) {
        $body = @{ to = $id.Trim(); messages = $finalMessages } | ConvertTo-Json -Depth 10
        Invoke-RestMethod -Uri "https://api.line.me/v2/bot/message/push" -Method Post -Headers @{ "Authorization" = "Bearer $token"; "Content-Type" = "application/json" } -Body $body
    }
}
