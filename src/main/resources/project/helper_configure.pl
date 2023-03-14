## generic config               -*- Perl -*-
##
## this perl code should be included
## as a property reference so it is inline
##
## assumes all config options are in parameters
## and creates an entry for each one given
##
use ElectricCommander;

my $opts;

if (!defined $PLUGIN_NAME) {
    print "PLUGIN_NAME must be defined\n";
    exit 1;
}

## get an EC object
my $ec = new ElectricCommander();
$ec->abortOnError(0);

## load option list from procedure parameters
my $x = $ec->getJobDetails($ENV{COMMANDER_JOBID});
my $nodeset = $x->find('//response/job/actualParameter');
my $desc;
foreach my $node ($nodeset->get_nodelist) {
    my $parm = $node->findvalue('actualParameterName');
    my $val = $node->findvalue('value');
    if ("$parm" eq "desc") {
        $desc = "$val";
    }
    else {
        $opts->{$parm}="$val";
    }
}

if (!defined $opts->{config} || "$opts->{config}" eq "" ) {
    print "config parameter must exist and be non-blank\n";
}

# check to see if a config with this name already exists before we do anything else
my $ecscmProj = "@PLUGIN_NAME@";
my $xpath = $ec->getProperty("/projects/$ecscmProj/scm_cfgs/$opts->{config}");
my $property = $xpath->findvalue("//response/property/propertyName");

if (defined $property && "$property" ne "") {
    my $errMsg = "A configuration with name '$opts->{config}' already exists";
    $ec->setProperty("/myJob/configError", $errMsg);
    print $errMsg;
    exit 1;
}

## find ECSCM plugin project
my $prop = "/projects/$ecscmProj/procedure_helpers/bootstrap";
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
    print "error: $!\n";
    exit 1;
}

# get ECSC base driver
if (!loadPerlCodeFromProperty($ec,"/projects/$ecscmProj/scm_driver/ECSCM::Base::Cfg")) {
    print "Could not load ECSCM base configuration module\n";
    exit 1;
}

if (!loadPerlCodeFromProperty($ec,"/projects/$ecscmProj/scm_driver/ECSCM::Base::Driver")) {
    print "Could not load ECSCM base driver module\n";
    exit 1;
}

# look up the plugin name for this config
my $cfg = new ECSCM::Base::Cfg($ec, "$opts->{config}");
if (!defined $cfg) {
    print "Could not create an ECSCM::Base::Cfg object\n";
    exit 1;
}


## create config using the scm driver
my $result = $cfg->createCfg("$opts->{config}","$PLUGIN_NAME","$desc");
if (!defined $result) {
    print "createCfg failed\n";
    exit 1;
}
print "config create result:$result\n";

# now add all the options as properties
foreach my $key (keys % {$opts}) {
    if ("$key" eq "config" || "$key" eq "resource") { 
        next;
    }
    $cfg->set($key,"$opts->{$key}");
}
exit 0;
