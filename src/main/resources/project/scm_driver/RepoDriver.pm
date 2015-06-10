# -------------------------------------------------------------------------
# Package
#    ECSCM::Repo::Driver
#
# Purpose
#    Object to represent interactions with Repo
# -------------------------------------------------------------------------
package ECSCM::Repo::Driver;
@ISA = (ECSCM::Base::Driver);

# -------------------------------------------------------------------------
# Includes
# -------------------------------------------------------------------------
use ElectricCommander;
use Getopt::Long;
use Cwd;
use HTTP::Date(qw {str2time time2str time2iso time2isoz});

$|=1;

if (!defined ECSCM::Base::Driver) {
    require ECSCM::Base::Driver;
}

if (!defined ECSCM::Repo::Cfg) {
    require ECSCM::Repo::Cfg;
}

####################################################################
# Object constructor for ECSCM::Repo::Driver
#
# Inputs
#    cmdr          previously initialized ElectricCommander handle
#    name          name of this configuration
#                 
####################################################################
sub new {
    my $this = shift;
    my $class = ref($this) || $this;

    my $cmdr = shift;
    my $name = shift;

    my $cfg = new ECSCM::Repo::Cfg($cmdr, "$name");
    if ("$name" ne '') {
        my $sys = $cfg->getSCMPluginName();
        if ("$sys" ne 'ECSCM-Repo') { die 'SCM config $name is not type ECSCM-Repo'; }
    }

    my ($self) = new ECSCM::Base::Driver($cmdr,$cfg);

    bless ($self, $class);
    return $self;
}

####################################################################
# isImplemented
####################################################################
sub isImplemented {
    my ($self, $method) = @_;
    
    if ($method eq 'getSCMTag' || 
        $method eq 'checkoutCode' || 
        $method eq 'apf_driver' || 
        $method eq 'cpf_driver') {
        return 1;
    } else {
        return 0;
    }
}

####################################################################
# helper utilties
####################################################################
#------------------------------------------------------------------------------
# repo
#
#       run the supplied command.
#------------------------------------------------------------------------------
sub repo
{
    my ($self, $opts, $command, $options) = @_;
    my $repoCommand = "repo ";
    if (defined($opts->{scm_repoPath}) && $opts->{scm_repoPath} ne ""){
        $repoCommand = qq{"$opts->{scm_repoPath}" };
    }
    $repoCommand .= "$command";        
	if ($options eq '') {
	  $options = {LogCommand => 1, LogResult => 0}; 
	}
    my $out = $self->RunCommand($repoCommand, $options);           
	return $out;
}

#------------------------------------------------------------------------------
# test_repo
#
#      return 0 if repo is not installed.
#------------------------------------------------------------------------------
sub test_repo
{
    my ($self, $opts) = @_;   
    my $out = "";
    my $command = "repo";   
    
    eval {
        $out = `$command 2>&1`;
    };
    if ($out =~ m/error: repo is not installed.  Use "repo init" to install it here./) {
        return 0;      
    } else {
        return 1;
    }    
}

#------------------------------------------------------------------------------
# repo_setup
#     
#      return the directory 
#------------------------------------------------------------------------------
sub repo_setup
{
    my ($self, $opts) = @_;   
    my $repoAgentPath = $opts->{RepoAgentPath};
    
    print join("\n","Reading options",
                    qq{Storing parameter "RepoAgentPath" with value: $repoAgentPath},
                    qq{Storing parameter "repo_working_dir" with value: $opts->{repo_working_dir}},
                    qq{Storing parameter "WorkDir" with value: $opts->{dest}},
                    qq{Storing parameter "RepoProjectList" with value: $opts->{RepoProjectList}},) . "\n";
    
    if($opts->{dest} eq "" && $repoAgentPath eq 0){
        warn "You need to provide a valid destination or a repo_agent_path\n";
        exit(1);
    }
    
    if ($repoAgentPath eq 0) {
        if (!defined $opts->{dest} ) {                
            print "No destination argument\n";
            return undef;            
        } elsif(!-d $opts->{dest}){
            if (!mkdir $opts->{dest}, 0777 ) {
                print "can't mkdir $opts->{dest}: $!\n";
                exit(1);
            }
        }
        return "$opts->{dest}";            
    }
    else {
        if (defined $opts->{repo_working_dir}){        
            if (!-d "$opts->{repo_working_dir}"){
                if (!mkdir $opts->{repo_working_dir}, 0777 ) {
                    print "can't mkdir $opts->{repo_working_dir}: $!\n";
                    exit(1);
                }
            }
            return "$opts->{repo_working_dir}";            
        } elsif($opts->{dest} ne "") {
            return $opts->{dest};
        }else{
            print "No repo work dir specified, check the resource properties.\n";
        }
    } 
}




