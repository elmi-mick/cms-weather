<#
Holt das aktuelle Wetter fuer Frankfurt (Open-Meteo, kein API-Key noetig) und
schreibt ein Portraet-Bild (1080x1920, 16:9 hochkant) nach image.png:
Hintergrund sonnig/bewoelkt, Temperatur gross mittig, Uhrzeit unten mittig.

Lokal per Dauerschleife nutzbar (Standard, alle 60s) oder einmalig mit -Once
(so wird es im GitHub-Actions-Workflow aufgerufen).
#>
param(
    [double]$Latitude = 50.1109,
    [double]$Longitude = 8.6821,
    [string]$OutputPath = (Join-Path $PSScriptRoot "image.png"),
    [int]$IntervalSeconds = 60,
    [switch]$Once
)

Add-Type -AssemblyName System.Drawing

function Get-CurrentWeather {
    param([double]$Lat, [double]$Lon)
    $url = "https://api.open-meteo.com/v1/forecast?latitude=$Lat&longitude=$Lon&current_weather=true"
    (Invoke-RestMethod -Uri $url -TimeoutSec 15).current_weather
}

function Test-IsSunny {
    param([int]$WeatherCode)
    # WMO weather codes: 0=klar, 1=ueberwiegend klar, 2=teilweise bewoelkt -> als "sonnig" gewertet
    $WeatherCode -le 2
}

function New-WeatherImage {
    param(
        [double]$Temperature,
        [bool]$IsSunny,
        [string]$Path
    )

    $width = 1080
    $height = 1920

    $bmp = [System.Drawing.Bitmap]::new($width, $height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

    if ($IsSunny) {
        $topColor = [System.Drawing.Color]::FromArgb(255, 79, 195, 247)
        $bottomColor = [System.Drawing.Color]::FromArgb(255, 225, 245, 254)
    } else {
        $topColor = [System.Drawing.Color]::FromArgb(255, 96, 112, 122)
        $bottomColor = [System.Drawing.Color]::FromArgb(255, 207, 216, 220)
    }

    $rect = [System.Drawing.Rectangle]::new(0, 0, $width, $height)
    $bgBrush = [System.Drawing.Drawing2D.LinearGradientBrush]::new($rect, $topColor, $bottomColor, [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
    $g.FillRectangle($bgBrush, $rect)
    $bgBrush.Dispose()

    if ($IsSunny) {
        $glowBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(90, 255, 235, 59))
        $g.FillEllipse($glowBrush, 620, 140, 440, 440)
        $glowBrush.Dispose()

        $sunBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 255, 193, 7))
        $g.FillEllipse($sunBrush, 700, 220, 280, 280)
        $sunBrush.Dispose()
    } else {
        $cloudBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(230, 255, 255, 255))
        $cloudPositions = @(
            @{X=120; Y=260; W=380; H=140},
            @{X=560; Y=180; W=420; H=160},
            @{X=300; Y=380; W=460; H=150}
        )
        foreach ($c in $cloudPositions) {
            $g.FillEllipse($cloudBrush, $c.X, $c.Y, $c.W, $c.H)
        }
        $cloudBrush.Dispose()
    }

    $format = [System.Drawing.StringFormat]::new()
    $format.Alignment = [System.Drawing.StringAlignment]::Center
    $format.LineAlignment = [System.Drawing.StringAlignment]::Center

    $degree = [char]0x00B0
    $tempText = "{0}{1}C" -f [math]::Round($Temperature), $degree
    $tempFont = [System.Drawing.Font]::new("Arial", 220, [System.Drawing.FontStyle]::Bold)
    $tempBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 33, 33, 33))
    $tempRectY = ($height / 2) - 200
    $tempRect = [System.Drawing.RectangleF]::new(0, $tempRectY, $width, 400)
    $g.DrawString($tempText, $tempFont, $tempBrush, $tempRect, $format)
    $tempFont.Dispose()
    $tempBrush.Dispose()

    $germanZone = [System.TimeZoneInfo]::FindSystemTimeZoneById("W. Europe Standard Time")
    $germanTime = [System.TimeZoneInfo]::ConvertTimeFromUtc([System.DateTime]::UtcNow, $germanZone)
    $timeText = $germanTime.ToString("HH:mm")
    $timeFont = [System.Drawing.Font]::new("Arial", 90, [System.Drawing.FontStyle]::Regular)
    $timeBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 33, 33, 33))
    $timeRectY = $height - 220
    $timeRect = [System.Drawing.RectangleF]::new(0, $timeRectY, $width, 160)
    $g.DrawString($timeText, $timeFont, $timeBrush, $timeRect, $format)
    $timeFont.Dispose()
    $timeBrush.Dispose()

    $format.Dispose()
    $g.Dispose()

    # ueber temp-datei speichern + verschieben, damit ein CMS nie eine halb geschriebene Datei liest
    $tmpPath = "$Path.tmp"
    $bmp.Save($tmpPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Move-Item -Path $tmpPath -Destination $Path -Force
}

Write-Host "Wetter-Bild-Updater gestartet fuer Frankfurt ($Latitude, $Longitude)"
Write-Host "Ziel: $OutputPath | Intervall: $IntervalSeconds s"

do {
    try {
        $weather = Get-CurrentWeather -Lat $Latitude -Lon $Longitude
        $isSunny = Test-IsSunny -WeatherCode $weather.weathercode
        New-WeatherImage -Temperature $weather.temperature -IsSunny $isSunny -Path $OutputPath
        $state = if ($isSunny) { "sonnig" } else { "bewoelkt" }
        $degreeSign = [char]0x00B0
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - $(Split-Path $OutputPath -Leaf) aktualisiert: $([math]::Round($weather.temperature))$($degreeSign)C, $state"
    } catch {
        Write-Warning "Fehler beim Aktualisieren: $($_.Exception.Message)"
    }

    if ($Once) { break }
    Start-Sleep -Seconds $IntervalSeconds
} while (-not $Once)
