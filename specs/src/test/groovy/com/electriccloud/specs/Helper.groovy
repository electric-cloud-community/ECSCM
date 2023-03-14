package com.electriccloud.specs

import com.electriccloud.client.groovy.ElectricFlow
import com.electriccloud.client.groovy.models.Filter
import com.electriccloud.spec.PluginSpockTestSupport
import groovy.json.JsonOutput
import spock.util.concurrent.PollingConditions

class Helper extends PluginSpockTestSupport {

    public static final String PREFIX = "ECSCM Spec"

    @Lazy
    ElectricFlow ef = {
        def ef = new ElectricFlow()
        ef.login("${config.protocol}://${config.server}:${config.port}", config.userName, config.password)
        return ef
    }()

    def loadSchedule(projectName, scheduleName, pipelineName = null, releaseName = null, procedureName = null, triggerName = null) {
        String projectDsl = new File(getClass().getResource('/project.groovy').toURI()).text
        dsl(projectDsl, [
            projectName  : projectName,
            pipelineName : pipelineName,
            releaseName  : releaseName,
            procedureName: procedureName,
            scheduleName : scheduleName,
            triggerName  : triggerName,
        ])

    }


    def loadProcedure(projectName, procedureName, command = 'echo 1') {
        String procedureDsl = loadDsl('/procedure.groovy')
        dsl(procedureDsl, [
            projectName  : projectName,
            procedureName: procedureName,
            command      : command
        ])
    }


    def loadPipeline(projectName, pipelineName, command) {
        String pipelineDsl = loadDsl('/pipeline.groovy')
        dsl(pipelineDsl, [
            projectName : projectName,
            pipelineName: pipelineName,
            command     : command
        ])
    }

    def loadRelease(projectName, releaseName, command) {
        String releaseDsl = loadDsl('/release.groovy')
        dsl(releaseDsl, [
            projectName: projectName,
            releaseName: releaseName,
            command    : command
        ])
    }


    def loadDsl(file) {
        String dsl = new File(getClass().getResource(file).toURI()).text
        return dsl
    }

    def runSentry(projectName, ignoreError = false) {
        def result = dsl """
runProcedure(projectName: '$projectName', scheduleName: 'ECSCM-SentryMonitor')
"""

        assert result.jobId
        PollingConditions poll = createPoll(60)
        poll.eventually {
            assert jobStatus(result.jobId).status == 'completed'
        }
        def logs = readJobLogs(result.jobId)
        def outcome = dsl("""getJobStatus(jobId: "${result.jobId}")""").outcome
        if (!ignoreError) {
            assert outcome != 'error'
        }
        return [outcome: outcome, logs: logs]
    }

    def touchProperty(projectName, property) {
        def value = randomize('trigger')
        dsl """
setProperty(projectName: '$projectName', propertyName: '$property', value: '$value')
"""
    }

    def findProcedureRuns(projectName, procedureName) {
        Filter projectFilter = new Filter(propertyName: 'projectName', operator: 'equals', operand1: projectName)
        Filter procedureFilter = new Filter(propertyName: 'procedureName', operator: 'equals', operand1: procedureName)
        return ef.findObjects(objectType: 'job',
                              filters: [new Filter(operator: 'and',
                                                   filter: [projectFilter, procedureFilter])])?.object?.job ?: []
    }

    def cleanProcedureRuns(projectName, procedureName) {
        def runs = findProcedureRuns(projectName, procedureName)
        runs.each {
            ef.deleteJob(jobId: it.jobId)
        }
    }

    def findPipelineRuns(projectName, pipelineName) {
        Filter projectFilter = new Filter(propertyName: 'projectName', operator: 'equals', operand1: projectName)
        Filter pipelineFilter = new Filter(propertyName: 'pipelineName', operator: 'equals', operand1: pipelineName)
        return ef.findObjects(objectType: 'flowRuntime',
                              filters: [new Filter(operator: 'and',
                                                   filter: [projectFilter, pipelineFilter])])?.object?.flowRuntime ?: []
    }


    def findReleaseRuns(projectName, releaseName) {
        Filter projectFilter = new Filter(propertyName: 'projectName', operator: 'equals', operand1: projectName)
        Filter releaseFilter = new Filter(propertyName: 'releaseName', operator: 'equals', operand1: releaseName)
        return ef.findObjects(objectType: 'flowRuntime',
                              filters: [new Filter(operator: 'and',
                                                   filter: [projectFilter, releaseFilter])])?.object?.flowRuntime ?: []

    }

    def cleanPipelineRuns(projectName, pipelineName) {
        def runs = findPipelineRuns(projectName, pipelineName)
        runs.each {
            ef.deletePipelineRun(flowRuntimeId: it.flowRuntimeId, projectName: projectName)
        }
    }


    def cleanReleaseRuns(projectName, releaseName) {
        def runs = findReleaseRuns(projectName, releaseName)
        runs.each {
            ef.deletePipelineRun(flowRuntimeId: it.flowRuntimeId, projectName: projectName)
        }
    }

    def doCleanupSpec() {
        if (System.getenv('CLEANUP_ALL')) {
            deleteAllProjects()
        }
    }


    def deleteAllProjects() {
        def projects = ef.findObjects(objectType: 'project',
                                      filters: [new Filter(operator: 'like',
                                                           propertyName: 'projectName',
                                                           operand1: PREFIX + '%')])?.object?.project
        projects.each {
            ef.deleteProject(projectName: it.projectName)
        }
    }

    def loadProcedureWebhookSchedule(projectName, scheduleName, procedureName, searchParams) {
        def scheduleDsl = loadDsl('/webhookSchedule.groovy')
        dsl(scheduleDsl, [
            projectName  : projectName,
            scheduleName : scheduleName,
            searchParams : searchParams,
            procedureName: procedureName,
        ])
    }

    def loadPipelineWebhookSchedule(projectName, scheduleName, pipelineName, searchParams) {
        def scheduleDsl = loadDsl('/webhookPipelineSchedule.groovy')
        dsl(scheduleDsl, [
            projectName : projectName,
            scheduleName: scheduleName,
            searchParams: searchParams,
            pipelineName: pipelineName,
        ])
    }

    def processWebHookSchedules(webhookData, searchParams) {
        def result = runProcedure('/plugins/ECSCM/project', 'ProcessWebHookSchedules', [
            ec_webhookData                 : JsonOutput.toJson(webhookData),
            ec_webhookSchedulesSearchParams: JsonOutput.toJson(searchParams)
        ])
        assert result.outcome == 'success'
        return result
    }

    def setScheduleParam(projectName, scheduleName, paramName, value) {
        dsl """
setProperty propertyName: '/projects/$projectName/schedules/$scheduleName/ec_customEditorData/$paramName', value: '$value'
"""
    }

    def getSchedule(projectName, scheduleName) {
        return dsl("getSchedule projectName: '$projectName', scheduleName: '$scheduleName'")
    }
}
