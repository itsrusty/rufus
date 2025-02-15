# PowerShell script to parse rufus.loc and create a listing.csv
# Copyright © 2023 Pete Batard <pete@akeo.ie>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

try {
  [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

function InsertMsg([object]$translated_msgs, [string]$lang, [string]$msg_id, [string]$msg)
{
  for ($i = 0; $i -lt $translated_msgs.MSG_ID.Count; $i++) {
    if ($translated_msgs.MSG_ID[$i] -eq $msg_id) {
      $translated_msgs.$lang[$i] = $msg
    }
  }
}

function GetMsg([object]$translated_msgs, [string]$lang, [string]$msg_id)
{
  for ($i = 0; $i -lt $translated_msgs.MSG_ID.Count; $i++) {
    if ($translated_msgs.MSG_ID[$i] -eq $msg_id) {
      if ($msg_id -eq "MSG_901" -or $msg_id -eq "MSG_902" -or $msg_id -eq "MSG_903") {
        if (-not $translated_msgs.$lang[$i]) {
          return $translated_msgs."en-us"[$i]
        }
      }
      return $translated_msgs.$lang[$i]
    }
  }
  return ""
}

$csv = Import-Csv -Path .\listing_template.csv -Encoding UTF8

# Get the translated MSG_ID's we need
$translated_msg_ids = @()
$empty = @()
foreach($row in $csv) {
  # There may be multiple MSG_ID's in the row
  Select-String "MSG_\d+" -input $row -AllMatches | foreach {
    foreach ($match in $_.matches) {
      $translated_msg_ids += $match.Value
      $empty += ""
    }
  }
}

$translated_msgs = New-Object PSObject
Add-Member -InputObject $translated_msgs -NotePropertyName MSG_ID -NotePropertyValue $translated_msg_ids

$lang = ""
$langs = @()
foreach ($line in Get-Content ..\loc\rufus.loc) {
  # Get the language for the current section
  if ($line -Like "l *") {
    $lang = $line.split(" ",[System.StringSplitOptions]::RemoveEmptyEntries)[1].Trim('"').ToLower()
    if ($lang -eq "sr-rs") {
      $lang = "sr-latn-rs"
    }
    $langs += $lang
    Add-Member -InputObject $translated_msgs -NotePropertyName $lang -NotePropertyValue $empty.PsObject.Copy()
  }
  # Add translated messages to our array
  if ($line -Like "t MSG_*") {
    $msg_id = $line.Substring(2, 7)
    if ($translated_msg_ids.Contains($msg_id)) {
      $msg = $line.Substring(10).Trim('"').Replace("\n","`n").Replace('\"','"')
      # Insert URLs in the relevant messages
      if ($msg.Contains("%s")) {
        $url = switch ($msg_id) {
          MSG_901 { "https://rufus.ie" }
          MSG_902 { "https://github.com/pbatard/rufus" }
          MSG_903 { "https://github.com/pbatard/rufus/blob/master/ChangeLog.txt" }
        }
        $msg = $msg.Replace("%s", $url)
      }
      InsertMsg $translated_msgs $lang $msg_id "$msg"
    }
  }
}

# Add the extra columns to our CSV
foreach ($lang in $langs) {
  $csv = $csv | Select-Object *, @{ n = $lang; e = " " }
}

# Now insert the translated strings and whatnot
foreach($row in $csv) {
  Select-String "MSG_\d+" -input $row -AllMatches | foreach {
    foreach ($lang in $langs) {
      $row.$lang = $row.default
      foreach ($match in $_.matches) {
        $msg = GetMsg $translated_msgs $lang $match.Value
        $row.$lang = $row.$lang.Replace($match.Value, $msg)
      }
    }
    # Override some defaults
    if ($row.default -eq "MSG_904") {
      $row.default = "https://www.gnu.org/licenses/gpl-3.0.html"
    } elseif ($row.default -eq "MSG_905") {
      $row.default = "Boot"
    } else {
      $row.default = ""
    }
  }
  if ($row.default -like "<AUTOGENERATED>") {
    # Insert current year into CopyrightTrademarkInformation
    if ($row.Field -eq "CopyrightTrademarkInformation") {
      $year = Get-Date -Format "yyyy"
      $row.default = "© 2011-" + $year + " Pete Batard"
    } elseif ($row.Field -eq "ReleaseNotes") {
      $section = 0
      $row.default = ""
      foreach ($line in Get-Content ..\..\ChangeLog.txt) {
        if ($line.StartsWith("o Version")) {
          $section++
          continue
        }
        if ($section -eq 1 -and $line) {
          if ($row.default) {
            $row.default += "`n"
          }
          $row.default += $line.Replace("    ", "• ")
        }
      }
    } elseif ($row.Field.StartsWith("DesktopScreenshot")) {
      $row.default = ""
      foreach ($lang in $langs) {
        $path = $lang  + "\" + $row.Field.Replace("Desktop", "") + ".png"
        if (Test-Path -Path ("listing\" + $path)) {
          $row.$lang = $path
        }
      }
    }
  }
}

$csv | Export-Csv 'listing\listing.csv' -NoTypeInformation -Encoding UTF8
