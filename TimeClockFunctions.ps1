# Given a number of hours needed for the week, computes hours needed by the end of the day
# to make that rate. 

function QuitTime([switch] $ProjectBTJ, [string] $Project, [timespan] $WeekHours, [timespan] $AddHours)
{
	if ($ProjectBTJ)
	{
		$Project = "BTJ"
	}

	if ($Project.Length -gt 0)
	{
		if ($Project -eq "GI" -and $WeekHours -eq $null)
		{
			$WeekHours = [TimeSpan]::FromHours(21.0);
			Write-Host "Project GI default week hours is $weekHours"
		}
	}

	if ($WeekHours -eq $null)
	{
		$WeekHours = [timespan]::FromHours(40.0)
	}

	if ($AddHours)
	{
		$WeekHours = $WeekHours + $AddHours
		Write-Host "Total week hours: $(FormatWeekHours $WeekHours)"
	}

	if ($Project.Length -gt 0)
	{
		$totalHours = [timespan] (timeclock.ps1 -Week -Project $Project)
	}
	else
	{
		$totalHours = [timespan] (timeclock.ps1 -Week)
	}

	$dayHours = [timespan]::FromHours($WeekHours.TotalHours / 5.0)
	$needHours = [timespan]::FromHours($dayHours.TotalHours * [Math]::Min(5, [int] [datetime]::Now.DayOfWeek))
	[string]::Format("`nTotal hours needed before quitting on {0}: {1} ({2} per day)", [datetime]::Now.DayOfWeek, (FormatWeekHours $needHours), (FormatWeekHours $dayHours))
	$shortHours = $needHours - $totalHours
	[string]::Format("`nAdditional hours needed by end of day: {0}, quit at {1}", $shortHours, ([datetime]::Now + $shortHours).ToShortTimeString())
}


# Given a string to be parsed as a timespan (e.g. 0:15:00 for fifteen minutes) and a string to be parsed as
# a DateTime for an end date, displays the GI time card for each day starting at $EndDate and going back by 
# one day each iteration until Monday is displayed, subtracting the $AddTimePerDay from the total hours for that day.

function AddTimeToWeek([string] $EndDate, [string] $AddTimePerDay, [string] $AddTimeToWeek, [int] $WorkDays)
{
	if ($WorkDays -eq 0)
	{
		$WorkDays = 5
	}

	if ($AddTimeToWeek.Length -gt -0)
	{
		$AddTimePerDay = [timespan]::FromHours(([timespan] $AddTimeToWeek).TotalHours / $WorkDays)
	}

	if ($AddTimePerDay.Length -gt 0)
	{
		$add = [timespan] $AddTimePerDay
	}
	else
	{
		$add = 0
	}

	$output = ""
	$grossHours = [timespan]::FromHours(0)
	$netHours = [timespan]::FromHours(0)
	$date = [datetime]::Parse($EndDate)
	
	do
	{
		$day = [timespan] (timeclock.ps1 -WorkingDate $date -Project GI)
		if ($add -gt 0 -and $day -gt 0)
		{
			$grossHours += $day
			$hours = $day + $AddTimePerDay
			$output = [string]::Format("{0}, {1:d}, {2} ({3} + {4}): `n", $date.DayOfWeek, $date, (FormatWeekHours $hours), (FormatWeekHours $day), (FormatWeekHours $add)) + $output
			$netHours += $hours
		}
		elseif ($add -lt 0 -and $day -gt 0)
		{
			$grossHours += $day
			$hours = $day + $AddTimePerDay
			$output = [string]::Format("{0}, {1:d}, {2} ({3} - {4}): `n", $date.DayOfWeek, $date, (FormatWeekHours $hours), (FormatWeekHours $day), (FormatWeekHours (-$add))) + $output
			$netHours += $hours
		}
		else
		{
			$output = [string]::Format("{0}, {1:d}, {2}: `n", $date.DayOfWeek, $date, (FormatWeekHours $day)) + $output
			$netHours += $day
		}

		$date -= [timespan]::FromDays(1)
	}
	while ($date.DayOfWeek -gt 0)

	$output | clip.exe
	"Daily hours copied to clipboard, hit Enter to continue... "
	PSConsoleHostReadline
	if ($add -gt 0)
	{
		[string]::Format("{0} ({1} + {2})",  (FormatWeekHours $netHours), (FormatWeekHours $grossHours), (SubtractWeekHours $netHours $grossHours)) | clip.exe
	}
	elseif ($add -lt 0)
	{
		[string]::Format("{0} ({1} - {2})",  (FormatWeekHours $netHours), (FormatWeekHours $grossHours), (SubtractWeekHours $grossHours $netHours)) | clip.exe
	}
	else
	{
		FormatWeekHours $netHours | clip.exe
	}

	"Total hours copied to clipboard... "
}

function AddWeekHours([timespan] $One, [timespan] $Two)
{
	FormatWeekHours ($One + $Two)
	($One + $Two).TotalHours
}

function SubtractWeekHours([timespan] $One, [timespan] $Two)
{
	FormatWeekHours ($One - $Two)
}

function FormatWeekHours([timespan] $Time)
{
	[string]::Format("{0}:{1:D2}:{2:D2}", $Time.Days * 24 + $Time.Hours, $Time.Minutes, $Time.Seconds)
}

# some handy aliases
Set-Alias tit timeclock.ps1

function titgifunction { timeclock.ps1 -Project GI }
function titbtjfunction { timeclock.ps1 -Project BTJ }

Set-Alias titgi titgifunction
Set-Alias titbtj titbtjfunction

Set-Alias ReportWeek AddTimeToWeek

# debug this
# AddTimeToWeek -EndDate 9/24 -AddTimeToWeek -6:24:00 -WeekDays 6
# debug this
# QuitTime
# QuitTime -ProjectGI
# QuitTime -WeekHours 35
# QuitTime -WeekHours 35 -Project GI
# QuitTime -ProjectGI -AddHours 12:55:15
# SubtractWeekHours 42:00:00 39:09:58