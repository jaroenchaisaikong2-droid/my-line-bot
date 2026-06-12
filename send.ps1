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
