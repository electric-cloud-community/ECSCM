package com.electriccloud.specs

import spock.lang.Ignore
import spock.lang.Shared
import spock.lang.Unroll

//TODO pipelines, releases
class ProcessWebHookSchedules extends Helper {

    @Shared
    def projectName = 'ECSCM ProcessWebHookSchedules'
    @Shared
    def procedureName = 'webhookProcedure'
    @Shared
    def scheduleName = 'PropSchedule'
    @Shared
    def webhookData = [commit: 'test']

    def doSetupSpec() {
        deleteAllProjects()
    }

    @Unroll
    def 'run procedure #scheduleProjectName #procedureProjectName'() {
        setup:
        def scheduleName = 'ECSCM WebHook Schedule'
        def searchParams = [param1: '1']
        loadProcedure(procedureProjectName, procedureName)
        loadProcedureWebhookSchedule(scheduleProjectName, scheduleName, scheduleProcedureName, searchParams)
        cleanProcedureRuns(procedureProjectName, procedureName)
        when:
        def result = processWebHookSchedules(webhookData, searchParams)
        then:
        logger.info result.logs
        def runs = findProcedureRuns(procedureProjectName, procedureName)
        assert runs.size() == 1
        def jobId = runs[0].jobId
        def properties = getJobProperties(jobId)
        assert properties.webhookData
        cleanup:
        cleanProcedureRuns(procedureProjectName, procedureName)
        where:
        scheduleProcedureName                              | scheduleProjectName | procedureProjectName
        procedureName                                      | projectName         | projectName
        "/projects/$projectName/procedures/$procedureName" | "schedule project"  | projectName
    }


    @Unroll
    def 'only matching schedule runs #searchParams'() {
        setup:
        def scheduleName = 'ECSCM WebHook Schedule1'
        def secondScheduleName = 'ECSCM WebHook Schedule2'
        loadProcedure(projectName, procedureName)
        loadProcedureWebhookSchedule(projectName, scheduleName, procedureName, scheduleParams)
        loadProcedureWebhookSchedule(projectName, scheduleName, procedureName, [param1: '2'])
        cleanProcedureRuns(projectName, procedureName)
        when:
        def result = processWebHookSchedules({}, searchParams)
        then:
        assert findProcedureRuns(projectName, procedureName).size() == 1
        cleanup:
        cleanProcedureRuns(projectName, procedureName)
        where:
        searchParams  | scheduleParams
        [param1: '1'] | [param1: '1']
        [param1: '1'] | [param1: '*']
    }


    def 'does not run disabled'() {
        setup:
        deleteProject projectName
        loadProcedure(projectName, procedureName)
        def scheduleParams = [
            param1: '1',
        ]
        loadProcedureWebhookSchedule(projectName, scheduleName, procedureName, scheduleParams)
        dsl "setProperty propertyName: '/projects/$projectName/schedules/$scheduleName/ec_customEditorData/TriggerFlag', value: '0'"
        cleanProcedureRuns(projectName, procedureName)
        when:
        def result = processWebHookSchedules({}, [param1: '1'])
        then:
        assert result.logs =~ /is disabled/
        println result.logs
        def runs = findProcedureRuns(projectName, procedureName)
        assert runs.size() == 0
        cleanup:
        cleanProcedureRuns(projectName, procedureName)
    }


}
