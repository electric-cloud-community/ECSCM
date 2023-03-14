## agent preflight              -*- Perl -*-
## 
## this perl code should be included
## as a property reference so it is inline
## 
## it passes ec_customEditorData properties
## to the specific SCM driver checkoutCode
## method.
##

use ElectricCommander;

my $opts = ();

## get an EC object
my $ec = new ElectricCommander();
$ec->abortOnError(0);

## load option list from ec_customEditorData
my $x = $ec->getProperties({path=>'/myStep/ec_customEditorData'});
my $nodeset = $x->find('//response/propertySheet/property');
foreach my $node ($nodeset->get_nodelist) {
    my $parm = $node->findvalue('propertyName');
    my $val = $node->findvalue('value');
    $opts->{$parm}="$val";
}

## find ECSCM plugin project
my $prop = "/plugins/@PLUGIN_NAME@/project/procedure_helpers/bootstrap";
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

## use routines in bootstrap to load an SCM driver
print "Running boostrap for $opts->{scmConfig} ...\n";
my $scm = loadSCMDriver($ec,$opts->{scmConfig});
if (!defined $scm) { 
    # failures should be verbose, no need to pile on
    exit(1); 
}

# run agent preflight
$scm->apf_driver($opts);
exit 0;

