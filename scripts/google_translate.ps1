#------------- Original Author: Strawberry --------------
# Watches to_be_translated.lua (written by the addon for each chat message), translates the
# message and writes it to translated_messages for the addon to show in chat.
#
# Translators are tried in order. One that fails (blocked, rate limited, down) is paused for a
# while and the next one is used. None need an account or key:
#   1) Google (translate.googleapis.com)
#   2) Google (clients5.google.com, the endpoint the Chrome extension uses)
#   3) MyMemory (about 5,000 characters a day, or 50,000 with an email set below)
param (
    [string]$lang = "en" # language to translate into, set by the .bat file
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# ======================= settings you can change =======================
$THROTTLE_MS    = 300   # minimum pause between requests (lower = faster, but more likely to be blocked)
$POLL_MS        = 100   # how often the chat file is checked
$HTTP_TIMEOUT   = 6     # seconds to wait for a translator before trying the next one
$MYMEMORY_EMAIL = ""    # optional: your email raises MyMemory's free limit to 50,000 characters a day
# =======================================================================

$inputFile  = Join-Path $PWD.Path "to_be_translated.lua"
$outputFile = Join-Path $PWD.Path "translated_messages"
$utf8NoBom  = New-Object System.Text.UTF8Encoding $false

$script:lastRequest = [datetime]::MinValue
$script:pausedUntil = @{}
$script:cache = @{}

# Downloads JSON and decodes it as UTF-8 (Windows PowerShell can mis-decode Korean, Russian etc.)
function Get-Json([string]$uri) {
    $resp = Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec $HTTP_TIMEOUT -Headers @{ "User-Agent" = "Mozilla/5.0" }
    $json = [System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray())
    return ,($json | ConvertFrom-Json)
}

# ---- translators: each takes URL-encoded text and returns @{ text; source } ----

function Translate-GoogleApis([string]$q) {
    $r = Get-Json "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=$lang&dt=t&q=$q"
    # [[["translation","original",...], ...], null, "detected language", ...]
    return @{ text = (@($r[0]) | ForEach-Object { $_[0] }) -join ""; source = [string]$r[2] }
}

function Translate-GoogleClients5([string]$q) {
    $r = Get-Json "https://clients5.google.com/translate_a/t?client=dict-chrome-ex&sl=auto&tl=$lang&q=$q"
    # Usually [["translation","detected language"]], sometimes { sentences = [...]; src = "..." }
    if ($r.sentences) {
        return @{ text = (@($r.sentences) | ForEach-Object { $_.trans }) -join ""; source = [string]$r.src }
    }
    return @{ text = [string]$r[0][0]; source = [string]$r[0][1] }
}

function Translate-MyMemory([string]$q) {
    $target = $lang
    if ($target -eq "zh") { $target = "zh-CN" }
    $uri = "https://api.mymemory.translated.net/get?q=$q&langpair=autodetect|$target"
    if ($MYMEMORY_EMAIL -ne "") { $uri += "&de=" + [uri]::EscapeDataString($MYMEMORY_EMAIL) }
    $r = Get-Json $uri
    $text = [string]$r.responseData.translatedText
    # Sent with an error status when the message is already in $lang, so check it first
    if ($text -match "DISTINCT LANGUAGES" -or [string]$r.responseDetails -match "DISTINCT LANGUAGES") {
        return @{ text = ""; source = $lang }
    }
    if ([string]$r.responseStatus -ne "200" -or $text -match "MYMEMORY WARNING") {
        throw "MyMemory: " + [string]$r.responseDetails
    }
    return @{ text = $text; source = [string]$r.responseData.detectedLanguage }
}

# name, function, and how long to pause it after a failure
$Translators = @(
    @{ name = "Google";          fn = ${function:Translate-GoogleApis};     pauseMinutes = 2 },
    @{ name = "Google clients5"; fn = ${function:Translate-GoogleClients5}; pauseMinutes = 2 },
    @{ name = "MyMemory";        fn = ${function:Translate-MyMemory};       pauseMinutes = 10 }
)

function Wait-Throttle {
    $wait = $THROTTLE_MS - ((Get-Date) - $script:lastRequest).TotalMilliseconds
    if ($wait -gt 0) { Start-Sleep -Milliseconds ([int]$wait) }
    $script:lastRequest = Get-Date
}

# Returns the translation, "" if the message is already in $lang, or $null if every translator failed
function Get-Translation([string]$text) {
    if ($script:cache.ContainsKey($text)) { return $script:cache[$text] }
    $q = [uri]::EscapeDataString($text)
    foreach ($translator in $Translators) {
        $pausedUntil = $script:pausedUntil[$translator.name]
        if ($pausedUntil -and (Get-Date) -lt $pausedUntil) { continue }
        Wait-Throttle
        try {
            $r = & $translator.fn $q
            $result = [string]$r.text
            if ($r.source -like "$lang*" -or $result.Trim() -eq "" -or $result.Trim() -eq $text.Trim()) {
                $result = ""
            }
            if ($script:cache.Count -gt 2000) { $script:cache.Clear() }
            $script:cache[$text] = $result
            if ($translator.name -ne "Google" -and $result -ne "") {
                Write-Host ("  (translated by " + $translator.name + ")") -ForegroundColor DarkGray
            }
            return $result
        } catch {
            Write-Host ($translator.name + " failed, pausing it for " + $translator.pauseMinutes + " min: " + $_.Exception.Message) -ForegroundColor DarkYellow
            $script:pausedUntil[$translator.name] = (Get-Date).AddMinutes($translator.pauseMinutes)
        }
    }
    return $null
}

# The addon keeps its last messages in the file, one per line:
#     "||||<session>||||<id>||||<channel>||||<name>||||<message>||||",
# with the string escaped by Lua's %q (\" and \\). Ids increase within a session.
$ChatLinePattern = '^\s*"\|\|\|\|(\d+)\|\|\|\|(\d+)\|\|\|\|(-?\d+)\|\|\|\|(.*?)\|\|\|\|(.*)\|\|\|\|",?\s*$'
function Read-ChatMessages {
    try { $lines = [System.IO.File]::ReadAllLines($inputFile, [System.Text.Encoding]::UTF8) } catch { return $null }
    $messages = @()
    foreach ($line in $lines) {
        if ($line -match $ChatLinePattern) {
            $messages += @{
                session = $Matches[1]
                id      = [long]$Matches[2]
                channel = $Matches[3]
                name    = $Matches[4] -replace '\\(["\\])', '$1'
                message = $Matches[5] -replace '\\(["\\])', '$1'
            }
        }
    }
    return ,$messages
}

# Translations are kept the same way for the addon, newest last:
#     "<session>;;;<id>;;;<channel>;;;<name>;;;<base64 translation>",
$MAX_OUTPUT = 30
$script:outputSession = [string][DateTime]::Now.Ticks
$script:outputId = 0
$script:outputLines = New-Object System.Collections.Generic.List[string]
function Write-Translation($chat, [string]$translation) {
    $script:outputId++
    $base64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($translation))
    $name = $chat.name -replace '["\\]', ''
    $script:outputLines.Add("    `"" + $script:outputSession + ";;;" + $script:outputId + ";;;" + $chat.channel + ";;;" + $name + ";;;" + $base64 + "`",")
    while ($script:outputLines.Count -gt $MAX_OUTPUT) { $script:outputLines.RemoveAt(0) }
    $content = "{`n" + ($script:outputLines -join "`n") + "`n}"
    [System.IO.File]::WriteAllText($outputFile, $content, $utf8NoBom)
}

