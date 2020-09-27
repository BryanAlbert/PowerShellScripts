# This script watches and processes shader files, either fsh for Android or hlsl
# for UWP. Run it from the folder containing the shader file(s) to watch.
#
# When the file watcher detects changes to the Android FragmentShader.fsh file, 
# it calls the script again with -FshSource $fshShaderFileName (the global: name).
# With this command line the script copies the updated fsh file to the (hard-coded)
# Shaders folder on the Android device. Since the device can't be mounted, we use
# a Shell.Application COM object to find the target folder and perform the copy.
# Since the flags on said COM object's CopyHere method don't work, we can't force
# the COM object to overwrite the file without a confirmation dialog, so when
# necessary we give the target file a unique name, which is the file name with a
# number appended. The app on the device then needs to look for the file with the
# greatest number suffix and use that for its purposes. We copy these files to the
# device's Shaders/Pending folder in this case. Note that the Shell.Application
# object can't tell when file structure changes are made on the device, so even
# though the consumer may delete the temporary file, we won't know that (so we'll
# make a new temporary file with the incremented number on the next file change).
# If the Shaders or Pending folder is deleted altogether on the device, copying
# the modified shader file one of these folders on the device will silently fail.
# In order to delete the local copy of the unique file, we wait for the copy to
# the device to finish; if the copy fails, we will time out waiting. In this case,
# reattach the device to the computer to refresh the Shell.Application object's
# view of the device's file structure.
#
# Since compiling hlsl files requires the Developer Command Prompt, CompileShaders.bat
# (which this script calls) will call VsDevCmd.bat batch to create that environment
# as necessary. Since that call takes time, the -WatchHlsl process launches the
# "Developer PowerShell for VS 2019" and configures the file watcher from there.
# When the file watcher then runs CompileShaders.bat in that Developer Powershell
# envrionment, it doesn't have to wait for the VsDevCmd.bat to run and thus runs
# more quickly.
#
# For changes to an hlsl file in the (current) Effects.UWP\Shaders folder, the file
# watcher calls the script again with -HlslPath set to the path to the modified
# hlsl file. In this case the script calls CompileShader.bat with the file name of
# the file to compile. The script can be configured to copy the compiled bin file
# to the hard-coded (and finicky) deploy path $uwpTargetFolderdeploy by specifying
# the file name with the -CopyFile parameter when the file watcher is launched,
# e.g. WatchShaderFile.ps1 -WatchHlsl -CopyFile BruceFilter.bin This filename is
# saved in the global:$uwpShaderFileName variable.
#
# Note that if the source file is modified in Visual Studio, this script won't work
# because VS doesn't actually modify the file (it deletes it and makes a new 
# version?). Visual Studio Code does, though, so use that for editing.
#
# TODO: make it work with Visual Studio (watch for file creation?).


param([switch] $WatchFsh, [switch] $WatchHlsl, [switch] $Status, [switch] $Unregister, $CopyFile, $HlslPath, $FshSource)


# the path to the target folder on the connected Android device, update this with your own path
# keep in the scope of our caller (global) since the event action command references it by name
$global:fshTargetFolder = "Bryan's Galaxy Tab S3\Card\Android\data\com.nfidev.InstantPhotoBooth4\files"

# the path to the shader file in the UWP app's LocalState folders, update with this with your own path
$uwpTargetFolder = "C:\Users\bryan\AppData\Local\Packages\4119f474-6e52-4081-b0bd-f14959d84c01_zy7gk4k2v4s0e" +
"\LocalState\ShaderFiles"

# keep in the scope of our caller (global) since the event action command references it by name
$global:scriptPath = $MyInvocation.MyCommand.Definition
$fshSourceFolderPath = $PWD.Path
$hlslSourceFolder = $PWD.Path

# the path to PowerShell so that we can launch it in "Developer PowerShell for VS 2019" mode
$powerShellPath = "C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe"


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
   $true
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
   $fileName = [System.IO.Path]::GetFileNameWithoutExtension($fshShaderFileName)
   $extension = [System.IO.Path]::GetExtension($fshShaderFileName)
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
   Copy-Item $fshShaderFileName $tempFile
   $tempFile
}

function GetTabletFilesFolder
{
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

   $target
}

