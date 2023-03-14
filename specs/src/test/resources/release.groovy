project args.projectName, {

    release args.releaseName, {
        description = ''
        plannedEndDate = '2018-12-05'
        plannedStartDate = '2018-11-21'

        pipeline args.releaseName, {
            enabled = '1'
            pipelineRunNameTemplate = null
            type = null

            formalParameter 'ec_stagesToRun', defaultValue: null, {
                expansionDeferred = '1'
                label = null
                orderIndex = null
                required = '0'
                type = null
            }

            stage 'Stage1', {
                colorCode = null
                completionType = 'auto'
                waitForPlannedStartDate = '0'

                gate 'PRE', {
                    condition = null
                    precondition = null
                }

                gate 'POST', {
                    condition = null
                    precondition = null
                }

                task 'Task', {
                    description = ''
                    actualParameter = [
                        'commandToRun': args.command,
                    ]
                    advancedMode = '0'
                    afterLastRetry = null
                    alwaysRun = '0'
                    enabled = '1'
                    errorHandling = 'stopOnError'
                    insertRollingDeployManualStep = '0'
                    skippable = '0'
                    subpluginKey = 'EC-Core'
                    subprocedure = 'RunCommand'
                    subprocess = null
                    subproject = null
                    subrelease = null
                    subreleasePipeline = null
                    subreleasePipelineProject = null
                    subreleaseSuffix = null
                    subservice = null
                    subworkflowDefinition = null
                    subworkflowStartingState = null
                    taskProcessType = null
                    taskType = 'COMMAND'
                    triggerType = null
                    waitForPlannedStartDate = '0'
                }
            }

        }
    }
}