<#
    vSphere 5.0 workaround for CBT bug when VMDK size is > 127GB
    Deploys the workaround in a throttled manner so as to not overwhelm vCenter or Backup
    
    Parul Jain
    CATE Storage and Backup Engineering
    parul.k.jain@citi.com
    Version 1.5

Pre-requisities
---------------

* vSphere 5.0 clusters that need remediation

* One or more vCenter instances managing the clusters that need to be fixed

* Windows desktop or server (here after referred to as "workstation") with:

    - PowerCLI: any version less than 3 years old; latest recommended
        To check PowerCLI version start PowerCLI from start menu and look at the title bar

    - PowerShell 2.0 or better
        To check PowerShell version run the following from command prompt:
            c:\> powershell get-host

    - Administrative access to enable running of PowerShell scripts

* Administrative access to all resources in the vSphere cluster

What is PowerShell?
-------------------
General purpose scripting language for Windows that replaces batch files and visual basic (VBS) scripts. Powershell
comes standard with Windows 7, 2008, and 2012 operating systems

What is PowerCLI?
-----------------
PowerCLI is a library for PowerShell from vmware that makes it easy to write PowerShell scripts to control
vSphere and vCenter

Setup
-----

* From a privileged command prompt on the workstation, execute the following:
    C:\> powershell set-executionpolicy unrestricted

    This only needs to be done once on the workstation

* Create a folder for the script and copy the script there. For purpose of this document
    we will assume that the folder where script is located is C:\myFolder

* From command prompt, start PowerShell

    C:\myFolder> powershell

* Load the script (notice the PowerShell prompt is prefixed with PS)

    PS C:\myFolder> import-module .\cbtfix.psm1 -DisableNameChecking

* Connect to vCenter server managing the cluster(s) where you want to apply the fix, Note
    that the username should be an administrator for resources in the cluster
    
    PS C:\myFolder> Connect-VIServer -server myVCserver.nam.nsroot.net -user aa12345 -password mypass

    This may take upto a minute. Ignore any warning messages. If you fail to connect, please troubleshoot with
    vmware support

The Fix
-------
For all VMs that have (1) CBT turned on and (2) at least one VMDK greater than 127GB size, the
following must occur:
    
    Step 1: Disable change block tracking (CBT). This is a virtual machine reconfigure operation
    Step 2: Take a snapshot of the virtual machine
    Step 3: Remove the snapshot taken in Step 2

Approach
--------
As a one time task, Virtual machines in the specified cluster that match the above criteria are listed
and stored into a file named inventory.csv in the folder where this script is located.

There after the Apply-Fix command is issued. The command reads virtual machines to fix from the inventory.
As machines get fixed, the inventory is updated so that machines do not get remediated repeatedly
across runs.

For each run of Apply-Fix, you can specify maximum number of simultaneous tasks outstanding against vCenter,
as well as the number of virtual machines to process. Because inventory is updated after each run, Apply-Fix
will pick the next set of virtual machines to fix on each run

Performance (Load) Concerns
---------------------------
* Backup
    The fix will force the next backup to be a full backup. By running small batches of fix every day, you can
    limit the backup load that night. The default setting is 100 virtual machines per run
 
* vCenter
    You can limit the maximum number of outstanding active tasks ordered by the script to keep vCenter from
    choking. The downside is that fewer simultaneous tasks means longer time to remediation. You can vary
    the number of parallel tasks for each run to strike a balance between vCenter load and average time taken
    to fix each virtual machine. The default setting is 20 tasks

* vSphere storage (datastores)
    Per vmware, the only performace concern related to snapshots is that increasing number of snapshots
    for a virtual machine reduce performance of that virtual machine. This is not applicable for this
    fix as only one snapshot is being created

Inventory.csv
-------------