function ListFiles($target, $indent)
{
   if ($null -ne $target)
   {
      Write-Host "$indent$($target.Name)"
      $indent += "   "
      $target.GetFolder().Items() | ForEach-Object `
      {
         if ($_.IsFolder)
         {
            ListFiles $_ $indent
         }
         else
         {
            Write-Host "$indent$($_.Name)"
         }
      }
   }
}

function ListTabletFiles
{
   Write-Host "fsh files in:`n$fshTargetFolder"
   $target = GetTabletFilesFolder
   $target = $target.Items() | Where-Object { $_.Name -eq "Shaders" }
   ListFiles $target ""
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
            if ($command.Contains("`$scriptPath")) { Write-Host "Script: `$scriptPath: $scriptPath" }
            if ($command.Contains("`$hlslSourceFolder")) { Write-Host "Source: `$hlslSourceFolder: $hlslSourceFolder" }
            if ($command.Contains("`$fshShaderFileName"))
            {
               Write-Host "Source: `$fshShaderFileName: $fshShaderFileName"
               Write-Host "Target: `$fshTargetFolder: $fshTargetFolder"
               ListTabletFiles
            }
         }

         if ($null -ne $uwpShaderFileName) { Write-Host "When $uwpShaderFileName changes, it will be copied to $uwpTargetFolder" }
         if ($null -ne $fshShaderFileName) { Write-Host "When $fshShaderFileName changes, it will be copied to $fshTargetFolder" }

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
      Write-Host "`nUse -WatchHlsl to monitor and compile (via CompileShader.bat) hlsl files in the current directory:`n$hlslSourceFolder"
      Write-Host "Add the -CopyFile file name to copy, when it changes, the specified file (defaults to FragmentShader.bin) to:"
      Write-Host "$uwpTargetFolder"
      Write-Host "`nUse -WatchFsh to monitor $fshShaderFileName, when modified, copies it to:`n$fshTargetFolder\Shaders"
      Write-Host "Add the -CopyFile file name to copy, when it changes, the specified file (defaults to FragmentShader.fsh) to:"
      Write-Host "$fshTargetFolder`n"
   }
}

function UnRegisterEventSubscriber
{
   Get-EventSubscriber | Where-Object{ $_.SourceIdentifier -eq "FileChanged" } | ForEach-Object `
   {
      $command = $_.Action.Command
      Write-Host "Unregistering watcher for $($_.SourceObject.Filter) in: $($_.SourceObject.Path)"
      if ($command.Contains("`$scriptPath"))
      {
         Write-Host "Unregistering subscriber with command: $command"
         $_ | Unregister-Event
      }
   }

   # reset global state variables
   $ShaderFileModifiedDate = $null
   if ($null -ne $uwpShaderFileName) { Remove-Variable -Scope global uwpShaderFileName }
   if ($null -ne $fshShaderFileName) { Remove-Variable -Scope global fshShaderFileName }
}

