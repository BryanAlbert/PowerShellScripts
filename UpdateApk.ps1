# A script for updating files in the SAB apk, extracts or updates the specified file in 
# lib/app-android-common.aar, typically res/layout/fragment_calculator.xml. If that file 
# is in the classes.jar (e.g. org/sil/app/android/common/fragment/CalculatorFragment.class), 
# we first extract common.jar from app-android-common.arr, as necessary. Use Android Studio
# to decompile the .java file into a .class file, which can be edited. 
# 
# With -extract, we extract the file from the appropriate archive(s). If the file is in 
# the classes.jar file, we extract the .java file from the arcive. Use Android Stuido 
# to decompile the .java file into a .class file and edit the .class file. 

# With -update, if the file is a .class file, we first compile it into the associated 
# .java file then update the classes.jar file with that, then update the aar file with that.

param([switch] $List, [switch] $Extract, [switch] $Update, [switch] $Cleanup, [switch] $Build, [string] $Path)


$javaPath = "C:\Program Files\Java\jdk1.8.0_161\bin\"
$silPath = "C:\Program Files (x86)\SIL\Scripture App Builder"
$silPath = "C:\Users\bryan\Source\repos\BTJCalculator"
$sabProject = "Calculator"
$aarFile = "lib/app-android-common.aar"
$jarFile = "classes.jar"

# make sure PATH includes Java
if ($env:Path.IndexOf("\Java\") -lt 0) {
   Write-Host "Adding to `$env:Path: $javaPath"
   $env:Path += ";" + $javaPath
}

#start in SIL directory
Push-Location $silPath


function ListFiles
{
   Push-Location (Split-Path $aarFile)
   $source = Split-Path $aarFile -Leaf
   Write-Host "Listing files in $source`:"
   jar.exe tf $source

   Write-Host "`nListing files in $jarFile`:"
   jar.exe xf $source $jarFile
   jar.exe tf $jarFile
   Remove-Item $jarFile
   Pop-Location
}

function ExtractFile
{
   Push-Location (Split-Path $aarFile)

   if (Test-Path $Path) {
      Remove-Item $Path
   }

   $source = Split-Path $aarFile -Leaf
   if ((jar.exe tf $source $Path) -eq $Path) {
      Write-Host "Extracting $Path from $source"
      jar.exe xf $source $Path
   } else {
      jar.exe xf $source $jarFile
      if (jar.exe tf $jarFile $Path) {
         Write-Host "Extracting $Path from $jarFile"
         jar.exe xf $jarFile $Path
      } else {
         Write-Host "Error: path not found: $Path"
      }

      if ($Path -ne $jarFile) {
         Remove-Item $jarFile
      }
   }

   Pop-Location
}

function UpdateFile
{
   $libFolder = Split-Path $aarFile
   Push-Location ($libFolder)

   if (!(Test-Path $Path)) {
      Write-Host "Error: $Path not found relative to: $(Join-Path $silPath $libFolder)."
      Pop-Location
      Pop-Location
      exit 1
   }

   $source = Split-Path $aarFile -Leaf
   if (jar.exe tf $source $Path -eq $Path) {
      Write-Host "Updating $Path in $aarFile"
      jar.exe uf $source $Path
   } else {
      jar.exe xf $source $jarFile
      if (jar.exe tf $jarFile $Path -eq $Path) {
         Write-Host "Updating $Path in $jarFile"
         jar.exe uf $jarFile $Path
         Write-Host "Updating $jarFile in $aarFile"
         jar.exe uf $source $jarFile
      } else {
         Write-Host "Error: $Path not found."
      }

      Remove-Item $jarFile
   }

   Pop-Location
}

function Build
{
   Write-Host "Building apk..."
   .\sab.bat -Load $sabProject -Build
}

function Cleanup {
   Push-Location (Split-Path $aarFile)
   $source = Split-Path $aarFile -Leaf
   foreach ($file in (jar.exe tf $source)) {
      if ((Test-Path $file) -and ($file[$file.Length - 1] -ne "/")) {
         Write-Host "Deleting file: $file"
         Remove-Item $file
         DeleteEmptyParentFolder $file
      }
   }

   jar.exe xf $source $jarFile
   foreach ($file in (jar.exe tf $jarFile)) {
      if ((Test-Path $file) -and ($file[$file.Length - 1] -ne "/")) {
         Write-Host "Deleting file: $file"
         Remove-Item $file
         DeleteEmptyParentFolder $file
      }
   }

   Remove-Item $jarFile
   Pop-Location
}

function DeleteEmptyParentFolder {
   param ($file)

   $parent = Split-Path $file -Parent
   if ((Get-ChildItem $parent).Count -eq 0) {
      Write-Host "Deleting empty folder $parent"
      Remove-Item $parent
      DeleteEmptyParentFolder $parent
   }
}


# testing in Visual Studio Code (use the .vscode\launch.json file instead...)
# $List = $true
# $Extract = $true
# $Path = "bruce.xml"
# $Update = $true
# $Path = "res/layout/fragment_calculator.xml"
# $Path = "org/sil/app/android/common/fragment/CalculatorFragment.class"
# $Build = $true
# $Cleanup = $true


if (($Extract -or $Update) -and $Path.Length -eq 0) {
   Write-Host "Error: Path must be specified with Extract or Update switch."
   Pop-Location
   exit 1
}

if (!(Test-Path $aarFile)) {
   Write-Host "Error: file $aarFile is missing."
   Pop-Location
   exit 1
}

if ($Path -eq (Split-Path $aarFile -Leaf)) {
   Write-Host "Error: Don't try to extract $aarFile"
   Pop-Location
   exit 1
}

if ($List) {
   ListFiles
}
elseif ($Extract) {
   ExtractFile
}
elseif ($Update) {
   UpdateFile
}
elseif ($Build) {
   Build
}
elseif ($Cleanup) {
   Cleanup
}

Pop-Location
