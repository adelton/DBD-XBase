
=head1 NAME

DBD::XBase - DBI driver for XBase

=head1 SYNOPSIS

    use DBI;
    my $dbh = DBI->connect("DBI:XBase:/directory/subdir")
    				or die $DBI::errstr;
    my $sth = $dbh->prepare("select MSG from test where ID != 1")
    				or die $dbh->errstr();
    $sth->execute() or die $sth->errstr();

    my @data;
    while (@data = $sth->fetchrow_array())
    	{
    	...
    	}

=head1 DESCRIPTION

DBI compliant driver for module XBase. I still work on it, currently
it supports just

=over 4

=item select

	select fields from table [ where condition ]

Fields is a comma separated list of fields or a * for all. The where
condition specifies which rows will be returned, you can compare
fields and constants and stack expressions using and or or, and also
(, ).

=item delete

	delete from table [ where condition ]

The where condition si the same as for select.

=over

=head1 VERSION

0.0394

=head1 AUTHOR

(c) Jan Pazdziora, adelton@fi.muni.cz

=head1 SEE ALSO

perl(1), DBI(3), XBase(3)

=cut


# ##################################
# Here starts the DBD::XBase package

package DBD::XBase;

use strict;
use DBI ();
use XBase;
use XBase::SQL;

use vars qw($VERSION @ISA @EXPORT $err $errstr $drh);

require Exporter;

$VERSION = '0.0394';

$err = 0;
$errstr = '';
$drh = undef;

sub driver
	{
	return $drh if $drh;
	my ($class, $attr) = @_;
	$class .= '::dr';
	$drh = DBI::_new_drh($class, {
		'Name'		=> 'XBase',
		'Version'	=> $VERSION,
		'Err'		=> \$DBD::XBase::err,
		'Errstr'	=> \$DBD::XBase::errstr,
		'Attribution'	=> 'DBD::XBase by Jan Pazdziora',
		});
	}


package DBD::XBase::dr;
use strict;
use vars qw( $imp_data_size );
$imp_data_size = 0;

sub connect
	{
	my ($drh, $dsn, $username, $password, $attrhash) = @_;

	if (not -d $dsn)
		{
		$DBD::XBase::err = 1;
		$DBD::XBase::errstr = "Directory $dsn doesn't exist";
		return undef;
		}
	my $this = DBI::_new_dbh($drh, { 'dsn' => $dsn } );
	$this;
	}

sub disconnect_all
	{ }


package DBD::XBase::db;
use strict;
use vars qw( $imp_data_size );
$imp_data_size = 0;

sub prepare
	{
	my ($dbh, $statement, @attribs)= @_;

	my $parsed_sql = parse XBase::SQL($statement);
	use Data::Dumper; print Dumper $parsed_sql;
	if (defined $parsed_sql->{'errstr'})
		{
		${$dbh->{'Err'}} = 2;
		${$dbh->{'Errstr'}} = 'Error in SQL parse: ' . $parsed_sql->{'errstr'};
		return;
		}

	if ($parsed_sql->{'command'} eq 'create')
		{
		return DBI::_new_sth($dbh, {
			'Statement'	=> $statement,
			'dbh'		=> $dbh,
			'xbase_parsed_sql'	=> $parsed_sql,
			});
		}
	
	my $table = $parsed_sql->{'table'}[0];
	my $xbase = $dbh->{'xbase_tables'}->{$table};
	if (not defined $xbase)
		{
		my $filename = $dbh->{'dsn'} . '/' . $table;
		$xbase = new XBase($filename);
		if (not defined $xbase)
			{
			${$dbh->{'Err'}} = 3;
			${$dbh->{'Errstr'}} =
				"Table $table not found: @{[XBase->errstr]}\n";
			return;
			}
		$dbh->{'xbase_tables'}->{$table} = $xbase;	
		}

	$parsed_sql->{'xbase'} = $xbase;

	my $field;
	my @nonexistfields = ();
	for $field (@{$parsed_sql->{'usedfields'}})
		{
		push @nonexistfields unless (defined $xbase->field_type($field) or grep { $_ eq $field } @nonexistfields);
		}
	if (@nonexistfields)
		{
		my $plural = ((scalar(@nonexistfields) > 1) ? 1 : 0);
		${$dbh->{'Err'}} = 4;
		${$dbh->{'Errstr'}} = qq!Field@{[$plural ? "s" : ""]} @{[$plural ? "do not" : "doesn't"]} exist in table $table\n!;
		return;
		}

	DBI::_new_sth($dbh, {
		'Statement'	=> $statement,
		'dbh'		=> $dbh,
		'xbase_parsed_sql'	=> $parsed_sql,
		'xbase_table'	=> $xbase,
		});
	}

sub STORE {
	my ($dbh, $attrib, $value) = @_;
	if ($attrib eq 'AutoCommit')
		{ return 1 if $value; }
	$dbh->DBD::_::db::STORE($attrib, $value);
	}


package DBD::XBase::st;
use strict;
use vars qw( $imp_data_size );
$imp_data_size = 0;

sub execute
	{
	my $sth = shift;
	my $xbase = $sth->{'xbase_table'};
	my $parsed_sql = $sth->{'xbase_parsed_sql'};

	delete $sth->{'xbase_current_record'}
				if defined $sth->{'xbase_current_record'};

	my $command = $parsed_sql->{'command'};
	if ($command eq 'delete')
		{
		my $recno = 0;
		my $last = $xbase->last_record();
		if (not defined $parsed_sql->{'wherefn'})
			{
			for ($recno = 0; $recno <= $last; $recno++)
				{ $xbase->delete_record($recno); }
			}
		else
			{
			for ($recno = 0; $recno <= $last; $recno++)
				{
				my $values = $xbase->get_record_as_hash($recno);
				next if $values->{'_DELETED'} != 0;
				next unless &{$parsed_sql->{'wherefn'}}($xbase, $values);
				$xbase->delete_record($recno);
				}
			}
		return 1;
		}
	elsif ($command eq 'create')
		{
		my $dbh = $sth->{'dbh'};
		my $table = $parsed_sql->{'table'};
		my $filename = $dbh->{'dsn'} . '/' . $table;
		my $xbase = XBase->create('name' => $filename,
			map { ($_, $parsed_sql->{$_}) }
				grep { /^field_/ } keys %$parsed_sql);
		
		if (not defined $xbase)
			{
			### ${$sth->{'Err'}} = 10;
			${$sth->{'Errstr'}} = XBase->errstr();
			return;
			}
		$dbh->{'xbase_tables'}->{$table} = $xbase;	
		}
	1;
	}

sub fetch
	{
        my $sth = shift;
	my $current = $sth->{'xbase_current_record'};
	my $parsed_sql = $sth->{'xbase_parsed_sql'};
	return unless $parsed_sql->{'command'} eq 'select';
	$current = 0 unless defined $current;
	my $table = $sth->{'xbase_table'};
	my @fields;
	if (defined $parsed_sql->{'selectall'})
		{ @fields = $table->field_names(); }
	else
		{ @fields = @{$parsed_sql->{'selectfields'}}; }
	while ($current <= $table->last_record())
		{
		my $values = $table->get_record_as_hash($current);
		$sth->{'xbase_current_record'} = ++$current;
		next if $values->{'_DELETED'} != 0;
		if (defined $parsed_sql->{'wherefn'})
			{ next unless &{$parsed_sql->{'wherefn'}}($table, $values); }
		return [ @{$values}{ @fields } ];
		}
	$sth->finish(); return;
	}
	
1;
