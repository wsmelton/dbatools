function Sync-DbaAgentJob {
    <#
        .SYNOPSIS
            Sync-DbaAgentJob synchronizes a job between one or more sql server instances

        .DESCRIPTION
            Sync-DbaAgentJob is able to synchronize a job between one or more sql server instances.
            It will check the differences from the source job with the jobs on the other instance(s).
            it will also check the schedules and steps and make sure they're all alike.

        .PARAMETER SourceSqlInstance
            SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

        .PARAMETER DestinationSqlInstance
            SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

        .PARAMETER SourceSqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER DestinationSqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Job
            The name of the job.

        .PARAMETER ExcludeSchedule
            Exclude synchronizing the schedule(s)

        .PARAMETER ExcludeStep
            Exclude synchronizing the step(s)

        .PARAMETER Mode
            Default: Strict
            How strict does the command take lesser issues?
            Strict: Interrupt if the job specified doesn't exist.
            Lazy:   Silently skip over jobs that don't exist.

        .PARAMETER WhatIf
            Shows what would happen if the command were to run. No actions are actually performed.

        .PARAMETER Confirm
            Prompts you for confirmation before executing any changing operations within the command.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Author: Sander Stad (@sqlstad, sqlstad.nl)
            Tags: Agent, Job

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Sync-DbaAgentJob

        .EXAMPLE

    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Low")]

    param(
        [parameter(Mandatory = $true)]
        [DbaInstanceParameter]$SourceSqlInstance,
        [parameter(Mandatory = $true)]
        [DbaInstanceParameter[]]$DestinationSqlInstance,
        [PSCredential]$SourceSqlCredential,
        [PSCredential]$DestinationSqlCredential,
        [Parameter(ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [object[]]$Job,
        [switch]$ExcludeSchedule,
        [switch]$ExcludeStep,
        [DbaMode]$Mode = (Get-DbaConfigValue -Name 'message.mode.default' -Fallback "Strict"),
        [switch]$EnableException
    )

    process {
        Write-Message -Level Verbose -Message "Connecting to source instance $SourceSqlInstance"
        try {
            $sourceServer = Connect-SqlInstance -SqlInstance $SourceSqlInstance -SqlCredential $SourceSqlCredential
        }
        catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SourceSqlInstance -Continue
        }

        # Get the entire collection of jobs in one go
        $jobCollection = @()
        $jobCollection = $sourceServer.JobServer.Jobs | Where-Object {$_.Name -in $Job}

        # Check if any jobs have been found
        if ($jobCollection.Count -eq 0) {
            switch ($Mode) {
                'Lazy' {
                    Write-Message -Level Verbose -Message "No jobs found on $SourceSqlInstance that describe the value from -Job" -Target $SourceSqlInstance
                }
                'Strict' {
                    Stop-Function -Message "No jobs found on $SourceSqlInstance that describe the value from -Job" -Continue -ContinueLabel main -Target $SourceSqlInstance -Category InvalidData
                }
            }

        }

        # Loop through each destination instance
        foreach ($instance in $DestinationSqlInstance) {
            Write-Message -Level Verbose -Message "Connecting to destination instance $instance"
            try {
                $destinationServer = Connect-SqlInstance -SqlInstance $instance -SqlCredential $DestinationSqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            # Loop through the jobs
            foreach ($job in $jobCollection) {
                # Check if the job is present on the destination server
                if ($destinationServer.JobServer.Jobs.Name -notcontains $job.Name) {
                    switch ($Mode) {
                        'Lazy' {
                            Write-Message -Level Verbose -Message "No jobs found on $instance that describe the value from -Job" -Target $instance
                        }
                        'Strict' {
                            Stop-Function -Message "No jobs found on $instance that describe the value from -Job" -Continue -ContinueLabel main -Target $instance -Category InvalidData
                        }

                    } # switch message mode

                } # end if server contains job
                else {
                    # Get the destination job
                    #$destJob = $destinationServer.JobServer.Jobs | Where-Object {$_.Name -contains $job.Name}

                    ##### !!!! ONLY FOR TESTING PURPOSES ON SAME MACHINE !!!!####
                    $destJob = Get-DbaAgentJob -SqlInstance $SourceSqlInstance -Job TestJob2
                    #############################################################

                    Write-Message -Level Verbose -Message "Start synchronizing job $($destJob.Name)"

                    try {
                        Set-DbaAgentJob -SqlInstance $instance -Job $destJob.Name -SqlCredential $DestinationSqlCredential -Enabled $job.Enabled -Description $job.Description -Category $job.Category -OwnerLogin $job.OwnerLoginName -EventLogLevel $job.EventLogLevel -EmailLevel $job.EmailLevel -NetsendLevel $job.NetsendLevel -PageLevel $job.PageLevel -EmailOperator $job.EmailOperator -NetsendOperator $job.NetsendOperator -PageOperator $job.PageOperator -DeleteLevel $job.DeleteLevel -EnableException
                    }
                    catch {
                        switch ($Mode) {
                            'Lazy' {
                                Write-Message -Level Verbose -Message "Couldn't set details for job $($job.Name)" -Target $instance
                            }
                            'Strict' {
                                Stop-Function -Message "Couldn't set details for job $($job.Name)" -Continue -ContinueLabel main -Target $instance
                            }

                        } # switch message mode
                    }

                    # Check if the schedules need to be synchronized too
                    if (-not $ExcludeSchedule) {
                        # Get all the job schedules
                        $jobSchedules = $job.JobSchedules

                        # Check if there are any job schedules
                        if($jobSchedules.Count -eq 0){
                            Write-Message -Level Verbose -Message "No schedules found for job $($destJob.Name)" -Target $instance
                        }

                        # Try to remove all job schedules
                        try {
                            $destJob.RemoveAllJobSchedules()
                        }
                        catch {
                            switch ($Mode) {
                                'Lazy' {
                                    Write-Message -Level Verbose -Message "Couldn't remove schedules for job $($job.Name)" -Target $instance
                                }
                                'Strict' {
                                    Stop-Function -Message "Couldn't remove schedules for job $($job.Name)" -Continue -ContinueLabel main -Target $instance
                                }

                            } # switch message mode
                        }

                        Write-Message -Level Verbose -Message "Start synchronizing schedules"

                        # Loop through each of the job schedules
                        foreach($schedule in $jobSchedules){
                            $null = New-DbaAgentSchedule -SqlInstance $instance -SqlCredential $DestinationSqlCredential -Job $destJob -Schedule $schedule.Name -FrequencyType $schedule.FrequencyTypes -Disabled:(-not $schedule.IsEnabled) -FrequencyInterval $schedule.FrequencyInterval -FrequencyRecurrenceFactor $schedule.FrequencyInterval -FrequencySubdayType $schedule.FrequencySubdayTypes -FrequencySubdayInterval $schedule.FrequencyInterval -FrequencyRelativeInterval $schedule.FrequencyRelativeIntervals -StartDate $schedule.ActiveStartDate.ToString("yyyyMMdd") -EndDate $schedule.ActiveEndDate.ToString("yyyyMMdd") -StartTime ($schedule.ActiveEndTimeOfDay).ToString().Replace(":", "") -EndTime ($schedule.ActiveEndTimeOfDay).ToString().Replace(":", "")
                        }

                    }

                    # Check if the steps need to be synchronized
                    if (-not $ExcludeStep) {
                        # Get all the job schedules
                        $jobSteps = $job.JobSteps

                        # Check if there are any job schedules
                        if($jobSteps.Count -eq 0){
                            Write-Message -Level Verbose -Message "No steps found for job $($job.Name)" -Target $instance
                        }

                        # Try to remove all job schedules
                        try {
                            $destJob.RemoveAllJobSteps()
                        }
                        catch {
                            switch ($Mode) {
                                'Lazy' {
                                    Write-Message -Level Verbose -Message "Couldn't remove steps for job $($job.Name)" -Target $instance
                                }
                                'Strict' {
                                    Stop-Function -Message "Couldn't remove steps for job $($job.Name)" -Continue -ContinueLabel main -Target $instance
                                }

                            } # switch message mode
                        }

                        # Loop through each of the job schedules
                        Write-Message -Level Verbose -Message "Start synchronizing steps"

                        foreach($step in $jobSteps){
                            $null = New-DbaAgentJobStep -SqlInstance $instance -SqlCredential $DestinationSqlCredential -Job $destJob -StepId $step.ID -StepName $step.Name -Subsystem $step.Subsystem -Command $step.Command -OnSuccessAction $step.OnSuccessAction -OnSuccessStepId $step.OnSuccessStepId -OnFailAction $step.OnFailAction -OnFailStepId $step.OnFailStepId -Database $step.DatabaseName -DatabaseUser $step.DatabaseUserName -CmdExecSuccessCode $step.CommandExecutionSuccessCode -RetryAttempts $step.RetryAttempts -RetryInterval $step.RetryInterval -OutputFileName $step.OutputFileName -Flag $step.JobStepFlags -ProxyName $step.ProxyName
                        }
                    }

                }

            } # for each job

        } # for each destinaton server

    } # process

    end {
        Write-Message -Level Verbose -Message "Finished synchronizing jobs" -Target $SourceSqlInstance
    }
}