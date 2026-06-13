# ========================================================================
# โปรแกรมย่อย: send.ps1 (สคริปต์หลักสำหรับตรวจสอบคิวงานและยิงข้อมูลเข้า LINE API)
# แพลตฟอร์ม: รองรับ PowerShell Core (pwsh) บนระบบปฏิบัติการ Linux (Ubuntu)
# ========================================================================

# ดึงรหัส Token บอท และรายชื่อกลุ่ม LINE จาก GitHub Environment (ที่ถูกส่งมาจากไฟล์ main.yml)
$token = $env:LINE_TOKEN

# แยกรายชื่อกลุ่ม LINE ออกจากกันด้วยเครื่องหมายลูกน้ำ (,) เพื่อเปลี่ยนให้เป็นกลุ่มข้อมูล (Array)
$groupIds = $env:LINE_GROUP_ID -split ","

# ------------------------------------------------------------------------
# 1. การจัดการเรื่องเวลา (เปลี่ยนเวลาของเซิร์ฟเวอร์ GitHub ให้เป็นเวลาไทย)
# ------------------------------------------------------------------------
# บังคับแปลงโซนเวลาให้เป็นเวลาของประเทศไทย (GMT+7) เนื่องจากเซิร์ฟเวอร์ของ GitHub ปกติใช้เวลาสากล (UTC)
$taiTime = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([System.DateTime]::Now, "SE Asia Standard Time")

# จัดรูปแบบ วัน/เดือน/ปี ค.ศ. ให้เป็นเลข 2 หลัก (เช่น วันที่ 05 มกราคม 2026 จะได้ "05/01/2026")
$currentDateStr = $taiTime.ToString("dd/MM/yyyy", [System.Globalization.CultureInfo]::InvariantCulture)

# จัดรูปแบบ ชั่วโมง:นาที (เช่น "08:00" หรือ "16:30")
$currentTimeStr = $taiTime.ToString("HH:mm") 

# ประกอบร่างวันที่และเวลาเข้าด้วยกันเพื่อเอาไว้ไปเทียบกับไฟล์ JSON (เช่น "15/06/2026@08:00")
$currentCheckStr = "${currentDateStr}@${currentTimeStr}"
Write-Host "เวลาปัจจุบันของไทย: $currentCheckStr"

# ------------------------------------------------------------------------
# 2. การอ่านไฟล์ตารางงาน JSON และค้นหาคิวงาน
# ------------------------------------------------------------------------
# อ่านข้อมูลดิบทั้งหมดจากไฟล์ schedule_tasks.json ขึ้นมาเป็นข้อความยาวๆ (Raw String)
$jsonContent = Get-Content -Path "./schedule_tasks.json" -Raw

# แปลงโครงสร้างข้อความ JSON ให้กลายเป็นวัตถุ (Object) เพื่อให้ PowerShell สามารถใช้คำสั่งค้นหาได้
$tasks = ConvertFrom-Json $jsonContent

# ตั้งค่าเริ่มต้นของข้อความที่จะส่งให้เป็นความว่างเปล่า ($null) เพื่อรอรับค่าหากเจอเวลาที่ตรงกัน
$matchedMessages = $null

# ใช้คำสั่ง Loop วิ่งไล่ดูตารางงานในไฟล์ทีละรายการ
foreach ($task in $tasks) {
    # ถ้าช่อง "sendAt" ในไฟล์ JSON มีค่าตรงกับวันเวลาปัจจุบันของไทยเป๊ะๆ
    if ($task.sendAt -eq $currentCheckStr) {
        $matchedMessages = $task.messages # ดึงกลุ่มข้อความทั้งหมดในรอบเวลานั้นเก็บไว้
        break                             # เจอแล้วให้หยุดค้นหาทันทีเพื่อประหยัดเวลา
    }
}

# ------------------------------------------------------------------------
# 3. ขั้นตอนการจัดส่งข้อความเข้ากลุ่ม LINE (ยิง API)
# ------------------------------------------------------------------------
# ตรวจสอบเงื่อนไข: ถ้าตรวจสอบแล้วพบว่ามีข้อความที่ตรงกับเวลาปัจจุบัน ($matchedMessages ไม่ว่างเปล่า)
if ($matchedMessages) {
    Write-Host "เจอคิวงานตรงกัน! กำลังจัดส่ง..."

    # วนลูปเพื่อส่งข้อความชุดนี้ไปหาทุกกลุ่ม LINE ตามรายชื่อที่ดึงมาจากตู้เซฟ GitHub
    foreach ($id in $groupIds) {
        # ตัดช่องว่างหน้า-หลังรหัสกลุ่ม LINE ออก (ถ้ามี) เพื่อป้องกันรหัสกลุ่มทำงานผิดพลาด
        $id = $id.Trim()
        
        # ตรวจสอบว่ารหัสกลุ่ม LINE ต้องไม่เป็นค่าว่าง
        if (-not [string]::IsNullOrEmpty($id)) {
            
            # จัดกลุ่มโครงสร้างข้อมูลสำหรับส่งให้ LINE API (ระบุว่าส่งหาใคร และส่งข้อความอะไรบ้าง)
            $bodyObj = @{
                to = $id
                messages = $matchedMessages
            }
            
            # [จุดสำคัญสำหรับ Linux] 
            # 1. แปลงวัตถุข้อความให้กลายเป็นข้อความ JSON แบบบีบอัดลดเนื้อที่ (-Compress) และรองรับความลึกถึง 20 ชั้น
            $bodyJson = ConvertTo-Json $bodyObj -Depth 20 -Compress
            # 2. บังคับแปลงข้อความทั้งหมดให้กลายเป็นรหัส Byte แบบ UTF-8 เพื่อป้องกันปัญหาภาษาไทยเพี้ยนหรืออ่านไม่ออกบน Linux
            $utf8Body = [System.Text.Encoding]::UTF8.GetBytes($bodyJson)

            # ยิงข้อมูล (HTTP POST Request) ไปยังเซิร์ฟเวอร์ของ LINE Messaging API
            Invoke-RestMethod -Uri "https://api.line.me/v2/bot/message/push" `
                              -Method Post `
                              -Headers @{ 
                                  "Authorization" = "Bearer $token"                  # แนบรหัสยืนยันตัวตนของบอท
                                  "Content-Type" = "application/json; charset=utf-8" # กำหนดประเภทข้อมูลและฟอนต์ภาษาไทย
                              } `
                              -Body $utf8Body
                              
            Write-Host "ส่งข้อความคอมโบไปกลุ่ม $id สำเร็จแล้ว"
        }
    }
} else {
    # ถ้าเวลาปัจจุบันไม่ตรงกับตารางงานใดๆ ในไฟล์ JSON เลย
    Write-Host "รอบนี้ไม่มีคิวงานที่ตรงกับเวลานี้"
}
