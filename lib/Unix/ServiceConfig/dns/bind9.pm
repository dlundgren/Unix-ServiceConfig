######################################################################
#
# Unix/ServiceConfig/dns/bind9.pm
#
# Copyright (C) 2006-2014 David Lundgren. All Rights Reserved
#
# MIT License
#
######################################################################

=pod

=head1 NAME

Unix::ServiceConfig::db::mysql41 - MySQL 4.1 Configuration Interface Class

=head1 SYNOPSIS

	use Unix::ServiceConfig;

	my @args = [ 'test_user' ];

	my $db = Unix::ServiceConfig::new(
		-type    => 'dns'
		-file    => 'file.conf',
		-action  => 'add');

	$db->execute(@args);

=cut

package Unix::ServiceConfig::dns::bind9;

no warnings 'portable';
use 5.6.0;
use strict;
use warnings;

use vars qw(@ISA);

=head1 REQUIRES

perl5.005, Term::ANSIColor, Unix::ServiceConfig

=cut

use Term::ANSIColor;
use Unix::ServiceConfig;

@ISA = qw(Unix::ServiceConfig);

my $VERSION   = '0.01';
my $REVISION  = sprintf("%d.%02d", q$Revision: 1.2 $ =~ m/(\d+)\.(\d+)/);

=head1 CLASS VARIABLES

=over

=item B<$actions>

The valid actions for this class are: add, del, delete, edit, 
hold, list, unhold.

=back

=cut

my $actions = [
	  'add',
	  'del',
	  'delete',
	  'edit',
	  'hold',
	  'list',
	  'unhold',
	];

=head1 CLASS FUNCTIONS

=over

=item B<new>

  Title    : new
  Usage    : my $sc = Unix::ServiceConfig->new(
                -type    => 'dns',
                -file    => 'file.conf',
                -action  => 'add',
             )
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
		
		$mconf = $c{'dns'};
		$gconf = $c{'generic'};
	}

	my %config = $pkg->_merge_config('dns', $mconf, $gconf);
	
	my $self = { 
		'config'    => ( \%config ),
		'file'      => $file,
		'actions'   => $actions,
		'main'      => 1,
		'check'     => 'Bind',
		'me'        => 'dns',
		'class'     => 'bind9',
		'base_type' => 'domain',
		'zone_type' => '',
		'debug'     => 0,
		'error'     => {
			'exists' => 0,
			'msg'    => '',
		},
		'log'     => {
			'action' => 'unknown',
			'what'   => 'dns',
			'status' => 'unknown',
			'args'   => '',
		}
	};

	bless($self, $class);
	
	return($self);
} #new

=item B<_create_serial>

  Title    : _create_serial
  Usage    : $self->_create_serial();
  Function : Returns a serial number created in YYYYMMDDNN format.
  Returns  : a number
  Args     : $iteration : The next in the sequence.

=cut

sub _create_serial
{
	my ($self, $iteration) = @_;
	$iteration = '00' if (!$iteration);
	
	# get the year, month, and day
	my @date = localtime();
	my $month  = ($date[4] < 10) ? '0' . $date[4] : $date[4];
	my $day    = ($date[3] < 10) ? '0' . $date[3] : $date[3];
	
	# put everything together
	return(($date[5] + 1900)  . $month . $day . '00');
} #_create_serial

=item B<make_path>

  Title    : make_path
  Usage    : $self->make_path();
  Function : 
  Returns  : 
  Args     : $path     : The path.
             $to       : Where the path is going.
             $absolute : Whether or not the path should be absolute. [optional]
                         Defaults to 0.

=cut

