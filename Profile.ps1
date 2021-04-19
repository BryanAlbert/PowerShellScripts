# add to the PATH environment variable C:\Util\Scripts path for PowerShell scripts
$env:Path += ";C:\Util;C:\Util\PowerShellScripts"

# some development tools
Set-Alias msbuild "C:\Program Files (x86)\Microsoft Visual Studio\2017\Community\MSBuild\15.0\Bin\MSBuild.exe"
# Set-Alias diffmerge 'C:\Program Files\SourceGear\Common\DiffMerge\sgdm.exe'
function diffmerge { &"C:\Program Files\SourceGear\Common\DiffMerge\sgdm.exe" -nosplash $args }

function fal { Start-Process -FilePath C:\Util\FilterAndroidLog.exe }
function falipb4 { Start-Process -FilePath C:\Util\FilterAndroidLog.exe -ArgumentList "IPB4Raw.log IPB4.log" }

# time clock functions
. C:\Util\PowerShellScripts\TimeClockFunctions.ps1

# miscellaneous
Set-Alias cal C:\Util\Calendar.exe
# function rpn { C:\Util\ConsoleRpn.exe }
Set-Alias rpn C:\Util\ConsoleRpn.exe
Set-Alias bike C:\Util\BikeComputer.exe
Set-Alias miacipher C:\Util\MiaCipher.exe
