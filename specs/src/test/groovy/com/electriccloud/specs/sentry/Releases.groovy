package com.electriccloud.specs.sentry

import com.electriccloud.specs.Helper
import spock.lang.Shared

class Releases extends Helper {
    @Shared
    def projectName = PREFIX + 'SentrySchedule Release'
    @Shared
    def releaseName = 'SentryRelease'
    @Shared
    def scheduleName = 'PropScheduleRelease'
    @Shared
    def triggerName = 'releaseTrigger'

    def doSetupSpec() {
        loadRelease(projectName, releaseName, 'echo 1')
        loadSchedule(projectName, scheduleName, null, releaseName, null, triggerName)
    }

    def 'runs on property change'() {
        setup:
        cleanReleaseRuns(projectName, releaseName)
        when:
        touchProperty(projectName, triggerName)
        def result = runSentry(projectName)
        then:
        def runs = findReleaseRuns(projectName, releaseName)
        println runs
        assert runs.size() == 1
    }

    def 'does not run duplicate'() {
        setup:
        def releaseName = 'Long release'
        def scheduleName = 'Long Schedule'
        def triggerName = 'longTrigger'
        loadRelease(projectName, releaseName, 'sleep 100')
        loadSchedule(projectName, scheduleName, null, releaseName, null, triggerName)
        cleanReleaseRuns(projectName, releaseName);
        when:
        touchProperty(projectName, triggerName)
        runSentry(projectName)
        then:
        def runs = findReleaseRuns(projectName, releaseName)
        assert runs.size() == 1
        touchProperty(projectName, triggerName)
        def result = runSentry(projectName)
        println result.logs
        and:
        def secondRuns = findReleaseRuns(projectName, releaseName)
        assert secondRuns.size() == 1
        cleanup:
        ef.abortAllPipelineRuns(projectName: projectName, releaseName: releaseName)
    }
}