sub make_path($$;$)
{
	my ($self, $path, $to, $absolute) = @_;
	my $_path = '';
	$absolute = 0 if (!$absolute);

	return(-1)    if (!$path);
	return($path) if ($path =~ m/^\//i);

	# we only have two types of paths zones (main,%zone_type%)
	if ('main' ne $to)
	{
		# main may be absolute at which point base MUST be absolute
		if ($self->{'config'}->{'directory-main'} !~ m/^\//)
		{
			if ( (!$self->{'config'}->{'directory-base'})
			  && ($self->{'config'}->{'directory-base'} !~ m/^\//)
			   )
			{
				$self->_set_error("directory-base in the generic config must exist and be absolute.");
				$self->_die_error() if ($self->{'main'}); # make_path
				return(-1);
			}
			$_path = $self->{'config'}->{'directory-base'} . '/' .
				$self->{'config'}->{'directory-main'}
		}
		else
		{
			$_path = $self->{'config'}->{'directory-main'};
		}
	}

	my $zone_dir = $self->{'zone_type'}.'-directory';

	if ( $self->{'zone_type'} && ($self->{'config'}->{$zone_dir}) )
	{
		my $zdir = $self->{'config'}->{$zone_dir};
		# type-directory must exist in the config
		if (!$zdir)
		{
			my $msg = "$zone_dir must exist in the config.";
			$self->_die_print($msg, 1) if ($self->{'main'});
			$self->_set_error($msg);
			return(-1);
		}

		if ($path !~ m/$zdir/)
		{
			$_path = ($_path ? $_path . '/' : '') . $zdir;
		}
	}

	return($_path.'/'.$path);
} #make_path

=item B<create_dir>

  Title    : create_dir
  Usage    : $self->create_dir();
  Function : Creates a directory based off the information supplied in th
             configuration.
  Returns  : 
  Args     : $dir  : The directory to create.
             $type : What type of directory we are creating.

=cut

sub create_dir($$)
{
	my ($self, $dir, $type) = @_;

	my $owner = $self->{'config'}->{$type.'-owner'};
	my $group = $self->{'config'}->{$type.'-group'};
	my $mode  = $self->{'config'}->{$type.'-mode'};
	  
	$self->_mkdir($dir, $owner, $group, $mode);
} #create_dir

=item B<extra_type_checks>

  Title    : 
  Usage    : $self->();
  Function : 
  Returns  : 
  Args     : 

=cut

sub extra_type_checks($$$$%)
{
	my ($self, $domain, $what, $e, $h, %args) = @_;

	return(0) if (!$self->{'zone_type'});

	my $t = $self->{'zone_type'};
	
	# Place extra checks on domains here

	my $type = lc($self->{'config'}->{'type'});	

	my $file = $self->{'config'}->{$t.'-conf-file'};
	my $tpl  = $self->{'config'}->{$t.'-template'};
	my $dir  = $self->{'config'}->{$t.'-directory'};

	$self->{'zone-type'} = $t;
	$dir  = $self->make_path($dir, $t, 1);
	$file = $self->make_path($file, $t, 0);
	$tpl  = $self->_path_to_tpl($tpl);
	
	return(-1) if ($dir  =~ m/^\-1$/i);
	return(-1) if ($file =~ m/^\-1$/i);

	# make sure that the files exists
	if ($self->_ask_to_create_file($file))
	{
		$self->_set_error("Can't $what from non-existant files: $file.\n");
		return(-1);
	}
	if ($self->_ask_to_create_directory($dir))
	{
		$self->_set_error("Can't $what from non-existant files: $file.\n");
		return(-1);
	}

	# the template must exist with data in it
	if (!-e $tpl)
	{
		$self->_set_error("Can't $what from non-existant files: $file.\n");
		return(-1);
	}

	return(0);
} #extra_type_checks

#
# Public
#

=item B<get_files>

  Title    : get_files
  Usage    : $self->get_files();
  Function : Gets the files that this domain type uses.
  Returns  : an array (directory, template, configuration file).
  Args     : $type : What type of directory we are creating.

=cut

sub get_files($)
{
	my ($self, $type) = @_;

	my $config = $self->{'config'}->{$type.'-conf-file'};
	my $tpl    = $self->{'config'}->{$type.'-template'};
	my $dir    = $self->{'config'}->{$type.'-directory'};

	$self->{'zone_type'} = $type;

	return(-1) if (($dir    = $self->make_path($dir, '', 1))       =~ m/^\-1/i);
	return(-1) if (($config = $self->make_path($config, $type, 0)) =~ m/^\-1/i);
	$tpl    = $self->_path_to_tpl($tpl);

	return($dir, $tpl, $config);
} #get_files

#
# Class
#

=item B<add>

  Title    : add
  Usage    : $self->add(@args);
  Function : Adds a domain to the DNS system.
  Returns  : an object
  Args     : @args : an array of the arguments to the function. 
                     The first argument is the type of domain to add, i.e. - 
                     master, slave, dynamic, etc.
                     The second argument is the domain to add.
                     If there is no second argument then the first is assumed
                     to be the domain name, and type is assumed to be master.

=cut

sub add
{
	my ($self, @args) = @_;
	$self->{'log'}->{'args'}   = \@args;
	$self->{'log'}->{'action'} = 'add';

	# Determine what the user wants, and if type is not specified then it is 
	# master and the domain is in type.
	my ($type, $domain) = @args;
	if (!$args[1])
	{
		$domain = $type;
		$type = 'master';
	}

	my ($serial, $re);

	# Check the domain if it is set or get one from the user
	$domain = $self->_get_valid_type_input($domain, '', ('type' => $type));

	$self->_width_to_status("Adding ($domain) as $type");

	$self->_print_check_start();
	return($self) if ($self->_print_error());

	my ($dir, $tpl, $config) = $self->get_files($type);

	return($self) if ($self->_print_error());
	$self->_print_ok();

	$self->_pretty_print_start("Adding ($domain) as $type");

	if ($self->{'config'}->{$type.'-split'})
	{
		$re = $self->{'config'}->{$type.'-split'};
		if ($domain =~ m/($re)/i)
		{
			$dir = $1;
			$dir = $self->make_path($dir, '',1);
			$self->create_dir($dir, $type);
		}
	}
	my $name = $self->{'config'}->{$type.'-file-name'};

	# continue unless we can't open the template file
	my $conf = join('', $self->_file_get($tpl));

	# what we are doing depends on the type
	if ('master' eq $type)
	{
		# create the zone information
		$serial = $self->_create_serial();

		$tpl = $self->_path_to_tpl(
			$self->{'config'}->{$type.'-db-template'});
		$name =~ s/\%domain\%/$domain/gi;
		my $zone = join('', $self->_file_get($tpl));
		$zone =~ s/\{domain\}/$domain/gi;
		$zone =~ s/\{serial\}/$serial/gi;
		
		$self->_file_create($dir.'/'.$name, $zone);
	}
	elsif ('slave' eq $type)
	{
=todo 2006.08.11 dlundgren add
Determine if Bind9 slave types have any configuration beyond their
entry (and associated values) in the named configuration as slaves.
=cut
		# There are no output templates for these
	}
	else
	{
		$self->_set_error("Invalid type specified ($type).\n");
	}
	return($self) if ($self->_print_error());

	# The files may be split among seperate directories on the letters of the
	# first characters.
	$dir = '';
	if ($self->{'config'}->{$type.'-split'})
	{
		$re = $self->{'config'}->{$type.'-split'};
		if ($domain =~ m/($re)/i)
		{
			$dir = $1;
		}
		$dir = $self->make_path($dir, 'main', 0);
	}

	$conf =~ s/\{domain\}/$domain/gi;
	$conf =~ s/\{dir\}/$dir/gi;
	$conf =~ s/\{file\}/$name/gi;

	$self->_file_append($config, $conf);
	return($self) if ($self->_print_error());
	$self->_print_ok();

	return($self);
} # add

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
	return($self) if (!$self->{'data'}->{'domain'});
	my $domain    = $self->{'data'}->{'domain'};

	push(@args, $domain);
	push(@args, $self->{'data'}->{'alias'}) 
	  if ( ($action =~ m/^alias$/i)
	    && ($self->{'data'}->{'alias'})
	     );

	$self->{'main'} = 0;
	
	$self->_print_section_run();

	$do = $self->_get_yesno("Add ($domain) to system", "Yn")
	  if ($action =~ /^add$/);
	$do = $self->_get_yesno("Delete ($domain) from System", "Yn")
	  if ($action =~ /^del(ete)?$/);
	$do = $self->_get_yesno("Hold ($domain) on system", "Yn")
	  if ($action =~ /^hold$/);
	$do = $self->_get_yesno("Re-Activate ($domain) on system", "Yn")
	  if ($action =~ /^unhold$/);

	$self->ask_action_exists($action, ucfirst($self->{'base_type'}), $domain);
	return($self) if ($self->_print_error());
	$self->_print_ok();

	if ($self->_is_enabled($do))
	{
		# Notify the command that we are not to get a username from the user
		$self->{'config'}->{'has_domain'}  = $domain;
		$self->add(@args)    if ($action =~ /^add$/);
		$self->del(@args)    if ($action =~ /^del(ete)?$/);
		$self->hold(@args)   if ($action =~ /^hold$/);
		$self->unhold(@args) if ($action =~ /^unhold$/);
	}

	return($self);
} #ask_action

=item B<del>

  Title    : del
  Usage    : $self->add(@args);
  Function : Deletes a domain from the DNS system.
  Returns  : an object
  Args     : @args : an array of the arguments to the function. 
                     The first argument must be the domain, if it doesn't
                     exist it will ask for one.

=cut

sub del
{
	my ($self, @args) = @_;
	$self->{'log'}->{'args'} = \@args;
	$self->{'log'}->{'action'} = 'del';
	my ($domain) = @args;
	my ($fh, $file);

	# get the domain and associated file information if they exist
	$domain = $self->_get_valid_type_input($domain);
	my ($t, $held, $type, $db_file) = $self->domain_exists($domain);

	$self->_width_to_status("Deleting ($domain)");
	$self->_print_check_start();
	return($self) if ($self->_print_error());

	# get the type information
	my ($dir, $tpl, $config) = $self->get_files($type);
	return($self) if ($self->_print_error());

	# make sure that the db_file is set to the absolute path
	$db_file = $self->make_path($db_file, $type, 1);
	$self->_set_error('Could not create proper paths') if ($db_file !~ m/^\//);
	return($self) if ($self->_print_error());

	# determine if we are splitting the domains into different directories
	if ($self->{'config'}->{$type.'-split'})
	{
		my $re = $self->{'config'}->{$type.'-split'};
		$dir = $1 if ($domain =~ m/($re)/i);
#book
		$dir = $self->make_path($dir, $type, 1);
		
	}
	
	# determine the file name for the file
	my $name = $self->{'config'}->{$type.'-file-name'};
	$name =~ s/\%domain\%/$domain/gi;

	if ($db_file ne "$dir/$name")
	{
		my $file1 = ( ( -e $db_file) ? 1 : 0 );
		my $file2 = ( ( -e "$dir/$name") ? 1 : 0 );
		if ( (1 == $file1) && (1 == $file2) )
		{
			my $choice = '';
			while(1)
			{
				$choice = $self->_get_input(
					"Zone Information found at:\n\t$db_file\nAND\n\t$dir/$name\n".
					'Delete which before deleting domain (1=file #1, 2=file #2 [default])'
					, '12', '?')
					if ( (1 == $file1) && (1 == $file2) );
				if ($choice =~ /^(12|2)/i)
				{
					unlink("$dir/$name");
					last;
				}
				elsif ($choice =~ /^1/)
				{
					unlink($db_file);
					$db_file = "$dir/$name";
					last;
				}
			}
		}
	}
	elsif ( !( -e $db_file ) )
	{
		$self->_set_error("Database file doesn't exist ($db_file).");
	}
	return($self) if ($self->_print_error());
	$self->_print_ok();

	$self->_pretty_print_start("Deleting ($domain)");
	$self->_delete($domain, $config, 1);
	return($self) if ($self->_print_error());
	# we delete the db-file after removing from the file itself because it will
	# error out before if it is not removed
	unlink($db_file);

	$self->_print_ok();

	return($self);
} #del

=item B<edit>

  Title    : edit
  Usage    : $self->edit(@args);
  Function : Calls an edit command to edit the domain file
  Returns  : an object
  Args     : @args : an array of the arguments to the function. 
                     The first argument must be the domain, if it doesn't
                     exist it will ask for one.

=cut

sub edit
{
	my ($self, @args) = @_;
	$self->{'log'}->{'args'}   = \@args;
	$self->{'log'}->{'action'} = 'list';
	my ($domain) = @args;
	my ($count, $fh, %domains, $list);

	$domain = $self->_get_valid_type_input($domain);

	if (1 == $self->{'error'}->{'exists'})
	{
		if ($self->{'error'}->{'msg'} =~ m/on hold/i)
		{
			print("Domain ($domain) is currently on hold.\n");
			my $answer = $self->_get_yesno("Edit ($domain) anyway", 'n', 1);
			if (!$self->_is_enabled($answer))
			{
				return($self) if ($self->_print_error());
				exit(0); # edit
			}
		}
	}

	my ($t, $held, $type, $db_file) = $self->domain_exists($domain);

	return($self) if ($self->_print_error());

	# we need to the absolute file path
	my $file = $self->make_path($db_file,$type,1);
	return($self) if ($self->_print_error());

	my %args;
	$args{'line'} = 0;
	$args{'file'} = $file;
	$self->_run_cmd('edit', 0, %args);
	$self->_print_error();
	return($self);
} #edit

=item B<hold>

  Title    : hold
  Usage    : $self->hold(@args);
  Function : Puts a domain on hold in the DNS system.
  Returns  : an object
  Args     : @args : an array of the arguments to the function. 
                     The first argument must be the domain, if it doesn't
                     exist it will ask for one.

=cut

sub hold
{
	my ($self, @args) = @_;
	$self->{'log'}->{'args'} = \@args;
	$self->{'log'}->{'action'} = 'hold';
	my ($domain) = @args;
	my $fh;

	$domain = $self->_get_valid_type_input($domain);
	my ($t, $held, $type, $db_file) = $self->type_exists($domain);

	my ($dir, $tpl, $config) = $self->get_files($type);

	$self->_width_to_status("Putting ($domain) on hold");

	$self->_print_check_start();
	return($self) if ($self->_print_error());
	$self->_print_ok();

	$self->_pretty_print_start("Putting ($domain) on hold");
	$self->_hold($domain, $config, 0, 1);
	return($self) if ($self->_print_error());
	$self->_print_ok();

	return($self);
} #hold

=item B<list>

  Title    : list
  Usage    : $self->list(@args);
  Function : Lists the domains in the DNS system
  Returns  : an object
  Args     : @args : an array of the arguments to the function. 
                     -type   : The type of zone.
                     -search : The term to search for. [optional]

=cut

sub list
{
	my ($self, @args) = @_;
	$self->{'log'}->{'args'}   = \@args;
	$self->{'log'}->{'action'} = 'list';
	my ($type, $search) = @args;
	if (!$args[1])
	{
		$search = $type;
		$type = '';
	}
	my ($count, %list);
	$type = $self->{'config'}->{'config-files'} if ( (!$type) || ($type eq 'all') );

	if ($type =~ /,/)
	{
		$type =~ s/\s//gi;
		my @files = split(',',$type);
		foreach my $f (@files)
		{
			($count, %list) = $self->_list($f, $search);
			my $fn = $self->{'config'}->{$f.'-conf-file'};
			print "Zones in: $fn\n"    if (!$search);
			print "Zones matching '$search*' in: $fn\n" if ($search);
			print "  No Zones found\n" if (0 == $count);
			$self->print_list(%list)   if (0 < $count);
			print "\n";
		}
	}
	else
	{
		($count, %list) = $self->_list($type, $search);
		my $fn = $self->{'config'}->{$type.'-conf-file'};
		print "Zones matching '$search*' in: $fn\n" if ($search);
		print "Zones in: $fn\n"    if (!$search);
		print "  No Zones found\n" if (0 == $count);
		$self->print_list(%list)   if (0 < $count);
	}
	exit(0); # list
} #list

=item B<print_list>

  Title    : print_list
  Usage    : $self->print_list('master', %list);
  Function : Lists the domain in the DNS system
  Returns  : 
  Args     : %list : A hash of the domains

=cut

sub print_list()
{
	my ($self, %list) = @_;
	my $count = 1;

	my $fsize = $list{'size'}{'fsize'};
	my $csize = length(keys(%list));
	$csize  = 4 if (4 > $csize);
    delete($list{'size'});

	printf("\%${csize}s  ",  ' ');
	printf("\%-${fsize}s  ", 'Domain');
	printf("Flags\n");

	foreach my $l (sort keys %list)
	{
		my $d     = sprintf('%-'.$fsize.'s',  $l);
		my $held  = (1 == $list{"$l"}{'held'}) ? '(held)' : '';
		my $line  = sprintf(' %s  %s', $d, $held);
		
		$self->_print_list_line($count, $line, $list{"$l"}{'held'});
		$count++;
	}
} #print_list

=item B<type_exists>

  Title    : type_exists
  Usage    : $self->type_exists(@args);
  Function : Determines if the $type exists on the MySQL server.
  Returns  : an object
  Args     : $domain : The domain to check existence for.

=cut

sub type_exists($;%)
{
	my ($self, $domain, %args) = @_;
	my $fh;
	my $held = my $zone =0;

	my @tests = split(',', $self->{'config'}->{'config-files'});

	foreach my $t (@tests)
	{
		my $file = $self->{'config'}->{$t.'-conf-file'} ;
		$file = $self->make_path($file,$t,1);
		next unless $file;
		if ( -e $file )
		{
			open($fh, $file);
			while(my $line = <$fh>)
			{
				chomp($line);
				if ($line =~ /zone (\"?)$domain\1/i)
				{
					$zone=1;
					# check if the domain is held
					$held = 1 if ($line=~ /\|\-\|(.*?)zone/i);
				}
				if ( (1 == $zone) && ($line =~ /file \"([^\"]*?$domain)\";/) )
				{
					$args{'type'}        = $t;
					$self->{'zone_type'} = $t;
					return(1, $held, $t, $1);
				}
			}
			close($fh);
		}
	}

	return(0, 0);
} #type_exists

=item B<unhold>

  Title    : unhold
  Usage    : $self->unhold(@args);
  Function : Removes a domain from hold in the DNS system.
  Returns  : an object
  Args     : @args : an array of the arguments to the function. 
                     The first argument must be the domain, if it doesn't
                     exist it will ask for one.

=cut

sub unhold
{
	my ($self, @args) = @_;
	$self->{'log'}->{'args'} = \@args;
	$self->{'log'}->{'action'} = 'unhold';
	my ($domain) = @args;
	my $fh;

	$domain = $self->_get_valid_type_input($domain);
	my ($t, $held, $type, $db_file) = $self->type_exists($domain);

	$self->_width_to_status("Taking ($domain) off hold");

	$self->_print_check_start();
	return($self) if ($self->_print_error());

	my ($dir, $tpl, $config) = $self->get_files($type);

	return($self) if ($self->_print_error());
	$self->_print_ok();

	$self->_pretty_print_start("Taking ($domain) off hold");
	$self->_unhold($domain, $config, 1, 1);
	return($self) if ($self->_print_error());
	$self->_print_ok();

	return($self);
} #unhold

1;
