# Watches $sourcePath with a file watcher, runs itself with this path and $targetDir 
# to copy the source to the Shader folder on the target. Since the tablet can't be 
# mounted, we use a Shell.Application COM object to find the target folder and perform
# the copy. Since the flags on the CopyHere method don't work, we can't force the 
# COM object to overwrite the file without a confirmation dialog, so we give the file 
# a unique name--the file name with a number appended. The consumer then needs to look 
# for the file with the greatest number. We copy these files to the Pending folder. 

# Note that if the source file is modified in Visual Studio, this script won't work 
# because VS doesn't actually modify the file. Visual Studio Code does, though. 

# TODO: make it work with Visual Studio (watch for file creation?).


param([switch] $Unregister, [switch] $Status)


$targetDir = "Bryan's Galaxy Tab S3\Card\Android\data\com.nfidev.InstantPhotoBooth4\files"
$sourcePath = "C:\temp\IPB4\FragmentShader.fsh"


function UnRegisterEventSubscriber($scriptPath)
{
   $existing = Get-EventSubscriber
   if ($null -ne $existing)
   {
      if ($existing.Action.Command.Trim() -eq "&`$scriptPath `$sourcePath `$targetDir")
      {
         Write-Host "Unregistering existing FileChanged event subscriber..."
         $existing | Unregister-Event
      }
   }
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
   $sourceFolderPath = Split-Path $sourcePath -Parent
   $sourceFileName = Split-Path $sourcePath -Leaf
   $fileName = [System.IO.Path]::GetFileNameWithoutExtension($sourceFileName)
   $extension = [System.IO.Path]::GetExtension($sourceFileName)
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
   $tempFile = Join-Path $sourceFolderPath "$filename$counter$extension"
   Copy-Item $sourcePath $tempFile
   return $tempFile
}

function CopyFile($source, $target)
{
   $sourceFolderPath = Split-Path $sourcePath -Parent
   $sourceFileName = Split-Path $sourcePath -Leaf
   $sourceFolder = (New-Object -ComObject Shell.Application).NameSpace($sourceFolderPath)
   if ($null -eq $sourceFolder)
   {
      Write-Host "Error: source folder '$sourceFolderPath' not found."
      return
   }

   $source = $sourceFolder.Items() | Where-Object { $_.Name -eq $sourceFileName }
   if ($null -eq $source)
   {
      Write-Host "Error: source file '$sourceFileName' not found in '$sourceFolderPath'."
      return
   }

   $modifiedDate = $source.ModifyDate

   $target = (New-Object -ComObject Shell.Application).NameSpace(0x11)
   foreach ($folder in $targetDir.Split("\\"))
   {
   #   $target | ForEach-Object{ $_.Name }
   #   $folder
      $directory = $target.Items() | Where-Object { $_.Name -eq $folder }
      if ($null -eq $directory)
      {
         "Error: folder '$folder' not found in '$targetDir'"
         $target = $null
         return
      }
      $target = $directory.GetFolder()
   }

   # create the Shaders folder as necessary
   $target = GetDirectory $target "Shaders"
   $targetDir = $targetDir + "\Shaders"

   # maintain a global hash contianing the file path and modified date (since ModifyDate on the FolderItem doesn't work)
   if ($null -eq $global:CopyShaderFile)
   {
      $global:CopyShaderFile = @{}
   }
   else
   {
      # if called a second time (as file watcher tends to do) with the same file, return
      if ($CopyShaderFile[$sourcePath] -eq $modifiedDate)
      {
         Write-Host "$sourceFileName modified date: $modifiedDate has not changed, not copying"
         return
      }
   }

   $CopyShaderFile[$sourcePath] = $modifiedDate

   $file = $target.Items() | Where-Object { $_.Name -eq $sourceFileName }
   if ($null -ne $file)
   {
      # create the Pending folder if the target exists in Shaders
      $target = GetDirectory $target "Pending"
      $targetDir += "\Pending"

      $file = $target.Items() | Where-Object { $_.Name -eq $sourceFileName }
      if ($null -ne $file)
      {
         # create a copy of the source with a unique filename if the target exists in Pending
         $uniqueSource = GetUniqueSource $target
         $source = $uniqueSource
      }
   }

   Write-Host "Copying '$sourcePath' to '$targetDir'"
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

   Write-Host "$sourceFileName modified date: $modifiedDate"
}


# source and target specified, copy the file
if ($args.Count -eq 2)
{
   CopyFile $sourcePath $targetDir
   return
}


# keep these in the scope of the WatchShaderFile.ps1 script's caller
$global:scriptPath = $MyInvocation.MyCommand.Definition
$global:sourceFolderPath = Split-Path $sourcePath -Parent
$global:sourceFileName = Split-Path $sourcePath -Leaf


if ($Unregister)
{
   UnRegisterEventSubscriber $scriptPath
   exit 0
}

if ($Status)
{
   Write-Host "Registered Action.Comand for FileChanged event:"
   Get-EventSubscriber | Where-Object{ $_.SourceIdentifier -eq "FileChanged" } | ForEach-Object{ $_.Action.Command }
   Write-Host "Script `$scriptPath: $scriptPath"
   Write-Host "Source: `$sourcePath: $sourcePath"
   Write-Host "Target: `$targetDir: $targetDir"
   Write-Host "Current modified date for '$($CopyShaderFile.Keys)': $($CopyShaderFile[$CopyShaderFile.Keys])"
   exit 0
}

# test in debugger
if ($false)
{
   CopyFile $sourcePath $targetDir
   return
}


UnRegisterEventSubscriber $scriptPath

Write-Host "Registering FileChanged event subscriber to watch '$sourceFilename' in '$sourceFolderPath'"
Write-Host "and run '$scriptPath' when it changes..."
$fsw = New-Object System.IO.FileSystemWatcher (Split-Path $sourcePath -Parent), (Split-Path $sourcePath -Leaf) 
Register-ObjectEvent $fsw Changed -SourceIdentifier FileChanged -Action { &$scriptPath $sourcePath $targetDir } > $null

Write-Host "Run with the '-Unregister' switch to turn off the file watcher."
