# This script watches and processes shader files, either fsh for Android or hlsl
# for UWP.
#
# For changes to the (hard-coded) FragmentShader.fsh file, the file watcher calls
# the script again with -FshSource set to the fsh file fshSourcePath. The script
# then copies the updated fsh file to the Shader folder on the (hard-coded) Android
# device. Since the device can't be mounted, we use a Shell.Application COM object
# to find the target folder and perform the copy. Since the flags on said COM
# object's CopyHere method don't work, we can't force the COM object to overwrite
# the file without a confirmation dialog, so we give the target file a unique name--
# the file name with a number appended, as necessary. The consumer then needs to
# look for the file with the greatest number suvix and use that for its purposes.
# We copy these files to the Pending folder in this case.
#
# Since the fsc.exe hlsl compiler requires the Developer Command Prompt, the
# CompileShaders.bat (which this script calls) will call VsDevCmd.bat batch to
# create that environment, as necessary. Since this takes time, the -WatchHlsl
# process launches the Developer PowerShell for VS 2019 and configures the file
# watcher from there. When CompileShaders.bat is then run by the file watcher in
# that Developer Powershell envrionment, it doesn't have to wait for that environment
# to be configured and runs more quickly.
#
# For changes to an hlsl file in the (hard-coded) Effects.UWP\Shaders folder, the
# file watcher calls the script again with -HlslPath set to the path to the modified
# hlsl file. In this case the script calls CompileShader.bat with the file name of
# the file to compile.
#
# Note that if the source file is modified in Visual Studio, this script won't work
# because VS doesn't actually modify the file (it deletes it and makes a new 
# version?). Visual Studio Code does, though, so use that.
#
# TODO: make it work with Visual Studio (watch for file creation?).


param([switch] $WatchFsh, [switch] $WatchHlsl, [switch] $Status, [switch] $Unregister, $HlslPath, $FshSource)


# the path to the target folder on the connected Android device, update this with your own path
# keep in the scope of our caller (global) since the event action command references it by name
$global:fshTargetFolder = "Bryan's Galaxy Tab S3\Card\Android\data\com.nfidev.InstantPhotoBooth4\files"

# the path to the source fsh file to watch, update with this with your own path
# keep in the scope of our caller (global) since the event action command references it by name
$global:fshSourcePath = "C:\temp\IPB4\FragmentShader.fsh"

$fshSourceFolderPath = Split-Path $fshSourcePath -Parent
$fshSourceFileName = Split-Path $fshSourcePath -Leaf

# the path to the hlsl folder to watch, update with this with your own path
# keep in the scope of our caller (global) since the event action command references it by name
$global:hlslSourceFolder = "C:\Users\bryan\Source\repos\InstantPhotoBooth4\Effects.UWP\Shaders"

# keep in the scope of our caller (global) since the event action command references it by name
$global:scriptPath = $MyInvocation.MyCommand.Definition

# the path to the shader file in the UWP app's LocalState folders, update with this with your own path
$uwpShaderFilePath = "C:\Users\bryan\AppData\Local\Packages\4119f474-6e52-4081-b0bd-f14959d84c01_zy7gk4k2v4s0e" +
   "\LocalState\ShaderFiles\FragmentShader.bin"

# the path to PowerShell so that we can launch it in "Developer PowerShell for VS 2019" mode
$powerShellPath = "C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe"


function UnRegisterEventSubscriber
{
   Get-EventSubscriber | Where-Object{ $_.SourceIdentifier -eq "FileChanged" } | ForEach-Object `
   {
      $command = $_.Action.Command
      Write-Host "Watcher for $($_.SourceObject.Filter) in: $($_.SourceObject.Path)"
      if ($command.Contains("`$scriptPath"))
      {
         Write-Host "Unregistering subscriber with command: $command"
         $_ | Unregister-Event
      }
   }

   $global:ShaderFileModifiedDate = $null;
}

