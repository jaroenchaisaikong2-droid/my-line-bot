# ========================================================================
# โปรแกรมย่อย: send.ps1 (เวอร์ชันเชื่อมต่อดึงตารางงานสดจาก Google Sheets โดยตรง)
# แพลตฟอร์ม: รองรับ PowerShell Core (pwsh) บนระบบปฏิบัติการ Linux (Ubuntu)
# ========================================================================

# ดึงค่า Token ของบอท LINE จากระบบตู้เซฟ GitHub Secrets
$token = $env:LINE_TOKEN

# ดึงรหัสกลุ่ม LINE ทั้งหมดมาตัดแยกด้วยเครื่องหมายลูกน้ำ (,) เพื่อทำเป็นกลุ่มข้อมูล (Array) สำหรับวนลูปส่ง
$groupIds = $env:LINE_GROUP_ID -split ","

# ดึงลิงก์ API ของ Google Sheets (หรือลิงก์ opensheet) ที่เราบันทึกไว้ใน GitHub Secrets
$sheetUrl = $env:GOOGLE_SHEET_API_URL 

# ------------------------------------------------------------------------
# 1. การจัดการเรื่องเวลา (แปลงเวลาเซิร์ฟเวอร์ GitHub ให้เป็นเวลาไทย)
# ------------------------------------------------------------------------
# บังคับโซนเวลาให้เป็นเวลาประเทศไทย (GMT+7) ป้องกันบอทรันผิดเวลาเพราะยึดเวลาสากล
$taiTime = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([System.DateTime]::Now, "SE Asia Standard Time")

# แปลงวันที่ปัจจุบันให้เป็นรูปแบบ วัน/เดือน/ปี ค.ศ. เลข 2 หลัก (เช่น "13/06/2026")
$currentDateStr = $taiTime.ToString("dd/MM/yyyy", [System.Globalization.CultureInfo]::InvariantCulture)

# แปลงเวลาปัจจุบันให้เป็นรูปแบบ ชั่วโมง:นาที (เช่น "08:00")
$currentTimeStr = $taiTime.ToString("HH:mm") 

# ประกอบร่างวันที่และเวลาเข้าด้วยกันเพื่อใช้ไปค้นหาในตาราง Google Sheets (เช่น "13/06/2026@08:00")
$currentCheckStr = "${currentDateStr}@${currentTimeStr}"
Write-Host "เวลาปัจจุบันของไทย: $currentCheckStr"

# ------------------------------------------------------------------------
# 2. การดึงข้อมูลตารางงานจาก Google Sheets และแปลงเป็นรูปแบบ LINE API
# ------------------------------------------------------------------------
Write-Host "กำลังเชื่อมต่อเพื่อดึงตารางงานจาก Google Sheets..."

# ส่งคำสั่งไปดาวน์โหลดข้อมูลจาก Google Sheets ออกมาเป็นข้อมูลโครงสร้าง JSON สดๆ ผ่านอินเทอร์เน็ต
$jsonContent = Invoke-RestMethod -Uri $sheetUrl -Method Get

# แปลงข้อความ JSON จาก Google Sheets ให้กลายเป็นวัตถุ (Object) เพื่อให้ PowerShell นำไปค้นหาต่อได้
$tasks = ConvertFrom-Json $jsonContent

# สร้างกล่องเปล่าๆ (Array) รอไว้สำหรับเก็บข้อความที่ตรวจเจอรอบเวลาตรงกับปัจจุบัน
$matchedMessages = @()

