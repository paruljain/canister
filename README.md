Powershell Webserver
====================

A micro standalone webserver designed to create RESTful APIs.

Enable your Windows system to run PowerShell scripts by running the following command on a privileged command prompt:

    powershell set-executionpolicy unrestricted
    
Allow using a TCP/IP port for HTTP on your system by running the following command on a privileged command prompt:

    netssh http add urlacl url=http://+:8000/ user=myComputername\myUsername
    
Optionally permit inbound port TCP 8000 on Windows Firewall to use the web server from other computers

Here is a script that will get your started:

    $scriptPath = Split-Path -parent $MyInvocation.MyCommand.Definition
    
    . "$scriptPath\WebServer.ps1"
    
    $handlers = @()
    
    function FileServer ($request, $response) {
        if ($request.RawUrl -eq '/') { $filename = '/index.html' }
        else { $filename = $request.RawUrl }
        $filename = $filename -replace '/', '\'
        $response.SendFile($scriptPath + $filename)
    }
    
    function HelloWorld ($request, $response) {
        $response.SendText('Hello World')
    }
    
    $handlers += @{route='^/hello$'; handler='HelloWorld'; method='GET'}
    $handlers += @{route='^/'; handler='FileServer'; method='GET'}
    WebServer-Start -handlers $handlers -log File
    
