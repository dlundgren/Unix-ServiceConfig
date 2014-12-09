######################################################################
#
# Unix/ServiceConfig/db/mysql41.pm
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
		-type    => 'db'
		-file    => 'file.conf',
		-action  => 'add');

	$db->execute(@args);

=cut

package Unix::ServiceConfig::db::mysql41;

no warnings 'portable';
use 5.6.0;
use strict;
use warnings;

use vars qw(@ISA);

=head1 REQUIRES

perl5.005, Term::ANSIColor, DBI, SystemConfig

=cut

use Term::ANSIColor;
use DBI;
use Unix::ServiceConfig;

@ISA = qw(Unix::ServiceConfig);

=head1 EXPORTS

None.

=cut

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
	  'database',
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
  Usage    : my $sc = SystemConfig->new(
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
		
		$mconf = $c{'db'};
		$gconf = $c{'generic'};
	}

	my %config = $pkg->_merge_config('db', $mconf, $gconf);
	
	my $self = { 
		'config'    => ( \%config ),
		'actions'   => $actions,
		'file'      => $file,
		'main'      => 1,
		'me'        => 'db',
		'class'     => 'mysql41',
		'base_type' => 'user',
		'check'     => 'MySQL',
		'debug'     => 0,
		'commands'  => [ $config{'command-restart'} ],
		'error'     => {
			'exists' => 0,
			'msg'    => '',
		},
		'log'     => {
			'action' => 'unknown',
			'what'   => 'db::mysql41',
			'status' => 'unknown',
			'args'   => '',
		}
	};

	bless($self, $class);
	
	return($self);
} #new

=item B<database>

=cut

sub database
{
	my ($self, @args) = @_;
	$self->{'log'}->{'args'} = \@args;
	$self->{'log'}->{'what'} = $self->{'log'}->{'what'} . '-alias';
	$self->{'log'}->{'action'} = 'alias';
	my ($action, $database, $user) = @args;
	my $rc;
	my $search = '';

	$self->{'check'} = $self->{'check'}.' Database';

	# start database connection
	$database = $self->_get_input_with_check(
	   'Database name to use',
	   'Must be a valid database name', 
	   0,
	   $database,
	   $self->{'config'}->{'regex-database'}) 
	  if ('list' ne $action);

	$self->start_connection();
	my $dbh = $self->{'conn'};

	$self->_print_check_start();
	if ($dbh->{'errno'})
	{
		$self->_set_error($dbh->{'error'});
		$self->stop_connection();
		return(-1) if ($self->_print_error(1));
	}

	if ('list' eq $action)
	{
		$self->_print_ok();
		print("Databases found:\n");

		$rc = $dbh->prepare('SHOW DATABASES');
		$rc->execute();
		my $count = 1;
		while(my $ref = $rc->fetchrow_hashref())
		{
			$self->_print_list_line($count++, ' '.$ref->{'Database'}, 0);
		}
		$rc->finish();
	}
	elsif ($action =~ m/^(add|del(ete)?)$/i)
	{
		$rc = $dbh->prepare('SHOW DATABASES');
		$rc->execute();
		my $found = 0;
		while(my $ref = $rc->fetchrow_hashref())
		{
			$found = 1 if ($ref->{'Database'} eq $database);
		}
		$rc->finish();
		
		if ( (1 == $found) && ('add' eq $action) )
		{
			$self->_set_error("Database already exists ($database).");
		}
		elsif ( (0 == $found) && ($action =~ m/^del(ete)?$/i) )
		{
			$self->_set_error("Database does not exist ($database).");
		}
		return($self) if ($self->_print_error());
		$self->_print_ok();

		# database names must be valid according to mysql preferences
		$self->_width_to_status("Deleting database ($database)");

		if ('add' eq $action)
		{
			$self->_pretty_print_start("Adding database ($database)");
			$rc = $dbh->func('createdb', $database, 'admin');
		} # add the database
		elsif ($action =~ m/^del(ete)?$/i)
		{
			$self->_pretty_print_start("Deleting database ($database)");
			$rc = $dbh->func('dropdb', $database, 'admin');
		}
		if ($dbh->{'errno'})
		{
			$self->_set_error($dbh->{'error'});
			return(-1) if ($self->_print_error(1));
		}
		$self->_print_ok();
	} # add/delete a database

	$self->stop_connection();	
	return($self);
} #database