####################################################################
# get scm tag for sentry (continuous integration)
####################################################################

####################################################################
# getSCMTag
# 
# Get the latest changelist on this branch/client
#
# Args:
# Return: 
#    changeNumber - a string representing the last change sequence #
#    changeTime   - a time stamp representing the time of last change     
####################################################################
sub getSCMTag {
    my ($self, $opts) = @_;

    # add configuration that is stored for this config
    my $name = $self->getCfg()->getName();
    my %row = $self->getCfg()->getRow($name);
    foreach my $k (keys %row) {
        $self->debug("Reading $k=$row{$k} from config");
        $opts->{$k}="$row{$k}";
    }
    
    my $here = getcwd();    
    my ($success, $xpath, $msg) = $self->InvokeCommander( { SuppressLog => 1, IgnoreError => 1 },
                                    'getProperty', "/myResource/repo_working_dir");
    if ($success) {
        $opts->{repo_working_dir} = $xpath->findvalue('//value')->string_value;                  
    }
        
    my $repo_dir = $self->repo_setup($opts);
    if($repo_dir eq ""){
       $repo_dir = cwd; 
    }
    print "Changing to $repo_dir\n";
    chdir ($repo_dir);  
    
        
    my $repoBranch = $opts->{RepoBranch};    
    my $repoMirror = $opts->{RepoMirror};
    my $repoURL = $opts->{RepoUrl};
       
    # Execute the checkout command 
    if ($repo_dir ne "") {
       print "Checking out code...\n";
       $self->checkoutCode($opts, "sentry");
    }    
    
    $repoBranch = 'master' unless ($RepoBranch eq "");
    #$output = $self->repo(" forall -c \"git log -1 --pretty=format:%H@%ct%n $repoBranch --\"");

    my $gitlog = $self->repo($opts," forall -pc \"git log -1 --pretty=format:%h%x09%an%x09%ad%x09%s%n\"", {LogCommand => 0, LogResult => 0});
    print "Latest commit in each project\n";
    print "----------------------------------\n";
    print "$gitlog\n";
    print "----------------------------------\n";
    $output = $self->repo($opts," forall -c \"git log -1 --pretty=format:%H@%ct%n --\"");

    my @out = split(/\n/, $output);

    my $lastChangeTime = 0;
    my $lastChangeNumber = 0;
    
    foreach (@out) {
        chomp($_);
        $_ =~ m/^(.+)@(\d+)$/;
        my $changeNumber = $1;
        my $changeTime =  $2;
        
        if($changeTime > $lastChangeTime) {
                    $lastChangeTime = $changeTime;
                    $lastChangeNumber = $changeNumber;
        }        
    }
    
    return ($lastChangeNumber, $lastChangeTime);    
}

