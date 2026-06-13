# ========================================================================
# โปรแกรมย่อย: send.ps1 (เวอร์ชันปรับปรุงระบบดักจับ Error กรณีลิงก์ Google Sheets ว่าง)
# ========================================================================

$token = $env:LINE_TOKEN
$groupIds = $env:LINE_GROUP_ID -split ","
$sheetUrl = $env:GOOGLE_SHEET_API_URL 

# 1. จัดการเรื่องเวลาไทย
$taiTime = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([System.DateTime]::Now, "SE Asia Standard Time")
$currentDateStr = $taiTime.ToString("dd/MM/yyyy", [System.Globalization.CultureInfo]::InvariantCulture)
$currentTimeStr = $taiTime.ToString("HH:mm") 
$currentCheckStr = "${currentDateStr}@${currentTimeStr}"
Write-Host "เวลาปัจจุบันของไทย: $currentCheckStr"

# ตรวจสอบเบื้องต้น: ถ้ายังไม่ได้กรอกลิงก์ Google Sheets ใน Secrets ให้หยุดทำงานทันที
if ([string]::IsNullOrEmpty($sheetUrl)) {
    Write-Warning "❌ ไม่พบลิงก์ GOOGLE_SHEET_API_URL ใน GitHub Secrets กรุณาตรวจสอบ!"
    exit 0
}

# 2. ไปดึงข้อมูลตารางงานสดๆ จาก Google Sheets
Write-Host "กำลังเชื่อมต่อเพื่อดึงตารางงานจาก Google Sheets..."

# ใช้คำสั่ง Try-Catch เพื่อดักจับ Error ป้องกันบอทตายกลางคัน
try {
    # สั่งดึงข้อมูลจากลิงก์
    $jsonContent = Invoke-RestMethod -Uri $sheetUrl -Method Get -TimeoutSec 15
    
    # [จุดที่เคยพัง] ตรวจสอบว่าถ้าดึงค่ามาแล้วดันได้เป็นค่าว่าง หรือช่องว่างเปล่าๆ ให้หยุดทำงานทันที
    if ([string]::IsNullOrWhiteSpace($jsonContent)) {
        Write-Warning "⚠️ ข้อมูลที่ดึงมาจาก Google Sheets เป็นค่าว่างเปล่า (ไม่มีแถวข้อมูลงาน) สคริปต์จะหยุดทำงานชั่วคราว"
        exit 0
    }

    # แปลงโครงสร้างข้อความ JSON
    $tasks = ConvertFrom-Json $jsonContent
} 
catch {
    Write-Warning "❌ ไม่สามารถดึงข้อมูลหรือแปลง JSON จาก Google Sheets ได้: $_"
    exit 0 # สั่งจบการทำงานแบบปลอดภัย ไม่ปล่อยให้ขึ้น Error แดง
}

$matchedMessages = @()

# วนลูปตรวจเช็คตารางงานจาก Google Sheets
foreach ($task in $tasks) {
    if ($task.sendAt -eq $currentCheckStr) {
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

# 3. ถ้าเจอคิวงานที่ตรงเป๊ะ ให้ส่งข้อมูลเข้ากลุ่ม LINE ทุกกลุ่ม
if ($matchedMessages.Count -gt 0) {
    Write-Host "เจอคิวงานบน Sheet ตรงกันจำนวน $($matchedMessages.Count) ชิ้น! กำลังจัดส่ง..."

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
                              
            Write-Host "ส่งข้อความจาก Sheet ไปยังกลุ่ม $id สำเร็จแล้ว"
        }
    }
} else {
    Write-Host "รอบนี้ไม่มีคิวงานบน Sheet ที่ตรงกับเวลานี้"
}