=item B<Database Functions>

=item B<db_error>

  Title    : db_error
  Usage    : $self->db_error();
  Function : Determines if there is an erro with a database operation. Will
             exit and clean up if $level is set.
  Returns  : 0 on no error, otherwise exits
  Args     : $level    : The level that we are at in the process of adding the
                         user. Defaults to 0. [optional]
             $username : The username. Required if $level is set.
             $hostname : The hostname. Required if $level is set.
             $database : The database. Required if $level is set.

=cut

sub db_error(;$$$$)
{
	my ($self, $level, $username, $hostname, $database) = @_;
	my $dbh = $self->{'conn'};
	my ($rc, $sql);
	$level = 0 if (!$level);
	
	# Determine if there was an error
	if ($dbh->{'mysql_errno'})
	{
		$self->_set_error($dbh->{'mysql_error'});
		if (0 == $level)
		{
			$self->stop_connection();
			return(-1) if ($self->_print_error());
		}
#book
		$self->_print_error(1);
	}
	else
	{
		return(0);
	}

	$self->_pretty_print_start('Cleaning from failed add');

	# cleanup the server by removing the database
	if ($level >= 1)
	{
		$rc = $dbh->func('dropdb', $database, 'admin');
		if ($dbh->{'mysql_errno'})
		{
			$self->_set_error($dbh->{'mysql_error'});
			$self->stop_connection();
			return(-1) if ($self->_print_error());
		}
	}

	# the database was added (and deleted) now remove the user from the 
	# database (who shouldn't have ANY other grants right now beyond usage)
	if ($level == 2)
	{
		$sql = 'DROP USER \'' . $username . '\'';
		$dbh->do($sql);
		if ($dbh->{'mysql_errno'})
		{
			$self->_set_error($dbh->{'mysql_error'});
			$self->stop_connection();
			return(-1) if ($self->_print_error());
		}
	}
	
	# the user may have grants so we need to do the hard way
	if ($level > 2)
	{
		$self->delete_user($username, $hostname);
	}
	
	$self->_print_ok();
	return(0);
} #db_error

=item B<delete_user>

  Title    : delete_user
  Usage    : $self->delete_user('test_user', 'localhost');
  Function : Removes the specified user@hostname from the database server
             without all the other checks required of the del function.
  Returns  : 0 always.
  Args     : $username : The username.
             $hostname : The hostname.
  

=cut

sub delete_user($$)
{
	my ($self, $username, $hostname) = @_;
	my $dbh = $self->{'conn'};
	my ($rc, $sql);
	
	# we ignore any of these errors

	# delete the user information from the user/db/columns_priv/table_priv
	# tables, then flush the privileges.
	$sql = 'DELETE FROM `user` where `User`=\'' . $username . '\'';
	$dbh->do($sql);
		
	$sql = 'DELETE FROM `db` where `User`=\'' . $username . '\'';
	$dbh->do($sql);

	$sql = 'DELETE FROM `columns_priv` where `User`=\'' . $username . '\'';
	$dbh->do($sql);

	$sql = 'DELETE FROM `tables_priv` where `User`=\'' . $username . '\'';
	$dbh->do($sql);

	$dbh->do('FLUSH PRIVILEGES');
	return(0);
} #delete_user

=item B<drop_db>

  Title    : drop_db
  Usage    : $self->drop_db();
  Function : Drops the database from the server. Asks the user to drop the
             database if the user doesn't equal the database name.
  Returns  : 
  Args     : $username :

