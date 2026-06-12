$token = $env:LINE_TOKEN
$groupIds = $env:LINE_GROUP_ID -split ","

# 1. เพิ่ม -Raw เข้าไปตรงนี้ เพื่อให้รองรับข้อความแบบหลายบรรทัด
$textMsg = (Get-Content -Path "./message.txt" -Raw).Trim()

# 2. ลิงก์รูปภาพ (แก้ลิงก์เป็นรูปที่คุณต้องการได้เลย)
$imageUrl = "https://cdn.pixabay.com/photo/2023/04/13/17/49/sunrise-7923120_1280.jpg"

# 3. จัดกลุ่มข้อมูล (รูป + ข้อความ)
$messageArray = @(
    @{
        type = "text"
        text = $textMsg
    },
    @{
    type = "template"
    altText = "ข้อความนี้มีปุ่มกด (สำหรับแสดงในแจ้งเตือน)"
    template = @{
        type = "buttons"
        thumbnailImageUrl = "https://example.com/cover.jpg"
        imageAspectRatio = "rectangle"
        imageSize = "cover"
        imageBackgroundColor = "#FFFFFF"
        title = "เมนูหลัก"
        text = "กรุณาเลือกรายการที่ต้องการ"
        actions = @(
            @{
                type = "uri"
                label = "คลิกเพื่อดูเอกสาร"
                uri = "https://www.youtube.com/watch?v=xVSl0UdF70I"
            }
        )
    }
    },
    @{
        type = "template"
        altText = "ข้อความแบบการ์ดเลื่อน"
        template = @{
            type = "carousel"
            columns = @(
                @{
                    thumbnailImageUrl = "https://example.com/img1.jpg"
                    title = "งานที่ 1"
                    text = "รายละเอียดงานที่ 1"
                    actions = @( @{ type = "uri"; label = "ดูรายละเอียด"; uri = "https://www.google.com" } )
                },
                @{
                    thumbnailImageUrl = "https://example.com/img2.jpg"
                    title = "งานที่ 2"
                    text = "รายละเอียดงานที่ 2"
                    actions = @( @{ type = "uri"; label = "ดูรายละเอียด"; uri = "https://www.google.com" } )
                }
            )
        }
    }
    
    )

# วนลูปส่งไปที่ทุกกลุ่ม
foreach ($id in $groupIds) {
    $id = $id.Trim()
    
    if (-not [string]::IsNullOrEmpty($id)) {
        $body = @{
            to = $id
            messages = $messageArray
        } | ConvertTo-Json -Depth 10 -Compress

        Invoke-RestMethod -Uri "https://api.line.me/v2/bot/message/push" `
                          -Method Post `
                          -Headers @{ "Authorization" = "Bearer $token"; "Content-Type" = "application/json; charset=utf-8" } `
                          -Body $body
                          
        Write-Host "ส่งข้อมูลคอมโบไปยังกลุ่ม: $id สำเร็จ"
    }
}
