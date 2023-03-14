package com.electriccloud.specs

import spock.lang.Shared
import spock.lang.Unroll

class ProcessWebHookSchedulesPipelines extends Helper {

    @Shared
    def projectName = PREFIX + ' ProcessWebHookSchedules Pipelines'
    @Shared
    def pipelineName = 'webhookPipeline'
    @Shared
    def scheduleName = 'PipelineSchedule'
    @Shared
    def webhookData = [commit: 'test']
    @Shared
    def searchParams = [param1: '1']

    def doSetupSpec() {
        deleteAllProjects()
    }

    @Unroll
    def 'runs pipelines #schedulePipelineName, #scheduleProjectName'() {
        setup:
        def scheduleName = PREFIX + ' WebHook Schedule Pipeline'
        def searchParams = [param1: '1']
        loadPipeline(pipelineProjectName, pipelineName, 'sleep 1')
        loadPipelineWebhookSchedule(scheduleProjectName, scheduleName, schedulePipelineName, searchParams)
        cleanPipelineRuns(pipelineProjectName, pipelineName)
        when:
        def result = processWebHookSchedules(webhookData, searchParams)
        then:
        logger.info result.logs
        def runs = findPipelineRuns(pipelineProjectName, pipelineName)
        assert runs.size() == 1
        cleanup:
        cleanPipelineRuns(pipelineProjectName, pipelineName)
        deleteSchedule(scheduleProjectName, scheduleName)
        where:
        schedulePipelineName                             | scheduleProjectName                 | pipelineProjectName
        pipelineName                                     | projectName                         | projectName
        "/projects/$projectName/pipelines/$pipelineName" | PREFIX + ' PipelineScheduleProject' | projectName
    }

    @Unroll
    def 'checks duplicates for pipelines runDuplicates == #runDuplicates'() {
        setup:
        def scheduleName = PREFIX + ' WebHook Schedule Pipeline'
        def searchParams = [param1: '1']
        loadPipeline(projectName, pipelineName, 'sleep 100')
        loadPipelineWebhookSchedule(projectName, scheduleName, pipelineName, searchParams)
        cleanPipelineRuns(projectName, pipelineName)
        dsl "setProperty propertyName: '/projects/$projectName/schedules/$scheduleName/ec_customEditorData/ec_runDuplicates', value: '$runDuplicates'"
        processWebHookSchedules(webhookData, searchParams)
        assert findPipelineRuns(projectName, pipelineName).size() == 1
        when:
        def result = processWebHookSchedules(webhookData, searchParams)
        println result.logs
        then:
        if (runDuplicates == '1' || runDuplicates == 'true') {
            assert findPipelineRuns(projectName, pipelineName).size() > 1
            assert result.logs =~ /Launched pipeline /
        }
        else {
            assert findPipelineRuns(projectName, pipelineName).size() == 1
            assert result.logs =~ /will not run again/
        }

        cleanup:
        ef.abortAllPipelineRuns(projectName: projectName, pipelineName: pipelineName)
        cleanPipelineRuns(projectName, pipelineName)
        deleteSchedule(projectName, scheduleName)
        where:
        runDuplicates << ['0', '1', 'true', 'false']
    }

    @Unroll
    def 'quiet time #quietTime minutes'() {
        setup:
        def searchParams = [quietTime: 'true']
        def scheduleName = PREFIX + ' WebHook Schedule Pipeline QuietTime'
        def pipelineName = 'WebHook Quiet Time'
        loadPipeline(projectName, pipelineName, 'sleep 1')
        loadPipelineWebhookSchedule(projectName, scheduleName, pipelineName, searchParams)
        cleanPipelineRuns(projectName, pipelineName)
        setScheduleParam(projectName, scheduleName, 'ec_quietTime', quietTime)
        when: 'webhook processor is launched'
        def result = processWebHookSchedules(webhookData, searchParams)
        assert result.outcome == 'success'
        logger.info result.logs
        then: 'there is no pipeline runs'
        findPipelineRuns(projectName, pipelineName).size() == 0
        and: 'there is schedule created in Electric Cloud project'
        def expectedScheduleName = "$projectName-$scheduleName-Webhook-Queue"
        assert getSchedule('Electric Cloud', expectedScheduleName)
        and: 'the pipeline is launched after quiet time'
//        This test may be unstable due to time frames
        System.sleep((quietTime * 60 + 1) * 1000)
        assert findPipelineRuns(projectName, pipelineName).size() == 1
        where:
        quietTime << [1]
    }

    def 'quiet time with burst'() {
        setup:
        def searchParams = [quietTime: 'true']
        def scheduleName = PREFIX + ' WebHook Schedule Pipeline QuietTime'
        def quietTime = 2
        def attempts = 2
        def pipelineName = 'WebHook Quiet Time'
        loadPipeline(projectName, pipelineName, 'sleep 1')
        loadPipelineWebhookSchedule(projectName, scheduleName, pipelineName, searchParams)
        cleanPipelineRuns(projectName, pipelineName)
        setScheduleParam(projectName, scheduleName, 'ec_quietTime', quietTime)
        setScheduleParam(projectName, scheduleName, 'ec_maxRetries', attempts)
        when: 'webhook processor is launched'
        processWebHookSchedules(webhookData, searchParams)
        then: 'there is no pipeline runs'
        findPipelineRuns(projectName, pipelineName).size() == 0
        for(int i = 0; i < attempts-1; i++) {
            processWebHookSchedules(webhookData, searchParams)
        }
        def latestData = [latest: true]
        def latestResult = processWebHookSchedules(latestData, searchParams)
        println latestResult
        assert latestResult.logs =~ /Max attempts for queue reached, launching anyway/
        assert findPipelineRuns(projectName, pipelineName).size() == 1

    }

    def deleteSchedule(projectName, scheduleName) {
        dsl "deleteSchedule projectName: '$projectName', scheduleName: '$scheduleName'"
    }


}
