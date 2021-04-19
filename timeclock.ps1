# TODO: Add output for when clocked out: the last entry until now showing current off time (with the message).

param([switch] $Punch, [switch] $ProjectBTJ, [switch] $Week, [switch] $Edit, [string] $Data, [string] $Comment, [datetime] $WorkingDate, [string] $Project, [datetime] $PunchTime)

if ($ProjectBTJ)
{
	$Project = "BTJ"
}

$cardPath = "C:\Users\bryan\Documents\TimeCards"

function Display($span, $startTime, $stopTime, $color, $comment)
{
	$shortSpan = [System.TimeSpan]::FromSeconds([int] $span.TotalSeconds)
	Write-Host ("{0:g} ({1:t} to {2:t})`t{3}" -f $shortSpan, $startTime, $stopTime, $comment) -ForegroundColor $color
}

function GetCardPath($date)
{
	(Join-Path $cardPath (Get-Date -Date $date -Format yyyy-MM-dd)) + ".txt"
}

function ProcessCommandLine
{
	# an unnamed string on the command line could be a time for the -Punch parameter or a comment
	$time = Get-Date
	if ($Data.Length -gt 0)
	{
		if ($Comment.Length -gt 0 -and $PunchTime.Length -gt 0)
		{
			Write-Host "Unidentified parameter: $Data"
			exit 1
		}
		elseif ([datetime]::TryParse($Data, [ref] $time))
		{
			$script:PunchTime = [datetime] $Data
		}
		elseif ($Comment.Length -eq 0)
		{
			$script:Comment = $Data
		}
		else
		{
			$script:PunchTime = [datetime] $Data
		}
	}
}

function Clock($card)
{
	$sorted = $card.GetEnumerator() | Sort-Object Name
	$date = [datetime]::Parse($sorted[0].Key)
	$date = [datetime]::new($date.Year, $date.Month, $date.Day)
	Write-Host
	Write-Host ("Spans for {0}, {1:d}:" -f $date.DayOfWeek, $date)
	$totalOn = [System.TimeSpan] 0
	$totalOff = [System.TimeSpan] 0
	for ($interval = 0; $interval -lt $sorted.Count - 1; $interval++)
	{
		$time = [datetime]::Parse($sorted[$interval].Key)
		$next = [datetime]::Parse($sorted[$interval + 1].Key)
		$message = $sorted[$interval].Value
		$span = $next - $time
		if ($interval % 2)
		{
			$totalOff += $span
			Display $span $time $next Magenta $message
		}
		else
		{
			$totalOn += $span
			Display $span $time $next Green $message
		}
	}

	$stopTime = Get-Date
	$last = [datetime]::Parse($sorted[$sorted.Count - 1].Key)
	$message = $sorted[$sorted.Count - 1].Value
	$span = $stopTime - $last
	if ($sorted.Count % 2 -eq 1)
	{
		$totalOn += $span
		Display $span $last $stopTime Green $message
	}
	elseif ($date -eq [datetime]::new($stopTime.Year, $stopTime.Month, $stopTime.Day))
	{
		$totalOff += $span
		Display $span $last $stopTime Magenta $message
	}
	elseif ($message.Length -gt 0)
	{
		Write-Host ("(Off at {0:t})`t`t{1}" -f $last, $message) -ForegroundColor Magenta
	}

	Write-Host
	Write-Host "Totals:"
	Write-Host ("On:  {0:g}" -f [System.TimeSpan]::FromSeconds([int] $totalOn.TotalSeconds)) -ForegroundColor Green
	Write-Host ("Off: {0:g}" -f [System.TimeSpan]::FromSeconds([int] $totalOff.TotalSeconds)) -ForegroundColor Magenta
	$totalOn
}

function LoadDay($date)
{
	$card = @{}
	$fileName = GetCardPath $date
	if (Test-Path $fileName)
	{
		Get-Content $fileName | ForEach-Object `
		{
			try
			{
				if ($_ -match '(^[0-9/: ]+[AP]M)\s*(.*)$')
				{
					$card.Add([DateTime] $Matches[1], $Matches[2])
				}
			}
			catch [Exception]
			{
			}
		}
	}
	
	$card
}

function LoadWeek($day)
{
	if ($day.DayOfWeek -ne "Monday")
	{
		LoadWeek ($day - [TimeSpan]::FromDays(1))
	}
	$cards[$day.DayOfWeek] = LoadDay $day
}

function Save($card)
{
	$fileName = GetCardPath $WorkingDate
	$output = ""
	foreach ($time in $card.GetEnumerator() | Sort-Object Name)
	{
		$output += $time.Name.ToString() + ' ' + $time.Value + "`r`n"
	}

	$output | Out-File $fileName
}

function SetWorkingDate()
{
	if ($null -eq $WorkingDate)
	{
		$now = [datetime]::Now
		[datetime]::new($now.Year, $now.Month, $now.Day, 0, 0, 0)
	}
	else
	{
		Get-Date $WorkingDate
	}
}


# for testing in Visual Studio (where specifying parameters is awkward)
# $Punch = $true
# $Comment = "Testing."
# $Project = "BTJ"
# $Edit = $true
# $Data = "17:30"
# $Data = "Resume."
# $PunchTime = "18:00"
# $Week = $true
# $WorkingDate = [datetime] "9/30"

$WorkingDate = SetWorkingDate

if ($Project)
{
	$cardPath = Join-Path $cardPath $Project
	if (!(Test-Path $cardPath))
	{
		Write-Error "Project path not found: $cardPath"
		return
	}
}

if ($Edit)
{
	Invoke-Item (GetCardPath $WorkingDate)
	exit 0
}

if ($Week)
{
	$cards = @{}
	$total = [System.TimeSpan] 0
	LoadWeek $(Get-Date $WorkingDate)

	# hashes aren't ordered, so process cards starting on Monday (10/1/2018 is a Monday)
	for ($dow = [datetime]::Parse("10/1/2018"); $dow.DayOfWeek -ne "Sunday"; $dow += [timespan]::FromDays(1))
	{
		$card = $cards[$dow.DayOfWeek]
		if ($card.Count -gt 0)
		{
			$total += Clock $card
		}
	}

	# add Sunday, too
	$card = $cards[$dow.DayOfWeek]
	if ($card.Count -gt 0)
	{
		$total += Clock $card
	}

	Write-Host
	Write-Host "Weekly total:"
	Write-Host ([string]::Format("{0}:{1:D2}:{2:D2}", (24 * $total.Days + $total.Hours), $total.Minutes, $total.Seconds))
	[string]::Format("{0}.{1}:{2:D2}:{3:D2}", $total.Days, $total.Hours, $total.Minutes, $total.Seconds)

	exit 0
}

Try
{
	ProcessCommandLine
}
Catch
{
	$_
	exit 2
}

$card = LoadDay $WorkingDate

if ($Punch -or $PunchTime)
{
	if ($null -eq $PunchTime)
	{
		$PunchTime = Get-Date
	}
	$PunchTime = [datetime]::new($WorkingDate.Year, $WorkingDate.Month, $WorkingDate.Day, $PunchTime.Hour, $PunchTime.Minute, $PunchTime.Second)

	$card.Add($PunchTime, $Comment)
	Save $card
}

$total = [System.TimeSpan]::FromTicks(0)
if ($card.Count -gt 0)
{
	$total = Clock $card 
}
else
{
	Write-Host "No entries."
}

"{0:g}" -f [System.TimeSpan]::FromSeconds([int] $total.TotalSeconds)
