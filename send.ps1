$token = $env:LINE_TOKEN
$groupIds = $env:LINE_GROUP_ID -split ","

# 1. ข้อความจากไฟล์ message.txt (ใส่ลิงก์เว็บต่างๆ ในไฟล์นี้ได้เลย)
$textMsg = (Get-Content -Path "./message.txt").Trim()

# 2. ลิงก์รูปภาพ (ต้องเป็น HTTPS และเป็นไฟล์รูปโดยตรง)
# ตัวอย่าง: เอารูปลงเว็บฝากรูปฟรี แล้วเอาลิงก์ตรงมาใส่ตรงนี้
$imageUrl = "https://cdn.pixabay.com/photo/2023/04/13/17/49/sunrise-7923120_1280.jpg"

# 3. จัดกลุ่มข้อมูลที่จะส่ง (ส่งได้สูงสุด 5 ชิ้นต่อ 1 ครั้ง)
$messageArray = @(
    # ชิ้นที่ 1: ส่งรูปภาพ
    @{
        type = "image"
        originalContentUrl = $imageUrl
        previewImageUrl = $imageUrl
    },
    # ชิ้นที่ 2: ส่งข้อความ (ที่มีลิงก์อยู่ข้างใน)
    @{
        type = "text"
        text = $textMsg
    },
    # ชิ้นที่ 3: สติกเกอร์ (Sticker)
    @{
        type = "sticker"
        packageId = "446"
        stickerId = "1988" 
    },
    # ชิ้นที่ 4: พิกัดแผนที่ (Location)
    @{
        type = "location"
        title = "สำนักงาน กฟภ. (PEA)"
        address = "ระบุที่อยู่ของสาขาลงไปตรงนี้ได้เลยครับ"
        latitude = 13.8441   # ละติจูด
        longitude = 100.5543 # ลองจิจูด
    },
    # ชิ้นที่ 5: วิดีโอ (Video)
    @{
        type = "video"
        originalContentUrl = "https://www.example.com/my-video.mp4" # ลิงก์ไฟล์วิดีโอตัวเต็ม
        previewImageUrl = "https://www.example.com/cover.jpg"      # ลิงก์รูปหน้าปกวิดีโอ
    },
    # ตัวเลือกเสริม: ไฟล์เสียง (Audio)
    @{
        type = "audio"
        originalContentUrl = "https://www.example.com/sound.m4a"
        duration = 60000 # ความยาวเสียง (มิลลิวินาที) เช่น 60000 = 1 นาที
    }
)

# วนลูปส่งไปที่ทุกกลุ่ม LINE ของคุณ
foreach ($id in $groupIds) {
    $id = $id.Trim()
    
    if (-not [string]::IsNullOrEmpty($id)) {
        $body = @{
            to = $id
            messages = $messageArray # ดึงกลุ่มข้อมูลด้านบนมาใส่ตรงนี้
        } | ConvertTo-Json -Depth 10 -Compress

        Invoke-RestMethod -Uri "https://api.line.me/v2/bot/message/push" `
                          -Method Post `
                          -Headers @{ "Authorization" = "Bearer $token"; "Content-Type" = "application/json; charset=utf-8" } `
                          -Body $body
                          
        Write-Host "ส่งข้อมูลคอมโบไปยังกลุ่ม: $id สำเร็จ"
    }
}
