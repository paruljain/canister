Powershell Webserver
====================

A micro, around 100 lines, of pure PowerShell standalone webserver designed to create RESTful APIs. Embed it in your application to enable rich web based user interface. Does not need IIS.

Setup
-----
Requires PowerShell 3.0 or better, and .Net 4.5 or better. Enable your Windows system to run PowerShell scripts by running the following command on a privileged command prompt:

    powershell set-executionpolicy unrestricted
    
Allow using a TCP/IP port for HTTP on your system by running the following command on a privileged command prompt:

    netssh http add urlacl url=http://+:8000/ user=myComputername\myUsername
    
Optionally permit inbound port TCP 8000 on Windows Firewall to use the web server from other computers.

Test Drive
----------
Run the sample.ps1 script. From any web browser on the same computer browse to the following:

    http://localhost:8000/hello
    http://localhost:8000