function ShowStatus
{
   $subscriber = Get-EventSubscriber
   if ($null -ne $subscriber)
   {
      Write-Host "Registered events for the FileChanged watcher:"
      Get-EventSubscriber | Where-Object{ $_.SourceIdentifier -eq "FileChanged" } | ForEach-Object `
      {
         $command = $_.Action.Command
         Write-Host "Watching $($_.SourceObject.Filter) in: $($_.SourceObject.Path)"

         if ($command.Contains("`$scriptPath"))
         {
            Write-Host "Action.Command is: $command"
            if ($command.Contains("`$scriptPath")) { Write-Host "Script `$scriptPath: $scriptPath" }
            if ($command.Contains("`$hlslSourceFolder")) { Write-Host "Source: `$hlslSourceFolder: $hlslSourceFolder" }
            if ($command.Contains("`$fshSourcePath")) { Write-Host "Source: `$fshSourcePath: $fshSourcePath" }
            if ($command.Contains("`$fshTargetFolder")) { Write-Host "Target: `$fshTargetFolder: $fshTargetFolder" }
         }

         if ($_.Action.JobStateInfo.State -eq "Running" -and $_.Action.Output.Count -gt 0)
         {
            # useful for figuring out error conditions
            Write-Host "Command is running, Output: $($_.Action.Output)"
         }
      }

      if ($null -ne $ShaderFileModifiedDate)
      {
         $ShaderFileModifiedDate.Keys | ForEach-Object `
         {
            Write-Host "Current modified date for '$($_)': $($ShaderFileModifiedDate[$_])"
         }
      }
   }
   else
   {
      Write-Host "No event subscribers registered"
      Write-Host "`nUse -WatchHlsl to monitor and compile (via CompileShader.bat) hlsl files in:`n$hlslSourceFolder"
      Write-Host "`nUse -WatchFsh to monitor $fshSourcePath (when modified, copies it to:`n$fshTargetFolder\Shaders`n"
   }
}

function CheckModifiedDate($file, $date)
{
   # maintain a global hash contianing the file path and modified date (since ModifyDate on the FolderItem doesn't work)
   if ($null -eq $ShaderFileModifiedDate)
   {
      $global:ShaderFileModifiedDate = @{}
   }
   else
   {
      # if called a second time (as file watcher tends to do) with the same file, return
      if ($ShaderFileModifiedDate[$file] -eq $date)
      {
         Write-Host "(Possible spurious filewatcher message) $file modified date: $date has not changed, not processing"
         return $false
      }
   }

   $ShaderFileModifiedDate[$file] = $date
   return $true
}

function GetDirectory($here, $directory)
{
   $target = $here.Items() | Where-Object { $_.Name -eq $directory }
   if ($null -eq $target)
   {
      $here.NewFolder($directory)
      ($here.Items() | Where-Object { $_.Name -eq $directory }).GetFolder()
   }
   else
   {
      $target.GetFolder()
   }
}

function GetUniqueSource($target)
{
   $fileName = [System.IO.Path]::GetFileNameWithoutExtension($fshSourceFileName)
   $extension = [System.IO.Path]::GetExtension($fshSourceFileName)
   [int] $counter = 0
   $target.Items() | ForEach-Object `
   {
      if ($_.Name -match "$filename[0-9]+$extension")
      {
         [int] $number = $_.Name -replace "$filename([0-9]+)$extension", '$1'
         if ($number -gt $counter)
         {
            $counter = $number
         }
      }
   }

   $counter++
   $tempFile = Join-Path $fshSourceFolderPath "$filename$counter$extension"
   Copy-Item $fshSourcePath $tempFile
   return $tempFile
}

function CopyFshFile($source)
{
   $fshSourceFileName = Split-Path $source -Leaf
   $fshSourceFolder = (New-Object -ComObject Shell.Application).NameSpace($fshSourceFolderPath)
   if ($null -eq $fshSourceFolder)
   {
      Write-Host "Error: source folder '$fshSourceFolderPath' not found."
      return
   }

   $source = $fshSourceFolder.Items() | Where-Object { $_.Name -eq $fshSourceFileName }
   if ($null -eq $source)
   {
      Write-Host "Error: source file '$fshSourceFileName' not found in '$fshSourceFolderPath'."
      return
   }

   $modifiedDate = $source.ModifyDate

   $target = (New-Object -ComObject Shell.Application).NameSpace(0x11)
   foreach ($folder in $fshTargetFolder.Split("\\"))
   {
      $directory = $target.Items() | Where-Object { $_.Name -eq $folder }
      if ($null -eq $directory)
      {
         "Error: folder '$folder' not found in '$fshTargetFolder'"
         $target = $null
         return
      }
      $target = $directory.GetFolder()
   }

   # create the Shaders folder as necessary
   $target = GetDirectory $target "Shaders"
   $fshTargetFolder = $fshTargetFolder + "\Shaders"

   if (!(CheckModifiedDate $fshSourceFileName $modifiedDate))
   {
      return
   }

   $file = $target.Items() | Where-Object { $_.Name -eq $fshSourceFileName }
   if ($null -ne $file)
   {
      # create the Pending folder if the target exists in Shaders
      $target = GetDirectory $target "Pending"
      $fshTargetFolder += "\Pending"

      $file = $target.Items() | Where-Object { $_.Name -eq $fshSourceFileName }
      if ($null -ne $file)
      {
         # create a copy of the source with a unique filename if the target exists in Pending
         $uniqueSource = GetUniqueSource $target
         $source = $uniqueSource
      }
   }

   Write-Host "Copying '$fshSourcePath' to '$fshTargetFolder'"
   $target.CopyHere($source)
   if ($null -ne $uniqueSource)
   {
      # wait for the copy to be finished, then delete the temp file
      $start = Get-Date
      while($true)
      {
         $target.Items() | ForEach-Object `
         {
            if ($_.Name -eq (Split-Path $uniqueSource -Leaf))
            {
               break;
            }
         }

         if (((Get-Date) - $start).TotalMilliSeconds -gt 500)
         {
            Write-Host "Waiting for copy to finish..."
            $start = Get-Date
         }
      }

      Remove-Item $uniqueSource
   }

   Write-Host "$fshSourceFileName modified date: $modifiedDate"
}

