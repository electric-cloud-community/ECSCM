##########################################################
# loadSCMDriver
#
# Given a config name, find the SCM driver
# and load both the ::Cfg and ::Driver modules
#
# args
#   ec        - initialized ElectricCommander object
#   scmConfig - the name of an SCM configuation
#  
# return
#   undef on failure
#   new ECSCM::Base::Driver derived object on success
##########################################################
sub loadSCMDriver {
    my $ec = shift;
    my $scmConfig = shift;
    

    # get ECSC base driver
    if (!loadPerlCodeFromProperty($ec,"/plugins/@PLUGIN_NAME@/project/scm_driver/ECSCM::Base::Cfg")) {
        print "Could not load ECSCM base configuration module\n";
        return undef;
    }

    if (!loadPerlCodeFromProperty($ec,"/plugins/@PLUGIN_NAME@/project/scm_driver/ECSCM::Base::Driver")) {
        print "Could not load ECSCM base driver module\n";
        return undef;
    }

    # look up the plugin name for this config
    my $cfg = new ECSCM::Base::Cfg($ec, "$scmConfig");
    if (!defined $cfg) {
        print "Could not create an ECSCM::Base::Cfg object\n";
        return undef;
    }
    my $ecscm = new ECSCM::Base::Driver($ec);
    if (!defined $ecscm) {
        print "Could not create an ECSCM::Base::Driver object\n";
        return undef;
    }

    my $scmPlugin = $cfg->getSCMPluginName();
    if (!defined $scmPlugin || "$scmPlugin" eq "") {
        print "Could not find configuration $scmConfig\n";
        return undef;
    }

    # create an SCM object
    my $mod = $ecscm->load_driver("$scmPlugin");
    if (!defined $mod || "$mod" eq "") {
        print "Load driver did not return a perl module name\n";
        return undef;
    }
    my $scm = new $mod($ec, $scmConfig);
    if (!defined $scm) {
        print "Could not create a $mod object\n";
        return undef;
    }
    return $scm;
}

#-------------------------------------------------------------------------
# loadPerlCodeFromProperty
#
# eval perl code from properties
#
# args
#   ec - commander object
#   prop - the property holding the code
#
# return
#   0 on failure
#   1 on success
#-------------------------------------------------------------------------
sub loadPerlCodeFromProperty {
    my $ec = shift;
    my $prop = shift;
    print "Loading $prop..\n";
    my $code = $ec->getProperty("$prop")->findvalue('//value')->string_value;
    if ("$code" eq "") {
        print "Error:" . $ec->getError() . "getting $prop\n";
        return 0;
    } 
    eval $code;
    if ($@) {
        warn $!;
        return 0;
    }
    return 1;
}