function CopyFshFile($source)
{
   $fshSourceFolder = (New-Object -ComObject Shell.Application).NameSpace($fshSourceFolderPath)
   if ($null -eq $fshSourceFolder)
   {
      Write-Host "Error: source folder '$fshSourceFolderPath' not found."
      return
   }

   $file = $fshSourceFolder.Items() | Where-Object { $_.Name -eq $source }
   if ($null -eq $file)
   {
      Write-Host "Error: source file '$source' not found in '$fshSourceFolderPath'."
      return
   }

   $modifiedDate = $file.ModifyDate
   if (!(CheckModifiedDate $source $modifiedDate))
   {
      return
   }

   $target = GetTabletFilesFolder

   # create the Shaders folder as necessary
   $target = GetDirectory $target "Shaders"
   $fshTargetFolder = $fshTargetFolder + "\Shaders"

   $file = $target.Items() | Where-Object { $_.Name -eq $source }
   if ($null -ne $file)
   {
      # create the Pending folder if the target exists in Shaders
      $target = GetDirectory $target "Pending"
      $fshTargetFolder = Join-Path $fshTargetFolder "Pending"

      $file = $target.Items() | Where-Object { $_.Name -eq $source }
      if ($null -ne $file)
      {
         # create a copy of the source with a unique filename if the target exists in Pending
         $uniqueSource = GetUniqueSource $target
         $source = $uniqueSource
      }
   }

   Write-Host "Copying '$source' to '$fshTargetFolder'"
   $source = Resolve-Path $source
   $target.CopyHere($source.Path)
   if ($null -ne $uniqueSource)
   {
      # wait for the copy to be finished, then delete the temp file
      $filename = Split-Path $uniqueSource -Leaf
      for ($try = 1; $try -le 10; $try++)
      {
         $target.Items() | Where-Object { $_.Name -eq $fileName } | ForEach-Object `
         {
            Remove-Item $uniqueSource
            break
         }

         Write-Host "Waiting $try of 10 for copy to finish..."
         Start-Sleep -Seconds 1
      }

      if ($try -gt 10)
      {
         Write-Host "Failed to detect that the target file exists. Reconnect the device and try again?"
      }
   }

   Write-Host "$source modified date: $modifiedDate"
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
            # if specified with $CopyFile (defaults to FragmentShader.bin), copy it to the app's LocalState folder
            if ($uwpShaderFileName -eq $targetFileName)
            {
               if (!(Test-Path $uwpTargetFolder))
               {
                  mkdir $uwpTargetFolder
               }

               $target = Join-Path $uwpTargetFolder $uwpShaderFileName
               Write-Host "Copying '$targetFileName' to: $target"
               Copy-Item $targetFileName $target
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

if ($WatchFsh)
{
   UnRegisterEventSubscriber

   if ($null -ne $CopyFile)
   {
      # track the file to copy to the device, defaults to FragmentShader.fsh
      $CopyFile = $CopyFile -replace "\.\\" 
      Write-Host "Will copy $CopyFile to $fshTargetFolder"
      $global:fshShaderFileName = $CopyFile
   }
   else
   {
      $global:fshShaderFileName = "FragmentShader.fsh"
   }

   Write-Host "Registering FileChanged event subscriber to watch '$fshShaderFileName' in:`n$fshSourceFolderPath"
   Write-Host "and when it changes run"
   Write-Host "`$scriptPath -FshSource `$fshShaderFileName"
   $watcher = New-Object System.IO.FileSystemWatcher $fshSourceFolderPath, $fshShaderFileName
   Register-ObjectEvent $watcher Changed -SourceIdentifier FileChanged -Action { &$scriptPath -FshSource $fshShaderFileName } > $null

   Write-Host "Run with the '-Unregister' switch to turn off the file watcher."
   exit 0
}

if ($null -ne $FshSource)
{
   CopyFshFile $FshSource
   exit 0
}

if ($WatchHlsl)
{
   if ($null -eq $env:WindowsSdkDir)
   {
      if ($null -ne $CopyFile)
      {
         # track the file to copy to the deployment folder, defaults to FragmentShader.hlsl
         $CopyFile = $CopyFile -replace "\.\\" -replace "\.hlsl", ".bin"
         Write-Host "Will copy $CopyFile to $uwpTargetFolder"
         $global:uwpShaderFileName = $CopyFile
      }
      else
      {
         $global:uwpShaderFileName = "FragmentShader.bin"
      }
   
      # CompileShader.bat runs faster if it's run in the Developer environment, relaunch there
      Write-Host "Launching Developer PowerShell for VS 2019..."
      $command = "-NoExit &{Import-Module " +
         "`"`"`"C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\Common7" +
         "\Tools\Microsoft.VisualStudio.DevShell.dll`"`"`"; " +
         "Enter-VsDevShell 95413e77; " +
         "Push-Location $PWD; " +
         ".\WatchShaderFile.ps1 -WatchHlsl -CopyFile $uwpShaderFileName" +
         "}"
      Start-Process $powerShellPath -ArgumentList $command
   }
   else
   {
      UnRegisterEventSubscriber
   
      if ($null -ne $CopyFile)
      {
         # track the file to copy to the deployment folder, defaults to FragmentShader.hlsl
         $CopyFile = $CopyFile -replace "\.\\" -replace "\.hlsl", ".bin"
         Write-Host "Will copy $CopyFile to $uwpTargetFolder"
         $global:uwpShaderFileName = $CopyFile
      }
      else
      {
         $global:uwpShaderFileName = "FragmentShader.bin"
      }

      Write-Host "`nRegistering FileChanged event subscriber to watch '*.hlsl' in:`n$hlslSourceFolder"
      $watcher = New-Object System.IO.FileSystemWatcher $hlslSourceFolder, *.hlsl
      Register-ObjectEvent $watcher Changed -SourceIdentifier FileChanged -Action { &$scriptPath -HlslPath $Event.SourceEventArgs.FullPath } > $null
   
      Write-Host "Run with the '-Unregister' switch to turn off the file watcher."
   }

   exit 0
}

if ($null -ne $HlslPath)
{
   CompileHlslFile $HlslPath
   Write-Host "`nTo exit file watching, type: exit <Enter>"
   exit 0
}

# test action in debugger
if ($false)
{
   Write-Host "(Hard-coded to test CompileHlslFile code)"
   CompileHlslFile C:\Users\bryan\Source\repos\InstantPhotoBooth4\Effects.UWP\Shaders\FragmentShader.hlsl
#   Write-Host "(Hard-coded to test CompileHlslFile code)"
#   CopyFshFile $fshShaderFileName
   exit 0
}

# default action is to show status
ShowStatus
