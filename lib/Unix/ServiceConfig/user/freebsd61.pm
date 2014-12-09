######################################################################
#
# Unix/ServiceConfig/user/freebsd61.pm
#
# Copyright (C) 2006-2014 David Lundgren. All Rights Reserved
#
# MIT License
#
######################################################################

=pod

=head1 NAME

Unix::ServiceConfig::user::freebsd61 - FreeBSD 6.1 User Configuration Interface Class

=head1 SYNOPSIS

	use Unix::ServiceConfig;

	my @args = [ 'test_user' ];

	my $db = Unix::ServiceConfig::new(
		-type    => 'user'
		-file    => 'file.conf',
		-action  => 'add');

	$db->execute(@args);

=cut

package Unix::ServiceConfig::user::freebsd61;

no warnings 'portable';
use 5.6.0;
use strict;
use warnings;

=head1 REQUIRES

perl5.005, File::Basename, Term::ANSIColor, Unix::ServiceConfig

=cut

use vars qw(@ISA);
use File::Basename;
use Term::ANSIColor;
use Unix::ServiceConfig;

=head1 EXPORTS

None.

=cut

@ISA = qw(Unix::ServiceConfig);

my $VERSION   = '0.01';
my $REVISION  = sprintf("%d.%02d", q$Revision: 1.3 $ =~ /(\d+)\.(\d+)/);

=head1 CLASS VARIABLES

=over

=item B<$valid_actions>

The valid actions for this class are: add, del, delete, hold, list, unhold.

=back

=cut

my $actions = [
	  'add',
	  'del',
	  'delete',
	  'hold',
	  'list',
	  'unhold',
	];

=head1 CLASS FUNCTIONS

=over

=item B<new>

  Title    : new
  Usage    : my $sc = Unix::ServiceConfig->new(
                -type    => 'user',
                -file    => 'file.conf',
                -action  => 'add',
                -config  => %config,
                -generic => %generic_config)
  Function : Returns an object of the type requested. If config or 
             generic are not defined then it will read the 
             configuration information from the file that was passed
             in.
  Returns  : A new object.
  Args     : -type    : The type of object to create 
                        (dns, web, mail, db, or user).
             -file    : The configuration filename.
             -action  : The action that the object is expected to perform.
             -config  : The configuration for the type. [optional]
             -generic : The generic configuration.      [optional]

=cut

sub new {
	my($pkg, $mconf, $gconf, $file) = @_;
	my $class = ref($pkg) || $pkg;

	if ( (!$mconf) || (!$gconf) )
	{
		# we load both if one is missing
		my %c = $pkg->_parse_configuration($file);
		
		$mconf = $c{'user'};
		$gconf = $c{'generic'};
	}

	my %config = $pkg->_merge_config('user', $mconf, $gconf);
	
	my $self = { 
		'config'    => ( \%config ),
		'actions'   => $actions,
		'me'        => 'user',
		'check'     => 'user',
		'class'     => 'freebsd61',
        'base_type' => 'user',
		'file'      => $file,
		'debug'     => 0,
		'main'      => 1,
		'commands'  => [ $config{'command-restart'} ],
		'section'   => {
			'extra'     => { },
			'db'        => { },
		},
		'error'     => {
			'exists' => 0,
			'msg'    => '',
		},
		'log'       => {
			'action' => 'unknown',
			'what'   => 'user::freebsd61',
			'status' => 'unknown',
			'args'   => '',
		}
	};

	bless($self, $class);
	
	return($self);
} #new

=item B<Class Specific>
=cut
# XXX: need to document these
sub _getLine($$)
{
    my ($self, $file, $search);
    my $file = $self->make_path($file);
    my ($found, $_line) = $self->_file_search($file, $search);
    if (!$found) {
        return -1;
    }
    my @u = split(/:/, $_line);
    return @u;
}
sub getpwuid
{
    my ($self, $uid) = @_;
    return $self->_getLine('/etc/passwd', "^.*?:\*:$uid:");
}
sub getgrgid
{
    my ($self, $gid) = @_;
    return $self->_getLine('/etc/group', "^.*?:\*:$gid:");
}
sub getpwnam
{
    my ($self, $username) = @_;
    return $self->_getLine('/etc/passwd', "^$username:");
}

=item B<_delete_user>

  Title    : _delete_user
  Usage    : $self->_delete_user($);
  Function : Removes the user from the system.
  Returns  : 1 on failure, 0 on success
  Args     : $user : Username to remove

=cut

sub _delete_user($)
{
	my ($self, $user) = @_;
	my %args;
	$args{'user_name'} = $user;
	# this subroutine bypasses the need to obtain a username since we already
	# have that information

	return($self->_run_cmd('delete', 1, %args));
} #_delete_user