Here is the meaning of the TaskStep:

    -1: Indicates that there was an error. See ErrorMsg for reason. The ErrorMsg starts with a numeric code which is
        the step number at which the error occured

    0: THis virtual machine is yet to be processed

    1: Task to disable CBT was submitted to vCenter

    2: Task to disable CBT completed successfully

    3: Task to create snapshot was submitted

    4: Task to create snapshot completed successfully

    5: Task to remove snapshot was submitted

    6: Task to remove snapshot completed successfully. Fix complete

Deploying the Fix
-----------------
Use the following commands on the PowerShell prompt started in the Setup section above after you are connected to
vCenter.

Step 1: Create an inventory of impacted virtual machines in the cluster (one time task):

	PS C:\myFolder> Get-ImpactedVMs -clusterName myCluster | Ready-VM | Save-Inventory

Step 2: Deploy the fix to a certain count of machines. Repeat this command every day

    PS C:\myFolder> Apply-Fix -parallelTasks 20 -count 100

After the command completes, examine the inventory.csv file for any errors

Notes
-----
* The progress bar indicates overall remediation, not this run's progress
* Do NOT open inventory.csv with Excel while the script is running. Excel will block access to the file from the
    script causing the script to fail. It is safe to open this file with Notepad while the script is running to
    track progress if required

#>

if ( (Get-PSSnapin -Name vmware.vimautomation.core -ErrorAction SilentlyContinue) -eq $null )
{
    Add-PsSnapin vmware.vimautomation.core
}

$ErrorActionPreference = 'Stop'
$scriptPath = Split-Path -parent $MyInvocation.MyCommand.Definition

function Get-ImpactedVMs ([string]$clusterName) {
    # Logic to select VMs that need to be processed
    # It can be any logic that outputs one or more VM objects
    foreach ($vm in @(Get-Cluster $clusterName | Get-VM)) {
        if ($vm.ExtensionData.Config.ChangeTrackingEnabled) {
            foreach ($disk in @($vm | Get-HardDisk)) {
                if ($disk.CapacityGB -gt 127) {
                    $vm
                    break
                }
            }
        }
    }
}

function Ready-VM {
    # Gets VMs ready for processing by this script
    Process {
        $vmObject = '' | select vm, VMName, errorMsg, taskStep, task
        $vmObject.vm = $_
        $vmObject.VMName = $_.Name
        $vmObject.errorMsg = $null
        $vmObject.taskStep = 0
        $vmObject.task = $null
        $vmObject
    }
}

$spec = New-Object VMware.Vim.VirtualMachineConfigSpec
$spec.ChangeTrackingEnabled = $false 

function Disable-CBTAsync {
    # Must pipe VM objects through Ready-VM before piping to this function
    Process {
        $vmObject = $_
        try {
            $vmObject.task = Get-VIObjectByVIView $vmObject.vm.ExtensionData.ReconfigVM_Task($spec)
            $vmObject.taskStep++
        } catch {
            #throw $_
            $vmObject.errorMsg = $vmObject.taskStep.toString() + ':' + $_.toString()
            $vmObject.taskStep = -1
        }
        $vmObject
    }
}

function Create-SnapAsync {
    # Must pipe VM objects through Ready-VM before piping to this function
    Process {
        $vmObject = $_
        try {
            $vmObject.task = $vmObject.vm | New-Snapshot -Name 'Disable CBT' -RunAsync
            $vmObject.taskStep++
        } catch {
            $vmObject.errorMsg = $vmObject.taskStep.toString() + ':' + $_.toString()
            $vmObject.taskStep = -1
        }
        $vmObject
    }
}

function Remove-SnapAsync {
    # Must pipe VM objects through Ready-VM before piping to this function
    Process {
        $vmObject = $_
        try {
            $snap = Get-Snapshot -VM $vmObject.vm -Name 'Disable CBT'
            $vmObject.task = $snap | Remove-Snapshot -confirm:$false -RunAsync
            $vmObject.taskStep++
        } catch {
            $vmObject.errorMsg = $vmObject.taskStep.toString() + ':' + $_.toString()
            $vmObject.taskStep = -1
        }
        $vmObject
    }
}

