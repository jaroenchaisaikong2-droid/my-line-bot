# ========================================================================
# โปรแกรมย่อย: send.ps1 (เวอร์ชันร่างสุดยอด: รองรับระบบหัวตาราง 2 ภาษา + ผ่อนผันเวลา 5 นาที)
# ========================================================================

$token = $env:LINE_TOKEN
$groupIds = $env:LINE_GROUP_ID -split ","
$sheetUrl = $env:GOOGLE_SHEET_API_URL 

# 1. จัดการเรื่องเวลาปัจจุบันของไทย
$taiTime = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([System.DateTime]::Now, "SE Asia Standard Time")
$currentDateStr = $taiTime.ToString("dd/MM/yyyy", [System.Globalization.CultureInfo]::InvariantCulture)
Write-Host "เวลาปัจจุบันของไทย: $($taiTime.ToString('dd/MM/yyyy@HH:mm'))"

if ([string]::IsNullOrEmpty($sheetUrl)) {
    Write-Warning "❌ ไม่พบลิงก์ GOOGLE_SHEET_API_URL ใน GitHub Secrets"
    exit 0
}

# 2. ดึงข้อมูลจาก Google Sheets
Write-Host "กำลังเชื่อมต่อเพื่อดึงตารางงานจาก Google Sheets..."
try {
    $jsonContent = Invoke-RestMethod -Uri $sheetUrl -Method Get -TimeoutSec 15
    if ([string]::IsNullOrWhiteSpace($jsonContent)) {
        Write-Warning "⚠️ ข้อมูลที่ดึงมาจาก Google Sheets เป็นค่าว่างเปล่า"
        exit 0
    }
    $tasks = ConvertFrom-Json $jsonContent
} 
catch {
    Write-Warning "❌ ไม่สามารถดึงข้อมูลหรือแปลง JSON ได้: $_"
    exit 0
}

$matchedMessages = @()

# วนลูปตรวจเช็คตารางงาน
foreach ($task in $tasks) {
    
    # [ปรับปรุงใหม่] ดึงค่าเวลาโดยรองรับทั้งคีย์ภาษาอังกฤษ และ ภาษาไทย
    $rawSendAt = $null
    if ($task.sendAt) { $rawSendAt = $task.sendAt }
    elif ($task.'วันที่และเวลา') { $rawSendAt = $task.'วันที่และเวลา' }
    
    # ถ้าไม่มีข้อมูลเวลาเลยให้ข้ามแถวนี้ไป
    if ([string]::IsNullOrEmpty($rawSendAt)) { continue }
    
    # แยกส่วน วันที่@เวลา ออกจากกัน
    $timeParts = $rawSendAt -split "@"
    if ($timeParts.Length -lt 2) { continue }
    
    $taskDate = $timeParts[0].Trim()
    $taskTimeStr = $timeParts[1].Trim().Replace(".", ":")

    # ตรวจสอบว่าเป็นวันที่ปัจจุบัน
    if ($taskDate -eq $currentDateStr) {
        
        # แปลงข้อความเวลาในตารางให้กลายเป็นวัตถุเวลา DateTime
        if ([DateTime]::TryParseExact($taskTimeStr, "HH:mm", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$taskTime)) {
            
            # วัตถุเวลาปัจจุบัน (ชั่วโมงและนาที)
            $currentHourMin = [DateTime]::ParseExact($taiTime.ToString("HH:mm"), "HH:mm", [System.Globalization.CultureInfo]::InvariantCulture)

            # คำนวณความต่างของเวลา (นาทีปัจจุบัน - นาทีในตาราง)
            $timeDiff = $currentHourMin - $taskTime
            $minutesDiff = $timeDiff.TotalMinutes

            # กฎผ่อนผันเวลา: ตรงเวลาเป๊ะ (0) หรือเลทไปไม่เกิน 5 นาที (1 ถึง 5)
            if ($minutesDiff -ge 0 -and $minutesDiff -le 5) {
                Write-Host "🎯 เจอคิวงานในตารางเวลา: $taskTimeStr (เลทไป $minutesDiff นาที) -> ผ่านเงื่อนไข"
                
                # ดึงข้อมูลข้อความ/ประเภท โดยรองรับทั้งระบบคีย์อังกฤษและไทย
                $type = if ($task.type) { $task.type } else { $task.'ประเภทข้อความ' }
                $param1 = if ($task.param1) { $task.param1 } else { $task.'ข้อความ / ลิงก์รูปภาพ' }
                $param2 = if ($task.param2) { $task.param2 } else { $task.'รหัสสติกเกอร์ / พิกัด' }

                $msgObject = @{}
                if ($type -eq "text") {
                    $msgObject = @{ type = "text"; text = $param1 }
                }
                elif ($type -eq "sticker") {
                    $msgObject = @{ type = "sticker"; packageId = $param1; stickerId = $param2 }
                }
                elif ($type -eq "image") {
                    $msgObject = @{ type = "image"; originalContentUrl = $param1; previewImageUrl = $param1 }
                }
                
                if ($msgObject.Count -gt 0) {
                    $matchedMessages += $msgObject
                }
            }
        }
    }
}

# 3. ส่งข้อมูลเข้ากลุ่ม LINE ทุกกลุ่ม
if ($matchedMessages.Count -gt 0) {
    Write-Host "กำลังจัดส่งข้อความรวมทั้งหมด $($matchedMessages.Count) ชิ้น..."

    foreach ($id in $groupIds) {
        $id = $id.Trim()
        if (-not [string]::IsNullOrEmpty($id)) {
            $bodyObj = @{ to = $id; messages = $matchedMessages }
            $bodyJson = ConvertTo-Json $bodyObj -Depth 20 -Compress
            $utf8Body = [System.Text.Encoding]::UTF8.GetBytes($bodyJson)

            Invoke-RestMethod -Uri "https://api.line.me/v2/bot/message/push" `
                              -Method Post `
                              -Headers @{ "Authorization" = "Bearer $token"; "Content-Type" = "application/json; charset=utf-8" } `
                              -Body $utf8Body
                              
            Write-Host "ส่งข้อความไปยังกลุ่ม $id สำเร็จแล้ว"
        }
    }
} else {
    Write-Host "รอบนี้ไม่มีคิวงานใน Sheet ที่อยู่ในช่วงเวลาผ่อนผัน (เลทไม่เกิน 5 นาที)"
}