=item B<add_to_apache_chroot>

  Title    : add_to_apache_chroot
  Usage    : $self->add_to_apache_chroot();
  Function : Adds the user to the apache chroot.
  Returns  : 
  Args     : $user : The username.
             $home : The home directory of the user in the primary system.
                     NOTE: This directory MUST be within the apache chroot.

=cut

sub add_to_apache_chroot($$)
{
	my ($self, $user, $home) = @_;
	my $chroot = $self->{'config'}->{'apache-chroot'};
	
	# if chroot is set AND chroot is the beginning of the path for the user
	# then we add them to the chroot, otherwise the user can't be added to
	# the chroot
	if ( ('' ne $chroot) && ($home =~ /^$chroot/) )
	{
		$self->{'error'}->{'exists'} = 0;
		$self->_pretty_print_start("Adding ($user) to Apache chroot");
		# get the information from the main database because the user should
		# already exist
		my @u = $self->getpwnam($user);
		if (-1 == $#u)
		{
			$self->_set_error("The user does not exist.\n");
			return(1) if ($self->_print_error(1));
		}

		# update the directory field by removing the $chroot, and any /./
		$u[7] =~ s/$chroot//i;
		$u[7] =~ s/\/\.\///g;
		
		# Generate the proper user information for the password database file.
		my @userinfo;
		$userinfo[0] = $u[0]; # username     'root'
		$userinfo[1] = '*';   # password     '*'
		$userinfo[2] = $u[2]; # uid          '0'
		$userinfo[3] = $u[3]; # gid          '0'
		$userinfo[4] = '';    # login class  ''
		$userinfo[5] = '0';   # uid          '0'
		$userinfo[6] = '0';   # gid          '0'
		$userinfo[7] = $u[6]; # gecos        'charlie root'
		$userinfo[8] = $u[7]; # directory    '/root'
		$userinfo[9] = $u[8]; # shell        '/bin/tcsh'
		my $user_output = join(':', @userinfo);
		$user_output = "$user_output\n";

		# The name of the file that we are going to create.
		my $file = "$chroot/etc/master.passwd";
		
		# append the data to the file.
		if (1 == $self->_file_append($file, $user_output))
		{
			return(1) if ($self->_print_error(1));
		}
		
		# update the chroot database so that things work internally
		my %args;
		$args{'pwd_dir'}    = "/etc";
		$args{'user_name'}  = $user;
		$args{'chroot_dir'} = $chroot;
		
		chdir($chroot);
		
		if (1 == $self->_run_cmd('pwd_mkdb', 1, %args))
		{
			return(1) if ($self->_print_error(1));
		}
		
		$self->_print_ok();
	}
	return(0);
} #add_to_apache_chroot

=item B<cleanup_user_files>

  Title    : cleanup_user_files
  Usage    : $self->cleanup_user_files();
  Function : Removes the users mailspool files, atjobs, crontabs, and kills
             any processes that are running.
  Returns  : 
  Args     : $user : The user to cleanup files for

=cut

sub cleanup_user_files($)
{
	my ($self, $user) = @_;
	my ($dir, $tmp);

	# remove mail spool
	$dir = $self->{'config'}->{'directory-mailspool'};
	unlink("$dir/$user")     if (-e "$dir/$user");
	unlink("$dir/$user.pop") if (-e "$dir/$user.pop");
	
	# remove at jobs
	$dir = $self->{'config'}->{'directory-at'};
	$tmp = `find 2>/dev/null $dir -maxdepth 1 -user $user`;
	my @files = split("\n", $tmp);
	if (1 <= $#files)
	{
		foreach my $f (@files)
		{
			unlink($f);
		}
	}
	
	# remove cron tabs
	$dir = $self->{'config'}->{'directory-cron'};
	unlink("$dir/$user") if (-e "$dir/$user");

	# kill any user processes
	$tmp = `ps 2>/dev/null -U $user | grep -v '^\ *PID' | awk '{print \$1}'`;
	my $signal = $self->{'config'}->{'signal-kill'};
	my @procs = split("\n", $tmp);
	if (1 <= $#procs)
	{
		foreach my $p (@procs)
		{
			kill($signal, $p);
		}
	}
	
	return(0);
} #cleanup_user_file

=item B<delete_from_apache_chroot>

  Title    : delete_from_apache_chroot
  Usage    : $self->delete_from_apache_chroot();
  Function : Remove a user from the apache chroots pwd files.
  Returns  : 
  Args     : $user : The username.
             $home : The home directory of the user in the primary system.
                     NOTE: This directory MUST be within the apache chroot.

=cut

sub delete_from_apache_chroot($)
{
	my ($self, $user, $home) = @_;
	my $chroot = $self->{'config'}->{'apache-chroot'};
	my $lineno = my $save = 0;
	my (@data, $fh);
	my $file = "$chroot/etc/master.passwd";
	
	# Don't do anything if the users home directory doesn't contain the apache
	# chroot.
	if ( ('' ne $chroot) && ($home =~ /^$chroot/) )
	{
		$self->_pretty_print_start("Removing ($user) from Apache chroot");
		# get the data from the file
		open($fh, "$file");
		while(my $line = <$fh>)
		{
			$lineno++;
			my $orig = $line;
			# trim any whitespace fore/aft of the string, and reduce multiple white-
			# space to single whitespace
			chomp($line);
			$line =~ s/^\s*//g;
			$line =~ s/\s+/ /g;
			if ($line !~ /^$user/i)
			{
				push(@data, $orig);
			}
			elsif ($line =~ /^$user/i)
			{
				$save = 1;
			}
		}
		if ( ($save) && (1 == $save) )
		{
			# Hopefully no other processes are using it (There could be a better way
			# for doing this)
			open($fh, ">$file");
			print $fh @data;
			close($fh);
		}
		$self->_print_ok();
	}
	return(0);
} #delete_from_apache_chroot

=item B<get_class>

  Title    : get_class
  Usage    : $self->get_class();
  Function : Returns the login class of the user.
             NOTE: There are currently no checks in place for this category.
  Returns  : a string
  Args     : none

=cut

sub get_class
{
	my ($self) = @_;
	
	my $class = $self->_get_input_with_check(
	  "Login class", "Not a valid class",
	  0,
	  $self->{'config'}->{'class-default'},
	  $self->{'config'}->{'class-valid'});

	# additional checks for the login class should go here.

	return($class);
} #get_class

=item B<get_gecos>

  Title    : get_gecos
  Usage    : $self->get_gecos();
  Function : Returns the comment that the user made about the user.
  Returns  : a string
  Args     : none

=cut

sub get_gecos
{
	my ($self) = @_;

	my $gecos = $self->_get_input_with_check(
	  "Full name", "Not valid data", 0, '',
	  $self->{'config'}->{'gecos-valid'});

	return($gecos);
} #get_gecos

=item B<get_group>

  Title    : get_group
  Usage    : $self->get_group();
  Function : Returns the primary group that the user will be placed in.
  Returns  : a string
  Args     : none

=cut

sub get_group
{
	my ($self)  = @_;
	my $_groups = $self->{'config'}->{'group-valid'};
	my $_syntax = $self->{'config'}->{'group-file-syntax'};
	my $_gs     =  '';
	
	# get the groups from the file specified if there is one
	my @_g = split(',', $_groups);
	@_g    = $self->_file_get_shell_commented($1) if ($_groups =~ /^f:(.*)/);

	foreach my $_group (@_g)
	{
		$_gs = "$_gs|$1" if ($_group =~ /$_syntax/);
	}
	$_gs =~ s/^|//gi;
	$_gs =  "^($_gs)\$";

	# Generally group is the user name but we are going to use whatever is given
	# in the configuration file
	my $group = $self->_get_input_with_check(
	  "Login group", "Not a valid group",
	  0,
	  $self->{'config'}->{'group-default'},
	  $self->{'config'}->{'group-default'});

	return($group);
} #get_group

=item B<get_groups>

  Title    : get_groups
  Usage    : $self->get_groups();
  Function : Returns the extra groups that a user will be joining.
  Returns  : a string (space delimited)
  Args     : $user  : The username.
             $group : The default group name

=cut

sub get_groups($$)
{
	my ($self, $user, $group) = @_;
	my $groups  = $self->{'config'}->{'group-default'};
	my $_groups = $self->{'config'}->{'group-valid'};
	my $_syntax = $self->{'config'}->{'group-file-syntax'};
	my $_gs     = '';
	
	# get a list of valid groups
	my @_g = split(',', $_groups);
	@_g    = $self->_file_get_shell_commented($1) if ($_groups =~ /^f:(.*)/);
	
	foreach my $_group (@_g)
	{
		$_gs = "$_gs|$1" if ($_group =~ /$_syntax/);
	}
	$_gs =~ s/^|//gi;
	$_gs =  "^($_gs)\$";

	# Generally group is the user name but we are going to use whatever is given
	# in the configuration file
	my $error = 0;
	do
	{
		$error  = 0;
		$groups = $self->_get_input("Login group is $group. Invite $user into other groups? ");
		my @__g = split(' ', $groups);
		foreach my $__g (@__g)
		{
			$error = 1 if ($__g !~ /$_gs/);
		}
	} while ($error);
	
	return($groups);
} #get_groups

=item B<get_home_dir>

  Title    : get_home_dir
  Usage    : $self->get_home_dir();
  Function : Returns the home directory specified.
  Returns  : a string
  Args     : $user : The username

=cut

sub get_home_dir($)
{
	my ($self, $user) = @_;
	my $split_dir;

	my $dir   = $self->{'config'}->{'home-default'};
	my $split = $self->{'config'}->{'home-split'};

	# determine if the user directories are being split on a rule
	my $use_split = ('ask' eq $self->{'config'}->{'use-home-split'}) ?
	  $self->_get_yesno("Split users in $dir (yes/no)") :
	  $self->{'config'}->{'use-home-split'};

	if ($self->_is_enabled($use_split))
	{
		$split_dir = $1 if ($user =~ /$split/i);
	}

	$dir =~ s/(\%)s()plit%/$split_dir/i if ($user =~ /$split/i);
	$dir =~ s/(\%)user_name%/$user/i;

	my $ddir =  $dir;
	$ddir    =~ s/(\%)c()hroot%//i;
	$ddir    =~ s/\/\//\//g;
	my $odir =  $ddir;
	
	# Anything works
	$ddir = $self->_get_input_with_check(
	  'Home directory', '', 0, $ddir, '.*');

	return($dir) if ($ddir eq $odir);
	return($ddir);
} #get_home_dir

=item B<get_shell>

  Title    : get_shell
  Usage    : $self->get_shell();
  Function : Returns the shell.
  Returns  : a string
  Args     : none

=cut

sub get_shell
{
	my ($self) = @_;
	
	my $shells_data = $self->{'config'}->{'shell-valid'};
	my $shells = '';
	my @sh;
	
	# get a list of valid shells
	@sh = split(',', $shells_data);
	@sh = $self->_file_get_shell_commented($1) if ($shells_data =~ /^f:(.*)/);
	
	# take the list and basename them all
	foreach my $shell (@sh)
	{
		if ('' ne $shell)
		{
			chomp($shell);
			$shells = "$shells " . basename($shell);
		}
	}
	$shells =~ s/^\s+//;
	my $regex = "^(".join('|',split(' ',$shells)).")\$";

	my $user_shell = $self->_get_input_with_check(
	  "Shell ($shells)", "Not a valid shell", 0,
	  basename($self->{'config'}->{'shell-default'}),
	  $regex);

	# now go through the shells and match the one that we were given
	foreach my $shell (@sh)
	{
		$user_shell = $shell if ($shell =~ /$user_shell/);
	}
	return($user_shell);
} #get_shell

=item B<get_uid>

  Title    : get_uid
  Usage    : $self->get_uid();
  Function : Returns the user ID.
  Returns  : an integer
  Args     : none

=cut

sub get_uid
{
	my ($self) = @_;
	my @u;
	
	my $uid = my $duid = 0;

	# we need to find the starting point of a valid uid
	for(my $i  = $self->{'config'}->{'uid-start'}; 
	    $i    <= $self->{'config'}->{'uid-max'};
	    $i++)
	{
		@u = $self->getpwuid($i);
		if (-1 == $#u)
		{
			$duid = $i;
			last;
		}
	}
	
	# if we have a 0 uid then we have a problem
	if (0 == $duid)
	{
		$self->_set_error("Couldn't find a valid UID");
		$self->_die_error() if ($self->{'main'}); # get_uid
	}

	# get the uid from the user and validate it
	my $error = 1;
	do
	{
		$error = 0;
		$uid = $self->_get_input("Uid", $duid);

		# This is a uid not a username
		if    ($uid =~ m/[a-z]/i)    { $error = 1; }
		# a valid uid must be below the max and above the min
		elsif ( ($uid > $self->{'config'}->{'uid-min'})
		     && ($uid < $self->{'config'}->{'uid-max'})
		      )
		{
			# check that the uid isn't in use
			@u = $self->getpwuid($uid);
			if (-1 != $#u)
			{
				$self->_error("UID ($uid) already in use.");
				$error = 1;
			}
		}
	} while ($error);
	
	return($uid);
} #get_uid

=item B<Filled in Stubs>

=item B<add>

  Title    : add
  Usage    : $self->add(@args);
  Function : Adds a user to the system.
  Returns  : an object
  Args     : @args : an array of the arguments to the function. 
                     The first argument must be the username, if it doesn't
                     exist it will ask for one.

=cut

sub add
{
	my ($self, @args) = @_;
	$self->{'log'}->{'args'}   = \@args;
	$self->{'log'}->{'action'} = 'add';
	my ($user) = @args;
	my $error;

	$user = $self->_get_valid_type_input($user);

	if (1 == $self->{'error'}->{'exists'})
	{
		$self->_print_check_start();
		return($self) if ($self->_print_error());
	}
	$self->{'section'}->{'extra'}->{'user_name'} = $user;

	my %args;

	# get the user information
	$args{'uid'}    = $self->get_uid();
	$args{'gecos'}  = $self->get_gecos();
	$args{'group'}  = $self->get_group();
	$args{'groups'} = $self->get_groups($user, $args{'group'});
=note 2006.08.00 dlundgren add
I deactivate this because I don't use it on my systems
and haven't taken the time to figure out WHERE the 
classes are to check against.
=cut
#	$args{'class'}  = $self->get_class();
	$args{'shell'}  = $self->get_shell();
	$args{'home'}   = $self->get_home_dir($user);
	$args{'chroot'} = ('ask' eq $self->{'config'}->{'use-chroot'}) ?
      $self->_get_yesno("Put ($user) in chroot") :
      $self->{'config'}->{'use-chroot'};

	# Get a password
	my ($pass, $display_pass, $use_random) = $self->get_password($user);
	$args{'password'} = $pass;

	# Lock out the account ?
	$args{'hold'} = $self->_get_yesno("Lock out the account after creation?",
	  $self->{'config'}->{'lock-account'});

	$self->_width_to_status("Chrooting user ($user)");
	$self->_width_to_status('Cleaning up from failed add attempt');
	$self->_width_to_status("Adding ($user) to Apache chroot");

	$self->_print_check_start();
	return($self) if ($self->_print_error());
	$self->_print_ok();

	# Print out the user information as a confirmation
	if (!$self->_is_enabled($self->{'config'}->{'verbose'}))
	{
		if ($self->_is_enabled($use_random))
		{
			$self->_pretty_print_start('Generated password');
			$self->_pretty_print_end('bold blue',$args{'password'});
		}
	}
	else
	{
		print "Username  : $user\n";
		print "Password  : $display_pass\n";
		print "Full Name : $args{'gecos'}\n";
		print "Uid       : $args{'uid'}\n";
#		print "Class     : $args{'class'}\n";
		print "Groups    : $args{'group'}";
		print " ($args{'groups'})" if ('' ne $args{'groups'});
		print "\n";
		print "Home      : $args{'home'}\n";
		print "Shell     : $args{'shell'}\n";
		print "Chroot    : $args{'chroot'}\n";
		print "Locked    : $args{'hold'}\n";
	}

	# if the user is to be chrooted then we add /./ to the end of it.
	$args{'home'} =~ s/(\%)c()hroot%\/?/\.\//i 
	  if ($self->_is_enabled($args{'chroot'}));
	$args{'real_home'} = $args{'home'};
	$args{'real_home'} = $self->_path_clean_chroot($args{'real_home'});

	# check if this information is ok
	if (!$self->_is_enabled($self->_get_yesno('OK (yes/no)', 'yes')))
	{
		$self->add($user, $pass);
		return($self);
	}

	# Now comes the true processing part of the module
	$self->_pretty_print_start("Adding ($user)");

	# we need to run the command-add to add the user to the system database
	$args{'user_name'} = $user;
	$args{'pipe_data'} = $args{'password'};

	if ($self->_run_cmd('add', 1, %args))
	{
		return($self) if ($self->_print_error());
	}

	# check that we have the user in the system
	my @u = $self->getpwnam($user);
	if (-1 == $#u)
	{
		$self->_set_error("User may already exist and was not detected.");
		if (1 == $self->{'error'}->{'exists'})
		{
			return($self) if ($self->_print_error());
		}
	}
	$self->_print_ok();

	# Make the users directory if we succeeded in adding the user
	$self->_pretty_print_start('Creating user home');
	my $home = $args{'real_home'};
	$home =~ s/$user//i;

	# make the primary directory (which should not be owned by the user)
	if ( (!-e $home) && (0 != $self->_mkdir($home, 0, 0, '0755')) )
	{
		return($self) if ($self->_print_error());
		exit(1)       if ($self->{'main'}); # user add (if main)
	}
	# make the users directory which should be owned by it.
	if ($self->_mkdir($args{'real_home'}, $args{'uid'}, $args{'group'}, '0755'))
	{
		return($self) if ($self->_print_error());
		exit(1)       if ($self->{'main'}); # user add (if main)
	}
	$self->_print_ok();
	
	# If apache has been chrooted and doesn't use the systems pwd.db for 
	# accessing where the users home directory is then we need to add the
	# user to apache's chroot passwd file and rebuild it. If there is an
	# error we cleanup by deleting the user from the system.
=todo 2006.08.11 dlundgren add
Ask if a failure in adding to the apache chroot means that the user
should be removed from the system.
=cut
	if ($self->add_to_apache_chroot($user, $args{'home'}))
	{
		$self->_pretty_print_start("Cleaning up from failed add attempt");

		# reverse the user add in the database and remove the directory
		if ($self->_delete_user($user))
		{
			return($self) if ($self->_print_error());
		}
		rmdir($args{'real_home'});
		$self->_print_ok();

		return($self);
	}
	
	# If the user is to be chrooted create the chroot.
=todo 2006.08.11 dlundgren add
Add another variable create-chroot to determine if the chroot has already
been created for the user.
=cut
	if ($self->_is_enabled($args{'chroot'}))
	{
		$self->_pretty_print_start("Chrooting user");
		my %arg;
		$arg{'user_name'} = $user;
		if ($self->_run_cmd('chroot', 1, %arg))
		{
			return($self) if ($self->_print_error());
		}
		$self->_print_ok();
	}
	
	return($self);
} #add

=item B<ask_action>

  Title    : ask_action
  Usage    : $self->ask_action();
  Function : Determines what to ask the user if this is being called as
             an extra section to the main one.
  Returns  : 
  Args     : $action : The action to perform.
             @args   : The arguments to the action.

=cut

sub ask_action
{
	my ($self, $action) = @_;
	my ($do, @args);
	return($self) if (!$self->{'data'});
	return($self) if (!$self->{'data'}->{'user_name'});
	my $user      = $self->{'data'}->{'user_name'};

	push(@args, $user);
	$self->{'main'} = 0;

	$self->_print_section_run();
	
	$do = $self->_get_yesno("Add ($user) to system", "Yn")
	  if ($action =~ /^add$/);
	$do = $self->_get_yesno("Delete ($user) from System", "Yn")
	  if ($action =~ /^del(ete)?$/);
	$do = $self->_get_yesno("Hold ($user) on system", "Yn")
	  if ($action =~ /^hold$/);
	$do = $self->_get_yesno("Re-Activate ($user) on system", "Yn")
	  if ($action =~ /^unhold$/);

	$self->ask_action_exists($action, ucfirst($self->{'base_type'}), $user);

	return($self) if ($self->_print_error());
	$self->_print_ok();

	if ($self->_is_enabled($do))
	{
		# Notify the command that we are not to get a username from the user
		$self->{'config'}->{'has_user'}  = $user;
		$self->add(@args)    if ($action =~ /^add$/);
		$self->del(@args)    if ($action =~ /^del(ete)?$/);
		$self->hold(@args)   if ($action =~ /^hold$/);
		$self->unhold(@args) if ($action =~ /^unhold$/);
	}

	return($self);
} #ask_action

=item B<del>

  Title    : del
  Usage    : $self->del(@args);
  Function : Deletes a user from the system.
  Returns  : an object
  Args     : @args : an array of the arguments to the function. 
                     The first argument must be the username, if it doesn't
                     exist it will ask for one.

=cut

sub del()
{
	my ($self, @args) = @_;
	$self->{'log'}->{'args'} = \@args;
	$self->{'log'}->{'action'} = 'del';
	my ($user) = @args;
	my ($fh, $file);

	$user = $self->_get_valid_type_input($user);

	$self->_width_to_status("Cleaning up ($user) files");
	$self->_width_to_status("Removing ($user)");
	$self->_width_to_status("Removing ($user) from Apache chroot");

	$self->_print_check_start();
	return($self) if ($self->_print_error());
	$self->_print_ok();

	$self->{'section'}->{'extra'}->{'user_name'} = $user;

	# clean up the users home directory from being in a chroot.
	my @u = $self->getpwnam($user);
	my $home = $self->_path_clean_chroot($u[7]);

	# remove from the apache chroot first, or fail otherwise
	if ($self->delete_from_apache_chroot($user, $home))
	{
		return($self) if ($self->_print_error());
	}

	# clean up the user directory and any crontab entries
	$self->_pretty_print_start("Cleaning up ($user) files");
	$self->cleanup_user_files($user);
	$self->_print_ok();

	# modify the users home directory if they are chrooted since some programs
	# do not like having the /./ in the path
	$self->_pretty_print_start("Removing ($user)");
	my %args;
	$args{'user_name'} = $user;
	$args{'dir'}       = $home;

	# modify the user directory in the system (but there is no need to worry)
	# if it doesn't modify then we can still delete it anyway, and not worry
	# about the command-delete not removing the directory since we will remove
	# the directory ourselves.
	$self->_run_cmd('modify', 1, %args);

	# remove the users directory
	if ($self->_deltree($home))
	{
		$self->_set_error("Error removing $home: $!.");
		return($self) if ($self->_print_error());
	}

	# now remove the user from the system
	if ($self->_delete_user($user))
	{
		return($self) if ($self->_print_error());
	}
	$self->_print_ok();
	
	return($self);
} #del

=item B<hold>

  Title    : hold
  Usage    : $self->hold(@args);
  Function : Puts a user on hold in the system.
  Returns  : an object
  Args     : @args : an array of the arguments to the function. 
                     The first argument must be the username, if it doesn't
                     exist it will ask for one.

=cut

sub hold
{
	my ($self, @args) = @_;
	$self->{'log'}->{'args'}   = \@args;
	$self->{'log'}->{'action'} = 'hold';
	my ($user) = @args;

	$user = $self->_get_valid_type_input($user);

	$self->_width_to_status("Putting ($user) on hold");
	$self->_width_to_status("Archiving ($user) directory");
	
	$self->_print_check_start();
	return($self) if ($self->_print_error());
	$self->_print_ok();

	$self->{'section'}->{'extra'}->{'user_name'} = $user;

	$self->_pretty_print_start("Putting ($user) on hold");
	my %args;
	$args{'user_name'} = $user;
=todo 2006.08.11 dlundgren hold
Kill all user processes, and move extra files, like what is done
when users are deleted.
=cut
	if ($self->_run_cmd('hold', 1, %args))
	{
		return($self) if ($self->_print_error());
	}
	$self->_print_ok();

	# If the user is to be put on hold, then check if the directory is to
	# to be archived and archive their home directory.
	if ($self->_is_enabled(
	    ('ask' eq $self->{'config'}->{'hide-directory'}) ? 
	      $self->_get_yesno("Archive user directory during hold?") :
	      $self->{'config'}->{'hide-directory'})
	   )
	{
		$self->_pretty_print_start("Archiving ($user) directory");
		my $dir = $self->{'config'}->{'directory-archive'};
		$self->_mkdir($dir, 0, 0, '0755') if (!-e $dir);
		my @u = $self->getpwnam($user);
		my $home = $self->_path_clean_chroot($u[7]);
		if (-1 == rename($home, "$dir/$user"))
		{
			return($self) if ($self->_print_error());
		}
		$self->_print_ok();
	}

	return($self);
} #hold

=item B<list>

  Title    : list
  Usage    : $self->list(@args);
  Function : Lists the users in the system
  Returns  : an object
  Args     : @args : an array of the arguments to the function. 
                     -search: The term to search for. [optional]
                              Defaults to '^.*';

=cut

sub list
{
	my ($self, @args) = @_;
	$self->{'log'}->{'args'}   = \@args;
	$self->{'log'}->{'action'} = 'list';
	my ($search) = @args;
	my (%list, $i);
	
	$search = '^.*' if (!$search);
	
	# remove the run-sections since we are not worried about listing for other
	# modules
	$self->{'config'}->{'run-sections'} = '';
	
	# we use the uid-min as the starting point for where to start finding users
	# we assume that the user knows that root exists
	my $uid_min    = $self->{'config'}->{'uid-min'};
	my $uid_max    = $self->{'config'}->{'uid-max'};
	my $regex_held = $self->{'config'}->{'hold-style'};
	my $count_size = 4;
	my $user_size  = 
	my $group_size = 
	my $home_size  = 0;

	# this takes a while to run through so many users. I was thinking about
	# using getpwent to get a list of the users, but I decided that the trade
	# off of time versus possible memory leaks is a good trade off, this way
	# only the users that are valid are being utilized.
	for($i = $uid_min; $i <= $uid_max; $i++)
	{
		my @u = $self->getpwuid($i);
		if ( (-1 != $#u) && ($u[0] =~ /^$search/) )
		{
			# the user exists so check if they are locked
			$list{$i}{'held'}   = 0;
			$list{$i}{'held'}   = 1 if ($u[1] =~ /$regex_held/);

			delete($u[1]); # delete the password as soon as possible

			my $user  = $u[0]; # get the username
			my $group = $self->getgrgid($u[3]); # get the group name
			my $home  = $self->_path_clean_chroot($u[7]); #clean the home
			
			# determine the width of the display columns
			$user_size  = length($user)  if (length($user)  > $user_size);
			$group_size = length($group) if (length($group) > $group_size);
			$home_size  = length($home)  if (length($home)  > $home_size);
			$count_size = length($i)     if (length($i)     > $count_size);

			# set the user information
			$list{$i}{'home'}   = $home;		
			$list{$i}{'group'}  = $group;
			$list{$i}{'name'}   = $user;
			
			# check if the user is chrooted
			$list{$i}{'chroot'} = 0;
			$list{$i}{'chroot'} = 1 if ($u[7] =~ /\/.\//);
		}
	}

	# print the list
	print("Users found (UID > $uid_min)\n");	

	$user_size  = 8 if (8 > $user_size);
	$group_size = 5 if (5 > $group_size);
	$home_size  = 4 if (4 > $home_size);
	$count_size = 3 if (3 > $count_size);

	# print the column headers
	printf("\%${count_size}s  ", 'UID');
	printf("\%-${user_size}s  ",  'Username');
	printf("\%-${group_size}s  ", 'Group');
	printf("\%-${home_size}s  ",  'Home');
	printf("Flags\n");

	# If there are no users then tell the user
	$self->_die_print('  No users found') if (0 == keys(%list)); # list

	# print the user list in sorted order
	foreach my $uid (sort {$a <=> $b} keys %list)
	{
		my $c      = sprintf("\%${count_size}s.", $uid);
		my $user   = sprintf("\%-${user_size}s",  $list{"$uid"}{'name'});
		my $group  = sprintf("\%-${group_size}s", $list{"$uid"}{'group'});
		my $home   = sprintf("\%-${home_size}s",  $list{"$uid"}{'home'});
		my $held   = (1 == $list{"$uid"}{'held'})   ? '(held)'  : '';
		my $chroot = (1 == $list{"$uid"}{'chroot'}) ? '(chrooted)' : '';
		my $line   = sprintf(" %s  %s  %s  %s%s",
		  $user, $group, $home, $held, $chroot);

		$self->_print_list_line($uid, $line, $list{"$uid"}{'held'});	
	}

	exit(0); # list
} #list

=item B<type_exists>

  Title    : type_exists
  Usage    : $self->type_exists(@args);
  Function : Determines if the user exists
  Returns  : an object
  Args     : $user : The username to check for existence.

=cut

sub type_exists($)
{
	my ($self, $user) = @_;
	my $fh;
	my $held = 0;

	my $regex_hold = $self->{'config'}->{'hold-style'};
	my @u = $self->getpwnam($user);
	if (-1 != $#u)
	{
		$held = 1 if ($u[1] =~ /$regex_hold/);
		return (1, $held);
	}

	return (0,$held);
} #type_exists

=item B<unhold>

  Title    : unhold
  Usage    : $self->unhold(@args);
  Function : Takes a user off hold in the system.
  Returns  : an object
  Args     : @args : an array of the arguments to the function. 
                     The first argument must be the username, if it doesn't
                     exist it will ask for one.

=cut

sub unhold
{
	my ($self, @args) = @_;
	$self->{'log'}->{'args'}   = \@args;
	$self->{'log'}->{'action'} = 'unhold';
	my ($user) = @args;

	$user         = $self->_get_valid_type_input($user);
	my $reinstate = ('ask' eq $self->{'config'}->{'hide-directory'}) ? 
      $self->_get_yesno("Reinstate user directory after hold?") :
      $self->{'config'}->{'hide-directory'};

	$self->_width_to_status("Taking ($user) off hold");
	$self->_width_to_status("Restoring ($user) directory");
	
	$self->_print_check_start();
	return($self) if ($self->_print_error());
	$self->_print_ok();

	$self->{'section'}->{'extra'}->{'user_name'} = $user;

	$self->_pretty_print_start("Taking ($user) off hold");

	my %args;
	$args{'user_name'} = $user;
	if (-1 == $self->_run_cmd('unhold', 1, %args))
	{
		return($self) if ($self->_print_error());
	}
	$self->_print_ok();

	# If the user is to be restored then their archived directory must also be
	# restored.
	if ($self->_is_enabled($reinstate))
	{
		$self->_pretty_print_start("Restoring ($user) directory");
		my $dir = $self->{'config'}->{'directory-archive'};
		$self->_mkdir($dir, 0, 0, '0755') if (!-e $dir);
		my @u = $self->getpwnam($user);
		my $home = $self->_path_clean_chroot($u[7]);
		if (-1 == rename("$dir/$user", $home))
		{
			return($self) if ($self->_print_error());
		}
		$self->_print_ok();
	}

	return($self);
} #unhold

1;

__END__