=cut

sub drop_db($$)
{
	my ($self, $username, $db) = @_;
	my $ask = 1;
	my $dbh = $self->{'conn'};

	# we ask only if the username does not equal the database name
	$ask = $self->_get_yesno("Drop $db (yes/no)")
	  if ($username ne $db);

	if ($self->_is_enabled($ask))
	{
		$self->_pretty_print_start("Dropping database ($db)");
		$dbh->func('dropdb', $db, 'admin');
		if ($dbh->{'errno'})
		{
			$self->_set_error($dbh->{'error'});
			return(-1) if ($self->_print_error(1));
		}
		$self->_print_ok();		
	}
} #drop_db


=item B<start_connection>

  Title    : start_connection
  Usage    : $self->start_connection();
  Function : Starts the connection to the database.
  Returns  : 
  Args     : none

=cut

sub start_connection
{
	my ($self) = @_;

	my $dbh = DBI->connect('DBI:mysql:'.
	  'mysql_socket=' . $self->{'config'}->{'database-socket'} . 
	  ';database='    . $self->{'config'}->{'database-name'} . 
	  ';host='        . $self->{'config'}->{'database-host'} . 
	  ';port='        . $self->{'config'}->{'database-port'},
	  $self->{'config'}->{'database-user'}, 
	  $self->{'config'}->{'database-pass'});	
	$dbh->{mysql_auto_reconnect} = 1;

	$self->{'conn'} = $dbh;
	return(0);
} #start_connection

=item B<stop_connection>

  Title    : stop_connection
  Usage    : $self->stop_connection();
  Function : Stops the connection to the database.
  Returns  : 
  Args     : none

=cut

sub stop_connection
{
	my ($self) = @_;
	my $dbh = $self->{'conn'};
	$dbh->disconnect();
	return(0);
} #stop_connection

=item B<User Interaction>

=item B<get_database>

  Title    : get_database
  Usage    : $self->get_database();
  Function : Gets the database that the user wants to use for the username.
  Returns  : a string
  Args     : $username : The username.

=cut

sub get_database($)
{
	my ($self, $username) = @_;
	my $db;

	# get some defaults
	my $auto_db     = $self->{'config'}->{'auto-database'};
	my $regex_valid = $self->{'config'}->{'regex-database'};

	# determine if we should use the username as the database name
	$auto_db = $self->_get_yesno('Use username as database (yes/no)')
	  	if ('ask' eq $auto_db);
	
	# use the username as the database name
	if ($self->_is_enabled(
	    ('ask' eq $self->{'config'}->{'auto-database'}) ?
	      $self->_get_yesno('Use username as database name (yes/no)') :
	      $self->{'config'}->{'auto-database'})
	   )
	{
		$db = $username;
	}
	# ask the user for a database name, and verify it is usable
	else
	{
		$db    = $self->_get_input_with_check(
		   'Database name to use',
		   'Must be a valid database name', 
		   0,
		   $db,
		   $self->{'config'}->{'regex-database'});
	}

	$self->_width_status($db);

	return($db);
} #get_database

=item B<get_hostname>

  Title    : get_hostname
  Usage    : $self->get_hostname();
  Function : Gets the hostname that the user wants to use for adding a username
             to the database server.
  Returns  : a string
  Args     : $hostname : The hostname.

=cut

