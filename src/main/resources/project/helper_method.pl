## generic method runner
##
## this perl code should be included
## as a property reference so it is inline
##
## it passes parameters of a procedure
## to the specific SCM driver checkoutCode
## method.
##
#
# expects $PLUGIN_NAME and $DRIVER_METHOD to be set.
#
# uses a CI Configuration if $CI_CONFIG_NAME and
# $CI_PROJECT are set.
#
# CLEANUP: CHECK

use ElectricCommander;

my $opts;

## get an EC object
my $ec = new ElectricCommander();
$ec->abortOnError(0);

## Populate the options list containing SCM parameters that will
## be needed by the specific driver method. How this is done depends
## on if we were invoked from the ECSCM:CICheckout procedure or by
## a ECSCM-<scmtype> procedure.
if (defined $PLUGIN_NAME && $PLUGIN_NAME eq "ECSCM:CICheckout") {
    ## Invoked from the ECSCM:CICheckout procedure.
    undef $PLUGIN_NAME; # clear to skip SCM type check later
    my $ciProject = "";
    my $ciConfigName = "";
    ## Locate the CI Configuration by getting the parameter values
    ## from the grandparent of this job step.
    my $x = $ec->getJobDetails($ENV{COMMANDER_JOBID});
    foreach my $parameter ($x->findnodes(
            "//jobStep[calledProcedure/jobStep/calledProcedure/jobStep/"
            . "jobStepId=\"$::ENV{COMMANDER_JOBSTEPID}\"]/"
            . "calledProcedure/actualParameter")) {
        my $name = $parameter->findvalue('actualParameterName');
        my $value = $parameter->findvalue('value');
        if ($name eq "ec_ci_projectName") {
            $ciProject = $value;
            print "Found parameter \"$name\" with value \"$value\".\n";
        } elsif ($name eq "ec_ci_configurationName") {
            $ciConfigName = $value;
            print "Found parameter \"$name\" with value \"$value\".\n";
        }
    }
    ## Now build the location of the CI Configuration
    my $ciConfig = "/projects/$ciProject/schedules/$ciConfigName/ec_ci/checkout";
    print "Getting properties from CI configuration: $ciConfig\n";
    ## Find and store all property values from the CI Configuration
    my $x = $ec->getProperties({"path" => "$ciConfig", "expand"=>"0"});
    if ($x->findvalue('//code') eq 'NoSuchProperty') {
        print "Could not find CI configuration properties: $ciConfig\n";
        exit 1;
    }
    foreach my $property ($x->findnodes( "//property")) {
        my $name = $property->findvalue('propertyName')->value();
        my $value = $property->findvalue('value')->value();

        # Need to expand the value of the property
        my $xpath = "";
        my $expandedValue = "";

        # Illegal to expandString an empty string
        if($value ne "") {

          $xpath = $ec->expandString($value);

          if($xpath->exists('//error')){
            # There was a problem with property expansion.
            # Set a sensible default, emit an error and move on.
            $expandedValue = "";
            print "ERROR: Could not expand property: $name with corresponding value: $value\n";
          }
          else {
            $expandedValue = $xpath->findvalue('//value')->value();
          }
        }

        print "Storing property \"$name\" with value \"$expandedValue\".\n";
        $opts->{$name} = $expandedValue;
    }
} else {
    ## Invoked from an ECSCM-<scmtype> checkout procedure.
    ## Find and store all parameter values for the grandparent of this job step
    my $x = $ec->getJobDetails($ENV{COMMANDER_JOBID});

    my $plugin_key = $ec->getProperty('/myFlowRuntimeState/subpluginKey')->findvalue('//value')->string_value;
    my $flowRuntimeStateId = $ec->getProperty('/myFlowRuntimeState/id')->findvalue('//value')->string_value;

    my $parameters;
    eval {
        $parameters = getParametersList($PLUGIN_NAME, $DRIVER_METHOD);
        1;
    } or do {
        $parameters = [];
    };
    if ($plugin_key =~ /ECSCM/ && @$parameters) {
        print "Running within a pipeline\n";

        for my $name (@$parameters) {

            my $value = $ec->getActualParameter({
                    flowRuntimeStateId => $flowRuntimeStateId,
                    actualParameterName => $name
                })->findvalue('//value')->string_value;

            if ($value =~ m/\$\[/) {
                # Need to expand
                my $xpanded = $ec->expandString($value, {
                    flowRuntimeStateId => $flowRuntimeStateId,
                    jobStepId => '', # to override environment variable
                });
                $value = $xpanded->findvalue('//value')->string_value;
            }
            $opts->{$name} = $value;

            print qq{Storing parameter "$name" with value "$value".\n};;
        }
    }
    else {
        # Fallback
        foreach my $parameter ($x->findnodes(
                "//jobStep[calledProcedure/jobStep/calledProcedure/jobStep/"
                . "jobStepId=\"$::ENV{COMMANDER_JOBSTEPID}\"]/"
                . "calledProcedure/actualParameter")) {
            my $name = $parameter->findvalue('actualParameterName');
            my $value = $parameter->findvalue('value');
            print "Storing parameter \"$name\" with value \"$value\".\n";
            $opts->{$name} = $value;
        }
    }

}

## find ECSCM plugin project
my $prop = "/myProject/procedure_helpers/bootstrap";
print "Getting ECSCM bootstrap code from $prop\n";

## get global bootstrap helper
my $bootstrap = $ec->getProperty("$prop")->findvalue('//value')->string_value;
if (!defined $bootstrap || "$bootstrap" eq "" ) {
    print "Could not find ECSCM bootstrap code in $prop\n";
    exit 1;
}
## load bootstrap code
eval $bootstrap;
if ($@) {
    print "Error: $!\n";
    exit 1;
}

## use routines in bootstrap to load an SCM driver
print "Running boostrap for: $opts->{config} ...\n";
my $scm = loadSCMDriver($ec,$opts->{config});
if (!defined $scm) {
    # failures should be verbose, no need to pile on
    exit(1);
}

if (defined $PLUGIN_NAME) {
    # sanity check that the config we were passed
    # is actually for this type of SCM plugin
    # the UI should not allow this, but check anyway
    my $SCM_MOD = ref($scm);
    my $PLUGIN_MOD="$PLUGIN_NAME";
    $PLUGIN_MOD =~ s/-/\:\:/g;
    if (!($SCM_MOD =~ m/$PLUGIN_MOD/)) {
        print "SCM configuration $opts->{config} is not for SCM $PLUGIN_NAME\n";
        exit 1;
    }
}

# add configuration that is stored for this config
my $name = $scm->getCfg()->getName();
my %row = $scm->getCfg()->getRow($name);
foreach my $k (keys %row) {
    $opts->{$k}=$row{$k};
}

## run checkout using the scm driver
print "Running driver method: $DRIVER_METHOD...\n";
# can - perl subroutine from UNIVERSAL. Every blessed reference
# can call can
if ($scm->can('beforeRunMethod')) {
    print "Calling beforeRunMethod hook\n";
    $scm->beforeRunMethod($DRIVER_METHOD);
}
my $result;

eval {
    $result = $scm->$DRIVER_METHOD($opts);
    1;
} or do {
    print "Error: $DRIVER_METHOD completed with error: $@\n";
};

print "$DRIVER_METHOD returned $result\n";

if ($scm->can('afterRunMethod')) {
    print "Calling afterRunMethod hook\n";
    $scm->afterRunMethod($DRIVER_METHOD);
}

exit 0;


sub getParametersList {
    my ($plugin, $method) = @_;

    my $xpath = $ec->getPlugin($plugin);
    my $pluginProjectName = $xpath->findvalue('//projectName')->value;

    $xpath = $ec->getProcedure($pluginProjectName, $method);
    my $procedureName = $xpath->findvalue('//procedureName')->value;

    $xpath = $ec->getFormalParameters({projectName => $pluginProjectName, procedureName => $procedureName});

    my @parameters = map { $_->findvalue('formalParameterName')->value } $xpath->findnodes('//formalParameter');
    return \@parameters;
}
