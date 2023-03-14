package com.electriccloud.specs.sentry

import com.electriccloud.specs.Helper
import spock.lang.Ignore
import spock.lang.Shared
import spock.lang.Unroll

//TODO parameters
class Pipelines extends Helper {
    @Shared
    def projectName = PREFIX + 'SentrySchedule Pipeline'
    @Shared
    def pipelineNameShared = 'SentryPipeline'
    @Shared
    def scheduleName = 'PropSchedulePipeline'

    def doSetupSpec() {
        deleteAllProjects()
    }

    @Unroll
    def 'runs on property change pipeline name:  schedule project name: #scheduleProjectName'() {
        setup:
        def pipelineName = randomize(pipelineNameShared)
        def schedulePipelineName = schedulePipelineNameClosure(pipelineName)
        loadPipeline(projectName, pipelineName, 'echo 1')
        cleanPipelineRuns(projectName, pipelineName)
        loadSchedule(scheduleProjectName, scheduleName, schedulePipelineName)
        when:
        touchProperty(scheduleProjectName, 'trigger')
        def result = runSentry(scheduleProjectName)
        then:
        def runs = findPipelineRuns(projectName, pipelineName)
        assert runs.size() == 1
        cleanup:
        cleanPipelineRuns(projectName, pipelineName)
        where:
        scheduleProjectName     | schedulePipelineNameClosure
        projectName             | { it -> it }
        "$projectName Schedule" | { it -> "/projects/$projectName/pipelines/$it" }
    }

    @Unroll
    def 'does not run duplicate #scheduleProjectName #schedulePipelineName'() {
        setup:
        def pipelineName = randomize(pipelineNameShared)
        def schedulePipelineName = schedulePipelineNameClosure(pipelineName)
        loadPipeline(projectName, pipelineName, 'sleep 100')
        def triggerName = 'longTrigger'
        loadSchedule(scheduleProjectName, scheduleName, schedulePipelineName, null, null, triggerName)
        cleanPipelineRuns(projectName, pipelineName)
        when:
        touchProperty(scheduleProjectName, triggerName)
        runSentry(scheduleProjectName)
        then:
        def runs = findPipelineRuns(projectName, pipelineName)
        assert runs.size() == 1
        touchProperty(scheduleProjectName, triggerName)
        def result = runSentry(scheduleProjectName)
        println result.logs
        and:
        def secondRuns = findPipelineRuns(projectName, pipelineName)
        assert secondRuns.size() == 1
        cleanup:
        ef.abortAllPipelineRuns(projectName: projectName, pipelineName: pipelineName)
        where:
        scheduleProjectName     | schedulePipelineNameClosure
        projectName             | { it -> it }
        "$projectName Schedule" | { it -> "/projects/$projectName/pipelines/$it" }
    }
}