sub get_hostname($)
{
	my ($self, $hostname) = @_;
	my $auto           = ($self->{'config'}->{'auto-hostname'}) ?
	   $self->{'config'}->{'auto-hostname'} :
	   'y';
	my $default        = ($self->{'config'}->{'default-hostname'}) ?
	   $self->{'config'}->{'default-hostname'} :
	   'localhost';
	my ($error);

	# determine what the user wants to do
	$auto = $self->_get_yesno("Use default hostname [$default] (yes/no)")
	  	if ('ask' eq $auto);

	# use the default hostname
	if ($self->_is_enabled(
	    ('ask' eq $self->{'config'}->{'auto-hostname'}) ?
	      $self->_get_yesno("Use default hostname [$default] (yes/no)") :
	      $self->{'config'}->{'auto-hostname'})
	   )
	{
		$hostname = $default;
	}
	# ask the user for a password;
	else
	{
		do
		{
			$hostname = $self->_get_input('Hostname', $default);
			$error = 0;
			# there are three types of valid hostnames %, localhost, and 
			# host names
			$error = 1 if ( ('%' ne $hostname) || 
			     ('localhost' ne $hostname) || 
			     ($self->_is_valid_domain($hostname) ||
			     (length($hostname) > 60)) # the user table has this limit
			   );

		} while (1 == $error);
	}

	$self->_width_status($hostname);
	return($hostname);
} #get_hostname

=item B<get_password>

  Title    : get_password
  Usage    : $self->get_password();
  Function : Returns the password to be used.
  Returns  : a string
  Args     : $username : The username.

=cut

sub get_password($)
{
	my ($self, $username) = @_;
	my $user_pass_same = ($self->{'config'}->{'user-pass-same'}) ?
	   $self->{'config'}->{'user-pass-same'} :
	   'y';
	my $pass_length    = ($self->{'config'}->{'password-length'}) ?
	   $self->{'config'}->{'password-length'} :
	   'y';
	my ($password, $error);

	# generate the password
	if ($self->_is_enabled(
	    ('ask' eq $self->{'config'}->{'auto-password'}) ?
	      $self->_get_yesno('Use a random password (yes/no)') :
	      $self->{'config'}->{'auto-password'})
	    )
	{
		$password = $self->_generate_password();
	}
	# ask the user for a password;
	else
	{
		do
		{
			$password = $self->_get_password();
			$error = $self->_check_password($password, $username);
		} while ($error);
	}

	$self->_width_status($password);
	return($password);
} #_get_password;

=item B<Validation>

=item B<is_valid_user>

  Title    : is_valid_user
  Usage    : $self->is_valid_user();
  Function : Checks if a user is valid for the MySQL system.
  Returns  : 1 on true, 0 on failure
  Args     : 

=cut

sub is_valid_user($)
{
	my ($self, $user) = @_;
	my $regex_valid = $self->{'config'}->{'regex-user'};

	# the actual characters can be almost anything, using !@#$%^&*()_+{}:" 
	# actually worked on phpMyAdmin. if it works normally is another question.
	# But I allow the regex to exist just in case it becomes limited, or the
	# sysadmin wants to limit it
	return(1) if ($user =~ /$regex_valid/);

	# max length is 16 characters per MySQL documentation
	return(1) if (length($user) <= 16);
	return(0);
} #is_valid_user

=item B<Filled Stubs>

=item B<ask_action>

  Title    : ask_action
  Usage    : $self->ask_action();
  Function : Determines what to ask the user if this is being called as
             an extra section to the main one.
  Returns  : 
  Args     : $action : The action to perform.
             @args   : The arguments to the action.

=cut

