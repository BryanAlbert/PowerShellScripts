# Watches $sourcePath with a file watcher, runs itself with this path and $targetDir 
# to copy the source to the Shader folder on the target. Since the tablet can't be 
# mounted, we use a Shell.Application COM object to find the target folder and perform
# the copy. Since the flags on the CopyHere method don't work, we can't force the 
# COM object to overwrite the file without a confirmation doalog, so we copy to a
# Pending folder instead with the understanding that the Android app consuming the 
# target file will first move it from the Pending folder to the Shaders folder. Note 
# that the copy goes to the Shaders folder if a previous version of the target file 
# doesn't exist, else to the Pending folder. Folders are created as necessary. 

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
      # create the Pending folder if the target exists in Shaders, delete the target if it exists in Pending
      $target = GetDirectory $target "Pending"
      $targetDir += "\Pending"

      $file = $target.Items() | Where-Object { $_.Name -eq $sourceFileName }
      if ($null -ne $file)
      {
         # the 0x10 flag (overwrite) on CopyHere doesn't work, so... delete the file manually if it exists (gives a warning)
         Write-Host "File '$sourceFileName' exists in the Pending folder, deleting (confirmation dialog will be displayed)"
         $file.InvokeVerb("Delete")
      }
   }

   Write-Host "Copying '$sourcePath' to '$targetDir'"
   $target.CopyHere($source)
   Write-Host "$sourceFileName modified date: $modifiedDate"
}

if ($args.Count -eq 2)
{
   CopyFile $sourcePath $targetDir
   return
}


# keep these in scope for the file watcher's execution of WatchShaderFile.ps1
$global:scriptPath = $MyInvocation.MyCommand.Definition
$global:sourceFolderPath = Split-Path $sourcePath -Parent
$global:sourceFileName = Split-Path $sourcePath -Leaf

if ($args[0] -eq "unregister")
{
   UnRegisterEventSubscriber $scriptPath
   return
}

if ($false)
{
   # test in debugger
   CopyFile $sourcePath $targetDir
   return
}

UnRegisterEventSubscriber $scriptPath

Write-Host "Registering FileChanged event subscriber to watch '$sourceFilename' in '$sourceFolderPath'"
Write-Host "and run '$scriptPath' when it changes..."
$fsw = New-Object System.IO.FileSystemWatcher (Split-Path $sourcePath -Parent), (Split-Path $sourcePath -Leaf) 
Register-ObjectEvent $fsw Changed -SourceIdentifier FileChanged -Action { &$scriptPath $sourcePath $targetDir } > $null