function CompileHlslFile($source)
{
   if (Test-Path $source)
   {
      if (!(CheckModifiedDate $source (Get-ChildItem $source).LastWriteTime))
      {
         return
      }

      $target = $source -replace "hlsl", "bin"
      if (!(Test-Path $target) -or (Get-ChildItem $source).LastWriteTime -gt (Get-ChildItem $target).LastWriteTime)
      {
         $targetFileName = Split-Path -Leaf $target
         Write-Host "Compiling '$source' to $targetFileName..."
         Push-Location (Split-Path -Parent $source)
         $process = Start-Process -PassThru -Wait $env:ComSpec "/C CompileShaders.bat $source" 
         if ($process.ExitCode -eq 0)
         {
            # if the file is to be reloaded at runtime (named FragmentShader.bin), copy to the app's LocalState folder
            if ((Split-Path -Leaf $uwpShaderFilePath) -eq $targetFileName)
            {
               $folder = Split-Path -Parent $uwpShaderFilePath
               if (!(Test-Path $folder))
               {
                  mkdir $folder
               }

               Write-Host "Copying '$targetFileName' to: $uwpShaderFilePath"
               Copy-Item $targetFileName $uwpShaderFilePath
            }
         }
         Pop-Location
      }
      else
      {
         Write-Host "Not compiling $(Split-Path -Leaf $source) (not newer than $(Split-Path -Leaf $target))"
      }
   }
   else
   {
      Write-Host "Error: hlsl file not found: $source"
   }
}

if ($Status)
{
   ShowStatus
   exit 0
}

if ($Unregister)
{
   UnRegisterEventSubscriber
   exit 0
}

if ($null -ne $HlslPath)
{
   CompileHlslFile $HlslPath
   Write-Host "`nTo exit file watching, type: exit <Enter>"
   exit 0
}

if ($null -ne $FshSource)
{
   CopyFshFile $FshSource
   exit 0
}

if ($WatchFsh)
{
   UnRegisterEventSubscriber

   Write-Host "Registering FileChanged event subscriber to watch '$sourceFilename' in:`n$fshSourceFolderPath"
   Write-Host "and when it changes run"
   Write-Host "`$scriptPath -FshSource `$fshSourcePath"
   $fsw = New-Object System.IO.FileSystemWatcher $fshSourceFolderPath, $sourceFilename
   Register-ObjectEvent $fsw Changed -SourceIdentifier FileChanged -Action { &$scriptPath -FshSource $fshSourcePath } > $null

   Write-Host "Run with the '-Unregister' switch to turn off the file watcher."
   exit 0
}

if ($WatchHlsl)
{
   if ($null -eq $env:WindowsSdkDir)
   {
      Write-Host "Launching Developer PowerShell for VS 2019..."
      $command = "-NoExit &{Import-Module " +
         "`"`"`"C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\Common7" +
         "\Tools\Microsoft.VisualStudio.DevShell.dll`"`"`"; " +
         "Enter-VsDevShell 95413e77; " +
         "Push-Location $PWD; " +
         ".\WatchShaderFile.ps1 -WatchHlsl" +
         "}"
      Start-Process $powerShellPath -ArgumentList $command
   }
   else
   {
      UnRegisterEventSubscriber
   
      Write-Host "`nRegistering FileChanged event subscriber to watch '*.hlsl' in:`n$hlslSourceFolder"
      $fsw = New-Object System.IO.FileSystemWatcher $hlslSourceFolder, *.hlsl
      Register-ObjectEvent $fsw Changed -SourceIdentifier FileChanged -Action { &$scriptPath -HlslPath $Event.SourceEventArgs.FullPath } > $null
   
      Write-Host "Run with the '-Unregister' switch to turn off the file watcher."
   }

   exit 0
}

# test action in debugger
if ($false)
{
   Write-Host "(Hard-coded to test CompileHlslFile code)"
   CompileHlslFile C:\Users\bryan\Source\repos\InstantPhotoBooth4\Effects.UWP\Shaders\FragmentShader.hlsl
   exit 0
}

# default action is to show status
ShowStatus
