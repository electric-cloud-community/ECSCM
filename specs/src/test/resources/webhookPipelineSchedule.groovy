deleteSchedule projectName: args.projectName,
               scheduleName: args.scheduleName

project args.projectName, {

    schedule args.scheduleName, {

        pipelineName = args.pipelineName

        property 'ec_customEditorData', {
            property 'TriggerFlag', value: '3'
            args.searchParams.each { k, v ->
                property k.toString(), value: v.toString()
            }

        }

        property 'ec_triggerType', value: 'webhook'
    }
}
