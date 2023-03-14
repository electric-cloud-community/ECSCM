package com.electriccloud.specs.sentry

import com.electriccloud.specs.Helper
import spock.lang.Narrative
import spock.lang.Shared
import spock.lang.Unroll

@Narrative("""
Creating schedule with a procedure or type property.
Change property -> Run ElectricSentry -> The procedure should be launched

We are using ECSCM-Property in this case. This triggers schedule run when a certain property is changed.
""")
class Procedures extends Helper {

    @Shared
    def projectName = PREFIX + ' SentrySchedule'
    @Shared
    def procedureName = 'SentryProcedure'
    @Shared
    def scheduleName = 'PropSchedule'

    def doSetupSpec() {
        deleteAllProjects()
    }

    @Unroll
    def 'runs on property change #scheduleProjectName #scheduleProcedureName'() {
        setup:
        loadProcedure(projectName, procedureName)
        loadSchedule(scheduleProjectName, scheduleName, null, null, scheduleProcedureName)
        cleanProcedureRuns(projectName, procedureName)
        when:
        touchProperty(scheduleProjectName, 'trigger')
        def result = runSentry(scheduleProjectName)
        then:
//        This part is different from flow part
        def procedureRuns = findProcedureRuns(scheduleProjectName, scheduleProcedureName)
        assert procedureRuns.size() >= 1
        def procedureRun = procedureRuns[0]
        assert procedureRun.liveSchedule
        where:
        scheduleProjectName     | scheduleProcedureName
        projectName             | procedureName
        "$projectName Schedule" | "/projects/$projectName/procedures/$procedureName"
    }


    @Unroll
    /*
    Change property, launch Sentry job.
    It should launch the schedule.
    Schedule runs for some time (100 seconds)
    Change property again, launch Sentry job,
    it should not launch the schedule for the second time as there is already one running job.
     */
    def 'does not run duplicates #scheduleProjectName'() {
        setup:
        def procedureName = randomize(procedureName)
        def scheduleProcedureName = scheduleProcedureNameClosure(procedureName)
        loadProcedure(projectName, procedureName, 'sleep 100')
        loadSchedule(scheduleProjectName, scheduleName, null, null, scheduleProcedureName)
        when:
        touchProperty(scheduleProjectName, 'trigger')
        runSentry(scheduleProjectName)
        then:
        def runs = findProcedureRuns(scheduleProjectName, scheduleProcedureName)
        assert runs.size() == 1
        touchProperty(scheduleProjectName, 'trigger')
        runSentry(scheduleProjectName)
        and:
        def secondRuns = findProcedureRuns(scheduleProjectName, scheduleProcedureName)
        assert secondRuns.size() == 1
        where:
        scheduleProjectName     | scheduleProcedureNameClosure
        projectName             | { it -> it }
        "$projectName Schedule" | { it -> "/projects/$projectName/procedures/$it" }

    }

    /*
    Change property, launch sentry.
    It launches the schedule.
    Launch sentry again.
    It should not launch the schedule.
     */
    def 'does not run if property did not change'() {
        setup:
        def procedureName = randomize(procedureName)
        touchProperty(projectName, 'trigger')
        runSentry(projectName)
        cleanProcedureRuns(projectName, procedureName)
        when:
        def result = runSentry(projectName)
        then:
        def procedureRuns = findProcedureRuns(projectName, procedureName)
        assert procedureRuns.size() == 0
    }


}
