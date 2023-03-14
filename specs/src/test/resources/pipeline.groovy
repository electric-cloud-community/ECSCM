project args.projectName, {
    pipeline args.pipelineName, {
        stage 'Stage 1', {

            task 'Task', {
                description = ''
                actualParameter = [
                    'commandToRun': """${args.command}""".toString(),
                ]
                enabled = '1'
                subpluginKey = 'EC-Core'
                subprocedure = 'RunCommand'
                taskType = 'COMMAND'
            }
        }
    }
}