####################################################################
# checkoutCode
#
# Results:
#   Uses the "repo sync" command to checkout code to the workspace.
#   If the user already has the repository defined in a custom 
#   resource agent, we only update the code. 
#   Collects data to call functions to set up the scm change log.
#
# Arguments:
#   self -              the object reference
#   opts -              A reference to the hash with values
#
# Returns
#   Output of the the "repo sync" command
####################################################################
sub checkoutCode
{
    my ($self, $opts, $source) = @_;

    # add configuration that is stored for this config
    my $name = $self->getCfg()->getName();
    my %row = $self->getCfg()->getRow($name);
    foreach my $k (keys %row) {
            $opts->{$k}=$row{$k};
    }
                                    
    my ($success, $xpath, $msg) = $self->InvokeCommander( { SuppressLog => 1, IgnoreError => 1 },
                                    'getProperty', "/myResource/repo_working_dir");
    if ($success) {
        $opts->{repo_working_dir} = $xpath->findvalue('//value')->string_value;             
    }                 
    my $here = getcwd();    
    my $repo_dir = $self->repo_setup($opts);     
    $opts->{RepoDir} = $repo_dir;
    
    print "Changing to $repo_dir\n";
    chdir($repo_dir);    
    
    my $RepoBranch = $opts->{RepoBranch};
    my $repoManifest = $opts->{RepoManifest};
    my $repoMirror = $opts->{RepoMirror};
    my $repoURL = $opts->{RepoUrl};
    my $projects = $opts->{RepoProjectList};
    
    if ($self->test_repo == 0) {
        #set git global configuration if required
        $self->setUserInfo($opts);
        my $command ="init -u $repoURL";
        
        $command .= " -m \"$repoManifest\" " unless ($repoManifest eq "");
        $command .= " -b \"$RepoBranch\" " unless ($RepoBranch eq "");
        $command .= " --mirror " unless ($repoMirror == 0);    
        #$command .= " 2>&1";
        
        my $output = $self->repo($opts,$command);
                      
        if ($output =~ m/repo initialized in/ || $output =~ m/repo mirror initialized in/ || $output =~ m/has been initialized in/ ){
            #$command = " sync 2>&1";
            $command = " sync $projects";
            $output = $self->repo($opts,$command);    
        }else {
            exit(1);
        }                         
    } else {        
        $RepoBranch = 'm/'.$RepoBranch unless ($RepoBranch eq "");
        $output = $self->repo($opts," forall -c \"git reset --hard $RepoBranch\"", 
		 {LogCommand => 1, LogResult => 0, IgnoreError => 1});		
        $output = $self->repo($opts," forall -c \"git clean -xfd\"");
        
        $command = " sync $projects";
        $output = $self->repo($opts,$command);
    } 

    my $currTime = time();
    my $now = time2str($currTime);
    my $key = $opts->{RepoUrl};
    $key =~ s/\//:/g;
    my $scmKey = "Repo-$key";
    my $lastSnapshotsForRepoProjects = $self->getLastSnapshotId($scmKey);
    my $changelog;
    my @shas = split(/\s/, $lastSnapshotsForRepoProjects);
    my $logFormat = "Revision: %H%nAuthor: %an<%ae> on %aD%nCommitter: %cn<%ce> on %cD%n%n %s%n %b%n";
    foreach $sha (@shas) {
        #We have to intentionally ignore error here because the SHA will be found only in one of the projects
        # and the rest of the git repos will complain because of it.
        $changelog .= $self->repo($opts," forall -pc \"git log --name-status --pretty='format:$logFormat' $sha..HEAD\"", {LogCommand => 1, LogResult => 0, IgnoreError => 1}) . "\n";
    }

	my $snapshot = $self->repo($opts," forall -c \"git describe --always\"",{LogCommand => 1, LogResult => 1});
    $self->setPropertiesOnJob($scmKey, $snapshot, $changelog);

    chdir $here;
    if (!$source && $changelog) {
        print "Repo Commits since last successful build\n";
        print "------------------------------------------------------------------\n";
        print "$changelog\n";
        print "------------------------------------------------------------------\n";
        $self->createLinkToChangelogReport("Changelog Report");
    }

    if (!defined $cmndReturn) {
        return 0;
    }
    
    return 1;    
}

#------------------------------------------------------------------------------
# setUserInfo
#
#       set the global configurations for git with the provided parameters in the scm configurations
#       e.g.:
#           git config --global user.email "you@example.com"
#           git config --global user.name "Your Name"
#------------------------------------------------------------------------------
sub setUserInfo{
    my ($self, $opts) = @_;
    my $command = "git config --global ";
    if($opts->{RepoUserEmail} && $opts->{RepoUserEmail} ne ""){
       $self->RunCommand($command. qq{user.email "$opts->{RepoUserEmail}"},{LogCommand => 1, LogResult => 0});
    }
    
    if($opts->{RepoUserName} && $opts->{RepoUserName} ne ""){
        $self->RunCommand($command. qq{user.name "$opts->{RepoUserName}"},{LogCommand => 1, LogResult => 0});
    }
}

#------------------------------------------------------------------------------
# getUserInfo
#
#       Get the user name and email from the git configuration on the
#       local system. When used with preflight, will provide the git details of the
#       user running the preflight.
#       e.g.:
#           git config --global user.email "you@example.com"
#           git config --global user.name "Your Name"
#------------------------------------------------------------------------------
sub getUserInfo{
    my ($self) = @_;
    my $userName = $self->RunCommand("git config --get user.name",{LogCommand => 0, LogResult => 0});
    my $userEmail = $self->RunCommand("git config --get user.email",{LogCommand => 0, LogResult => 0});
    chomp($userName);
    chomp($userEmail);
    return $userName . "<" . $userEmail . ">";
}

#----------------------------------------------------------
# agent preflight functions
#----------------------------------------------------------

#------------------------------------------------------------------------------
# apf_getScmInfo
#
#       If the client script passed some SCM-specific information, then it is
#       collected here.
#------------------------------------------------------------------------------