sub ask_action($)
{
	my ($self, $action) = @_;
	my ($do, @args);
	return($self) if (!$self->{'data'});
	return($self) if (!$self->{'data'}->{'user_name'});
	my $user      = $self->{'data'}->{'user_name'};

	push(@args, $user);
	$self->{'main'} = 0;

	$self->start_connection();

	$self->_print_section_run();

	# we only need to determine if the action being requested has an ask command
	$do = $self->_get_yesno("Add ($user) to MySQL Server", "Yn")
	  if ($action =~ /^add$/);
	$do = $self->_get_yesno("Delete ($user) from MySQL Server", "Yn")
	  if ($action =~ /^del(ete)?$/);
	$do = $self->_get_yesno("Hold ($user) on MySQL Server", "Yn")
	  if ($action =~ /^hold$/);
	$do = $self->_get_yesno("Re-Activate ($user) on MySQL Server", "Yn")
	  if ($action =~ /^unhold$/);

	# check for the user and figure out if the user exists
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

	return(0);
} #ask_action

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
	my ($rc, $sql);

	# start database connection
	$self->start_connection();
	my $dbh = $self->{'conn'};

	# get a username if needed
	$user = $self->_get_valid_type_input($user, 'MySQL')
	  if (!$self->{'config'}->{'has_user'});

	# get the password/database/hostname
	my $password = $self->_generate_password($user);
	my $database = $self->get_database($user);
	my $hostname = $self->get_hostname($self->{'config'}->{'default-hostname'});

	$self->_width_to_status('Cleaning from failed add');
	$self->_width_to_status("Dropping database ($database)");
	$self->_width_to_status("Adding user ($user)");

	$self->_print_check_start();
	return($self) if ($self->_print_error());
	$self->_print_ok();

	# display password/database/host
	$self->_pretty_print_start('MySQL password:');
	$self->_pretty_print_end('bold blue',$password);
	$self->_pretty_print_start('MySQL database:');
	$self->_pretty_print_end('bold blue',$database);
	$self->_pretty_print_start('MySQL hostname:');
	$self->_pretty_print_end('bold blue',$hostname);

	# Modify the server
	$self->_pretty_print_start("Adding user ($user)");

	# create the user database
	$rc = $dbh->func('createdb', $database, 'admin');
	if (-1 == $self->db_error(0, $user, $hostname, $database))
	{
		$self->_print_error();
		return($self);
	}

	# create the users general usage rights
	$sql = 'GRANT USAGE ON *.* TO \'' . $user . '\'@\'' . $hostname . '\'' .
	       ' IDENTIFIED BY \'' . $password . '\'';
	$dbh->do($sql);
	$dbh->do($sql);
	if (-1 == $self->db_error(1, $user, $hostname, $database))
	{
		$self->_print_error();
		return($self);
	}

	# give the user all privileges for their database
	$sql = 'GRANT ALL PRIVILEGES ON `' . $database . '` . * TO \'' . $user .
	       '\'@\'' . $hostname . '\' WITH GRANT OPTION';
	$dbh->do($sql);
	if (-1 == $self->db_error(2, $user, $hostname, $database))
	{
		$self->_print_error();
		return($self);
	}

	$self->_print_ok();

	$self->stop_connection();
	return($self);
} #add

=item B<del>

  Title    : del
  Usage    : $self->del(@args);
  Function : Deletes a user from the MySQL system.
  Returns  : an object
  Args     : @args : an array of the arguments to the function. 
                     The first argument must be the username, if it doesn't
                     exist it will ask for one.

=cut

sub del
{
	my ($self, @args) = @_;
	$self->{'log'}->{'args'} = \@args;
	$self->{'log'}->{'action'} = 'del';
	my ($user) = @args;
	my ($rc, $sql);

	# start database connection
	$self->start_connection();
	my $dbh = $self->{'conn'};

	# get a username if needed
	$user = $self->_get_valid_type_input($user, 'MySQL')
	  if (!$self->{'config'}->{'has_user'});

	$self->_width_to_status('Cleaning from failed add');
	$self->_width_to_status("Removing user ($user)");

	$self->_print_check_start();
	return($self) if ($self->_print_error());
	$self->_print_ok();
	
	# we need to get the database that this user has access to
	$sql = 'SELECT `Db` FROM `db` WHERE `User`=\'' . $user . '\'';
	$rc = $dbh->prepare($sql);
	$rc->execute();
	if (0 < $rc->rows)
	{
		# we have at least 1 database to drop
		while(my $ref = $rc->fetchrow_hashref())
		{
			$self->drop_db($user, $ref->{'Db'});
		}
	}
	$rc->finish();
	$dbh->func("dropdb", $user, 'admin');

	$self->_pretty_print_start("Removing user ($user)");

	# this deletes the user completely from the mysql database (flushing will
	# remove them from the server, unless there is an active session, but we
	# already dropped their database anyway)
=todo 2006.08.09 dlundgren del
Check for any errors during the delete
=cut
	$self->delete_user($user);

	$self->_print_ok();

	return($self);
} #del

