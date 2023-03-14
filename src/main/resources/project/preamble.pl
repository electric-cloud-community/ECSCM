$|=1;

use ElectricCommander;
my $server = "$ENV{COMMANDER_SERVER}:$ENV{COMMANDER_PORT}";
my $ec = new ElectricCommander($server);
$ec->abortOnError(0);

sub loadPerlCodeFromProperty {
    my $prop = shift;
    print "Loading $prop..\n";
    my $code = $ec->getProperty("$prop")->findvalue('//value')->string_value;
    if ("$code" eq "") {
        print "Error:" . $ec->getError() . "getting $prop\n";
        exit 1;
    }
    eval $code;
    if ($@) {
       die "Error evaluating script loaded from '$prop': $@\n";
    }
}

loadPerlCodeFromProperty("/myProject/scm_driver/ECSCM::Base::Cfg");
loadPerlCodeFromProperty("/myProject/scm_driver/ECSCM::Base::Driver");
loadPerlCodeFromProperty("/myProject/scm_driver/ElectricSentry::TriggerCfg");
loadPerlCodeFromProperty("/myProject/scm_driver/ElectricSentry::ScheduleCfg");
loadPerlCodeFromProperty("/myProject/scm_driver/ElectricSentry::JobCfg");
loadPerlCodeFromProperty("/myProject/scm_driver/ElectricSentry::GlobalCfg");
loadPerlCodeFromProperty("/myProject/scm_driver/ElectricSentry::Driver");

my $sentry = ElectricSentry::Driver->new($ec, "$[/myProcedure/EnableLogging]");
