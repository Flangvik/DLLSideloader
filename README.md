# DLLSideloader
PowerShell script to generate "proxy" counterpart of DLL files load unsafely by binaries on runtime, makes it super easy to perform  a DLL Sideloading attack or hijacking  

See the below articles for more details  
https://flangvik.com/privesc/windows/bypass/2019/06/25/Sideload-like-your-an-APT.html  
https://flangvik.com/2019/07/24/Bypassing-AV-DLL-Side-Loading.html

Both demo's are using GUP.exe signed from NotePad ++ (32bit), loading a malicious libcurl sideloading malware:  

Sideloading payload.dll( meterpreter revshell)
![Meterpreter sideload](https://github.com/SkiddieTech/DLLSideloader/blob/master/dll-sideload-demogif.gif)


Loading C++ code getting revshell and bypassing AV's

[![AV Bypass](https://img.youtube.com/vi/pWJ_pd0QhFM/maxresdefault.jpg)](https://youtu.be/pWJ_pd0QhFM)
