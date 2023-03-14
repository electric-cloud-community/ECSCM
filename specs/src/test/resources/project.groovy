def triggerName = args.triggerName ?: 'trigger'

project args.projectName, {

    schedule args.scheduleName, {
        if (args.procedureName) {
            procedureName = args.procedureName
        }
        else if (args.pipelineName) {
            pipelineName = args.pipelineName
        }
        else if (args.releaseName) {
            releaseName = args.releaseName
        }

        property 'ec_customEditorData', {
            TriggerFlag = '2'
            TriggerPropertyName = '/projects/' + args.projectName + '/' + triggerName
            formType = '$[/plugins/ECSCM-Property/project/scm_form/sentry]'
            scmConfig = 'Property'
            QuietTimeMinutes = '0'
        }

        if (args.pipelineName) {
            actualParameter 'ec_stagesToRun', '["Stage 1"]'
        }
    }


    schedule 'ECSCM-SentryMonitor', {
        procedureName = '/plugins/ECSCM/project/procedures/ElectricSentry'
        actualParameter 'projectList', args.projectName
        actualParameter 'sentryResource', 'local'
    }

}