=item B<hold>

  Title    : hold
  Usage    : $self->hold(@args);
  Function : Puts a user on hold in the MySQL system.
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
	my ($rc, $sql, $host, $ref, $sth);
	
	# start database connection
	$self->start_connection();
	my $dbh = $self->{'conn'};

	# get a username if needed
	$user = $self->_get_valid_type_input($user, 'MySQL')
	  if (!$self->{'config'}->{'has_user'});

	$self->_width_to_status("Putting ($user) on hold");

	$self->_print_check_start();
	return($self) if ($self->_print_error());
	$self->_print_ok();

	$self->_pretty_print_start("Holding MySQL user ($user)");
	# get the current hostname
	$sql = 'SELECT `Host` FROM `user` WHERE `User`=\'' . $user . '\'';
	$rc  = $dbh->prepare($sql);
	$rc->execute();
	$ref = $rc->fetchrow_hashref() if (0 < $rc->rows);
	$rc->finish();

	# transform the hostname
	$host = '^' . $ref->{'Host'};
	# the hostname must be less than 60 characters (this is in the tables)
	if (length($host) > 60)
	{
		$host = $ref->{'Host'};
		# we can't lock anything above 60 characters so we change all the .'s
		# to ^'s. 
		$host =~ s/\./\^/g if (length($host) > 59);
	}
	
	# If there are no ^ then there is a problem.
	if ($host !~ m/\^/)
	{
		$self->_set_error("Couldn't place ($user) on hold.");
		return($self) if ($self->_print_error());
	}

	# update the database	
	$sql = 'UPDATE `user` SET ' .
	       '`Host`=\'' . $host . '\' ' .
	       'WHERE `User`=\'' . $user . '\'';
	$dbh->do($sql);
	if ($dbh->{'mysql_errno'})
	{
		$self->_set_error($dbh->{'mysql_error'});
		$self->stop_connection();
		return($self) if ($self->_print_error());
	}

	$dbh->do('FLUSH PRIVILEGES');
	$self->_print_ok();

	$self->stop_connection();
	return($self);
} #hold

=item B<list>

  Title    : list
  Usage    : $self->list(@args);
  Function : List the users in the MySQL server.
  Returns  : an object
  Args     : @args : an array of the arguments to the function. 
                     -search : The term to search for. [optional]

=cut

