use ElectricCommander;
use utf8;

ElectricCommander::initEncodings;
my $ec = new ElectricCommander();

my $projName = "@PLUGIN_KEY@-@PLUGIN_VERSION@";
$ec->deleteProperty("/projects/$projName/scm_cfgs/$[config]");
$ec->deleteCredential($projName, "$[config]");
eval { $ec->deleteCredential($projName, "$[config]_webhookSecret") };
