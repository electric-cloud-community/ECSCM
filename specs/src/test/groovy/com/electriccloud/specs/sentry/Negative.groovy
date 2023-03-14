package com.electriccloud.specs.sentry

import com.electriccloud.specs.Helper
import spock.lang.Shared

class Negative extends Helper {
    @Shared
    def projectName = PREFIX + ' SentrySchedule Negative'
    @Shared
    def scheduleName = 'PropSchedule'

    def doSetupSpec() {
        loadSchedule(projectName, scheduleName, null, null, null)
    }

    def 'does not fail on invalid schedule'() {
        when:
        touchProperty(projectName, 'trigger')
        def result = runSentry(projectName, true)
        then:
        println result.logs
        assert result.outcome == 'error'
        assert result.logs =~ /Cannot run schedule PropSchedule of project/
    }

}
