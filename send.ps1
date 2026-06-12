$token = $env:LINE_TOKEN
$groupId = $env:LINE_GROUP_ID

# อ่านไฟล์ และใช้ .Trim() เพื่อลบช่องว่างหรือบรรทัดใหม่ที่เกินมาที่ต้นและท้ายข้อความออก
$msg = (Get-Content -Path "./message.txt" -Encoding UTF8).Trim()

$body = @{
    to = $groupId
    messages = @(@{ type = "text"; text = $msg })
} | ConvertTo-Json -Compress

Invoke-RestMethod -Uri "https://api.line.me/v2/bot/message/push" -Method Post -Headers @{ "Authorization" = "Bearer $token"; "Content-Type" = "application/json; charset=utf-8" } -Body $body
