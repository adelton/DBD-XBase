
=head1 NAME

XbaseTable - Perl module for reading and writing the dbf file

=head1 SYNOPSIS

	use XbaseTable;
	my $table = new XbaseTable("dbase.dbf");
	for (0 .. $table->last_record())
		{
		my ($deleted, $id, $msg)
			= $table->get_record($_, "ID", "MSG");
		print "$id:$msg\n" unless $deleted;
		}

=head1 DESCRIPTION

This module can read and write Xbase database file, known as dbf in
dBase and FoxPro world. With the help of ( ... ) it reads memo (and
the like) fields from the dbt files, if needed. This module should
really be used via DBD::Xbase DBI driver, but this is the alternative
interface.

Remember: Since the version number is pretty low now, you might want
to check the CHANGES file any time you upgrade to see wheather some of
the features you use haven't disappeared.

Warning: It doesn't support any index files at the present time!

The following methods are supported:

=over 4

=item new

Creates the XbaseTable object, takes the file's name as argument,
parses the file's header, fills the data structures.

=item close

Closes the object/file.

=item get_record

Returns data from the specified record (line of the table). The first
argument is the number of the record. If there are any other
arguments, they are considered to be the names of the fields and only
the specified fields are returned. If no field names are present,
returns all fields in the record. The first value of the returned list
is always 1/0 value saying if the record is deleted or not.

=item last_record

Number of the last records in the file. The lines deleted but present
in the file included in the number.

=back

If the method fails (returns undef of null), the error message is
stored in the $XbaseTable::errstr variable and there is a method
errstr that will just return the string.

There are following variables (parameters) in the XbaseTable
namespace:

=over 4

=item $DEBUG

Enables error messages on stderr.

=item $FIXERRORS

When reading the file, try to continue, even if there is some
(minor) missmatch in the data.

=item $CLEARNULLS

If true, cuts off spaces and nulls from the end of character fields.

=back

=head1 HISTORY

I have been using the Xbase(3) module by ( ... ) for quite a time to
read the dbf files, but it had no writing capabilities, it was not
-w/use strict clean and the author did not support the module behind
the version 1.07. So I started to make my own patches and thought it
would be nice if other people could make use of them. I thought about
taking over the development of the original Xbase package, but the
interface seemed rather complicated to me and I also disliked the
licence ( ... ) had about the module.