# เริ่มวนลูปตรวจสอบแถวข้อมูลในตาราง Google Sheets ทีละแถว (ทีละ Task)
foreach ($task in $tasks) {
    
    # ตรวจสอบเงื่อนไข: ถ้าช่องคอลัมน์ "sendAt" ใน Sheet ตรงกับวันและเวลาปัจจุบันของไทยเป๊ะๆ
    if ($task.sendAt -eq $currentCheckStr) {
        
        # สร้างวัตถุข้อความว่างขึ้นมาเพื่อรอจัดรูปแบบตามกฎของ LINE
        $msgObject = @{}
        
        # เงื่อนไข A: ถ้าในคอลัมน์ type ระบุว่าเป็นข้อความธรรมดา (text)
        if ($task.type -eq "text") {
            # ดึงข้อความจากคอลัมน์ param1 ไปใส่ในรูปแบบของ LINE
            $msgObject = @{ type = "text"; text = $task.param1 }
        }
        # เงื่อนไข B: ถ้าในคอลัมน์ type ระบุว่าเป็นสติกเกอร์ (sticker)
        elif ($task.type -eq "sticker") {
            # ดึงรหัส Package จากคอลัมน์ param1 และรหัส Sticker จากคอลัมน์ param2
            $msgObject = @{ type = "sticker"; packageId = $task.param1; stickerId = $task.param2 }
        }
        # เงื่อนไข C: ถ้าในคอลัมน์ type ระบุว่าเป็นรูปภาพ (image)
        elif ($task.type -eq "image") {
            # ดึงลิงก์รูปภาพจากคอลัมน์ param1 ไปใส่ทั้งช่องรูปเต็มและรูปย่อพรีวิว
            $msgObject = @{ type = "image"; originalContentUrl = $task.param1; previewImageUrl = $task.param1 }
        }
        
        # ถ้าจัดรูปแบบวัตถุข้อความเสร็จสิ้น (มีข้อมูลอยู่จริง) ให้จับใส่ลงกล่องรวมข้อความทันที
        if ($msgObject.Count -gt 0) {
            $matchedMessages += $msgObject
        }
    }
}

# ------------------------------------------------------------------------
# 3. ขั้นตอนการยิงข้อมูลเข้ากลุ่ม LINE API ทั้งหมด
# ------------------------------------------------------------------------
# ตรวจสอบเงื่อนไข: ถ้าพบข้อความในตาราง Sheet ที่ตรงกับเวลาปัจจุบัน (มีจำนวนชิ้นมากกว่า 0)
if ($matchedMessages.Count -gt 0) {
    Write-Host "เจอคิวงานบน Sheet ตรงกันจำนวน $($matchedMessages.Count) ชิ้น! กำลังจัดส่ง..."

    # วนลูปส่งข้อความชุดนี้ไปหาทุกกลุ่ม LINE ตามรายชื่อกลุ่มที่สปลิตไว้ตอนแรก
    foreach ($id in $groupIds) {
        # ตัดช่องว่างหน้าและหลังรหัสกลุ่ม LINE ทิ้งเพื่อความปลอดภัย
        $id = $id.Trim()
        
        # ตรวจสอบว่ารหัสกลุ่ม LINE ต้องไม่เป็นค่าว่างเปล่า
        if (-not [string]::IsNullOrEmpty($id)) {
            
            # ประกอบโครงสร้างคำสั่งซื้อของ LINE API (ระบุรหัสกลุ่มปลายทาง และอาร์เรย์ข้อความที่จะส่ง)
            $bodyObj = @{ to = $id; messages = $matchedMessages }
            
            # แปลงวัตถุให้เป็นข้อความ JSON แบบบีบอัดลดเนื้อที่ (-Compress) เพื่อให้ฝั่ง LINE อ่านง่าย
            $bodyJson = ConvertTo-Json $bodyObj -Depth 20 -Compress
            
            # [สําคัญมากสำหรับ Linux] แปลงข้อความทั้งหมดเป็นรหัส Byte แบบ UTF-8 เพื่อป้องกันภาษาไทยเพี้ยนหรือเป็นต่างดาว
            $utf8Body = [System.Text.Encoding]::UTF8.GetBytes($bodyJson)

            # ใช้คำสั่งยิงข้อมูล (HTTP POST) ส่งตรงไปที่เซิร์ฟเวอร์ของ LINE Messaging API
            Invoke-RestMethod -Uri "https://api.line.me/v2/bot/message/push" `
                              -Method Post `
                              -Headers @{ 
                                  "Authorization" = "Bearer $token"                  # แนบกุญแจบอท
                                  "Content-Type" = "application/json; charset=utf-8" # ระบุประเภทข้อมูลและฟอนต์ภาษาไทย
                              } `
                              -Body $utf8Body
                              
            Write-Host "ส่งข้อความจาก Sheet ไปยังกลุ่ม $id สำเร็จแล้ว"
        }
    }
} else {
    # ถ้าเวลาปัจจุบันไม่ตรงกับตารางนัดหมายแถวใดๆ บน Google Sheets เลย
    Write-Host "รอบนี้ไม่มีคิวงานบน Sheet ที่ตรงกับเวลานี้"
}
