my $projPrincipal = "project: $pluginName";
my $ecscmProj = '$[/plugins/ECSCM/project]';

if ($promoteAction eq 'promote') {
    # Register our SCM type with ECSCM
    $batch->setProperty("/plugins/ECSCM/project/scm_types/@PLUGIN_KEY@", "Repo");
    
    # Give our project principal execute access to the ECSCM project
    my $xpath = $commander->getAclEntry("user", $projPrincipal,
                                        {projectName => $ecscmProj});
    if ($xpath->findvalue('//code') eq 'NoSuchAclEntry') {
        $batch->createAclEntry("user", $projPrincipal,
                               {projectName => $ecscmProj,
                                executePrivilege => "allow"});
    }
} elsif ($promoteAction eq 'demote') {
    # unregister with ECSCM
    $batch->deleteProperty("/plugins/ECSCM/project/scm_types/@PLUGIN_KEY@");
    
    # remove permissions
    my $xpath = $commander->getAclEntry("user", $projPrincipal,
                                        {projectName => $ecscmProj});
    if ($xpath->findvalue('//principalName') eq $projPrincipal) {
        $batch->deleteAclEntry("user", $projPrincipal,
                               {projectName => $ecscmProj});
    }
}

# Unregister current and past entries first.
$batch->deleteProperty("/server/ec_customEditors/pickerStep/ECSCM-Repo - Checkout");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/ECSCM-Repo - Preflight");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/Repo - Checkout");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/Repo - Preflight");

# Data that drives the create step picker registration for this plugin.
my %checkoutStep = (
    label       => "Repo - Checkout",
    procedure   => "CheckoutCode",
    description => "Checkout code from Repo.",
    category    => "Source Code Management"
);

my %Preflight = (
    label => "Repo - Preflight",
    procedure => "Preflight",
    description => "Checkout code from Repo during Preflight",
    category => "Source Code Management"
);
@::createStepPickerSteps = (\%checkoutStep, \%Preflight);
