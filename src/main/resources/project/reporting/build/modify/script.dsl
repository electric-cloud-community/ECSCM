import com.electriccloud.domain.DevOpsInsightDataSourceResult;
import com.electriccloud.errors.EcException;
import com.electriccloud.errors.ErrorCodes;

// Validate that all the input arguments are passed in as expected
def releaseName = checkRequiredScriptArgument(args?.releaseName, 'releaseName')
def projectName = checkRequiredScriptArgument(args?.projectName, 'projectName')
def devOpsInsightDataSourceName = checkRequiredScriptArgument(args?.devOpsInsightDataSourceName, 'getDevOpsInsightDataSourceName')

// Validate plugin parameters
def pluginParameters = args.pluginParameters?:[:]
def ciProjectName  = checkRequiredPluginParameter(pluginParameters, 'ciProjectName', 'Continuous Integration Schedule Project Name')
def ciScheduleName = checkRequiredPluginParameter(pluginParameters, 'ciScheduleName', 'Continuous Integration Schedule Name')

// Check that the ci schedule exists.
// The lookup will fail with NoSuchSchedule or NoSuchProject in case the schedule or project do not exist.
def sched = getSchedule (projectName: ciProjectName, scheduleName: ciScheduleName)

// Confirm that it is a ci-schedule
def triggerFlagProp = sched.ec_customEditorData?.TriggerFlag
// ec_triggerType property is not expected to be set for CI schedules
def triggerTypeProp = sched.ec_triggerType
def isCISchedule = !triggerTypeProp && (triggerFlagProp?.value == '2' || triggerFlagProp?.value == '0')
if (!isCISchedule) {
    throw EcException.code(ErrorCodes.InvalidArgument)
                .message(
                "Schedule '%s' is not a continuous integration schedule.", ciScheduleName)
                .build();
}

def releases = getReleases()

releases?.each { r ->
    def datasources = getDevOpsInsightDataSources(projectName: r.projectName, releaseName: r.releaseName)
    debug("Datasources for release ${r.releaseName}: " + datasources.size())

    datasources.each { ds ->

            debug("Datasource plugin details for release ${r.releaseName}: ${ds.pluginKey} ${ds.reportObjectType}")
            if (ds.pluginKey == 'ECSCM' && ds.reportObjectType == 'build') {

                debug("Datasource schedule details for release ${r.releaseName}: ${ds.scheduleProjectName}:${ds.scheduleName}")
                if (ds.scheduleName == ciScheduleName && ds.scheduleProjectName == ciProjectName) {
                    debug("Matching schedule found ${r.projectName}:${r.releaseName}")
                    if (r.releaseName == releaseName && r.projectName == projectName) {

                        if (ds.devOpsInsightDataSourceName != devOpsInsightDataSourceName) {
                            debug("Schedule attached to same release ${r.projectName}:${r.releaseName}")
                            //the schedule is already attached to this release
                            throw EcException.code(ErrorCodes.InvalidArgument)
                                            .message(
                                            "Schedule '%s' is already assigned to the current release.", ciScheduleName)
                                            .build();
                        }

                    } else {
                        debug("Schedule attached to another release ${r.projectName}:${r.releaseName}")
                        //check that schedule is not attached to an incomplete release
                        if (r.releaseStatus != Release.ReleaseStatus.COMPLETED) {
                            throw EcException.code(ErrorCodes.InvalidArgument)
                                        .message(
                                        "Schedule '%s' is assigned to another release that is not complete.", ciScheduleName)
                                        .build();
                        }
                    }
                }
            }
        }

}

// nothing else needs to be done for the CI schedule
// the association is created by the createDevOpsInsightDataSource API
// so finally just return response

def retval = new DevOpsInsightDataSourceResult();
retval.connectionInfo      = '' //no connection info since this pertains to this EF server itself
retval.sourceDetails       = "CI Schedule - $ciProjectName: $ciScheduleName"
retval.scheduleName        = ciScheduleName;
retval.scheduleProjectName = ciProjectName;

return retval

// End of main script

// Helper functions
def checkRequiredScriptArgument(def arg, def argName) {
    if (!arg?.toString()?.trim()) {
        throw EcException.code(ErrorCodes.MissingArgument)
                .message(
                "'%s' argument is missing.", argName)
                .build();
    }
    arg?.toString()?.trim()
}

def checkRequiredPluginParameter(def params, def argName, def paramLabel) {
    if (!params[argName] || !params[argName].toString() || !params[argName].toString().trim()) {
        throw EcException.code(ErrorCodes.MissingArgument)
                .message(
                "Please provide '%s'.", paramLabel)
                .build();
    }
    params[argName].toString().trim()
}

def debug(String msg) {
    if (args.debug && args.debug.toString().toBoolean()) {
        println msg
    }
}


// End of helper functions