function Update-TaskStatus {
    # Must pipe VM objects through Ready-VM before piping to this function
    Process {
        $vmObject = $_
        if ($vmObject.task -ne $null) {
            if ($vmObject.task.State -ne 'Success') {
                try {
                    $vmObject.task = Get-Task -Id $vmObject.task.Id
                    if ($vmObject.task.State -notmatch 'Running|Success') {
                        $vmObject.errorMsg = $vmObject.taskStep.toString() + ':' + $vmObject.task.State
                        $vmObject.taskStep = -1
                    } elseif ($vmObject.task.State -eq 'Success') { $vmObject.taskStep++ }
                } catch {
                    $vmObject.errorMsg = $vmObject.taskStep.toString() + ':' + $_.toString()
                    $vmObject.taskStep = -1
                }
            }
        }
        $vmObject
    }
}

function Apply-Fix ($parallelTasks = 20, $count = 100) {
    if ($parallelTasks -gt $count) { $parallelTasks = $count }
    
    $vms = @(Load-Inventory)

    $processedVMCount = 0
    $runningTaskCount = 0
    while ($processedVMCount -lt $count) {
            
        $erroredVMCount = @($vms | where { $_.taskStep -eq -1 }).Count
        $completedVMCount = @($vms | where { $_.taskStep -eq 6 }).Count
        $runningTaskCount =  @($vms | where { $_.task.State -eq 'Running' }).Count

        $startedTaskCount = @($vms | where { $_.taskStep -eq 0 } | select -first ($parallelTasks - $runningTaskCount) | Disable-CBTAsync).Count
        if ($runningTaskCount -eq 0 -and $startedTaskCount -eq 0) { break }

        $processedVMCount += $startedTaskCount
        Write-Progress -Activity 'Applying Fix' -status ('Processed VMs in this run: ' + $processedVMCount.toString()) -percentComplete ($completedVMCount/$vms.Count*100)

        $vms | Save-Inventory
        
        Start-Sleep 10 #seconds
        
        $vms | where { $_.taskStep -ne -1 } | Update-TaskStatus | where { $_.taskStep -eq 2 } | Create-SnapAsync | Out-Null
        $vms | Save-Inventory

        Start-Sleep 10

        $vms | where { $_.taskStep -ne -1 } | Update-TaskStatus | where { $_.taskStep -eq 4 } | Remove-SnapAsync | Out-Null
        $vms | Save-Inventory
            
        Start-Sleep 10
    }
    $vms | where { $_.taskStep -ne -1 } | Update-TaskStatus | Save-Inventory
    write-host 'Done'
}

function Save-Inventory {
    Begin { $export = @() }
    Process {
        $exportObj = '' | select VMName, TaskStep, ErrorMsg
        $exportObj.VMName = $_.vm.Name
        $exportObj.TaskStep = $_.taskStep
        $exportObj.ErrorMsg = $_.errorMsg
        $export += $exportObj
    }
    End { $export | Export-Csv -NoTypeInformation "$scriptPath\inventory.csv" }
}

function Load-Inventory {
    if (!(Test-Path "$scriptPath\inventory.csv")) {
        throw 'Inventory.csv not found in script folder. Did you Save-Inventory?'
    }
    $inventory = Import-Csv "$scriptPath\inventory.csv"
    
    $i = 1
    $inventory | % {
        $vmObject = $_
        Write-Progress -Activity 'Loading Inventory' -status ('Loading ' + $vmObject.VMName) -percentComplete ($i/$inventory.Count*100)

        try {
            $vm = Get-VM -Name $vmObject.VMName 
            $vmObject | Add-Member -MemberType NoteProperty -Name vm -Value $vm
            $vmObject | Add-Member -MemberType NoteProperty -Name task -Value $null
            $vmObject.taskStep = [int]$vmObject.taskStep
            $vmObject # return to caller
        }
        catch { write-host 'VM ' + $vmObject.VMName + ' in inventory was not found on vCenter. It will be deleted from inventory' }
        $i++
    }
}
