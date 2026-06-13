# ========================================================================
# โปรแกรมย่อย: send.ps1 (เวอร์ชันมาตรฐานสากล: หัวตารางอังกฤษ + ผ่อนผันเวลา 5 นาที)
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
    
    # [จุดแก้ไขสำคัญ] สั่งให้อ่านหัวตารางจากคีย์ภาษาอังกฤษ (sendAt) ตามหน้าตาราง Sheets ปัจจุบัน
    if (-not $task.sendAt) { continue }
    
    # แยกส่วน วันที่@เวลา ออกจากกัน
    $timeParts = $task.sendAt -split "@"
    if ($timeParts.Length -lt 2) { continue }
    
    $taskDate = $timeParts[0].Trim()
    # รองรับทั้งคนที่พิมพ์เครื่องหมายจุด (.) หรือ ทวิภาค (:) โดยแปลงให้เป็นเครื่องหมาย : เสมอ
    $taskTimeStr = $timeParts[1].Trim().Replace(".", ":")

    # ตรวจสอบว่าต้องเป็นวันที่ปัจจุบันก่อน
    if ($taskDate -eq $currentDateStr) {
        
        # แปลงข้อความเวลาใน Sheet ให้กลายเป็นวัตถุเวลา DateTime เพื่อใช้วัดระยะห่าง
        if ([DateTime]::TryParseExact($taskTimeStr, "HH:mm", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$taskTime)) {
            
            # สร้างวัตถุเวลาปัจจุบันที่มีเฉพาะ ชั่วโมงและนาที เอาไว้เทียบกัน
            $currentHourMin = [DateTime]::ParseExact($taiTime.ToString("HH:mm"), "HH:mm", [System.Globalization.CultureInfo]::InvariantCulture)

            # คำนวณความต่างของเวลา (เวลาปัจจุบัน ลบด้วย เวลาในตาราง)
            $timeDiff = $currentHourMin - $taskTime
            $minutesDiff = $timeDiff.TotalMinutes

            # ถ้ารันตรงเวลาเป๊ะ (0) หรือรันเลทไปไม่เกิน 5 นาที (1, 2, 3, 4, 5)
            if ($minutesDiff -ge 0 -and $minutesDiff -le 5) {
                Write-Host "🎯 เจอคิวงานใกล้เคียง! เวลาในตาราง: $taskTimeStr (เลทไป $minutesDiff นาที) -> อนุญาตให้ส่งได้"
                
                # [จุดแก้ไขสำคัญ] ดึงค่าจากหัวตารางภาษาอังกฤษ (type, param1, param2)
                $msgObject = @{}
                if ($task.type -eq "text") {
                    $msgObject = @{ type = "text"; text = $task.param1 }
                }
                elif ($task.type -eq "sticker") {
                    $msgObject = @{ type = "sticker"; packageId = $task.param1; stickerId = $task.param2 }
                }
                elif ($task.type -eq "image") {
                    $msgObject = @{ type = "image"; originalContentUrl = $task.param1; previewImageUrl = $task.param1 }
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