sub apf_getScmInfo
{
    my ($self,$opts) = @_;
    my $scmInfo = $self->pf_readFile("ecpreflight_data/scmInfo");
    $scmInfo =~ m/(.*)\n(.*)\nPreflightChangelog:(.*)/s;
    $opts->{RepoWorkdir} = $1;
    $opts->{AgentWorkdir} = $2;
    $opts->{PreflightChangelog} = $3;
    print("Repo information received from client:\n"
            . "RepoWorkdir: $opts->{RepoWorkdir}\n"
            . "AgentWorkdir: $opts->{AgentWorkdir}\n"
            . "PreflightChangelog: $opts->{PreflightChangelog}\n");
}

#------------------------------------------------------------------------------
# apf_createSnapshot
#
#       Create the basic source snapshot before overlaying the deltas passed
#       from the client.
#------------------------------------------------------------------------------

sub apf_createSnapshot
{
    my ($self,$opts) = @_;

    my $jobId = $::ENV{COMMANDER_JOBID};
    
    my $result = $self->checkoutCode($opts, "preflight");
    if (defined $result) {
        print "checked out $result\n";
    }
}

#------------------------------------------------------------------------------
# driver
#
#       Main program for the application.
#------------------------------------------------------------------------------

sub apf_driver()
{  
    my ($self,$opts) = @_;    
    
    if ($opts->{test}) { $self->setTestMode(1); }
    
    $opts->{delta} = 'ecpreflight_files';

    $self->apf_downloadFiles($opts);
    $self->apf_transmitTargetInfo($opts);
    $self->apf_getScmInfo($opts);
    $self->apf_createSnapshot($opts);
        
    my $dir = File::Spec->catdir($opts->{AgentWorkdir});     
    $opts->{dest} = $dir; 
    
    $self->apf_deleteFiles($opts);
    $self->apf_overlayDeltas($opts);
    $self->addPreflightUpdatesToChangelog($opts);
    $self->createLinkToChangelogReport("Preflight Report");
}

sub addPreflightUpdatesToChangelog {

    my ($self,$opts) = @_;

    my $preflightUpdates = $opts->{PreflightChangelog};

    my $prop = "/myJob/ecscm_changeLogs/Preflight Updates";

    my ($success, $xpath, $msg) = $self->InvokeCommander({SuppressLog=>1,IgnoreError=>1}, "setProperty", $prop, $preflightUpdates);
    if (!$success) {
        print "WARNING: Could not set the property $prop to $preflightUpdates\n";
    }

}


####################################################################
# client preflight file
####################################################################


#------------------------------------------------------------------------------
# copyDeltas
#
#       Finds all new and modified files, and calls putFiles to upload them
#       to the server.
#------------------------------------------------------------------------------
sub cpf_copyDeltas()
{
    my ($self, $opts) = @_;
    $self->cpf_display("Collecting delta information");
         
    # change to the repo dir
    if (!defined($opts->{scm_repoworkdir}) ||  "$opts->{scm_repoworkdir}" eq "") {
        $self->cpf_error("Could not change to directory $opts->{scm_repoworkdir}");
    }   
    
    chdir ($opts->{scm_repoworkdir}) || $self->cpf_error("Could not change to directory $opts->{scm_repoworkdir}");
    my $output  = $self->repo($opts, "status", {LogCommand => 1,IgnoreError=>1});
    my $authorInfo  = $self->getUserInfo();
    $self->cpf_saveScmInfo($opts,"$opts->{scm_repoworkdir}\n"
                           . "$opts->{scm_agentworkdir}\n"
                           . "PreflightChangelog:Author: $authorInfo\n$output\n");
    
    $self->cpf_findTargetDirectory($opts);
    $self->cpf_createManifestFiles($opts);
    

    $self->cpf_debug("$output");
    
    my $top = getcwd();
    my $project, $branch;    
    foreach(split(/\n/, $output)) {
        my $line = $_;
        $line =~ m/project\s(.*)\s*(branch (.*)|\((.*)\))/;        
        #project name and branch matchers
        #it´s a No branch project
        if ($4){  
            $project = $1;
            $project =~ s/^\s+|\s+$//g;
            $branch = undef; 
            next;                      
        }
        #it´s a branch project
        if ($3){
          $project = $1;
          $project =~ s/^\s+|\s+$//g;
          $branch = $3; 
          next;                 
        }        
        #file and action matchers        
        $line =~ m/\s+(|-|A-|M-|D-|R-|C-|T-|U-)\s+(.*)/;
        
        my $file, $action,$path;        
        if ($1 && $2) {       
            $file = $2;
            $action = $1;
            $path = $project.$file;     
           
            if (($action eq 'A-') || ($action eq 'M-') ) {           
                my $fpath = $top . "/$path";
                my $fpath = File::Spec->rel2abs($fpath);               
                $self->cpf_addDelta($opts,$fpath, "$path");    
            } elsif ($action = 'D-'){
                $self->cpf_addDelete("$path");
            }           
        }         
    }
      
    $self->cpf_closeManifestFiles($opts);
    $self->cpf_uploadFiles($opts);
}

