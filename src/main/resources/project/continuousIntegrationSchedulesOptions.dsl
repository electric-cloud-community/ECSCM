import com.electriccloud.domain.FormalParameterOptionsResult

def result = new FormalParameterOptionsResult()

def selectedProject = args.parameters['ciProjectName']

if (selectedProject) {
    def schedules = getSchedules(projectName: selectedProject)

    schedules.sort{it.scheduleName}.each{ it ->
        def isCISchedule = !it.ec_triggerType &&
                (it.ec_customEditorData?.TriggerFlag?.value == '2' ||
                        it.ec_customEditorData?.TriggerFlag?.value == '0')
        if (isCISchedule) {
            def enabled = it.ec_customEditorData.TriggerFlag.value == '2'
            def suffix = enabled ? "" : " (currently disabled)"
            result.add(it.scheduleName, it.scheduleName + suffix)
        }
    }
}

result
