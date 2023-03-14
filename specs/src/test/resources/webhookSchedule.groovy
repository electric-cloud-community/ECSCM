deleteSchedule projectName: args.projectName,
    scheduleName: args.scheduleName

project args.projectName, {

    schedule args.scheduleName, {

        procedureName = args.procedureName

        property 'ec_customEditorData', {
            property 'TriggerFlag', value: '3'
            args.searchParams.each { k, v ->
                property k.toString(), value: v.toString()
            }

        }

        property 'ec_triggerType', value: 'webhook'
    }
}