#------------------------------------------------------------------------------
# autoCommit
#
#       Automatically commit changes in the user's client.  Error out if:
#       - A check-in has occurred since the preflight was started, and the
#         policy is set to die on any check-in.
#       - A check-in has occurred and opened files are out of sync with the
#         head of the branch.
#       - A check-in has occurred and non-opened files are out of sync with
#         the head of the branch, and the policy is set to die on any changes
#         within the client workspace.
#------------------------------------------------------------------------------
sub cpf_autoCommit()
{
    my ($self, $opts) = @_;

    $self->cpf_display("Committing changes");
    $self->repo($opts, "upload", {LogCommand =>1});
   
    $self->cpf_display("Changes have been successfully submitted");
}

#------------------------------------------------------------------------------
# driver
#
#       Main program for the application.
#------------------------------------------------------------------------------
sub cpf_driver
{
    my ($self,$opts) = @_;
    $self->cpf_display("Executing Repo actions for ecpreflight");

    $::gHelpMessage .= "
  Repo Options: 
  --repoworkdir   <path>      The developer's source directory. 
  --agentworkdir  <path>      The path to the source directory used by the agent
  --repoPath      <path>      The path to the repo executable";

    my %ScmOptions = (         
        "repoworkdir=s"             => \$opts->{scm_repoworkdir},    
        "agentworkdir=s"            => \$opts->{scm_agentworkdir},
        "repoPath=s"                => \$opts->{scm_repoPath},
    );

    Getopt::Long::Configure("default");
    if (!GetOptions(%ScmOptions)) {
        error($::gHelpMessage);
    }    

    if ($::gHelp eq "1") {
        $self->cpf_display($::gHelpMessage);
        return;
    }    

    $self->extractOption($opts,"scm_repoworkdir", { required => 1, cltOption => "repoworkdir" });  
    $self->extractOption($opts,"scm_agentworkdir", { required => 0, cltOption => "agentworkdir" }); 
    $self->extractOption($opts,"scm_repoPath", { required => 0, cltOption => "repoPath" }); 
    
    # Copy the deltas to a specific location.
    $self->cpf_copyDeltas($opts);

    # Auto commit if the user has chosen to do so.

    if ($opts->{scm_autoCommit}) {
        if (!$opts->{opt_Testing}) {
            $self->cpf_waitForJob($opts);
        }
        $self->cpf_autoCommit($opts);
    }
}

#-------------------------------------------------------------------
# updateLastGoodAndLastCompleted
#
# Side Effects:
#   If the current job outcome is "success" copy the current
#   revision from the job level property to the "lastGood"
#   property and the "lastCompleted" property.  If not success,
#   only copy the current revision to the "lastCompleted" property.
#
# Arguments:
#   self -              the object reference
#   opts -              A reference to the hash with values
#
# Returns:
#   nothing.
#
#-------------------------------------------------------------------
sub updateLastGoodAndLastCompleted
{
    my ($self, $opts) = @_;

    my $prop = "/myJob/outcome";

    my ($success, $xpath, $msg) = $self->InvokeCommander({SuppressLog=>1,IgnoreError=>1}, "getProperty", $prop);

    if ($success) {

    my $grandParentStepId = "";
    $grandParentStepId = $self->getGrandParentStepId();
    
    if (!$grandParentStepId || $grandParentStepId eq "") {
        # log that we couldn't get the grand parent step id
        return;
    }

    my $properties = $self->getPropertyNamesAndValuesFromPropertySheet("/myJob/ecscm_snapshots");

    foreach my $key ( keys % {$properties}) {
        my $snapshot = $properties->{$key}; 
        
        if ("$snapshot" ne "") { 
            $prop = "/myProcedure/ecscm_snapshots/$key/lastCompleted";
            $self->InvokeCommander({SuppressLog=>1,IgnoreError=>1}, "setProperty", "$prop", "$snapshot", {jobStepId => $grandParentStepId});

            my $val = "";
            $val = $xpath->findvalue('//value')->value();

            if ($val eq "success") {
                $prop = "/myProcedure/ecscm_snapshots/$key/lastGood";
                $self->InvokeCommander({SuppressLog=>1,IgnoreError=>1}, "setProperty", "$prop", "$snapshot", {jobStepId => $grandParentStepId});            
            }
        } else {
            # log that we couldn't get the job revision
        }
    }

    } else {
    # log the error code and msg
    }
}
1;

