Powershell Webserver
====================

A micro standalone webserver designed to create RESTful APIs.

Enable your Windows system to run PowerShell scripts by running the following command on a privileged command prompt:

    powershell set-executionpolicy unrestricted
    
Allow using a TCP/IP port for HTTP on your system by running the following command on a privileged command prompt:

    netssh http add urlacl url=http://+:8000/ user=myComputername\myUsername
    
Optionally permit inbound port TCP 8000 on Windows Firewall to use the web server from other computers.

Now run the sample.ps1 script. From any web browser on the same computer where the script is running browse to the following:

        http://localhost:8000/hello
        http://localhost:8000

