use ElectricCommander;
use utf8;

ElectricCommander::initEncodings;
my $ec = new ElectricCommander();
$ec->abortOnError(0);

my $credName = "$[/myJob/config]";
my $xpath = $ec->getFullCredential("credential");
my $userName = $xpath->findvalue("//userName");
my $password = $xpath->findvalue("//password");

# Create credential
my $projName = '$[/myProject/projectName]';

$ec->deleteCredential($projName, $credName);
$xpath = $ec->createCredential($projName, $credName, $userName, $password);
my $errors = $ec->checkAllErrors($xpath);

# Give config the credential's real name
my $configPath = "/projects/$projName/scm_cfgs/$credName";
$xpath = $ec->setProperty($configPath . "/credential", $credName);
$errors .= $ec->checkAllErrors($xpath);

# Give job launcher full permissions on the credential
my $user = '$[/myJob/launchedByUser]';
$xpath = $ec->createAclEntry("user", $user,
    {projectName => $projName,
     credentialName => $credName,
     readPrivilege => 'allow',
     modifyPrivilege => 'allow',
     executePrivilege => 'allow',
     changePermissionsPrivilege => 'allow'});
$errors .= $ec->checkAllErrors($xpath);


# Attach credential to steps that will need it
$xpath = $ec->attachCredential($projName, $credName,
    {procedureName => "RunMethod",
     stepName => "runMethod"});
$errors .= $ec->checkAllErrors($xpath);
$xpath = $ec->attachCredential($projName, $credName,
    {procedureName => "ElectricSentry",
     stepName => "Check for New Sources"});
$errors .= $ec->checkAllErrors($xpath);


eval {
    $ec->abortOnError(1);
    my $webhookCredName = "${credName}_webhookSecret";
    my $webhookCred = $ec->getFullCredential('webhookSecret');
    my $webhookCredUsername = $webhookCred->findvalue('//userName')->string_value;
    my $webhookSecret = $webhookCred->findvalue('//password')->string_value;
    $ec->deleteCredential($projName, $webhookCredName);
    $xpath = $ec->createCredential($projName, $webhookCredName, $webhookCredUsername, $webhookSecret);

    # Give config the credential's real name
    my $configPath = "/projects/$projName/scm_cfgs/$credName";
    $xpath = $ec->setProperty($configPath . "/webhookSecret", $webhookCredName);

    # Give job launcher full permissions on the credential
    my $user = '$[/myJob/launchedByUser]';
    $xpath = $ec->createAclEntry("user", $user,
        {projectName => $projName,
         credentialName => $webhookCredName,
         readPrivilege => 'allow',
         modifyPrivilege => 'allow',
         executePrivilege => 'allow',
         changePermissionsPrivilege => 'allow'});

    # Attach credential to steps that will need it
    $xpath = $ec->attachCredential($projName, $webhookCredName,
        {procedureName => "RunMethod",
         stepName => "runMethod"});
    $xpath = $ec->attachCredential($projName, $webhookCredName,
        {procedureName => "ElectricSentry",
         stepName => "Check for New Sources"});


    $ec->abortOnError(0);
    1;
} or do {
    print "Error occured while creating second credential: $@";
    $ec->abortOnError(0);
};



if ("$errors" ne "") {

    # Cleanup the partially created configuration we just created
    $ec->deleteProperty($configPath);
    $ec->deleteCredential($projName, $credName);
    my $errMsg = "Error creating configuration credential: " . $errors;
    $ec->setProperty("/myJob/configError", $errMsg);
    print $errMsg;
    exit 1;
}