if (-not (Test-Path $inputFile)) {
    Write-Host "Chat log file not found: $inputFile"
    exit 2
}
if (Test-Path $outputFile) { Remove-Item $outputFile }
Write-Host "Translating chat into '$lang'. Leave this window open while you play."

# Last message handled. Messages left in the file from before the script started are skipped.
$lastSession = $null
$lastId = 0
$existing = Read-ChatMessages
if ($existing -and $existing.Count -gt 0) {
    $lastSession = $existing[-1].session
    $lastId = $existing[-1].id
}
while ($true) {
    Start-Sleep -Milliseconds $POLL_MS
    $messages = Read-ChatMessages
    if ($null -eq $messages) { continue }
    foreach ($chat in $messages) {
        if ($chat.session -ne $lastSession) {
            # The game or addon was restarted, its ids start over
            $lastSession = $chat.session
            $lastId = 0
        }
        if ($chat.id -le $lastId) { continue }
        $lastId = $chat.id

        $translation = Get-Translation $chat.message
        if ($null -eq $translation) {
            Write-Host ("Every translator is unavailable right now, skipped: " + $chat.message) -ForegroundColor Red
            continue
        }
        if ($translation -eq "") { continue } # already in the chosen language

        Write-Host ("[" + $chat.name + "] " + $chat.message) -ForegroundColor DarkGray
        Write-Host ("  " + $translation)
        try {
            Write-Translation $chat $translation
        } catch {
            Write-Host "Error writing to log file: $_" -ForegroundColor Red
            exit 1
        }
    }
}
