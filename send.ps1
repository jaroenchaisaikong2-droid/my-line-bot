$token = $env:LINE_TOKEN
# รับค่า ID ทั้งหมดมา แล้วใช้ -split หั่นด้วยเครื่องหมายลูกน้ำ
$groupIds = $env:LINE_GROUP_ID -split ","
$msg = (Get-Content -Path "./message.txt").Trim()

# เริ่มการวนลูป (Loop) ส่งข้อความไปยังทุก Group ID ที่หาเจอ
foreach ($id in $groupIds) {
    $id = $id.Trim() # ลบช่องว่างเผื่อพิมพ์เกิน
    
    if (-not [string]::IsNullOrEmpty($id)) {
        $body = @{
            to = $id
            messages = @(@{ type = "text"; text = $msg })
        } | ConvertTo-Json -Compress

        Invoke-RestMethod -Uri "https://api.line.me/v2/bot/message/push" `
                          -Method Post `
                          -Headers @{ "Authorization" = "Bearer $token"; "Content-Type" = "application/json; charset=utf-8" } `
                          -Body $body
                          
        Write-Host "ส่งข้อความไปยังกลุ่ม: $id สำเร็จ"
    }
}