So with the help of article Xbase File Format Description by Erik
Bachmann, URL ( http:// ... ) I have written a new module. It doesn't
use any code from Xbase-1.07 and you are free to use it under the same
terms as Perl itself.

Please send all bug reports CC'ed to my e-mail, since I might miss
your post in c.l.p.misc or c.l.p.modules. Any comments from both Perl
and Xbase gurus are welcome, since I do neither use dBase nor Fox, so
there are probably pieces missing.

=head1 VERSION

0.021

=head1 AUTHOR

Jan Pazdziora, adelton@fi.muni.cz

=head1 SEE ALSO

perl(1), DBD::Xbase(3), DBI(3), Xbase(3)

=cut

use 5.004;	# hmm, maybe it would work with 5.003 or so, but I do
		# not have it, so this is more like a note, on which
		# version it has been tested


# ##################################
# Here starts the XbaseTable package

package XbaseTable;

use strict;
use IO::File;


# ##############
# General things

use vars qw( $VERSION $DEBUG $errstr $FIXERRORS $CLEARNULLS );
$VERSION = "0.021";

# Sets the debug level
$DEBUG = 1;
sub DEBUG () { $DEBUG };

# FIXERRORS can be set to make XbaseTable to try to work (read) even
# partially dameged file. Such actions are logged via Warning
$FIXERRORS = 1;
sub FIXERRORS () { $FIXERRORS };

# If set, will cut off the spaces and null from ends of character fields
$CLEARNULLS = 1;

# Holds the text of the error, if there was one
$errstr = '';

# Issues warning to STDERR if there is debug level set, but does Error
# if not FIXERRORS
sub Warning
	{
	if (not FIXERRORS) { Error(@_); return; }
	shift if ref $_[0];
	print STDERR "Warning: ", @_ if DEBUG;
	}
# Prints error on STDERR if there is debug level set and sets $errstr
sub Error
	{
	shift if ref $_[0];
	print STDERR @_ if DEBUG;
	$errstr .= join '', @_;
	}
# Nulls the $errstr, should be called upon method call from the mail
# program
sub NullError
	{ $errstr = ''; }


# ########################
# Constructor, open, close

# Constructor of the class; expects class name and filename of the
# .dbf file, returns the object if the file can be read, null otherwise
sub new
	{
	NullError();
	my ($class, $filename) = @_;
	my $new = { 'filename' => $filename };
	bless $new, $class;
	$new->open() and return $new;
	return;
	}
# Called by XbaseTable::new; opens the file and parses the header,
# sets the data structures of the object (field names, types, etc.).
# Returns 1 on success, null otherwise.
sub open
	{
	my $self = shift;
	return 1 if defined $self->{'opened'};
				# won't open if already opened

	my $fh = new IO::File;
	my ($filename, $writable, $mode) = ($self->{'filename'}, 0, "r");
	($writable, $mode) = (1, "r+") if -w $filename;
				# decide if we want r or r/w access

	$fh->open($filename, $mode) or do
		{ Error "Error opening file $self->{'filename'}: $!\n";
		return; };	# open the file
	
	my $header;
	$fh->read($header, 32) == 32 or do
		{ Error "Error reading header of $filename\n"; return; };

	my ($version, $last_update, $num_rec, $header_len, $record_len,
		$res1, $incompl_trans, $enc_flag, $rec_thread,
		$multiuser, $mdx_flag, $language_dr, $res2)
		= unpack "Ca3Vvva2CCVa8CCa2", $header;
				# read and parse the header

	my ($names, $types, $lengths, $decimals) = ( [], [], [], [] );

				# will read the field descriptions
	while (tell($fh) < $header_len - 1)
		{
		my $field_def;
		$fh->read($field_def, 32) == 32 or do
			{	# read the field description
			my $offset = tell $fh;
			Warning "Error reading field description at offset $offset\n";
			last if FIXERRORS;
			return;
			};
		
		last if substr $field_def, 0, 1 eq "\x0d";
				# we have found the terminator

		my ($name, $type, $address, $length, $decimal,
			$multiuser1, $work_area, $multiuser2,
			$set_fields_flag, $res, $index_flag)
				= unpack "A11aVCCa2Ca2Ca7C", $field_def;
		if ($type eq "C")
			{ $length += 256 * $decimal; $decimal = 0; }
				# fixup for char length > 256

		push @$names, $name;
		push @$types, $type;
		push @$lengths, $length;
		push @$decimals, $decimal;
				# store the information
		}

				# create name-to-num_of_field hash
	my ($hashnames, $i) = ({}, 0);
	for $i (0 .. $#$names)
		{
		$hashnames->{$names->[$i]} = $i
			unless defined $hashnames->{$names->[$i]};
		}
	my $template = "a1";
	my $num;
	for ($num = 0; $num <= $#$lengths; $num++)
		{
		my $totlen = $lengths->[$num] + $decimals->[$num];
		$template .= "a$totlen";
		}

				# now it's the time to store the
				# values to the object
	@{$self}{ qw( fh writable version last_update num_rec
		header_len record_len field_names field_types
		field_lengths field_decimals opened hash_names
		unpack_template last_field ) } =
			( $fh, $writable, $version, $last_update, $num_rec,
			$header_len, $record_len, $names, $types,
			$lengths, $decimals, 1, $hashnames, $template,
			$#$names );
	
	1;	# return true since everything went fine
	}

# Close the file, finish the work
sub close
	{
	NullError();
	my $self = shift;
	if (not defined $self->{'opened'})
		{ Error "Can't close file that is not opened\n"; return; }
	$self->{'fh'}->close();
	delete @{$self}{'opened', 'fh'};
	1;
	}

# ###############
# Little decoding

# Returns the number of the last record
sub last_record
	{ shift->{'num_rec'} - 1; }
# And the same for fields
sub last_field
	{ shift->{'last_field'}; }
# computes record's offset in the file
sub get_record_offset
	{
	my ($self, $num) = @_;
	return $self->{'header_len'} + $num * $self->{'record_len'};
	}

# #############################
# Header, field and record info

# Returns (not prints!) the info about the header of the object
sub get_header_info
	{
	my $self = shift;
	my $hexversion = sprintf "0x%02x", $self->{'version'};
	my $printdate = $self->decode_last_change($self->{'last_update'});
	my $numfields = scalar @{$self->{'field_types'}};
	my $result = sprintf <<"EOF";
Filename:	$self->{'filename'}
Version:	$hexversion
Num of records:	$self->{'num_rec'}
Header length:	$self->{'header_len'}
Record length:	$self->{'record_len'}
Last change:	$printdate
Num fields:	$numfields
Field info:
	Name		Type	Len	Decimal
EOF
	return $result, map { $self->get_field_info($_) }
					(0 .. $self->last_field());
	}

# Returns info about field in dbf file
sub get_field_info
	{
	my ($self, $num) = @_;
	sprintf "\t%-16.16s%-8.8s%-8.8s%-8.8s\n", map { $self->{$_}[$num] }
		qw( field_names field_types field_lengths field_decimals );
	}

# Returns last_change item in printable string
sub decode_last_change
	{
	shift if ref $_[0];
	my ($year, $mon, $day) = unpack "C3", shift;
	$year += 1900;
	return "$year/$mon/$day";
	}

# Prints the records as comma separated fields
sub dump_records
	{
	my $self = shift;
	my $num;
	for $num (0 .. $self->last_record())
		{ print join(':', map { defined $_ ? $_ : ''; }
				$self->get_record($num, @_)), "\n"; }
	}


# ###################
# Reading the records

# Returns fields of the specified record; parameters and number of the
# record (starting from 0) and optionally names of the required
# fields. If no names are specified, all fields are returned. The
# first value in the returned list if always 1/0 deleted flag. Returns
# empty list on error
sub get_record
	{
	NullError();
	my ($self, $num, @fields) = @_;

	if (not defined $num)
		{ Error "Record number to read must be specified\n"; return; }

	if ($num > $self->last_record())
		{ Error "Can't read record $num, there is not so many of them\n"; return; }

	my @data;
	if (defined $self->{'cached_num'} and $self->{'cached_num'} == $num)
		{ @data = @{$self->{'cached_data'}}; }
	else
		{ @data = $self->read_record($num); return unless @data; }

	# now make a list of numbers of fields to be returned
	if (@fields)
		{
		return $data[0], map {
			if (not defined $self->{'hash_names'}{$_})
				{
				Warning "Field named '$_' does not seem to exist\n";
				return unless FIXERRORS;
				undef;
				}
			else
				{ $data[$self->{'hash_names'}{$_} + 1]; }
			} @fields;
		}
	return @data;
	}

# Once we have the binary data from the pack, we want to convert them
# into reasonable perlish types. The arguments are the number of the
# field and the value. The delete flag has special number -1
sub process_item_on_read
	{
	my ($self, $num, $value) = @_;

	my $type = $self->{'field_types'}[$num];

	if ($num == -1)		# delete flag
		{
		if ($value eq '*')	{ return 1; }
		if ($value eq ' ')	{ return 0; }
		Warning "Unknown deleted flag '$value' found\n";
		return undef;
		}

	# now the other fields	
	if ($type eq 'C')
		{
		$value =~ s/\s+$// if $CLEARNULLS;
		return $value;
		}
	if ($type eq 'L')
		{
		if ($value =~ /^[YyTt]$/)	{ return 1; }
		if ($value =~ /^[NnFf]$/)	{ return 0; }
		return undef;	# ($value eq '?')
		}
	if ($type eq 'N' or $type eq 'F')
		{
		substr($value, $self->{'field_lengths'}[$num], 0) = '.';
		return $value + 0;
		}
	###
	### Fixup for MGBP ### to be added, read from dbt
	###
	$value;
	}

# Actually reads the record from file, stores in cache as well
sub read_record
	{
	my ($self, $num) = @_;
	
	my ($fh, $tell, $record_len, $filename ) =
		@{$self}{ qw( fh tell record_len filename ) };

	if (not defined $self->{'opened'})
		{ Error "The file $filename is not opened, can't read it\n";
		return; }	# will only read from opened file

	my $offset = $self->get_record_offset($num);
				# need to know where to start

	if (not defined $tell or $tell != $offset)
		{		# seek to the start of the record
		$fh->seek($offset, 0) or do {
			Error "Error seeking on $filename to offset $offset: $!\n";
			return;
			};
		}
	
	delete $self->{'tell'};
	my $buffer;
				# read the record
	$fh->read($buffer, $record_len) == $record_len or do {
			Warning "Error reading the whole record from $filename\nstarting offset $offset, record length $record_len\n";
			return unless FIXERRORS;
			};

	$self->{'tell'} = $tell = $offset + $record_len;
				# now we know where we are

	my $template = $self->{'unpack_template'};

	my @data = unpack $template, $buffer;
				# unpack the data
	
	my @result = map { $self->process_item_on_read($_, $data[$_ + 1]); }
					( -1 .. $self->last_field() );
				# process them

	$self->{'cached_data'} = [ @result ];
	$self->{'cached_num'} = $num;		# store in cache

	@result;		# and send back
	}


# #############
# Write records

sub write_record
	{
	NullError();
	my ($self, $num, %hash) = @_;
	if ($num > $self->last_record())
		{ Error "Can't rewrite record $num, there is not so many of them\n"; return; }
	my $offset = $self->get_record_offset($num);
	unless ($self->will_write_to($offset + 1))
		{ Error "Can't rewrite record $num\n"; return; }
	return;
	$self->{'fh'}->print(map { $self->pricess_item_on_write() } 1);	
	}
sub update_record
	{
	NullError();
	my ($self, $num, %hash) = @_;

	}

# Delete and undelete record
sub delete_record
	{
	NullError();
	my ($self, $num) = @_;
	if ($num > $self->last_record())
		{ Error "Can't delete record $num, there is not so many of them\n"; return; }
	my $offset = $self->get_record_offset($num);
	unless ($self->will_write_to($offset))
		{ Error "Can't delete the record $num\n"; return; }
	$self->{'fh'}->print("*");
	1;
	}
sub undelete_record
	{
	NullError();
	my ($self, $num) = @_;
	if ($num > $self->last_record())
		{ Error "Can't undelete record $num, there is not so many of them\n"; return; }
	my $offset = $self->get_record_offset($num);
	unless ($self->will_write_to($offset))
		{ Error "Can't undelete the record $num\n"; return; }
	$self->{'fh'}->print(" ");
	1;
	}

# Prepares everything for write at given position
sub will_write_to
	{
	my ($self, $offset) = @_;
	my $filename = $self->{'filename'};

				# the file should really be opened and
				# writable
	unless (defined $self->{'opened'})
		{ Error "The file $filename is not opened\n"; return; }
	if (not $self->{'writable'})
		{ Error "The file $filename is not writable\n"; return; }

	my ($fh, $header_len, $record_len) =
		@{$self}{ qw( fh header_len record_len ) };

				# we will cancel the tell position
	delete $self->{'tell'};

				# seek to the offset
	$fh->seek($offset, 0) or do {
		Error "Error seeking on $filename to offset $offset: $!\n";
		return;
		};
	1;
	}


1;

package XbaseTable::dbt;

sub new
	{
	
	}
sub close
	{
	}

1;

1;

