# ========================================================================
# โปรแกรมย่อย: send.ps1 (เวอร์ชันปฏิวัติระบบ: ดึงตรงด้วย Google CSV API + ผ่อนผัน 5 นาที)
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

# 2. ดึงข้อมูลสดๆ จาก Google Sheets รูปแบบ CSV
Write-Host "กำลังดึงข้อมูลตารางงานสดจาก Google Sheets API..."
try {
    # ดาวน์โหลดข้อมูล CSV แบบเปิดใจกว้าง บังคับใช้ Encoding เป็น UTF-8 สำหรับภาษาไทย
    $csvRaw = Invoke-RestMethod -Uri $sheetUrl -Method Get -TimeoutSec 15
    if ([string]::IsNullOrWhiteSpace($csvRaw)) {
        Write-Warning "⚠️ ข้อมูลที่ดึงมาจาก Google Sheets ว่างเปล่า"
        exit 0
    }
    
    # แปลงข้อมูลจาก CSV ให้กลายเป็นวัตถุในระบบอัตโนมัติ
    $tasks = ConvertFrom-Csv -InputObject $csvRaw
} 
catch {
    Write-Warning "❌ ไม่สามารถดึงข้อมูลตรงจาก Google Sheets ได้: $_"
    exit 0
}

$matchedMessages = @()

# วนลูปตรวจเช็คตารางงาน
foreach ($task in $tasks) {
    
    # ค้นหาค่าเวลา รองรับหัวตารางภาษาอังกฤษ (sendAt) หรือภาษาไทย (วันที่และเวลา)
    $rawSendAt = $null
    if ($task.sendAt) { $rawSendAt = $task.sendAt }
    elseif ($task.'วันที่และเวลา') { $rawSendAt = $task.'วันที่และเวลา' }
    
    if ([string]::IsNullOrEmpty($rawSendAt)) { continue }
    
    $timeParts = $rawSendAt -split "@"
    if ($timeParts.Length -lt 2) { continue }
    
    $taskDate = $timeParts[0].Trim()
    $taskTimeStr = $timeParts[1].Trim().Replace(".", ":")

    # ตรวจสอบเงื่อนไขวันที่ปัจจุบัน
    if ($taskDate -eq $currentDateStr) {
        
        if ([DateTime]::TryParseExact($taskTimeStr, "HH:mm", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$taskTime)) {
            
            $currentHourMin = [DateTime]::ParseExact($taiTime.ToString("HH:mm"), "HH:mm", [System.Globalization.CultureInfo]::InvariantCulture)
            $timeDiff = $currentHourMin - $taskTime
            $minutesDiff = $timeDiff.TotalMinutes

            # กฎผ่อนผันเวลาเลทได้ไม่เกิน 5 นาที
            if ($minutesDiff -ge 0 -and $minutesDiff -le 5) {
                Write-Host "🎯 เจอคิวงานในตารางเวลา: $taskTimeStr (เลทไป $minutesDiff นาที) -> ผ่านเงื่อนไข"
                
                # รองรับหัวคอลัมน์ทั้ง 2 ภาษา
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

# 3. ส่งข้อมูลเข้ากลุ่ม LINE
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