sub list
{
	my ($self, @args) = @_;
	$self->{'log'}->{'args'}   = \@args;
	$self->{'log'}->{'action'} = 'list';
	my ($search) = @args;
	my ($rc, $sql, %list);
	my $usize = my $hsize = my $csize = 0;

	$search = ($search) ? " WHERE `User` LIKE '$search%'" : '';

	# start database connection
	$self->start_connection();
	my $dbh = $self->{'conn'};
	
	$rc = $dbh->prepare("SELECT `User`, `Password`, `Host` FROM `user`$search");
	$rc->execute();
	while(my $ref = $rc->fetchrow_hashref())
	{
		my $user    = $ref->{'User'};
		my $host    = $ref->{'Host'};
		$usize  = length($user)  if (length($user)  > $usize);
		$hsize  = length($host)  if (length($host)  > $hsize);

		my $held = 0;
		$held    = 1 if ($host =~ /\^/);

		# transform a held host to a none held one for display purposes
		$host =~ s/^\^//;
		$host =~ s/\^/\./g;

		my $key = "$user\@$host";
		
		$list{$key}{'held'} = $held;
	}
	$rc->finish();
	
	my $count = 1;
	$csize = length(keys(%list));

	$csize  = 4 if (4 > $csize);
	$usize  = 4 if (4 > $usize);
	$hsize  = 4 if (4 > $hsize);

	printf("\%${csize}s  ",  ' ');
	printf("\%-${usize}s  ", 'User');
	printf("\%-${hsize}s  ", 'Host');
	printf("Flags\n");

	$self->_die_print('  No MySQL users found') if (0 == keys(%list)); # list

	foreach my $l (sort { $a cmp $b } keys %list)
	{
		my $c  = sprintf("\%${csize}s. ",$count);
		
		$l =~ m/([^@]*)@(.*)/;
		my $user = sprintf("\%-${usize}s", $1);
		my $host = sprintf("\%-${hsize}s", $2);
		my $held = (1 == $list{"$l"}{'held'}) ? '(held)' : '';
		my $line = sprintf("%s  %s  %s", $user, $host, $held);
		
		print color('yellow'),$c,color('reset');

		my $color = color('green');
		$color    = color('bold red') 
		  if ($self->_is_enabled($list{"$l"}{'held'}));

		print $color, $line, color('reset');

		print "\n";
		$count++;
	}
	
	$self->stop_connection();
	exit(0); # list
} #list

=item B<type_exists>

  Title    : type_exists
  Usage    : $self->type_exists(@args);
  Function : Determines if the $type exists on the MySQL server.
  Returns  : an object
  Args     : $username : The username to check existence for.

=cut

sub type_exists($)
{
	my ($self, $user) = @_;
	my $fh;
	my $held = 0;
	my $dbh = $self->{'conn'};

	my $sth = $dbh->prepare(
	  'SELECT `Host` FROM `mysql`.`user` WHERE `User`=\'' . $user . '\'');
	
	$sth->execute();
	if (0 != $sth->rows)
	{
		# user exists, see if they are on hold
		my $ref = $sth->fetchrow_hashref();
		$held   = 1 if ($ref->{'Host'} =~ /\^/);
		return(1, $held);
	}
	$sth->finish();
	return(0, $held);
} #user_exists

=item B<unhold>

  Title    : unhold
  Usage    : $self->unhold(@args);
  Function : Removes a user from hold on the MySQL server.
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
	my ($rc, $sql, $host, $ref, $sth);
	
	# start database connection
	$self->start_connection();
	my $dbh = $self->{'conn'};

	# get a username if needed
	$user = $self->_get_valid_type_input($user, 'MySQL')
	  if (!$self->{'config'}->{'has_user'});

	$self->_width_to_status("Taking ($user) off hold");

	$self->_print_check_start();
	return($self) if ($self->_print_error());
	$self->_print_ok();

	$self->_pretty_print_start("Activating MySQL user ($user)");
	# get the current hostname
	$sql = 'SELECT `Host` FROM `user` WHERE `User`=\'' . $user . '\'';
	$rc  = $dbh->prepare($sql);
	$rc->execute();
	$ref = $rc->fetchrow_hashref() if (0 < $rc->rows);
	$rc->finish();

	# transform the hostname
	$host = $ref->{'Host'};
	$host =~ s/^\^// if ($host =~ /^\^/);
	$host =~ s/\^/\./g;

	# unhold the user
	$sql = 'UPDATE `user` SET ' .
	       '`Host`=\'' . $host . '\' ' .
	       'WHERE `User`=\'' . $user . '\'';
	$dbh->do($sql);
	if ($dbh->{'mysql_errno'})
	{
		$self->_set_error($dbh->{'mysql_error'});
		$self->stop_connection();
		return($self) if ($self->_print_error());
	}

	$dbh->do('FLUSH PRIVILEGES');
	$self->_print_ok();
	$self->stop_connection();
	return($self);
} #unhold

1;
