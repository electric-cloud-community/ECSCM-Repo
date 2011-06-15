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
    my ($self,$command, $options) = @_;
    my $repoCommand = "repo $command";        
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
        
    if ($repoAgentPath eq 0) {
        if (!defined $opts->{dest} ) {                
            print "No destination argument\n";
            return undef;            
        } else {            
            if (!mkdir $opts->{dest}, 0777 ) {
                print "can't mkdir $opts->{dest}: $!\n";
                exit(1);
            }
            return "$opts->{dest}";            
        }
    } else {
        if (defined $opts->{repo_working_dir}){        
            if (!-d "$opts->{repo_working_dir}"){
                if (!mkdir $opts->{repo_working_dir}, 0777 ) {
                    print "can't mkdir $opts->{repo_working_dir}: $!\n";
                    exit(1);
                }
            }
            return "$opts->{repo_working_dir}";            
        } else {
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
    chdir ($repo_dir);  
    
        
    my $repoBranch = $opts->{RepoBranch};    
    my $repoMirror = $opts->{RepoMirror};
    my $repoURL = $opts->{RepoUrl};
       
    # Execute the checkout command 
    if ($repo_dir ne "") {
       print "Checking out code...\n";
       #$self->checkoutCode($opts);
    }    
    
    $repoBranch = 'master' unless ($RepoBranch eq "");
    $output = $self->repo(" forall -c \"git log -1 --pretty=format:%H@%ct%n $repoBranch --\"");
    
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
    my ($self, $opts) = @_;

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
    
    chdir($repo_dir);    
    
    my $RepoBranch = $opts->{RepoBranch};
    my $repoManifest = $opts->{RepoManifest};
    my $repoMirror = $opts->{RepoMirror};
    my $repoURL = $opts->{RepoUrl};
    
    if ($self->test_repo == 0) {
        my $command ="init -u $repoURL";
        
        $command .= " -m \"$repoManifest\" " unless ($repoManifest eq "");
        $command .= " -b \"$RepoBranch\" " unless ($RepoBranch eq "");
        $command .= " --mirror " unless ($repoMirror == 0);    
        $command .= " 2>&1";
        
        my $output = $self->repo($command);
        
        if ($output =~ m/repo initialized in/){            
            $command = " sync 2>&1";
            $output = $self->repo($command);    
        }else {
            exit(1);
        }                         
    } else {        
        $RepoBranch = 'm/'.$RepoBranch unless ($RepoBranch eq "");
        $output = $self->repo(" forall -c \"git reset --hard $RepoBranch\"", 
		 {LogCommand => 1, LogResult => 0, IgnoreError => 1});		
        $output = $self->repo(" forall -c \"git clean -xfd\"");
        
        $command = " sync 2>&1";
        $output = $self->repo($command);
    } 

    my $currTime = time();
        
    my $now = time2str($currTime);
                    
    my $scmKey = "Repo-$now";

    $changeLogs_since = "";
    $changeLogs_since = $self->getStartForChangeLog($scmKey);
      
    if ($changeLogs_since eq "") {
        $changeLogs_since = $now;
    }    
        
               
    my $changelog = $self->repo(" forall -c \"git log --since=\"$changeLogs_since\"\"");
	
	my $snapshot = $self->repo(" forall -c \"git describe --always\""); 
        
       
    $self->setPropertiesOnJob($scmKey, $snapshot, $changelog);
      
    chdir $here;

    if (!defined $cmndReturn) { 
        return 0;
    }
      
    return 1;    
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
    $scmInfo =~ m/(.*)\n(.*)\n/;
    $opts->{RepoWorkdir} = $1;
    $opts->{AgentWorkdir} = $2;
    print("Repo information received from client:\n"
            . "RepoWorkdir: $opts->{RepoWorkdir}\n"
            . "AgentWorkdir: $opts->{AgentWorkdir}\n");
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
    
    my $result = $self->checkoutCode($opts);
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
    $self->cpf_saveScmInfo($opts,"$opts->{scm_repoworkdir}\n"
                           . "$opts->{scm_agentworkdir}\n"); 
    
    $self->cpf_findTargetDirectory($opts);
    $self->cpf_createManifestFiles($opts);
    

    my $output  = $self->RunCommand( "repo status", {LogCommand => 1,IgnoreError=>1});
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
           
            if (($action = 'A-') || ($action = 'M-') ) {           
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
    $self->RunCommand("repo upload", {LogCommand =>1});
   
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
  --agentworkdir  <path>      The path to the source directory used by the agent";

    my %ScmOptions = (         
        "repoworkdir=s"             => \$opts->{scm_repoworkdir},    
        "agentworkdir=s"             => \$opts->{scm_agentworkdir},       
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